//
//  AnyUprightOuterStretchOSCPreview.swift
//  AnyUpright
//

import CoreMedia
import Foundation
import Metal

enum AUOuterStretchOSCPreviewDebugLog {
    private static let lock = NSLock()
    private static let markerURL = URL(fileURLWithPath: "/tmp/AnyUprightOuterStretchOSCPreview.debug")
    private static let logURL = URL(fileURLWithPath: "/tmp/AnyUprightOuterStretchOSCPreview.log")

    static func record(_ message: String) {
        guard FileManager.default.fileExists(atPath: markerURL.path) else {
            return
        }

        let line = "\(DispatchTime.now().uptimeNanoseconds) \(message)\n"
        lock.lock()
        defer { lock.unlock() }
        if !FileManager.default.fileExists(atPath: logURL.path) {
            FileManager.default.createFile(atPath: logURL.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: logURL) else {
            return
        }
        defer { try? handle.close() }
        try? handle.seekToEnd()
        try? handle.write(contentsOf: Data(line.utf8))
    }

    static func describe(_ query: AUOuterStretchOSCPreviewQuery) -> String {
        var hash: UInt64 = 1469598103934665603
        for value in query.signature.values {
            hash ^= UInt64(value)
            hash &*= 1099511628211
        }
        let seconds = CMTimeGetSeconds(query.renderTime)
        return "time=\(String(format: "%.6f", seconds)) sig=\(String(hash, radix: 16))"
    }

    static func describe(_ sourceID: ObjectIdentifier) -> String {
        String(sourceID.hashValue, radix: 16)
    }
}

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
    let renderOutputSize: AUSize
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
        if let existing = records[sourceID],
           CMTimeCompare(existing.query.renderTime, query.renderTime) == 0,
           existing.entry.texture.device.registryID == entry.texture.device.registryID,
           !AUOuterStretchOSCPreviewRenderPolicy.shouldReplace(
               candidateOutputSize: entry.renderOutputSize,
               existingOutputSize: existing.entry.renderOutputSize,
               hasMatchingSignature: existing.query.signature == query.signature
           ) {
            let count = records.count
            lock.unlock()
            AUOuterStretchOSCPreviewDebugLog.record(
                "cache_store_skipped_lower_quality source=\(AUOuterStretchOSCPreviewDebugLog.describe(sourceID)) " +
                "\(AUOuterStretchOSCPreviewDebugLog.describe(query)) " +
                "candidate_output=\(Int(entry.renderOutputSize.width))x\(Int(entry.renderOutputSize.height)) " +
                "candidate_texture=\(entry.texture.width)x\(entry.texture.height) " +
                "existing_output=\(Int(existing.entry.renderOutputSize.width))x\(Int(existing.entry.renderOutputSize.height)) " +
                "existing_texture=\(existing.entry.texture.width)x\(existing.entry.texture.height) records=\(count)"
            )
            return
        }
        records[sourceID] = Record(query: query, entry: entry, storedAt: now)
        if records.count > maximumRecordCount,
           let oldest = records.min(by: { $0.value.storedAt < $1.value.storedAt })?.key {
            records.removeValue(forKey: oldest)
        }
        let count = records.count
        lock.unlock()
        AUOuterStretchOSCPreviewDebugLog.record(
            "cache_store source=\(AUOuterStretchOSCPreviewDebugLog.describe(sourceID)) " +
            "\(AUOuterStretchOSCPreviewDebugLog.describe(query)) " +
            "output=\(Int(entry.renderOutputSize.width))x\(Int(entry.renderOutputSize.height)) " +
            "texture=\(entry.texture.width)x\(entry.texture.height) records=\(count)"
        )
    }

    func entry(
        matching query: AUOuterStretchOSCPreviewQuery,
        deviceRegistryID: UInt64
    ) -> AUOuterStretchOSCPreviewEntry? {
        lock.lock()
        let exactMatches = records.values.filter {
            CMTimeCompare($0.query.renderTime, query.renderTime) == 0
                && $0.query.signature == query.signature
                && $0.entry.texture.device.registryID == deviceRegistryID
        }
        let result: AUOuterStretchOSCPreviewEntry?
        let resultKind: String
        if exactMatches.count == 1 {
            result = exactMatches[0].entry
            resultKind = "hit"
        } else if records.count == 1,
                  let stale = records.values.first,
                  CMTimeCompare(stale.query.renderTime, query.renderTime) == 0,
                  stale.entry.texture.device.registryID == deviceRegistryID {
            // Motion can request OSC before the current low-resolution Warp
            // render has completed. Keep the last completed preview visible
            // rather than clearing the texture for one host callback.
            result = stale.entry
            resultKind = "stale"
        } else {
            result = nil
            resultKind = "miss"
        }
        let count = records.count
        let resultSize = result.map { "\($0.texture.width)x\($0.texture.height)" } ?? "none"
        lock.unlock()
        AUOuterStretchOSCPreviewDebugLog.record(
            "cache_lookup \(AUOuterStretchOSCPreviewDebugLog.describe(query)) " +
            "result=\(resultKind) texture=\(resultSize) records=\(count)"
        )
        return result
    }

    func remove(sourceID: ObjectIdentifier) {
        lock.lock()
        let removed = records.removeValue(forKey: sourceID) != nil
        lock.unlock()
        AUOuterStretchOSCPreviewDebugLog.record(
            "cache_remove source=\(AUOuterStretchOSCPreviewDebugLog.describe(sourceID)) " +
            "removed=\(removed ? 1 : 0)"
        )
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
