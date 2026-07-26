//
//  AnyUprightImageResampler.swift
//  AnyUpright
//

import Foundation
import Metal
import MetalPerformanceShaders

enum AUAppleSiliconMetalDeviceResolver {
    static func resolve(
        preferredRegistryID: UInt64,
        availableDevices: [MTLDevice] = MTLCopyAllDevices(),
        systemDefaultDevice: MTLDevice? = MTLCreateSystemDefaultDevice()
    ) -> MTLDevice? {
        if preferredRegistryID != 0,
           let exactDevice = availableDevices.first(where: { $0.registryID == preferredRegistryID }) {
            return exactDevice
        }
        return systemDefaultDevice
    }
}

enum AUImageResamplingLayout: Hashable {
    case stretch
    case aspectFillCenterCrop
}

enum AUImageTensorChannels: Int {
    case grayscale = 1
    case rgb = 3
}

struct AUImageResamplingGeometry: Hashable {
    let sourceWidth: Int
    let sourceHeight: Int
    let targetWidth: Int
    let targetHeight: Int
    let resizedWidth: Int
    let resizedHeight: Int
    let cropLeft: Int
    let cropTop: Int

    init(
        sourceWidth: Int,
        sourceHeight: Int,
        targetWidth: Int,
        targetHeight: Int,
        layout: AUImageResamplingLayout
    ) throws {
        guard sourceWidth > 0,
              sourceHeight > 0,
              targetWidth > 0,
              targetHeight > 0 else {
            throw AUImageResamplingError.invalidDimensions
        }

        self.sourceWidth = sourceWidth
        self.sourceHeight = sourceHeight
        self.targetWidth = targetWidth
        self.targetHeight = targetHeight

        switch layout {
        case .stretch:
            resizedWidth = targetWidth
            resizedHeight = targetHeight
            cropLeft = 0
            cropTop = 0
        case .aspectFillCenterCrop:
            let scale = max(
                Double(targetWidth) / Double(sourceWidth),
                Double(targetHeight) / Double(sourceHeight)
            )
            resizedWidth = max(targetWidth, Int(Double(sourceWidth) * scale))
            resizedHeight = max(targetHeight, Int(Double(sourceHeight) * scale))
            cropLeft = (resizedWidth - targetWidth + 1) / 2
            cropTop = (resizedHeight - targetHeight + 1) / 2
        }
    }

    var scaleTransform: MPSScaleTransform {
        MPSScaleTransform(
            scaleX: Double(resizedWidth) / Double(sourceWidth),
            scaleY: Double(resizedHeight) / Double(sourceHeight),
            translateX: -Double(cropLeft),
            translateY: -Double(cropTop)
        )
    }
}

struct AUImageResampledTensor {
    let values: [Float]
    let shape: [Int]
}

enum AUImageResamplingError: Error, CustomStringConvertible {
    case invalidDimensions
    case sourceBoundsExceedTexture
    case unsupportedTexture
    case resourceAllocationFailed(String)
    case commandFailed(String)

    var description: String {
        switch self {
        case .invalidDimensions:
            return "Image resampling dimensions must be positive"
        case .sourceBoundsExceedTexture:
            return "Image resampling source bounds exceed the Metal texture"
        case .unsupportedTexture:
            return "Image resampling requires a 2D, non-array Metal texture"
        case .resourceAllocationFailed(let message):
            return "Image resampling resource allocation failed: \(message)"
        case .commandFailed(let message):
            return "Image resampling command failed: \(message)"
        }
    }
}

enum AUAppleSiliconImageResampler {
    private struct PipelineKey: Hashable {
        let registryID: UInt64
    }

    private struct LanczosSlotKey: Hashable {
        let registryID: UInt64
        let targetWidth: Int
        let targetHeight: Int
        let layout: AUImageResamplingLayout
    }

    private final class CachedLanczosScaler {
        let geometry: AUImageResamplingGeometry
        let scaler: MPSImageLanczosScale
        let encodeLock = NSLock()

        init(geometry: AUImageResamplingGeometry, scaler: MPSImageLanczosScale) {
            self.geometry = geometry
            self.scaler = scaler
        }
    }

    private struct TensorPackConfig {
        var width: UInt32
        var height: UInt32
        var channelCount: UInt32
    }

    private static let cacheLock = NSLock()
    private static var packPipelines: [PipelineKey: MTLComputePipelineState] = [:]
    private static var lanczosScalers: [LanczosSlotKey: CachedLanczosScaler] = [:]

    static func resample(
        sourceTexture: MTLTexture,
        sourceWidth: Int,
        sourceHeight: Int,
        targetWidth: Int,
        targetHeight: Int,
        layout: AUImageResamplingLayout,
        channels: AUImageTensorChannels,
        commandQueue: MTLCommandQueue
    ) throws -> AUImageResampledTensor {
        guard sourceTexture.textureType == .type2D,
              sourceTexture.arrayLength == 1 else {
            throw AUImageResamplingError.unsupportedTexture
        }
        guard sourceWidth <= sourceTexture.width,
              sourceHeight <= sourceTexture.height else {
            throw AUImageResamplingError.sourceBoundsExceedTexture
        }

        let geometry = try AUImageResamplingGeometry(
            sourceWidth: sourceWidth,
            sourceHeight: sourceHeight,
            targetWidth: targetWidth,
            targetHeight: targetHeight,
            layout: layout
        )
        let (planeSize, planeOverflow) = targetWidth.multipliedReportingOverflow(by: targetHeight)
        let (outputCount, channelOverflow) = planeSize.multipliedReportingOverflow(by: channels.rawValue)
        guard !planeOverflow,
              !channelOverflow,
              targetWidth <= Int(UInt32.max),
              targetHeight <= Int(UInt32.max) else {
            throw AUImageResamplingError.invalidDimensions
        }
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: sourceTexture.pixelFormat,
            width: targetWidth,
            height: targetHeight,
            mipmapped: false
        )
        textureDescriptor.storageMode = .private
        textureDescriptor.usage = [.shaderRead, .shaderWrite]

        let device = sourceTexture.device
        guard let resampledTexture = device.makeTexture(descriptor: textureDescriptor) else {
            throw AUImageResamplingError.resourceAllocationFailed("destination texture")
        }
        guard let outputBuffer = device.makeBuffer(
            length: outputCount * MemoryLayout<Float>.stride,
            options: .storageModeShared
        ) else {
            throw AUImageResamplingError.resourceAllocationFailed("output tensor buffer")
        }
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            throw AUImageResamplingError.resourceAllocationFailed("command buffer")
        }

        let samplingTexture: MTLTexture
        if sourceWidth == sourceTexture.width, sourceHeight == sourceTexture.height {
            samplingTexture = sourceTexture
        } else {
            let sourceDescriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: sourceTexture.pixelFormat,
                width: sourceWidth,
                height: sourceHeight,
                mipmapped: false
            )
            sourceDescriptor.storageMode = .private
            sourceDescriptor.usage = [.shaderRead]
            guard let exactSourceTexture = device.makeTexture(descriptor: sourceDescriptor),
                  let blit = commandBuffer.makeBlitCommandEncoder() else {
                throw AUImageResamplingError.resourceAllocationFailed("exact source texture")
            }
            blit.copy(
                from: sourceTexture,
                sourceSlice: 0,
                sourceLevel: 0,
                sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                sourceSize: MTLSize(width: sourceWidth, height: sourceHeight, depth: 1),
                to: exactSourceTexture,
                destinationSlice: 0,
                destinationLevel: 0,
                destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0)
            )
            blit.endEncoding()
            samplingTexture = exactSourceTexture
        }

        let lanczos = lanczosScaler(device: device, geometry: geometry, layout: layout)
        lanczos.encodeLock.lock()
        lanczos.scaler.encode(
            commandBuffer: commandBuffer,
            sourceTexture: samplingTexture,
            destinationTexture: resampledTexture
        )
        lanczos.encodeLock.unlock()

        guard let encoder = commandBuffer.makeComputeCommandEncoder() else {
            throw AUImageResamplingError.resourceAllocationFailed("tensor pack encoder")
        }
        let pipeline = try packPipeline(device: device)
        var config = TensorPackConfig(
            width: UInt32(targetWidth),
            height: UInt32(targetHeight),
            channelCount: UInt32(channels.rawValue)
        )
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(resampledTexture, index: 0)
        encoder.setBuffer(outputBuffer, offset: 0, index: 0)
        encoder.setBytes(&config, length: MemoryLayout<TensorPackConfig>.stride, index: 1)
        encoder.dispatchThreads(
            MTLSize(width: outputCount, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(
                width: min(pipeline.maxTotalThreadsPerThreadgroup, 256),
                height: 1,
                depth: 1
            )
        )
        encoder.endEncoding()

        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        if let error = commandBuffer.error {
            throw AUImageResamplingError.commandFailed(String(describing: error))
        }

        let pointer = outputBuffer.contents().bindMemory(to: Float.self, capacity: outputCount)
        return AUImageResampledTensor(
            values: Array(UnsafeBufferPointer(start: pointer, count: outputCount)),
            shape: [1, channels.rawValue, targetHeight, targetWidth]
        )
    }

    private static func lanczosScaler(
        device: MTLDevice,
        geometry: AUImageResamplingGeometry,
        layout: AUImageResamplingLayout
    ) -> CachedLanczosScaler {
        let key = LanczosSlotKey(
            registryID: device.registryID,
            targetWidth: geometry.targetWidth,
            targetHeight: geometry.targetHeight,
            layout: layout
        )
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if let cached = lanczosScalers[key], cached.geometry == geometry {
            return cached
        }

        let scaler = MPSImageLanczosScale(device: device)
        scaler.edgeMode = .clamp
        var transform = geometry.scaleTransform
        withUnsafePointer(to: &transform) { pointer in
            scaler.scaleTransform = pointer
        }
        let cached = CachedLanczosScaler(geometry: geometry, scaler: scaler)
        lanczosScalers[key] = cached
        return cached
    }

    private static func packPipeline(device: MTLDevice) throws -> MTLComputePipelineState {
        let key = PipelineKey(registryID: device.registryID)
        cacheLock.lock()
        if let cached = packPipelines[key] {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()

        guard let library = device.makeDefaultLibrary(),
              let function = library.makeFunction(name: "auPackResampledTextureToNCHW") else {
            throw AUImageResamplingError.resourceAllocationFailed("tensor pack Metal function")
        }
        let pipeline = try device.makeComputePipelineState(function: function)

        cacheLock.lock()
        packPipelines[key] = pipeline
        cacheLock.unlock()
        return pipeline
    }
}
