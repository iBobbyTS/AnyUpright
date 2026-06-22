//
//  AnyUprightGeoCalibDirectPreprocessor.swift
//  AnyUpright
//

import Foundation
import Metal

private struct AUGeoCalibDirectPreprocessConfig {
    var inputWidth: UInt32
    var inputHeight: UInt32
    var outputWidth: UInt32
    var outputHeight: UInt32
    var resizedWidth: UInt32
    var resizedHeight: UInt32
    var cropLeft: UInt32
    var cropTop: UInt32
    var kernelWidth: UInt32
    var kernelHeight: UInt32
    var usesAntialias: UInt32
}

enum AUGeoCalibDirectImagePreprocessor {
    private static let pipelineLock = NSLock()
    private static var pipelineStatesByRegistryID: [UInt64: MTLComputePipelineState] = [:]

    static func preprocessFrame(
        _ frame: FxImageTile,
        targetShortSide: Int = 320,
        edgeDivisibleBy: Int = 32,
        targetInputShape: [Int]? = nil,
        deviceCache: MetalDeviceCache = MetalDeviceCache.deviceCache
    ) throws -> AUGeoCalibPreprocessedImage {
        guard frame.ioSurface != nil else {
            throw AUGeoCalibHorizonDetectorError.invalidImage("analysis frame has no IOSurface")
        }

        let bounds = frame.imagePixelBounds
        let sourceWidth = max(1, Int(bounds.right - bounds.left))
        let sourceHeight = max(1, Int(bounds.top - bounds.bottom))
        let geometry = try AUGeoCalibPreprocessGeometry(
            sourceWidth: sourceWidth,
            sourceHeight: sourceHeight,
            targetShortSide: targetShortSide,
            edgeDivisibleBy: edgeDivisibleBy,
            targetInputShape: targetInputShape
        )

        guard let device = deviceCache.device(with: frame.deviceRegistryID) ?? MTLCopyAllDevices().first(where: { $0.registryID == frame.deviceRegistryID }),
              let sourceTexture = frame.metalTexture(for: device) else {
            throw AUGeoCalibHorizonDetectorError.invalidImage("unable to create Metal texture for analysis frame")
        }
        guard sourceWidth <= sourceTexture.width, sourceHeight <= sourceTexture.height else {
            throw AUGeoCalibHorizonDetectorError.invalidImage(
                "analysis bounds \(sourceWidth)x\(sourceHeight) exceed source texture \(sourceTexture.width)x\(sourceTexture.height)"
            )
        }

        let pixelFormat = MetalDeviceCache.FxMTLPixelFormat(for: frame)
        let commandQueueLease = deviceCache.commandQueueLease(with: frame.deviceRegistryID, pixelFormat: pixelFormat)
        let commandQueue = commandQueueLease?.commandQueue ?? device.makeCommandQueue()
        defer { commandQueueLease?.returnToCache() }

        let outputCount = 3 * geometry.cropWidth * geometry.cropHeight
        guard let outputBuffer = device.makeBuffer(length: outputCount * MemoryLayout<Float>.stride, options: .storageModeShared),
              let kernelXBuffer = device.makeBuffer(
                bytes: geometry.kernelX,
                length: geometry.kernelX.count * MemoryLayout<Float>.stride,
                options: .storageModeShared
              ),
              let kernelYBuffer = device.makeBuffer(
                bytes: geometry.kernelY,
                length: geometry.kernelY.count * MemoryLayout<Float>.stride,
                options: .storageModeShared
              ),
              let commandBuffer = commandQueue?.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            throw AUGeoCalibHorizonDetectorError.invalidImage("unable to allocate Metal preprocessing resources")
        }

        let pipelineState = try pipelineState(for: device)
        var config = AUGeoCalibDirectPreprocessConfig(
            inputWidth: UInt32(sourceWidth),
            inputHeight: UInt32(sourceHeight),
            outputWidth: UInt32(geometry.cropWidth),
            outputHeight: UInt32(geometry.cropHeight),
            resizedWidth: UInt32(geometry.resizedWidth),
            resizedHeight: UInt32(geometry.resizedHeight),
            cropLeft: UInt32(geometry.cropLeft),
            cropTop: UInt32(geometry.cropTop),
            kernelWidth: UInt32(geometry.kernelX.count),
            kernelHeight: UInt32(geometry.kernelY.count),
            usesAntialias: geometry.needsAntialias ? 1 : 0
        )

        commandBuffer.label = "AnyUpright GeoCalib Direct Preprocess"
        encoder.setComputePipelineState(pipelineState)
        encoder.setTexture(sourceTexture, index: 0)
        encoder.setBuffer(outputBuffer, offset: 0, index: 0)
        encoder.setBytes(&config, length: MemoryLayout<AUGeoCalibDirectPreprocessConfig>.stride, index: 1)
        encoder.setBuffer(kernelXBuffer, offset: 0, index: 2)
        encoder.setBuffer(kernelYBuffer, offset: 0, index: 3)
        let threadsPerGroup = MTLSize(width: min(pipelineState.maxTotalThreadsPerThreadgroup, 256), height: 1, depth: 1)
        let grid = MTLSize(width: outputCount, height: 1, depth: 1)
        encoder.dispatchThreads(grid, threadsPerThreadgroup: threadsPerGroup)
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        if let error = commandBuffer.error {
            throw AUGeoCalibHorizonDetectorError.invalidImage("Metal preprocessing failed: \(error)")
        }

        let outputPointer = outputBuffer.contents().bindMemory(to: Float.self, capacity: outputCount)
        let output = Array(UnsafeBufferPointer(start: outputPointer, count: outputCount))
        return AUGeoCalibPreprocessedImage(
            inputRGBNCHW: output,
            inputShape: geometry.inputShape,
            scales: geometry.scales
        )
    }

    private static func pipelineState(for device: MTLDevice) throws -> MTLComputePipelineState {
        pipelineLock.lock()
        if let cached = pipelineStatesByRegistryID[device.registryID] {
            pipelineLock.unlock()
            return cached
        }
        pipelineLock.unlock()

        guard let library = device.makeDefaultLibrary(),
              let function = library.makeFunction(name: "auGeoCalibDirectPreprocessTextureKernel") else {
            throw AUGeoCalibHorizonDetectorError.invalidImage("missing GeoCalib direct preprocessing Metal kernel")
        }
        let pipelineState = try device.makeComputePipelineState(function: function)

        pipelineLock.lock()
        pipelineStatesByRegistryID[device.registryID] = pipelineState
        pipelineLock.unlock()
        return pipelineState
    }
}
