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

        appendPrimitiveQuad(
            p0: centerPixel - axis * (halfLength + padding) + normal * (halfThickness + padding),
            p1: centerPixel + axis * (halfLength + padding) + normal * (halfThickness + padding),
            p2: centerPixel + axis * (halfLength + padding) - normal * (halfThickness + padding),
            p3: centerPixel - axis * (halfLength + padding) - normal * (halfThickness + padding),
            color: color,
            primitiveOrigin: centeredPixel(centerPixel, width: width, height: height),
            primitiveAxis: SIMD2<Float>(Float(axis.x), Float(axis.y)),
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
            primitiveOrigin: centeredPixel(centerPixel, width: width, height: height),
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
            primitiveOrigin: centeredPixel(centerPixel, width: width, height: height),
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
                position: centeredPixel(point, width: width, height: height),
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

    private func centeredPixel(_ point: SIMD2<Double>, width: Double, height: Double) -> SIMD2<Float> {
        SIMD2<Float>(
            Float(point.x - width / 2.0),
            Float(point.y - height / 2.0)
        )
    }

    private func antialiasPadding() -> Double {
        1.5
    }
}
