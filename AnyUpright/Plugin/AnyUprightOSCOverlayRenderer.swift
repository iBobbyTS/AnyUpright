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

    var center: SIMD2<Double> {
        SIMD2<Double>((minX + maxX) / 2.0, (minY + maxY) / 2.0)
    }

    var coordinateFrame: AUCoordinateFrame {
        AUCoordinateFrame(minX: minX, minY: minY, maxX: maxX, maxY: maxY)
    }

    init(_ coordinateFrame: AUCoordinateFrame) {
        self.minX = coordinateFrame.minX
        self.minY = coordinateFrame.minY
        self.maxX = coordinateFrame.maxX
        self.maxY = coordinateFrame.maxY
    }

    init(minX: Double, minY: Double, maxX: Double, maxY: Double) {
        self.minX = minX
        self.minY = minY
        self.maxX = maxX
        self.maxY = maxY
    }
}

enum AUOSCOverlayCoordinateSpace {
    case normalized
    case pixels
    case canvasFramePixels
}

final class AnyUprightOSCOverlayRenderer {
    private enum OverlayPrimitiveKind: Float {
        case fill = 0.0
        case rect = 1.0
        case circle = 2.0
    }

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
        dimmingQuads: [[AUPoint]] = [],
        debugLog: ((String) -> Void)? = nil
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

        let ioSurfaceWidth = destinationImage.ioSurface.map { IOSurfaceGetWidth($0) }
        let ioSurfaceHeight = destinationImage.ioSurface.map { IOSurfaceGetHeight($0) }
        let surfaceWidth = max(1.0, Double(ioSurfaceWidth ?? outputTexture.width))
        let surfaceHeight = max(1.0, Double(ioSurfaceHeight ?? outputTexture.height))
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

        debugOverlayRenderTarget(
            destinationImage: destinationImage,
            destinationSize: destinationSize,
            canvasFrame: canvasFrame,
            coordinateSpace: coordinateSpace,
            coordinateFrame: coordinateFrame,
            width: width,
            height: height,
            ioSurfaceWidth: ioSurfaceWidth,
            ioSurfaceHeight: ioSurfaceHeight,
            textureWidth: outputTexture.width,
            textureHeight: outputTexture.height,
            pixelFormat: outputTexture.pixelFormat.rawValue,
            log: debugLog
        )
        debugOverlayMapping(
            segments: segments,
            handles: handles,
            coordinateSpace: coordinateSpace,
            coordinateFrame: coordinateFrame,
            coordinateSize: coordinateSize,
            width: width,
            height: height,
            log: debugLog
        )

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

        debugOverlayVertexSummary(vertices: vertices, width: width, height: height, log: debugLog)

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
        let vertexBufferLength = MemoryLayout<AnyUprightOverlayVertex2D>.stride * vertices.count
        guard let vertexBuffer = device.makeBuffer(bytes: vertices, length: vertexBufferLength, options: .storageModeShared) else {
            return
        }
        let viewport = MTLViewport(originX: 0.0, originY: 0.0, width: width, height: height, znear: -1.0, zfar: 1.0)
        encoder.setViewport(viewport)
        encoder.setRenderPipelineState(pipelineState)
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: Int(AUVII_Vertices.rawValue))
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
        let axis = SIMD2<Double>(delta.x / length, delta.y / length)
        let normal = SIMD2<Double>(-axis.y, axis.x)
        let halfLength = length / 2.0
        let halfThickness = thickness / 2.0
        let padding = antialiasPadding()
        let centerPixel = (startPixel + endPixel) / 2.0
        let metalStart = metalCenteredPixel(startPixel, width: width, height: height)
        let metalEnd = metalCenteredPixel(endPixel, width: width, height: height)
        let metalDelta = metalEnd - metalStart
        let metalLength = max(0.0001, hypot(metalDelta.x, metalDelta.y))
        let metalAxis = SIMD2<Float>(Float(metalDelta.x / metalLength), Float(metalDelta.y / metalLength))

        appendPrimitiveQuad(
            p0: centerPixel - axis * (halfLength + padding) + normal * (halfThickness + padding),
            p1: centerPixel + axis * (halfLength + padding) + normal * (halfThickness + padding),
            p2: centerPixel + axis * (halfLength + padding) - normal * (halfThickness + padding),
            p3: centerPixel - axis * (halfLength + padding) - normal * (halfThickness + padding),
            color: color,
            primitiveOrigin: metalCenteredPixel(centerPixel, width: width, height: height),
            primitiveAxis: metalAxis,
            primitiveSize: SIMD2<Float>(Float(halfLength), Float(halfThickness)),
            primitiveKind: .rect,
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
        let padding = antialiasPadding()
        appendPrimitiveQuad(
            p0: centerPixel + SIMD2<Double>(-(radius + padding), -(radius + padding)),
            p1: centerPixel + SIMD2<Double>(radius + padding, -(radius + padding)),
            p2: centerPixel + SIMD2<Double>(radius + padding, radius + padding),
            p3: centerPixel + SIMD2<Double>(-(radius + padding), radius + padding),
            color: color,
            primitiveOrigin: metalCenteredPixel(centerPixel, width: width, height: height),
            primitiveAxis: SIMD2<Float>(1.0, 0.0),
            primitiveSize: SIMD2<Float>(Float(radius), Float(radius)),
            primitiveKind: .rect,
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
        let padding = antialiasPadding()
        appendPrimitiveQuad(
            p0: centerPixel + SIMD2<Double>(-(radius + padding), -(radius + padding)),
            p1: centerPixel + SIMD2<Double>(radius + padding, -(radius + padding)),
            p2: centerPixel + SIMD2<Double>(radius + padding, radius + padding),
            p3: centerPixel + SIMD2<Double>(-(radius + padding), radius + padding),
            color: color,
            primitiveOrigin: metalCenteredPixel(centerPixel, width: width, height: height),
            primitiveAxis: SIMD2<Float>(1.0, 0.0),
            primitiveSize: SIMD2<Float>(Float(radius), 0.0),
            primitiveKind: .circle,
            width: width,
            height: height,
            to: &vertices
        )
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
        appendPrimitiveQuad(
            p0: pixels[0],
            p1: pixels[1],
            p2: pixels[2],
            p3: pixels[3],
            color: color,
            primitiveOrigin: SIMD2<Float>(0.0, 0.0),
            primitiveAxis: SIMD2<Float>(1.0, 0.0),
            primitiveSize: SIMD2<Float>(0.0, 0.0),
            primitiveKind: .fill,
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
        case .canvasFramePixels:
            let surfacePixel = oscSurfacePixel(
                fromHostCanvasPixel: point,
                surfaceSize: AUSize(width: width, height: height)
            )
            return SIMD2<Double>(surfacePixel.x, surfacePixel.y)
        }
    }

    private func debugOverlayMapping(
        segments: [AUOSCStyledSegment],
        handles: [AUOSCHandle],
        coordinateSpace: AUOSCOverlayCoordinateSpace,
        coordinateFrame: AUOSCOverlayPixelFrame,
        coordinateSize: AUSize,
        width: Double,
        height: Double,
        log: ((String) -> Void)?
    ) {
        guard let log else {
            return
        }

        var points: [(String, AUPoint)] = []
        for (index, handle) in handles.enumerated() {
            points.append(("h\(index + 1)/part\(handle.part)", handle.point))
        }
        for (index, segment) in segments.prefix(4).enumerated() {
            points.append(("s\(index + 1)a", segment.start))
            points.append(("s\(index + 1)b", segment.end))
        }

        var seen = Set<String>()
        let mappings = points.compactMap { label, point -> String? in
            let key = String(format: "%.3f,%.3f", point.x, point.y)
            guard seen.insert(key).inserted else {
                return nil
            }

            let pixel = localPixel(
                from: point,
                coordinateSpace: coordinateSpace,
                coordinateSize: coordinateSize,
                pixelFrame: coordinateFrame,
                width: width,
                height: height
            )
            let direct = oscSurfacePixel(fromHostCanvasPixel: point, surfaceSize: AUSize(width: width, height: height))
            let frameLocal = frameLocalPixel(from: point, pixelFrame: coordinateFrame, width: width, height: height, flipsY: false)
            let frameLocalFlipped = frameLocalPixel(from: point, pixelFrame: coordinateFrame, width: width, height: height, flipsY: true)
            let centerRelative = centerRelativePixel(from: point, pixelFrame: coordinateFrame, width: width, height: height)
            let centered = metalCenteredPixel(pixel, width: width, height: height)
            let clip = clipSpacePosition(fromCenteredPixel: centered, width: width, height: height)
            return String(
                format: "%@ in=(%.2f,%.2f) local=(%.2f,%.2f) direct=(%.2f,%.2f) frameLocal=(%.2f,%.2f) frameLocalFlipY=(%.2f,%.2f) centerRel=(%.2f,%.2f) centered=(%.2f,%.2f) clip=(%.5f,%.5f)",
                label,
                point.x,
                point.y,
                pixel.x,
                pixel.y,
                direct.x,
                direct.y,
                frameLocal.x,
                frameLocal.y,
                frameLocalFlipped.x,
                frameLocalFlipped.y,
                centerRelative.x,
                centerRelative.y,
                centered.x,
                centered.y,
                clip.x,
                clip.y
            )
        }
        let frameDescription = String(
            format: "coordSpace=%@ coordFrame=(%.2f,%.2f,%.2f,%.2f) coordCenter=(%.2f,%.2f) coordSize=(%.2f,%.2f) surface=(%.2f,%.2f)",
            debugDescription(of: coordinateSpace),
            coordinateFrame.minX,
            coordinateFrame.minY,
            coordinateFrame.maxX,
            coordinateFrame.maxY,
            coordinateFrame.center.x,
            coordinateFrame.center.y,
            coordinateSize.width,
            coordinateSize.height,
            width,
            height
        )
        log("overlay-map \(frameDescription) \(mappings.joined(separator: " | "))")

        debugOverlayPrimitiveSamples(
            segments: segments,
            handles: handles,
            coordinateSpace: coordinateSpace,
            coordinateSize: coordinateSize,
            pixelFrame: coordinateFrame,
            width: width,
            height: height,
            log: log
        )
    }

    private func debugOverlayRenderTarget(
        destinationImage: FxImageTile,
        destinationSize: AUSize?,
        canvasFrame: [AUPoint]?,
        coordinateSpace: AUOSCOverlayCoordinateSpace,
        coordinateFrame: AUOSCOverlayPixelFrame,
        width: Double,
        height: Double,
        ioSurfaceWidth: Int?,
        ioSurfaceHeight: Int?,
        textureWidth: Int,
        textureHeight: Int,
        pixelFormat: UInt,
        log: ((String) -> Void)?
    ) {
        guard let log else {
            return
        }

        let destinationDescription = destinationSize.map {
            String(format: "(%.2f,%.2f)", $0.width, $0.height)
        } ?? "nil"
        let canvasDescription = canvasFrame.map { debugDescription(of: $0) } ?? "nil"
        let ioSurfaceDescription: String
        if let ioSurfaceWidth, let ioSurfaceHeight {
            ioSurfaceDescription = "\(ioSurfaceWidth)x\(ioSurfaceHeight)"
        } else {
            ioSurfaceDescription = "nil"
        }

        log(
            String(
                format: "overlay-target coordSpace=%@ drawSurface=(%.2f,%.2f) ioSurface=%@ texture=%dx%d pixelFormat=%lu imageBounds=%@ tileBounds=%@ destinationSize=%@ canvasFrame=%@ coordFrame=(%.2f,%.2f,%.2f,%.2f)",
                debugDescription(of: coordinateSpace),
                width,
                height,
                ioSurfaceDescription,
                textureWidth,
                textureHeight,
                pixelFormat,
                debugDescription(of: destinationImage.imagePixelBounds),
                debugDescription(of: destinationImage.tilePixelBounds),
                destinationDescription,
                canvasDescription,
                coordinateFrame.minX,
                coordinateFrame.minY,
                coordinateFrame.maxX,
                coordinateFrame.maxY
            )
        )
    }

    private func debugOverlayPrimitiveSamples(
        segments: [AUOSCStyledSegment],
        handles: [AUOSCHandle],
        coordinateSpace: AUOSCOverlayCoordinateSpace,
        coordinateSize: AUSize,
        pixelFrame: AUOSCOverlayPixelFrame,
        width: Double,
        height: Double,
        log: (String) -> Void
    ) {
        let lineRows = segments.prefix(4).enumerated().map { index, segment -> String in
            let startPixel = localPixel(from: segment.start, coordinateSpace: coordinateSpace, coordinateSize: coordinateSize, pixelFrame: pixelFrame, width: width, height: height)
            let endPixel = localPixel(from: segment.end, coordinateSpace: coordinateSpace, coordinateSize: coordinateSize, pixelFrame: pixelFrame, width: width, height: height)
            let delta = endPixel - startPixel
            let length = max(0.0001, hypot(delta.x, delta.y))
            let axis = SIMD2<Double>(delta.x / length, delta.y / length)
            let normal = SIMD2<Double>(-axis.y, axis.x)
            let halfLength = length / 2.0
            let halfThickness = segment.style.lineThickness / 2.0
            let padding = antialiasPadding()
            let centerPixel = (startPixel + endPixel) / 2.0
            let firstVertex = centerPixel - axis * (halfLength + padding) + normal * (halfThickness + padding)
            let centered = metalCenteredPixel(centerPixel, width: width, height: height)
            let vertexCentered = metalCenteredPixel(firstVertex, width: width, height: height)
            let centerClip = clipSpacePosition(fromCenteredPixel: centered, width: width, height: height)
            let vertexClip = clipSpacePosition(fromCenteredPixel: vertexCentered, width: width, height: height)
            return String(
                format: "s%d localStart=(%.2f,%.2f) localEnd=(%.2f,%.2f) center=(%.2f,%.2f) axis=(%.5f,%.5f) firstVertexLocal=(%.2f,%.2f) centerClip=(%.5f,%.5f) firstVertexClip=(%.5f,%.5f)",
                index + 1,
                startPixel.x,
                startPixel.y,
                endPixel.x,
                endPixel.y,
                centerPixel.x,
                centerPixel.y,
                axis.x,
                axis.y,
                firstVertex.x,
                firstVertex.y,
                centerClip.x,
                centerClip.y,
                vertexClip.x,
                vertexClip.y
            )
        }.joined(separator: " | ")

        if !lineRows.isEmpty {
            log("overlay-line-sample \(lineRows)")
        }

        let handleRows = handles.prefix(4).enumerated().map { index, handle -> String in
            let centerPixel = localPixel(from: handle.point, coordinateSpace: coordinateSpace, coordinateSize: coordinateSize, pixelFrame: pixelFrame, width: width, height: height)
            let radius = 15.0
            let localMin = centerPixel - SIMD2<Double>(radius, radius)
            let localMax = centerPixel + SIMD2<Double>(radius, radius)
            let centered = metalCenteredPixel(centerPixel, width: width, height: height)
            let clip = clipSpacePosition(fromCenteredPixel: centered, width: width, height: height)
            return String(
                format: "h%d/part%d centerLocal=(%.2f,%.2f) localBounds=(%.2f,%.2f)-(%.2f,%.2f) centerClip=(%.5f,%.5f)",
                index + 1,
                handle.part,
                centerPixel.x,
                centerPixel.y,
                localMin.x,
                localMin.y,
                localMax.x,
                localMax.y,
                clip.x,
                clip.y
            )
        }.joined(separator: " | ")

        if !handleRows.isEmpty {
            log("overlay-handle-sample \(handleRows)")
        }
    }

    private func debugOverlayVertexSummary(
        vertices: [AnyUprightOverlayVertex2D],
        width: Double,
        height: Double,
        log: ((String) -> Void)?
    ) {
        guard let log, !vertices.isEmpty else {
            return
        }

        var minPosition = SIMD2<Double>(Double.greatestFiniteMagnitude, Double.greatestFiniteMagnitude)
        var maxPosition = SIMD2<Double>(-Double.greatestFiniteMagnitude, -Double.greatestFiniteMagnitude)
        for vertex in vertices {
            let position = SIMD2<Double>(Double(vertex.position.x), Double(vertex.position.y))
            minPosition = simd.min(minPosition, position)
            maxPosition = simd.max(maxPosition, position)
        }

        let localBounds = surfaceBounds(
            fromMetalCenteredMin: minPosition,
            maxPosition,
            width: width,
            height: height
        )
        let clipMin = clipSpacePosition(fromCenteredPixel: SIMD2<Float>(Float(minPosition.x), Float(minPosition.y)), width: width, height: height)
        let clipMax = clipSpacePosition(fromCenteredPixel: SIMD2<Float>(Float(maxPosition.x), Float(maxPosition.y)), width: width, height: height)
        log(
            String(
                format: "overlay-vertex-bounds count=%d centeredMin=(%.2f,%.2f) centeredMax=(%.2f,%.2f) localMin=(%.2f,%.2f) localMax=(%.2f,%.2f) clipMin=(%.5f,%.5f) clipMax=(%.5f,%.5f)",
                vertices.count,
                minPosition.x,
                minPosition.y,
                maxPosition.x,
                maxPosition.y,
                localBounds.min.x,
                localBounds.min.y,
                localBounds.max.x,
                localBounds.max.y,
                clipMin.x,
                clipMin.y,
                clipMax.x,
                clipMax.y
            )
        )

        let samples = vertices.prefix(6).enumerated().map { index, vertex -> String in
            let centered = SIMD2<Float>(vertex.position.x, vertex.position.y)
            let local = surfacePixel(fromMetalCenteredPixel: SIMD2<Double>(Double(centered.x), Double(centered.y)), width: width, height: height)
            let clip = clipSpacePosition(fromCenteredPixel: centered, width: width, height: height)
            return String(
                format: "v%d centered=(%.2f,%.2f) local=(%.2f,%.2f) clip=(%.5f,%.5f) kind=%.1f",
                index,
                centered.x,
                centered.y,
                local.x,
                local.y,
                clip.x,
                clip.y,
                vertex.primitiveKind
            )
        }.joined(separator: " | ")
        log("overlay-vertex-sample \(samples)")
    }

    private func frameLocalPixel(
        from point: AUPoint,
        pixelFrame: AUOSCOverlayPixelFrame,
        width: Double,
        height: Double,
        flipsY: Bool
    ) -> SIMD2<Double> {
        let normalizedX = (point.x - pixelFrame.minX) / pixelFrame.width
        let normalizedY = (point.y - pixelFrame.minY) / pixelFrame.height
        return SIMD2<Double>(
            normalizedX * width,
            (flipsY ? 1.0 - normalizedY : normalizedY) * height
        )
    }

    private func centerRelativePixel(
        from point: AUPoint,
        pixelFrame: AUOSCOverlayPixelFrame,
        width: Double,
        height: Double
    ) -> SIMD2<Double> {
        let centerDelta = pixelFrame.center - SIMD2<Double>(width / 2.0, height / 2.0)
        return SIMD2<Double>(point.x, point.y) - centerDelta
    }

    private func clipSpacePosition(
        fromCenteredPixel point: SIMD2<Float>,
        width: Double,
        height: Double
    ) -> SIMD2<Double> {
        SIMD2<Double>(
            Double(point.x) / (width / 2.0),
            Double(point.y) / (height / 2.0)
        )
    }

    private func debugDescription(of coordinateSpace: AUOSCOverlayCoordinateSpace) -> String {
        switch coordinateSpace {
        case .normalized:
            return "normalized"
        case .pixels:
            return "pixels"
        case .canvasFramePixels:
            return "canvasFramePixels"
        }
    }

    private func debugDescription(of points: [AUPoint]) -> String {
        points.map { point in
            String(format: "(%.1f,%.1f)", point.x, point.y)
        }
        .joined(separator: " ")
    }

    private func debugDescription(of rect: FxRect) -> String {
        String(format: "(%.1f,%.1f,%.1f,%.1f)", Double(rect.left), Double(rect.bottom), Double(rect.right), Double(rect.top))
    }

    private func pixelFrame(
        for destinationImage: FxImageTile,
        destinationSize: AUSize?,
        canvasFrame: [AUPoint]?,
        coordinateSpace: AUOSCOverlayCoordinateSpace,
        textureWidth: Double,
        textureHeight: Double
    ) -> AUOSCOverlayPixelFrame {
        if coordinateSpace == .pixels || coordinateSpace == .canvasFramePixels {
            if let canvasFrame = canvasFrameFromPoints(canvasFrame) {
                return canvasFrame
            }

            if let destinationSize, destinationSize.width > 1.0, destinationSize.height > 1.0 {
                let outputFrame = AUOSCOverlayPixelFrame(minX: 0.0, minY: 0.0, maxX: destinationSize.width, maxY: destinationSize.height)
                return aspectFittedCoordinateFrame(for: outputFrame, textureWidth: textureWidth, textureHeight: textureHeight)
            }

            let imageFrame = pixelFrame(for: destinationImage.imagePixelBounds)
            if imageFrame.width > 1.0, imageFrame.height > 1.0 {
                return imageFrame
            }

            return AUOSCOverlayPixelFrame(minX: 0.0, minY: 0.0, maxX: textureWidth, maxY: textureHeight)
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

    private func aspectFittedCoordinateFrame(
        for frame: AUOSCOverlayPixelFrame,
        textureWidth: Double,
        textureHeight: Double
    ) -> AUOSCOverlayPixelFrame {
        AUOSCOverlayPixelFrame(
            frame.coordinateFrame.aspectFitted(toSurfaceSize: AUSize(width: textureWidth, height: textureHeight))
        )
    }

    private func appendPrimitiveQuad(
        p0: SIMD2<Double>,
        p1: SIMD2<Double>,
        p2: SIMD2<Double>,
        p3: SIMD2<Double>,
        color: SIMD4<Float>,
        primitiveOrigin: SIMD2<Float>,
        primitiveAxis: SIMD2<Float>,
        primitiveSize: SIMD2<Float>,
        primitiveKind: OverlayPrimitiveKind,
        width: Double,
        height: Double,
        to vertices: inout [AnyUprightOverlayVertex2D]
    ) {
        let converted = [p0, p1, p2, p0, p2, p3].map { point in
            AnyUprightOverlayVertex2D(
                position: metalCenteredPixel(point, width: width, height: height),
                color: color,
                primitiveOrigin: primitiveOrigin,
                primitiveAxis: primitiveAxis,
                primitiveSize: primitiveSize,
                primitiveKind: primitiveKind.rawValue,
                reserved0: 0.0
            )
        }
        vertices.append(contentsOf: converted)
    }

    private func metalCenteredPixel(_ point: SIMD2<Double>, width: Double, height: Double) -> SIMD2<Float> {
        let metalPoint = oscMetalCenteredPixel(
            fromSurfacePixel: AUPoint(x: point.x, y: point.y),
            surfaceSize: AUSize(width: width, height: height)
        )
        return SIMD2<Float>(Float(metalPoint.x), Float(metalPoint.y))
    }

    private func surfacePixel(fromMetalCenteredPixel point: SIMD2<Double>, width: Double, height: Double) -> SIMD2<Double> {
        let surfacePoint = oscSurfacePixel(
            fromMetalCenteredPixel: AUPoint(x: point.x, y: point.y),
            surfaceSize: AUSize(width: width, height: height)
        )
        return SIMD2<Double>(
            surfacePoint.x,
            surfacePoint.y
        )
    }

    private func surfaceBounds(
        fromMetalCenteredMin minPosition: SIMD2<Double>,
        _ maxPosition: SIMD2<Double>,
        width: Double,
        height: Double
    ) -> (min: SIMD2<Double>, max: SIMD2<Double>) {
        let corners = [
            SIMD2<Double>(minPosition.x, minPosition.y),
            SIMD2<Double>(minPosition.x, maxPosition.y),
            SIMD2<Double>(maxPosition.x, minPosition.y),
            SIMD2<Double>(maxPosition.x, maxPosition.y)
        ].map {
            surfacePixel(fromMetalCenteredPixel: $0, width: width, height: height)
        }

        return (
            min: corners.reduce(SIMD2<Double>(Double.greatestFiniteMagnitude, Double.greatestFiniteMagnitude)) { simd.min($0, $1) },
            max: corners.reduce(SIMD2<Double>(-Double.greatestFiniteMagnitude, -Double.greatestFiniteMagnitude)) { simd.max($0, $1) }
        )
    }

    private func antialiasPadding() -> Double {
        1.5
    }
}
