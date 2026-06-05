//
//  AnyUprightOSCOverlayRenderer.swift
//  AnyUpright
//

import Foundation
import Metal

struct AUOSCOverlayStyle {
    var lineColor = SIMD4<Float>(1.0, 1.0, 1.0, 0.95)
    var shadowColor = SIMD4<Float>(0.0, 0.0, 0.0, 0.65)
    var dimOutsideColor = SIMD4<Float>(0.0, 0.0, 0.0, 0.30)
    var handleColor = SIMD4<Float>(0.18, 0.44, 1.0, 0.95)
    var activeHandleColor = SIMD4<Float>(1.0, 0.85, 0.25, 1.0)
    var lineThickness: Double = 2.0
    var handleRadius: Double = 7.0
}

struct AUOSCHandle {
    var point: AUPoint
    var part: Int
}

struct AUOSCStyledSegment {
    var start: AUPoint
    var end: AUPoint
    var style: AUOSCOverlayStyle
}

final class AnyUprightOSCOverlayRenderer {
    private struct PipelineKey: Hashable {
        var registryID: UInt64
        var pixelFormat: MTLPixelFormat
    }

    private static var pipelineCache: [PipelineKey: MTLRenderPipelineState] = [:]
    private static let pipelineLock = NSLock()

    func renderQuad(
        points: [AUPoint],
        handles: [AUOSCHandle],
        activePart: Int,
        destinationImage: FxImageTile,
        style: AUOSCOverlayStyle = AUOSCOverlayStyle()
    ) {
        guard points.count >= 2 else {
            return
        }

        let segments = points.indices.map { index -> (AUPoint, AUPoint) in
            let nextIndex = index == points.index(before: points.endIndex) ? points.startIndex : points.index(after: index)
            return (points[index], points[nextIndex])
        }

        renderSegments(
            segments,
            handles: handles,
            activePart: activePart,
            destinationImage: destinationImage,
            style: style
        )
    }

    func renderQuadAdjuster(
        points: [AUPoint],
        handles: [AUOSCHandle],
        activePart: Int,
        destinationImage: FxImageTile,
        style: AUOSCOverlayStyle = AUOSCOverlayStyle()
    ) {
        guard points.count == 4 else {
            renderQuad(
                points: points,
                handles: handles,
                activePart: activePart,
                destinationImage: destinationImage,
                style: style
            )
            return
        }

        let segments = points.indices.map { index -> (AUPoint, AUPoint) in
            let nextIndex = index == points.index(before: points.endIndex) ? points.startIndex : points.index(after: index)
            return (points[index], points[nextIndex])
        }

        renderStyledSegments(
            segments.map { AUOSCStyledSegment(start: $0.0, end: $0.1, style: style) },
            handles: handles,
            activePart: activePart,
            destinationImage: destinationImage,
            handleStyle: style,
            dimmingQuads: outsideDimmingQuads(around: points)
        )
    }

    func renderSegments(
        _ segments: [(AUPoint, AUPoint)],
        handles: [AUOSCHandle],
        activePart: Int,
        destinationImage: FxImageTile,
        style: AUOSCOverlayStyle = AUOSCOverlayStyle()
    ) {
        renderStyledSegments(
            segments.map { AUOSCStyledSegment(start: $0.0, end: $0.1, style: style) },
            handles: handles,
            activePart: activePart,
            destinationImage: destinationImage,
            handleStyle: style
        )
    }

    func renderStyledSegments(
        _ segments: [AUOSCStyledSegment],
        handles: [AUOSCHandle],
        activePart: Int,
        destinationImage: FxImageTile,
        handleStyle: AUOSCOverlayStyle = AUOSCOverlayStyle(),
        dimmingQuads: [[AUPoint]] = []
    ) {
        guard !segments.isEmpty || !handles.isEmpty else {
            return
        }

        let pixelFormat = MetalDeviceCache.FxMTLPixelFormat(for: destinationImage)
        let deviceCache = MetalDeviceCache.deviceCache
        guard let device = deviceCache.device(with: destinationImage.deviceRegistryID),
              let outputTexture = destinationImage.metalTexture(for: device),
              let commandQueue = device.makeCommandQueue(),
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let pipelineState = pipelineState(device: device, pixelFormat: pixelFormat) else {
            return
        }

        let tileBounds = destinationImage.tilePixelBounds
        let width = max(1.0, Double(tileBounds.right - tileBounds.left))
        let height = max(1.0, Double(tileBounds.top - tileBounds.bottom))
        var vertices: [AnyUprightOverlayVertex2D] = []

        for quad in dimmingQuads where quad.count == 4 {
            appendObjectQuad(quad, color: handleStyle.dimOutsideColor, width: width, height: height, to: &vertices)
        }
        for segment in segments {
            appendLine(
                from: segment.start,
                to: segment.end,
                color: segment.style.shadowColor,
                thickness: segment.style.lineThickness + 2.0,
                width: width,
                height: height,
                to: &vertices
            )
        }
        for segment in segments {
            appendLine(
                from: segment.start,
                to: segment.end,
                color: segment.style.lineColor,
                thickness: segment.style.lineThickness,
                width: width,
                height: height,
                to: &vertices
            )
        }
        for handle in handles {
            let color = handle.part == activePart ? handleStyle.activeHandleColor : handleStyle.handleColor
            appendSquare(center: handle.point, radius: handleStyle.handleRadius + 2.0, color: handleStyle.shadowColor, width: width, height: height, to: &vertices)
            appendSquare(center: handle.point, radius: handleStyle.handleRadius, color: color, width: width, height: height, to: &vertices)
        }

        guard !vertices.isEmpty else {
            return
        }

        let colorAttachment = MTLRenderPassColorAttachmentDescriptor()
        colorAttachment.texture = outputTexture
        colorAttachment.clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 0.0)
        colorAttachment.loadAction = .clear
        colorAttachment.storeAction = .store

        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0] = colorAttachment

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            return
        }

        var viewportSize = simd_uint2(UInt32(width), UInt32(height))
        let viewport = MTLViewport(originX: 0.0, originY: 0.0, width: width, height: height, znear: -1.0, zfar: 1.0)
        encoder.setViewport(viewport)
        encoder.setRenderPipelineState(pipelineState)
        encoder.setVertexBytes(&vertices, length: MemoryLayout<AnyUprightOverlayVertex2D>.stride * vertices.count, index: Int(AUVII_Vertices.rawValue))
        encoder.setVertexBytes(&viewportSize, length: MemoryLayout.size(ofValue: viewportSize), index: Int(AUVII_ViewportSize.rawValue))
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertices.count)
        encoder.endEncoding()

        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }

    private func outsideDimmingQuads(around points: [AUPoint]) -> [[AUPoint]] {
        let topLeft = points[0]
        let topRight = points[1]
        let bottomRight = points[2]
        let bottomLeft = points[3]

        let frameTopLeft = AUPoint(x: 0.0, y: 1.0)
        let frameTopRight = AUPoint(x: 1.0, y: 1.0)
        let frameBottomRight = AUPoint(x: 1.0, y: 0.0)
        let frameBottomLeft = AUPoint(x: 0.0, y: 0.0)

        return [
            [frameTopLeft, frameTopRight, topRight, topLeft],
            [frameTopRight, frameBottomRight, bottomRight, topRight],
            [frameBottomRight, frameBottomLeft, bottomLeft, bottomRight],
            [frameBottomLeft, frameTopLeft, topLeft, bottomLeft]
        ]
    }

    private func pipelineState(device: MTLDevice, pixelFormat: MTLPixelFormat) -> MTLRenderPipelineState? {
        let key = PipelineKey(registryID: device.registryID, pixelFormat: pixelFormat)

        Self.pipelineLock.lock()
        if let cached = Self.pipelineCache[key] {
            Self.pipelineLock.unlock()
            return cached
        }
        Self.pipelineLock.unlock()

        guard let library = device.makeDefaultLibrary(),
              let vertexFunction = library.makeFunction(name: "anyUprightOverlayVertex"),
              let fragmentFunction = library.makeFunction(name: "anyUprightOverlayFragment") else {
            return nil
        }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = "AnyUprightOSCOverlay"
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.colorAttachments[0].pixelFormat = pixelFormat
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].rgbBlendOperation = .add
        descriptor.colorAttachments[0].alphaBlendOperation = .add
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha

        do {
            let pipelineState = try device.makeRenderPipelineState(descriptor: descriptor)
            Self.pipelineLock.lock()
            Self.pipelineCache[key] = pipelineState
            Self.pipelineLock.unlock()
            return pipelineState
        } catch {
            NSLog("Unable to create AnyUpright OSC overlay pipeline: %@", String(describing: error))
            return nil
        }
    }

    private func appendLine(
        from start: AUPoint,
        to end: AUPoint,
        color: SIMD4<Float>,
        thickness: Double,
        width: Double,
        height: Double,
        to vertices: inout [AnyUprightOverlayVertex2D]
    ) {
        let startPixel = SIMD2<Double>(start.x * width, start.y * height)
        let endPixel = SIMD2<Double>(end.x * width, end.y * height)
        let delta = endPixel - startPixel
        let length = max(0.0001, hypot(delta.x, delta.y))
        let normal = SIMD2<Double>(-delta.y / length, delta.x / length) * (thickness / 2.0)

        appendQuad(
            p0: startPixel + normal,
            p1: endPixel + normal,
            p2: endPixel - normal,
            p3: startPixel - normal,
            color: color,
            width: width,
            height: height,
            to: &vertices
        )
    }

    private func appendSquare(
        center: AUPoint,
        radius: Double,
        color: SIMD4<Float>,
        width: Double,
        height: Double,
        to vertices: inout [AnyUprightOverlayVertex2D]
    ) {
        let centerPixel = SIMD2<Double>(center.x * width, center.y * height)
        appendQuad(
            p0: centerPixel + SIMD2<Double>(-radius, -radius),
            p1: centerPixel + SIMD2<Double>(radius, -radius),
            p2: centerPixel + SIMD2<Double>(radius, radius),
            p3: centerPixel + SIMD2<Double>(-radius, radius),
            color: color,
            width: width,
            height: height,
            to: &vertices
        )
    }

    private func appendObjectQuad(
        _ points: [AUPoint],
        color: SIMD4<Float>,
        width: Double,
        height: Double,
        to vertices: inout [AnyUprightOverlayVertex2D]
    ) {
        let pixels = points.map { SIMD2<Double>($0.x * width, $0.y * height) }
        appendQuad(
            p0: pixels[0],
            p1: pixels[1],
            p2: pixels[2],
            p3: pixels[3],
            color: color,
            width: width,
            height: height,
            to: &vertices
        )
    }

    private func appendQuad(
        p0: SIMD2<Double>,
        p1: SIMD2<Double>,
        p2: SIMD2<Double>,
        p3: SIMD2<Double>,
        color: SIMD4<Float>,
        width: Double,
        height: Double,
        to vertices: inout [AnyUprightOverlayVertex2D]
    ) {
        let converted = [p0, p1, p2, p0, p2, p3].map { point in
            AnyUprightOverlayVertex2D(
                position: SIMD2<Float>(
                    Float(point.x - width / 2.0),
                    Float(point.y - height / 2.0)
                ),
                color: color
            )
        }
        vertices.append(contentsOf: converted)
    }
}
