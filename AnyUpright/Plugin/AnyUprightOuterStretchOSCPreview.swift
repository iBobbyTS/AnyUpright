//
//  AnyUprightOuterStretchOSCPreview.swift
//  AnyUpright
//

import CoreMedia
import Foundation
import Metal

struct AUOuterStretchOSCPreviewSignature: Equatable {
    let values: [UInt32]

    init(state: AnyUprightParameterState) {
        values = [
            UInt32(bitPattern: state.stretchMode),
            UInt32(bitPattern: state.stretchRatioMode),
            state.topLeftPercentX.bitPattern,
            state.topLeftPercentY.bitPattern,
            state.topLeftPixelX.bitPattern,
            state.topLeftPixelY.bitPattern,
            state.topRightPercentX.bitPattern,
            state.topRightPercentY.bitPattern,
            state.topRightPixelX.bitPattern,
            state.topRightPixelY.bitPattern,
            state.bottomRightPercentX.bitPattern,
            state.bottomRightPercentY.bitPattern,
            state.bottomRightPixelX.bitPattern,
            state.bottomRightPixelY.bitPattern,
            state.bottomLeftPercentX.bitPattern,
            state.bottomLeftPercentY.bitPattern,
            state.bottomLeftPixelX.bitPattern,
            state.bottomLeftPixelY.bitPattern
        ]
    }
}

struct AUOuterStretchOSCPreviewQuery {
    let renderTime: CMTime
    let signature: AUOuterStretchOSCPreviewSignature
}

struct AUOuterStretchOSCPreviewEntry {
    let texture: MTLTexture
    let objectFrame: [AUPoint]
}

final class AUOuterStretchOSCPreviewCache {
    static let shared = AUOuterStretchOSCPreviewCache()

    private struct Record {
        let query: AUOuterStretchOSCPreviewQuery
        let entry: AUOuterStretchOSCPreviewEntry
        let storedAt: UInt64
    }

    private let lock = NSLock()
    private var records: [ObjectIdentifier: Record] = [:]
    private let maximumRecordCount = 8

    func store(
        sourceID: ObjectIdentifier,
        query: AUOuterStretchOSCPreviewQuery,
        entry: AUOuterStretchOSCPreviewEntry,
        now: UInt64 = DispatchTime.now().uptimeNanoseconds
    ) {
        lock.lock()
        defer { lock.unlock() }
        records[sourceID] = Record(query: query, entry: entry, storedAt: now)
        if records.count > maximumRecordCount,
           let oldest = records.min(by: { $0.value.storedAt < $1.value.storedAt })?.key {
            records.removeValue(forKey: oldest)
        }
    }

    func entry(
        matching query: AUOuterStretchOSCPreviewQuery,
        deviceRegistryID: UInt64
    ) -> AUOuterStretchOSCPreviewEntry? {
        lock.lock()
        defer { lock.unlock() }
        let matches = records.values.filter {
            CMTimeCompare($0.query.renderTime, query.renderTime) == 0
                && $0.query.signature == query.signature
                && $0.entry.texture.device.registryID == deviceRegistryID
        }
        guard matches.count == 1 else {
            return nil
        }
        return matches[0].entry
    }

    func remove(sourceID: ObjectIdentifier) {
        lock.lock()
        records.removeValue(forKey: sourceID)
        lock.unlock()
    }
}

enum AUOuterStretchOSCPreviewRenderer {
    private struct PipelineKey: Hashable {
        let registryID: UInt64
        let pixelFormat: MTLPixelFormat
    }

    private static let pipelineLock = NSLock()
    private static var pipelineCache: [PipelineKey: MTLRenderPipelineState] = [:]

    static func encode(
        commandBuffer: MTLCommandBuffer,
        device: MTLDevice,
        inputTexture: MTLTexture,
        warpState: inout AnyUprightWarpState,
        layout: AUOuterStretchOSCPreviewLayout
    ) -> MTLTexture? {
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Float,
            width: layout.textureWidth,
            height: layout.textureHeight,
            mipmapped: false
        )
        textureDescriptor.storageMode = .private
        textureDescriptor.usage = [.renderTarget, .shaderRead]
        guard let texture = device.makeTexture(descriptor: textureDescriptor),
              let pipeline = pipelineState(device: device, pixelFormat: texture.pixelFormat) else {
            return nil
        }
        texture.label = "AnyUpright Outer Stretch OSC Preview"

        let colorAttachment = MTLRenderPassColorAttachmentDescriptor()
        colorAttachment.texture = texture
        colorAttachment.clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 0.0)
        colorAttachment.loadAction = .clear
        colorAttachment.storeAction = .store
        let passDescriptor = MTLRenderPassDescriptor()
        passDescriptor.colorAttachments[0] = colorAttachment
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor) else {
            return nil
        }

        var vertices = layout.offscreenVertices.map {
            AnyUprightVertex2D(
                position: vector_float2(Float($0.position.x), Float($0.position.y)),
                outputCoordinate: vector_float2(Float($0.outputCoordinate.x), Float($0.outputCoordinate.y))
            )
        }
        var viewportSize = simd_uint2(UInt32(layout.textureWidth), UInt32(layout.textureHeight))
        encoder.setViewport(MTLViewport(originX: 0.0, originY: 0.0, width: Double(layout.textureWidth), height: Double(layout.textureHeight), znear: -1.0, zfar: 1.0))
        encoder.setRenderPipelineState(pipeline)
        encoder.setVertexBytes(&vertices, length: MemoryLayout<AnyUprightVertex2D>.stride * vertices.count, index: Int(AUVII_Vertices.rawValue))
        encoder.setVertexBytes(&viewportSize, length: MemoryLayout.size(ofValue: viewportSize), index: Int(AUVII_ViewportSize.rawValue))
        encoder.setFragmentTexture(inputTexture, index: Int(AUTI_InputImage.rawValue))
        encoder.setFragmentBytes(&warpState, length: MemoryLayout<AnyUprightWarpState>.stride, index: Int(AUFII_WarpState.rawValue))
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: vertices.count)
        encoder.endEncoding()
        return texture
    }

    private static func pipelineState(device: MTLDevice, pixelFormat: MTLPixelFormat) -> MTLRenderPipelineState? {
        let key = PipelineKey(registryID: device.registryID, pixelFormat: pixelFormat)
        pipelineLock.lock()
        if let cached = pipelineCache[key] {
            pipelineLock.unlock()
            return cached
        }
        pipelineLock.unlock()

        guard let library = device.makeDefaultLibrary(),
              let vertexFunction = library.makeFunction(name: "anyUprightWarpVertex"),
              let fragmentFunction = library.makeFunction(name: "anyUprightOuterStretchOSCPreviewFragment") else {
            return nil
        }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = "AnyUpright Outer Stretch OSC Preview"
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.colorAttachments[0].pixelFormat = pixelFormat
        guard let pipeline = try? device.makeRenderPipelineState(descriptor: descriptor) else {
            return nil
        }
        pipelineLock.lock()
        pipelineCache[key] = pipeline
        pipelineLock.unlock()
        return pipeline
    }
}
