//
//  AnyUprightOSCOverlayRenderer.swift
//  AnyUpright
//

import Foundation
import IOSurface
import Metal

enum AUOSCOverlayHandleShape {
    case square
    case circle
}

struct AUOSCOverlayStyle {
    var lineColor = SIMD4<Float>(1.0, 1.0, 1.0, 1.0)
    var shadowColor = SIMD4<Float>(0.0, 0.0, 0.0, 0.75)
    var dimOutsideColor = SIMD4<Float>(0.0, 0.0, 0.0, 0.30)
    var handleColor = SIMD4<Float>(0.0, 0.55, 1.0, 1.0)
    var activeHandleColor = SIMD4<Float>(1.0, 0.85, 0.25, 1.0)
    var lineThickness: Double = 3.0
    var handleRadius: Double = 15.0
    var handleShape: AUOSCOverlayHandleShape = .square
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

private struct AUOSCOverlayPixelFrame {
    var minX: Double
    var minY: Double
    var maxX: Double
    var maxY: Double

    var width: Double {
        max(1.0, maxX - minX)
    }

    var height: Double {
        max(1.0, maxY - minY)
    }
}

enum AUOSCOverlayCoordinateSpace {
    case normalized
    case pixels
}

final class AnyUprightOSCOverlayRenderer {
    private struct PipelineKey: Hashable {
        var registryID: UInt64
        var pixelFormat: MTLPixelFormat
    }

    private static var pipelineCache: [PipelineKey: MTLRenderPipelineState] = [:]
    private static let pipelineLock = NSLock()

    func clear(destinationImage: FxImageTile) {
        let deviceCache = MetalDeviceCache.deviceCache
        guard let device = deviceCache.device(with: destinationImage.deviceRegistryID) ?? MTLCreateSystemDefaultDevice(),
              let outputTexture = destinationImage.metalTexture(for: device),
              let commandQueue = device.makeCommandQueue(),
              let commandBuffer = commandQueue.makeCommandBuffer() else {
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

        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }

    func renderQuad(
        points: [AUPoint],
        handles: [AUOSCHandle],
        activePart: Int,
        destinationImage: FxImageTile,
        destinationSize: AUSize? = nil,
        canvasFrame: [AUPoint]? = nil,
        coordinateSpace: AUOSCOverlayCoordinateSpace = .normalized,
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
            destinationSize: destinationSize,
            canvasFrame: canvasFrame,
            coordinateSpace: coordinateSpace,
            style: style
        )
    }

    func renderQuadAdjuster(
        points: [AUPoint],
        handles: [AUOSCHandle],
        activePart: Int,
        destinationImage: FxImageTile,
        destinationSize: AUSize? = nil,
        canvasFrame: [AUPoint]? = nil,
        coordinateSpace: AUOSCOverlayCoordinateSpace = .normalized,
        dimmingFrame: [AUPoint]? = nil,
        style: AUOSCOverlayStyle = AUOSCOverlayStyle()
    ) {
        guard points.count == 4 else {
            renderQuad(
                points: points,
                handles: handles,
                activePart: activePart,
                destinationImage: destinationImage,
                destinationSize: destinationSize,
                canvasFrame: canvasFrame,
                coordinateSpace: coordinateSpace,
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
            destinationSize: destinationSize,
            canvasFrame: canvasFrame,
            coordinateSpace: coordinateSpace,
            handleStyle: style,
            dimmingQuads: outsideDimmingQuads(around: points, frame: dimmingFrame)
        )
    }

    func renderSegments(
        _ segments: [(AUPoint, AUPoint)],
        handles: [AUOSCHandle],
        activePart: Int,
        destinationImage: FxImageTile,
        destinationSize: AUSize? = nil,
        canvasFrame: [AUPoint]? = nil,
        coordinateSpace: AUOSCOverlayCoordinateSpace = .normalized,
        style: AUOSCOverlayStyle = AUOSCOverlayStyle()
    ) {
        renderStyledSegments(
            segments.map { AUOSCStyledSegment(start: $0.0, end: $0.1, style: style) },
            handles: handles,
            activePart: activePart,
            destinationImage: destinationImage,
            destinationSize: destinationSize,
            canvasFrame: canvasFrame,
            coordinateSpace: coordinateSpace,
            handleStyle: style
        )
    }

    func renderStyledSegments(
        _ segments: [AUOSCStyledSegment],
        handles: [AUOSCHandle],
        activePart: Int,
        destinationImage: FxImageTile,
        destinationSize: AUSize? = nil,
        canvasFrame: [AUPoint]? = nil,
        coordinateSpace: AUOSCOverlayCoordinateSpace = .normalized,
        handleStyle: AUOSCOverlayStyle = AUOSCOverlayStyle(),
        dimmingQuads: [[AUPoint]] = []
    ) {
        guard !segments.isEmpty || !handles.isEmpty else {
            return
        }

        let deviceCache = MetalDeviceCache.deviceCache
        guard let device = deviceCache.device(with: destinationImage.deviceRegistryID) ?? MTLCreateSystemDefaultDevice() else {
            return
        }
        guard let outputTexture = destinationImage.metalTexture(for: device) else {
            return
        }
        guard let commandQueue = device.makeCommandQueue(),
              let commandBuffer = commandQueue.makeCommandBuffer() else {
            return
        }

        guard let pipelineState = pipelineState(device: device, pixelFormat: outputTexture.pixelFormat) else {
            return
        }

        let surfaceWidth = max(1.0, Double(destinationImage.ioSurface.map { IOSurfaceGetWidth($0) } ?? outputTexture.width))
        let surfaceHeight = max(1.0, Double(destinationImage.ioSurface.map { IOSurfaceGetHeight($0) } ?? outputTexture.height))
        let width = surfaceWidth
        let height = surfaceHeight
        let coordinateFrame = pixelFrame(
            for: destinationImage,
            destinationSize: destinationSize,
            canvasFrame: canvasFrame,
            coordinateSpace: coordinateSpace,
            textureWidth: width,
            textureHeight: height
        )
        let coordinateSize = AUSize(width: coordinateFrame.width, height: coordinateFrame.height)
        var vertices: [AnyUprightOverlayVertex2D] = []

        for quad in dimmingQuads where quad.count == 4 {
            appendCoordinateQuad(quad, color: handleStyle.dimOutsideColor, coordinateSpace: coordinateSpace, coordinateSize: coordinateSize, pixelFrame: coordinateFrame, width: width, height: height, to: &vertices)
        }
        for segment in segments {
            appendLine(
                from: segment.start,
                to: segment.end,
                color: segment.style.shadowColor,
                thickness: segment.style.lineThickness + 2.0,
                coordinateSpace: coordinateSpace,
                coordinateSize: coordinateSize,
                pixelFrame: coordinateFrame,
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
                coordinateSpace: coordinateSpace,
                coordinateSize: coordinateSize,
                pixelFrame: coordinateFrame,
                width: width,
                height: height,
                to: &vertices
            )
        }
        for handle in handles {
            let color = handle.part == activePart ? handleStyle.activeHandleColor : handleStyle.handleColor
            appendHandle(center: handle.point, radius: handleStyle.handleRadius + 2.0, color: handleStyle.shadowColor, shape: handleStyle.handleShape, coordinateSpace: coordinateSpace, coordinateSize: coordinateSize, pixelFrame: coordinateFrame, width: width, height: height, to: &vertices)
            appendHandle(center: handle.point, radius: handleStyle.handleRadius, color: color, shape: handleStyle.handleShape, coordinateSpace: coordinateSpace, coordinateSize: coordinateSize, pixelFrame: coordinateFrame, width: width, height: height, to: &vertices)
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

    private func outsideDimmingQuads(around points: [AUPoint], frame: [AUPoint]? = nil) -> [[AUPoint]] {
        let topLeft = points[0]
        let topRight = points[1]
        let bottomRight = points[2]
        let bottomLeft = points[3]

        let framePoints = frame?.count == 4 ? frame! : [
            AUPoint(x: 0.0, y: 1.0),
            AUPoint(x: 1.0, y: 1.0),
            AUPoint(x: 1.0, y: 0.0),
            AUPoint(x: 0.0, y: 0.0)
        ]
        let frameTopLeft = framePoints[0]
        let frameTopRight = framePoints[1]
        let frameBottomRight = framePoints[2]
        let frameBottomLeft = framePoints[3]

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
        coordinateSpace: AUOSCOverlayCoordinateSpace,
        coordinateSize: AUSize,
        pixelFrame: AUOSCOverlayPixelFrame,
        width: Double,
        height: Double,
        to vertices: inout [AnyUprightOverlayVertex2D]
    ) {
        let startPixel = localPixel(from: start, coordinateSpace: coordinateSpace, coordinateSize: coordinateSize, pixelFrame: pixelFrame, width: width, height: height)
        let endPixel = localPixel(from: end, coordinateSpace: coordinateSpace, coordinateSize: coordinateSize, pixelFrame: pixelFrame, width: width, height: height)
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
        coordinateSpace: AUOSCOverlayCoordinateSpace,
        coordinateSize: AUSize,
        pixelFrame: AUOSCOverlayPixelFrame,
        width: Double,
        height: Double,
        to vertices: inout [AnyUprightOverlayVertex2D]
    ) {
        let centerPixel = localPixel(from: center, coordinateSpace: coordinateSpace, coordinateSize: coordinateSize, pixelFrame: pixelFrame, width: width, height: height)
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

    private func appendHandle(
        center: AUPoint,
        radius: Double,
        color: SIMD4<Float>,
        shape: AUOSCOverlayHandleShape,
        coordinateSpace: AUOSCOverlayCoordinateSpace,
        coordinateSize: AUSize,
        pixelFrame: AUOSCOverlayPixelFrame,
        width: Double,
        height: Double,
        to vertices: inout [AnyUprightOverlayVertex2D]
    ) {
        switch shape {
        case .square:
            appendSquare(
                center: center,
                radius: radius,
                color: color,
                coordinateSpace: coordinateSpace,
                coordinateSize: coordinateSize,
                pixelFrame: pixelFrame,
                width: width,
                height: height,
                to: &vertices
            )
        case .circle:
            appendCircle(
                center: center,
                radius: radius,
                color: color,
                coordinateSpace: coordinateSpace,
                coordinateSize: coordinateSize,
                pixelFrame: pixelFrame,
                width: width,
                height: height,
                to: &vertices
            )
        }
    }

    private func appendCircle(
        center: AUPoint,
        radius: Double,
        color: SIMD4<Float>,
        coordinateSpace: AUOSCOverlayCoordinateSpace,
        coordinateSize: AUSize,
        pixelFrame: AUOSCOverlayPixelFrame,
        width: Double,
        height: Double,
        to vertices: inout [AnyUprightOverlayVertex2D]
    ) {
        let centerPixel = localPixel(from: center, coordinateSpace: coordinateSpace, coordinateSize: coordinateSize, pixelFrame: pixelFrame, width: width, height: height)
        let segmentCount = 48

        for index in 0..<segmentCount {
            let angle0 = Double(index) / Double(segmentCount) * Double.pi * 2.0
            let angle1 = Double(index + 1) / Double(segmentCount) * Double.pi * 2.0
            let p0 = centerPixel
            let p1 = centerPixel + SIMD2<Double>(cos(angle0) * radius, sin(angle0) * radius)
            let p2 = centerPixel + SIMD2<Double>(cos(angle1) * radius, sin(angle1) * radius)
            appendTriangle(p0: p0, p1: p1, p2: p2, color: color, width: width, height: height, to: &vertices)
        }
    }

    private func appendCoordinateQuad(
        _ points: [AUPoint],
        color: SIMD4<Float>,
        coordinateSpace: AUOSCOverlayCoordinateSpace,
        coordinateSize: AUSize,
        pixelFrame: AUOSCOverlayPixelFrame,
        width: Double,
        height: Double,
        to vertices: inout [AnyUprightOverlayVertex2D]
    ) {
        let pixels = points.map { localPixel(from: $0, coordinateSpace: coordinateSpace, coordinateSize: coordinateSize, pixelFrame: pixelFrame, width: width, height: height) }
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

    private func localPixel(
        from point: AUPoint,
        coordinateSpace: AUOSCOverlayCoordinateSpace,
        coordinateSize: AUSize,
        pixelFrame: AUOSCOverlayPixelFrame,
        width: Double,
        height: Double
    ) -> SIMD2<Double> {
        switch coordinateSpace {
        case .normalized:
            return SIMD2<Double>(point.x * width, point.y * height)
        case .pixels:
            let normalizedX = (point.x - pixelFrame.minX) / max(coordinateSize.width, 1.0)
            let normalizedY = (point.y - pixelFrame.minY) / max(coordinateSize.height, 1.0)
            return SIMD2<Double>(normalizedX * width, normalizedY * height)
        }
    }

    private func pixelFrame(
        for destinationImage: FxImageTile,
        destinationSize: AUSize?,
        canvasFrame: [AUPoint]?,
        coordinateSpace: AUOSCOverlayCoordinateSpace,
        textureWidth: Double,
        textureHeight: Double
    ) -> AUOSCOverlayPixelFrame {
        if coordinateSpace == .pixels {
            if let canvasFrame = canvasFrameFromPoints(canvasFrame) {
                return canvasFrame
            }

            return AUOSCOverlayPixelFrame(
                minX: 0.0,
                minY: 0.0,
                maxX: textureWidth,
                maxY: textureHeight
            )
        }

        let imageFrame = pixelFrame(for: destinationImage.imagePixelBounds)
        if imageFrame.width > 1.0, imageFrame.height > 1.0 {
            return imageFrame
        }

        return AUOSCOverlayPixelFrame(
            minX: 0.0,
            minY: 0.0,
            maxX: max(1.0, destinationSize?.width ?? 1.0),
            maxY: max(1.0, destinationSize?.height ?? 1.0)
        )
    }

    private func canvasFrameFromPoints(_ points: [AUPoint]?) -> AUOSCOverlayPixelFrame? {
        guard let points, points.count >= 2 else {
            return nil
        }

        let xs = points.map(\.x)
        let ys = points.map(\.y)
        guard let minX = xs.min(),
              let maxX = xs.max(),
              let minY = ys.min(),
              let maxY = ys.max(),
              maxX - minX > 1.0,
              maxY - minY > 1.0 else {
            return nil
        }

        return AUOSCOverlayPixelFrame(minX: minX, minY: minY, maxX: maxX, maxY: maxY)
    }

    private func pixelFrame(for rect: FxRect) -> AUOSCOverlayPixelFrame {
        AUOSCOverlayPixelFrame(
            minX: Double(rect.left),
            minY: Double(rect.bottom),
            maxX: Double(rect.right),
            maxY: Double(rect.top)
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

    private func appendTriangle(
        p0: SIMD2<Double>,
        p1: SIMD2<Double>,
        p2: SIMD2<Double>,
        color: SIMD4<Float>,
        width: Double,
        height: Double,
        to vertices: inout [AnyUprightOverlayVertex2D]
    ) {
        let converted = [p0, p1, p2].map { point in
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
