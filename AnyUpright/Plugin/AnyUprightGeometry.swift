//
//  AnyUprightGeometry.swift
//  AnyUpright
//

import Foundation
import simd

struct AUPoint: Equatable {
    var x: Double
    var y: Double
}

struct AUSize: Equatable {
    var width: Double
    var height: Double
}

struct AUPixelBounds: Equatable {
    var left: Int32
    var bottom: Int32
    var right: Int32
    var top: Int32

    var width: Double {
        Double(right - left)
    }

    var height: Double {
        Double(top - bottom)
    }
}

struct AUOutputCoordinateBounds: Equatable {
    var left: Double
    var right: Double
    var top: Double
    var bottom: Double
}

struct AUTextureCoordinateMapping: Equatable {
    var imageOriginInTexture: AUPoint
    var textureSize: AUSize
}

struct AUQuad: Equatable {
    var topLeft: AUPoint
    var topRight: AUPoint
    var bottomRight: AUPoint
    var bottomLeft: AUPoint

    static func fullFrame(_ size: AUSize) -> AUQuad {
        AUQuad(
            topLeft: AUPoint(x: 0.0, y: 0.0),
            topRight: AUPoint(x: size.width, y: 0.0),
            bottomRight: AUPoint(x: size.width, y: size.height),
            bottomLeft: AUPoint(x: 0.0, y: size.height)
        )
    }
}

struct AULineSegment: Equatable {
    var start: AUPoint
    var end: AUPoint

    var length: Double {
        hypot(end.x - start.x, end.y - start.y)
    }

    var midpoint: AUPoint {
        AUPoint(x: (start.x + end.x) / 2.0, y: (start.y + end.y) / 2.0)
    }

    func distance(to point: AUPoint) -> Double {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0.000001 else {
            return hypot(point.x - start.x, point.y - start.y)
        }

        let projection = ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared
        let clampedProjection = min(1.0, max(0.0, projection))
        let closest = AUPoint(
            x: start.x + dx * clampedProjection,
            y: start.y + dy * clampedProjection
        )
        return hypot(point.x - closest.x, point.y - closest.y)
    }
}

enum AUReferenceOrientation {
    case horizontal
    case vertical
}

enum AUQuadTransformMode: Int32 {
    case outputCorners = 0
    case innerStretch = 1
}

enum AUQuadCorner {
    case topLeft
    case topRight
    case bottomRight
    case bottomLeft
}

enum AUQuadDetectionPrimitiveKind {
    case corner
    case edge
}

struct AUQuadDetectionPrimitiveID: Equatable {
    var kind: AUQuadDetectionPrimitiveKind
    var index: Int
}

struct AUQuadDetectionSelectionState: Equatable {
    var selectedCornerIndexes: Set<Int> = []
    var selectedEdgeIndexes: Set<Int> = []
    var hover: AUQuadDetectionPrimitiveID?

    var isEmpty: Bool {
        selectedCornerIndexes.isEmpty && selectedEdgeIndexes.isEmpty
    }

    var selectsCorners: Bool {
        !selectedCornerIndexes.isEmpty
    }

    var selectsEdges: Bool {
        !selectedEdgeIndexes.isEmpty
    }

    mutating func clear() {
        selectedCornerIndexes.removeAll()
        selectedEdgeIndexes.removeAll()
        hover = nil
    }

    mutating func toggle(_ primitive: AUQuadDetectionPrimitiveID) {
        switch primitive.kind {
        case .corner:
            guard selectedEdgeIndexes.isEmpty else {
                return
            }
            if selectedCornerIndexes.contains(primitive.index) {
                selectedCornerIndexes.remove(primitive.index)
            } else {
                selectedCornerIndexes.insert(primitive.index)
            }
        case .edge:
            guard selectedCornerIndexes.isEmpty else {
                return
            }
            if selectedEdgeIndexes.contains(primitive.index) {
                selectedEdgeIndexes.remove(primitive.index)
            } else {
                selectedEdgeIndexes.insert(primitive.index)
            }
        }
    }

    func shouldShowCorner(index: Int) -> Bool {
        !selectsEdges
    }

    func shouldShowEdge(index: Int) -> Bool {
        !selectsCorners
    }

    func isSelected(_ primitive: AUQuadDetectionPrimitiveID) -> Bool {
        switch primitive.kind {
        case .corner:
            return selectedCornerIndexes.contains(primitive.index)
        case .edge:
            return selectedEdgeIndexes.contains(primitive.index)
        }
    }

    func isActive(_ primitive: AUQuadDetectionPrimitiveID) -> Bool {
        hover == primitive || isSelected(primitive)
    }
}

struct AULineCandidate: Equatable {
    var line: AULineSegment
    var orientation: AUReferenceOrientation
    var signedDeviationRadians: Double
    var length: Double

    var absoluteDeviationRadians: Double {
        abs(signedDeviationRadians)
    }
}

struct AUCornerOffsets {
    var topLeftPercent: AUPoint = AUPoint(x: 0.0, y: 0.0)
    var topRightPercent: AUPoint = AUPoint(x: 0.0, y: 0.0)
    var bottomRightPercent: AUPoint = AUPoint(x: 0.0, y: 0.0)
    var bottomLeftPercent: AUPoint = AUPoint(x: 0.0, y: 0.0)

    var topLeftPixels: AUPoint = AUPoint(x: 0.0, y: 0.0)
    var topRightPixels: AUPoint = AUPoint(x: 0.0, y: 0.0)
    var bottomRightPixels: AUPoint = AUPoint(x: 0.0, y: 0.0)
    var bottomLeftPixels: AUPoint = AUPoint(x: 0.0, y: 0.0)
}

struct AUCanvasSurfaceMapper {
    var minX: Double
    var minY: Double
    var maxX: Double
    var maxY: Double
    var surfaceSize: AUSize

    var width: Double {
        max(1.0, maxX - minX)
    }

    var height: Double {
        max(1.0, maxY - minY)
    }

    init?(canvasFrame: [AUPoint], surfaceSize: AUSize) {
        guard canvasFrame.count >= 2 else {
            return nil
        }

        let xs = canvasFrame.map(\.x)
        let ys = canvasFrame.map(\.y)
        guard let minX = xs.min(),
              let maxX = xs.max(),
              let minY = ys.min(),
              let maxY = ys.max(),
              maxX - minX > 1.0,
              maxY - minY > 1.0 else {
            return nil
        }

        self.minX = minX
        self.minY = minY
        self.maxX = maxX
        self.maxY = maxY
        self.surfaceSize = AUSize(width: max(1.0, surfaceSize.width), height: max(1.0, surfaceSize.height))
    }

    func eventPoint(fromCanvasPoint point: AUPoint) -> AUPoint {
        AUPoint(
            x: (point.x - minX) / width * surfaceSize.width,
            y: (1.0 - (point.y - minY) / height) * surfaceSize.height
        )
    }

    func canvasPoint(fromEventPoint point: AUPoint) -> AUPoint {
        AUPoint(
            x: minX + point.x / surfaceSize.width * width,
            y: maxY - point.y / surfaceSize.height * height
        )
    }
}

func isPointInsideAxisAlignedFrame(_ point: AUPoint, frame: [AUPoint], padding: Double = 0.0) -> Bool {
    guard frame.count >= 2 else {
        return false
    }

    let xs = frame.map(\.x)
    let ys = frame.map(\.y)
    guard let minX = xs.min(),
          let maxX = xs.max(),
          let minY = ys.min(),
          let maxY = ys.max() else {
        return false
    }

    let inset = max(0.0, padding)
    return point.x >= minX - inset
        && point.x <= maxX + inset
        && point.y >= minY - inset
        && point.y <= maxY + inset
}

func shouldIncludeMappedSurfaceOSCCandidate(forInitialEventPoint point: AUPoint, canvasFrame: [AUPoint]) -> Bool {
    !isPointInsideAxisAlignedFrame(point, frame: canvasFrame)
}

func shouldIncludeMappedSurfaceOSCCandidate(
    forInitialEventPoint point: AUPoint,
    canvasFrame: [AUPoint],
    visibleControlPoints: [AUPoint],
    hitPadding: Double
) -> Bool {
    if isPointInsideAxisAlignedFrame(point, frame: visibleControlPoints, padding: hitPadding) {
        return false
    }

    return shouldIncludeMappedSurfaceOSCCandidate(forInitialEventPoint: point, canvasFrame: canvasFrame)
}

func shouldIncludeMappedSurfaceOSCCandidate(
    forInitialEventPoint point: AUPoint,
    mappedCanvasPoint: AUPoint,
    canvasFrame: [AUPoint],
    visibleControlPoints: [AUPoint],
    hitPadding: Double
) -> Bool {
    guard shouldIncludeMappedSurfaceOSCCandidate(
        forInitialEventPoint: point,
        canvasFrame: canvasFrame,
        visibleControlPoints: visibleControlPoints,
        hitPadding: hitPadding
    ) else {
        return false
    }

    return isPointInsideAxisAlignedFrame(mappedCanvasPoint, frame: visibleControlPoints, padding: hitPadding)
}

func isFinalCutProHost(_ bundleIdentifier: String?) -> Bool {
    guard let normalized = bundleIdentifier?.lowercased() else {
        return false
    }

    return normalized == "com.apple.finalcut"
        || normalized == "com.apple.finalcutapp"
}

func shouldAllowMappedSurfaceOSCEvents(hostBundleIdentifier: String?) -> Bool {
    !isFinalCutProHost(hostBundleIdentifier)
}

func shouldUseMappedSurfaceOSCEvent(
    forInitialEventPoint point: AUPoint,
    mappedCanvasPoint: AUPoint,
    canvasFrame: [AUPoint],
    visibleControlPoints: [AUPoint],
    hitPadding: Double,
    hostBundleIdentifier: String?
) -> Bool {
    guard shouldAllowMappedSurfaceOSCEvents(hostBundleIdentifier: hostBundleIdentifier) else {
        return false
    }

    return shouldIncludeMappedSurfaceOSCCandidate(
        forInitialEventPoint: point,
        mappedCanvasPoint: mappedCanvasPoint,
        canvasFrame: canvasFrame,
        visibleControlPoints: visibleControlPoints,
        hitPadding: hitPadding
    )
}

func oscSurfacePixel(fromHostCanvasPixel point: AUPoint, surfaceSize _: AUSize) -> AUPoint {
    point
}

func oscMetalCenteredPixel(fromSurfacePixel point: AUPoint, surfaceSize: AUSize) -> AUPoint {
    let width = max(1.0, surfaceSize.width)
    let height = max(1.0, surfaceSize.height)
    return AUPoint(
        x: point.x - width / 2.0,
        y: height / 2.0 - point.y
    )
}

func oscSurfacePixel(fromMetalCenteredPixel point: AUPoint, surfaceSize: AUSize) -> AUPoint {
    let width = max(1.0, surfaceSize.width)
    let height = max(1.0, surfaceSize.height)
    return AUPoint(
        x: point.x + width / 2.0,
        y: height / 2.0 - point.y
    )
}

struct AUAspectFitPixelSurfaceMapper {
    var coordinateFrame: AUCoordinateFrame
    var surfaceSize: AUSize

    init?(coordinateSize: AUSize, surfaceSize: AUSize) {
        let coordinateFrame = AUCoordinateFrame(minX: 0.0, minY: 0.0, maxX: coordinateSize.width, maxY: coordinateSize.height)
        self.init(coordinateFrame: coordinateFrame, surfaceSize: surfaceSize)
    }

    init?(coordinateFrame: AUCoordinateFrame, surfaceSize: AUSize) {
        guard coordinateFrame.width > 1.0,
              coordinateFrame.height > 1.0,
              surfaceSize.width > 1.0,
              surfaceSize.height > 1.0 else {
            return nil
        }

        self.coordinateFrame = coordinateFrame.aspectFitted(toSurfaceSize: surfaceSize)
        self.surfaceSize = AUSize(width: max(1.0, surfaceSize.width), height: max(1.0, surfaceSize.height))
    }

    func eventPoint(fromCoordinatePoint point: AUPoint) -> AUPoint {
        AUPoint(
            x: (point.x - coordinateFrame.minX) / coordinateFrame.width * surfaceSize.width,
            y: (1.0 - (point.y - coordinateFrame.minY) / coordinateFrame.height) * surfaceSize.height
        )
    }

    func coordinatePoint(fromEventPoint point: AUPoint) -> AUPoint {
        AUPoint(
            x: coordinateFrame.minX + point.x / surfaceSize.width * coordinateFrame.width,
            y: coordinateFrame.maxY - point.y / surfaceSize.height * coordinateFrame.height
        )
    }
}

struct AUCoordinateFrame: Equatable {
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

    func aspectFitted(toSurfaceSize surfaceSize: AUSize) -> AUCoordinateFrame {
        let surfaceWidth = max(1.0, surfaceSize.width)
        let surfaceHeight = max(1.0, surfaceSize.height)
        let scale = min(surfaceWidth / width, surfaceHeight / height)
        guard scale.isFinite, scale > 0.0 else {
            return self
        }

        let horizontalInset = max(0.0, (surfaceWidth - width * scale) / 2.0)
        let verticalInset = max(0.0, (surfaceHeight - height * scale) / 2.0)
        let fittedMinX = minX - horizontalInset / scale
        let fittedMinY = minY - verticalInset / scale

        return AUCoordinateFrame(
            minX: fittedMinX,
            minY: fittedMinY,
            maxX: fittedMinX + surfaceWidth / scale,
            maxY: fittedMinY + surfaceHeight / scale
        )
    }
}

func resolveOSCDragPart(hostActivePart: Int, localHitPart: Int?, nonePart: Int = 0) -> Int? {
    if hostActivePart != nonePart {
        return hostActivePart
    }

    guard let localHitPart, localHitPart != nonePart else {
        return nil
    }

    return localHitPart
}

func resolveOSCDisplayPart(hostActivePart: Int = 0, hoverPart: Int, dragPart: Int?, nonePart: Int = 0) -> Int {
    if let dragPart, dragPart != nonePart {
        return dragPart
    }

    if hostActivePart != nonePart {
        return hostActivePart
    }

    return hoverPart
}

enum AnyUprightGeometry {
    private static let innerStretchInset = 0.10

    static func outputCoordinateBounds(for tileBounds: AUPixelBounds, imageBounds: AUPixelBounds) -> AUOutputCoordinateBounds {
        AUOutputCoordinateBounds(
            left: Double(tileBounds.left - imageBounds.left),
            right: Double(tileBounds.right - imageBounds.left),
            top: Double(imageBounds.top - tileBounds.top),
            bottom: Double(imageBounds.top - tileBounds.bottom)
        )
    }

    static func textureCoordinateMapping(for imageBounds: AUPixelBounds, tileBounds: AUPixelBounds, textureSize: AUSize) -> AUTextureCoordinateMapping {
        AUTextureCoordinateMapping(
            imageOriginInTexture: AUPoint(
                x: Double(imageBounds.left - tileBounds.left),
                y: Double(tileBounds.top - imageBounds.top)
            ),
            textureSize: textureSize
        )
    }

    static func sourceTileBounds(for imageBounds: AUPixelBounds, destinationTileBounds: AUPixelBounds, usesIdentityPreview: Bool) -> AUPixelBounds {
        usesIdentityPreview ? destinationTileBounds : imageBounds
    }

    static func quad(from offsets: AUCornerOffsets, size: AUSize) -> AUQuad {
        quad(from: offsets, base: AUQuad.fullFrame(size), size: size)
    }

    static func innerStretchDefault(_ size: AUSize) -> AUQuad {
        AUQuad(
            topLeft: AUPoint(x: size.width * innerStretchInset, y: size.height * innerStretchInset),
            topRight: AUPoint(x: size.width * (1.0 - innerStretchInset), y: size.height * innerStretchInset),
            bottomRight: AUPoint(x: size.width * (1.0 - innerStretchInset), y: size.height * (1.0 - innerStretchInset)),
            bottomLeft: AUPoint(x: size.width * innerStretchInset, y: size.height * (1.0 - innerStretchInset))
        )
    }

    static func innerStretch(from offsets: AUCornerOffsets, size: AUSize) -> AUQuad {
        quad(from: offsets, base: innerStretchDefault(size), size: size)
    }

    static func imagePoint(fromNormalizedLowerLeftPoint point: AUPoint, size: AUSize) -> AUPoint {
        AUPoint(
            x: point.x * size.width,
            y: (1.0 - point.y) * size.height
        )
    }

    static func imagePoint(fromNormalizedObjectPoint point: AUPoint, size: AUSize) -> AUPoint {
        imagePoint(fromNormalizedLowerLeftPoint: point, size: size)
    }

    static func imageLine(fromNormalizedObjectLine line: AULineSegment, size: AUSize) -> AULineSegment {
        AULineSegment(
            start: imagePoint(fromNormalizedObjectPoint: line.start, size: size),
            end: imagePoint(fromNormalizedObjectPoint: line.end, size: size)
        )
    }

    static func imageQuad(fromNormalizedLowerLeftQuad quad: AUQuad, size: AUSize) -> AUQuad {
        AUQuad(
            topLeft: imagePoint(fromNormalizedLowerLeftPoint: quad.topLeft, size: size),
            topRight: imagePoint(fromNormalizedLowerLeftPoint: quad.topRight, size: size),
            bottomRight: imagePoint(fromNormalizedLowerLeftPoint: quad.bottomRight, size: size),
            bottomLeft: imagePoint(fromNormalizedLowerLeftPoint: quad.bottomLeft, size: size)
        )
    }

    static func orderedImageQuad(from points: [AUPoint]) -> AUQuad? {
        guard points.count == 4, points.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else {
            return nil
        }

        let topLeftIndex = points.indices.min { lhs, rhs in
            (points[lhs].x + points[lhs].y) < (points[rhs].x + points[rhs].y)
        }
        let bottomRightIndex = points.indices.max { lhs, rhs in
            (points[lhs].x + points[lhs].y) < (points[rhs].x + points[rhs].y)
        }
        let topRightIndex = points.indices.max { lhs, rhs in
            (points[lhs].x - points[lhs].y) < (points[rhs].x - points[rhs].y)
        }
        let bottomLeftIndex = points.indices.max { lhs, rhs in
            (points[lhs].y - points[lhs].x) < (points[rhs].y - points[rhs].x)
        }

        guard let topLeftIndex,
              let topRightIndex,
              let bottomRightIndex,
              let bottomLeftIndex else {
            return nil
        }

        let uniqueIndexes = Set([topLeftIndex, topRightIndex, bottomRightIndex, bottomLeftIndex])
        guard uniqueIndexes.count == 4 else {
            return nil
        }

        let quad = AUQuad(
            topLeft: points[topLeftIndex],
            topRight: points[topRightIndex],
            bottomRight: points[bottomRightIndex],
            bottomLeft: points[bottomLeftIndex]
        )
        return isConvexImageQuad(quad) ? quad : nil
    }

    static func imageQuad(fromNormalizedObjectPoints points: [AUPoint], size: AUSize) -> AUQuad? {
        orderedImageQuad(from: points.map { imagePoint(fromNormalizedObjectPoint: $0, size: size) })
    }

    static func imageQuad(fromNormalizedObjectLines lines: [AULineSegment], size: AUSize) -> AUQuad? {
        guard lines.count == 4 else {
            return nil
        }

        let imageLines = lines.map { imageLine(fromNormalizedObjectLine: $0, size: size) }
        let horizontal = imageLines.filter { abs($0.end.y - $0.start.y) <= abs($0.end.x - $0.start.x) }
            .sorted { $0.midpoint.y < $1.midpoint.y }
        let vertical = imageLines.filter { abs($0.end.y - $0.start.y) > abs($0.end.x - $0.start.x) }
            .sorted { $0.midpoint.x < $1.midpoint.x }

        guard horizontal.count == 2, vertical.count == 2 else {
            return nil
        }

        guard let topLeft = intersection(of: horizontal[0], and: vertical[0]),
              let topRight = intersection(of: horizontal[0], and: vertical[1]),
              let bottomRight = intersection(of: horizontal[1], and: vertical[1]),
              let bottomLeft = intersection(of: horizontal[1], and: vertical[0]) else {
            return nil
        }

        let quad = AUQuad(topLeft: topLeft, topRight: topRight, bottomRight: bottomRight, bottomLeft: bottomLeft)
        return isConvexImageQuad(quad) ? quad : nil
    }

    static func normalizedObjectPoint(fromImagePoint point: AUPoint, size: AUSize) -> AUPoint {
        let width = max(size.width, 1.0)
        let height = max(size.height, 1.0)
        return AUPoint(
            x: min(1.0, max(0.0, point.x / width)),
            y: min(1.0, max(0.0, 1.0 - point.y / height))
        )
    }

    static func isConvexImageQuad(_ quad: AUQuad) -> Bool {
        let points = [quad.topLeft, quad.topRight, quad.bottomRight, quad.bottomLeft]
        guard points.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else {
            return false
        }

        var previousSign = 0.0
        for index in points.indices {
            let current = points[index]
            let next = points[(index + 1) % points.count]
            let afterNext = points[(index + 2) % points.count]
            let cross = (next.x - current.x) * (afterNext.y - next.y) - (next.y - current.y) * (afterNext.x - next.x)
            guard abs(cross) > 0.000001 else {
                return false
            }

            let sign = cross > 0.0 ? 1.0 : -1.0
            if previousSign == 0.0 {
                previousSign = sign
            } else if sign != previousSign {
                return false
            }
        }

        return abs(polygonArea(points)) > 0.000001
    }

    private static func polygonArea(_ points: [AUPoint]) -> Double {
        guard points.count >= 3 else {
            return 0.0
        }

        var area = 0.0
        for index in points.indices {
            let current = points[index]
            let next = points[(index + 1) % points.count]
            area += current.x * next.y - next.x * current.y
        }
        return area / 2.0
    }

    static func normalizedObjectQuad(fromImageQuad quad: AUQuad, size: AUSize) -> AUQuad {
        AUQuad(
            topLeft: normalizedObjectPoint(fromImagePoint: quad.topLeft, size: size),
            topRight: normalizedObjectPoint(fromImagePoint: quad.topRight, size: size),
            bottomRight: normalizedObjectPoint(fromImagePoint: quad.bottomRight, size: size),
            bottomLeft: normalizedObjectPoint(fromImagePoint: quad.bottomLeft, size: size)
        )
    }

    static func normalizedObjectLine(fromImageLine line: AULineSegment, size: AUSize) -> AULineSegment {
        AULineSegment(
            start: normalizedObjectPoint(fromImagePoint: line.start, size: size),
            end: normalizedObjectPoint(fromImagePoint: line.end, size: size)
        )
    }

    static func intersection(of first: AULineSegment, and second: AULineSegment) -> AUPoint? {
        let x1 = first.start.x
        let y1 = first.start.y
        let x2 = first.end.x
        let y2 = first.end.y
        let x3 = second.start.x
        let y3 = second.start.y
        let x4 = second.end.x
        let y4 = second.end.y
        let denominator = (x1 - x2) * (y3 - y4) - (y1 - y2) * (x3 - x4)
        guard abs(denominator) > 0.000001 else {
            return nil
        }

        let firstCross = x1 * y2 - y1 * x2
        let secondCross = x3 * y4 - y3 * x4
        return AUPoint(
            x: (firstCross * (x3 - x4) - (x1 - x2) * secondCross) / denominator,
            y: (firstCross * (y3 - y4) - (y1 - y2) * secondCross) / denominator
        )
    }

    static func normalizedScores(_ scores: [Double]) -> [Double] {
        let maximum = scores.reduce(0.0) { partial, score in
            max(partial, score.isFinite ? score : 0.0)
        }
        return scores.map { score in
            normalizedScore(score, maximum: maximum)
        }
    }

    static func normalizedScore(_ score: Double, maximum: Double) -> Double {
        guard score.isFinite, maximum.isFinite, maximum > 0.0 else {
            return 0.0
        }

        return min(1.0, max(0.0, score / maximum))
    }

    static func innerStretchOffsets(forInnerStretch quad: AUQuad, size: AUSize) -> AUCornerOffsets {
        func objectPoint(fromImagePoint point: AUPoint) -> AUPoint {
            normalizedObjectPoint(fromImagePoint: point, size: size)
        }

        return AUCornerOffsets(
            topLeftPercent: sourceCornerPercentOffset(forObjectPoint: objectPoint(fromImagePoint: quad.topLeft), corner: .topLeft),
            topRightPercent: sourceCornerPercentOffset(forObjectPoint: objectPoint(fromImagePoint: quad.topRight), corner: .topRight),
            bottomRightPercent: sourceCornerPercentOffset(forObjectPoint: objectPoint(fromImagePoint: quad.bottomRight), corner: .bottomRight),
            bottomLeftPercent: sourceCornerPercentOffset(forObjectPoint: objectPoint(fromImagePoint: quad.bottomLeft), corner: .bottomLeft)
        )
    }

    private static func quad(from offsets: AUCornerOffsets, base: AUQuad, size: AUSize) -> AUQuad {
        func apply(_ base: AUPoint, percent: AUPoint, pixels: AUPoint) -> AUPoint {
            AUPoint(
                x: base.x + percent.x * size.width + pixels.x,
                y: base.y - percent.y * size.height - pixels.y
            )
        }

        return AUQuad(
            topLeft: apply(base.topLeft, percent: offsets.topLeftPercent, pixels: offsets.topLeftPixels),
            topRight: apply(base.topRight, percent: offsets.topRightPercent, pixels: offsets.topRightPixels),
            bottomRight: apply(base.bottomRight, percent: offsets.bottomRightPercent, pixels: offsets.bottomRightPixels),
            bottomLeft: apply(base.bottomLeft, percent: offsets.bottomLeftPercent, pixels: offsets.bottomLeftPixels)
        )
    }

    static func quadObjectPoints(from offsets: AUCornerOffsets, size: AUSize) -> AUQuad {
        quadObjectPoints(from: offsets, base: fullFrameObjectBase(), size: size)
    }

    static func innerStretchObjectPoints(from offsets: AUCornerOffsets, size: AUSize) -> AUQuad {
        quadObjectPoints(from: offsets, base: innerStretchObjectBase(), size: size)
    }

    static func objectPixelQuad(fromNormalizedObjectQuad quad: AUQuad, size: AUSize) -> AUQuad {
        AUQuad(
            topLeft: objectPixelPoint(fromNormalizedObjectPoint: quad.topLeft, size: size),
            topRight: objectPixelPoint(fromNormalizedObjectPoint: quad.topRight, size: size),
            bottomRight: objectPixelPoint(fromNormalizedObjectPoint: quad.bottomRight, size: size),
            bottomLeft: objectPixelPoint(fromNormalizedObjectPoint: quad.bottomLeft, size: size)
        )
    }

    static func normalizedObjectPoint(fromObjectPixelPoint point: AUPoint, size: AUSize) -> AUPoint {
        AUPoint(
            x: point.x / max(size.width, 1.0),
            y: point.y / max(size.height, 1.0)
        )
    }

    static func normalizedSourceObjectPoint(fromOSCPixelPoint point: AUPoint, outputSize: AUSize) -> AUPoint {
        AUPoint(
            x: point.x / max(outputSize.width, 1.0),
            y: point.y / max(outputSize.height, 1.0)
        )
    }

    static func verticallyFlippedObjectPoint(_ point: AUPoint) -> AUPoint {
        AUPoint(x: point.x, y: 1.0 - point.y)
    }

    static func verticallyFlippedObjectQuad(_ quad: AUQuad) -> AUQuad {
        AUQuad(
            topLeft: verticallyFlippedObjectPoint(quad.topLeft),
            topRight: verticallyFlippedObjectPoint(quad.topRight),
            bottomRight: verticallyFlippedObjectPoint(quad.bottomRight),
            bottomLeft: verticallyFlippedObjectPoint(quad.bottomLeft)
        )
    }

    static func verticallyFlippedPixelPoint(_ point: AUPoint, size: AUSize) -> AUPoint {
        AUPoint(x: point.x, y: max(size.height, 1.0) - point.y)
    }

    static func verticallyFlippedPixelQuad(_ quad: AUQuad, size: AUSize) -> AUQuad {
        AUQuad(
            topLeft: verticallyFlippedPixelPoint(quad.topLeft, size: size),
            topRight: verticallyFlippedPixelPoint(quad.topRight, size: size),
            bottomRight: verticallyFlippedPixelPoint(quad.bottomRight, size: size),
            bottomLeft: verticallyFlippedPixelPoint(quad.bottomLeft, size: size)
        )
    }

    static func distanceToQuadEdge(from point: AUPoint, quad: AUQuad) -> Double {
        [
            AULineSegment(start: quad.topLeft, end: quad.topRight),
            AULineSegment(start: quad.topRight, end: quad.bottomRight),
            AULineSegment(start: quad.bottomRight, end: quad.bottomLeft),
            AULineSegment(start: quad.bottomLeft, end: quad.topLeft)
        ].reduce(Double.greatestFiniteMagnitude) { partial, segment in
            min(partial, segment.distance(to: point))
        }
    }

    private static func quadObjectPoints(from offsets: AUCornerOffsets, base: AUQuad, size: AUSize) -> AUQuad {
        AUQuad(
            topLeft: objectPoint(for: .topLeft, offsets: offsets, base: base, size: size),
            topRight: objectPoint(for: .topRight, offsets: offsets, base: base, size: size),
            bottomRight: objectPoint(for: .bottomRight, offsets: offsets, base: base, size: size),
            bottomLeft: objectPoint(for: .bottomLeft, offsets: offsets, base: base, size: size)
        )
    }

    static func cornerPixelOffset(forObjectPoint point: AUPoint, corner: AUQuadCorner, offsets: AUCornerOffsets, size: AUSize) -> AUPoint {
        cornerPixelOffset(forObjectPoint: point, corner: corner, offsets: offsets, base: fullFrameObjectBase(), size: size)
    }

    static func sourceCornerPixelOffset(forObjectPoint point: AUPoint, corner: AUQuadCorner, offsets: AUCornerOffsets, size: AUSize) -> AUPoint {
        cornerPixelOffset(forObjectPoint: point, corner: corner, offsets: offsets, base: innerStretchObjectBase(), size: size)
    }

    static func sourceCornerPercentOffset(forObjectPoint point: AUPoint, corner: AUQuadCorner) -> AUPoint {
        let base = objectBasePoint(for: corner, in: innerStretchObjectBase())
        return AUPoint(x: point.x - base.x, y: point.y - base.y)
    }

    private static func cornerPixelOffset(forObjectPoint point: AUPoint, corner: AUQuadCorner, offsets: AUCornerOffsets, base: AUQuad, size: AUSize) -> AUPoint {
        let base = objectBasePoint(for: corner, in: base)
        let percent = percentOffset(for: corner, in: offsets)
        return AUPoint(
            x: (point.x - base.x - percent.x) * size.width,
            y: (point.y - base.y - percent.y) * size.height
        )
    }

    private static func objectPixelPoint(fromNormalizedObjectPoint point: AUPoint, size: AUSize) -> AUPoint {
        AUPoint(x: point.x * size.width, y: point.y * size.height)
    }

    static func uprightQuad(vertical: Double, horizontal: Double, size: AUSize) -> AUQuad {
        let sourceToOutput = simd_inverse(uprightOutputToSourceMatrix(vertical: vertical, horizontal: horizontal, size: size))
        let frame = AUQuad.fullFrame(size)
        return AUQuad(
            topLeft: transform(frame.topLeft, by: sourceToOutput),
            topRight: transform(frame.topRight, by: sourceToOutput),
            bottomRight: transform(frame.bottomRight, by: sourceToOutput),
            bottomLeft: transform(frame.bottomLeft, by: sourceToOutput)
        )
    }

    static func uprightOutputToSourceMatrix(vertical: Double, horizontal: Double, size: AUSize) -> simd_float3x3 {
        guard size.width > 0.0, size.height > 0.0 else {
            return matrix(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0)
        }

        let centerX = size.width / 2.0
        let centerY = size.height / 2.0
        let scale = max(size.width, size.height, 1.0)
        let maxProjectiveStrength = 1.5
        let verticalStrength = max(-1.0, min(1.0, vertical)) * maxProjectiveStrength / scale
        let horizontalStrength = -max(-1.0, min(1.0, horizontal)) * maxProjectiveStrength / scale

        let toCenter = matrix(
            1.0, 0.0, -centerX,
            0.0, 1.0, -centerY,
            0.0, 0.0, 1.0
        )
        let perspective = matrix(
            1.0, 0.0, 0.0,
            0.0, 1.0, 0.0,
            horizontalStrength, verticalStrength, 1.0
        )
        let fromCenter = matrix(
            1.0, 0.0, centerX,
            0.0, 1.0, centerY,
            0.0, 0.0, 1.0
        )

        return multiply(multiply(fromCenter, perspective), toCenter)
    }

    static func lineCandidates(
        from lines: [AULineSegment],
        orientation: AUReferenceOrientation,
        maxDeviationRadians: Double = .pi / 6.0,
        minimumLength: Double = 1.0
    ) -> [AULineCandidate] {
        lines.compactMap { line in
            let length = line.length
            guard length >= minimumLength else {
                return nil
            }

            let deviation = signedDeviationRadians(of: line, from: orientation)
            guard isStrictlyWithinDeviationLimit(deviation, limit: maxDeviationRadians) else {
                return nil
            }

            return AULineCandidate(
                line: line,
                orientation: orientation,
                signedDeviationRadians: deviation,
                length: length
            )
        }
        .sorted {
            if abs($0.signedDeviationRadians) == abs($1.signedDeviationRadians) {
                return $0.length > $1.length
            }
            return abs($0.signedDeviationRadians) < abs($1.signedDeviationRadians)
        }
    }

    static func bestReferenceLines(
        from lines: [AULineSegment],
        orientation: AUReferenceOrientation,
        maximumCount: Int = 2,
        maxDeviationRadians: Double = .pi / 6.0,
        minimumLength: Double = 1.0
    ) -> [AULineSegment] {
        Array(
            lineCandidates(
                from: lines,
                orientation: orientation,
                maxDeviationRadians: maxDeviationRadians,
                minimumLength: minimumLength
            )
            .prefix(maximumCount)
            .map(\.line)
        )
    }

    static func horizonCorrectionRadians(from lines: [AULineSegment], maximumCount: Int = 2) -> Double? {
        rotationCorrectionRadians(from: lines, orientation: .horizontal, maximumCount: maximumCount)
    }

    static func dominantHorizonCorrectionRadians(from lines: [AULineSegment], maximumCount: Int = 2) -> Double? {
        dominantRotationCorrectionRadians(from: lines, orientation: .horizontal, maximumCount: maximumCount)
    }

    static func rotationCorrectionRadians(from lines: [AULineSegment], orientation: AUReferenceOrientation, maximumCount: Int = 2) -> Double? {
        let candidates = Array(lineCandidates(from: lines, orientation: orientation).prefix(maximumCount))
        let totalWeight = candidates.reduce(0.0) { $0 + $1.length }
        guard totalWeight > 0.0 else {
            return nil
        }

        let weightedDeviation = candidates.reduce(0.0) { partial, candidate in
            partial + candidate.signedDeviationRadians * candidate.length
        } / totalWeight

        return -weightedDeviation
    }

    static func dominantRotationCorrectionRadians(
        from lines: [AULineSegment],
        orientation: AUReferenceOrientation,
        maximumCount: Int = 2,
        maxDeviationRadians: Double = .pi / 6.0,
        minimumLength: Double = 1.0
    ) -> Double? {
        let candidates = Array(lines.compactMap { line -> AULineCandidate? in
            let length = line.length
            guard length >= minimumLength else {
                return nil
            }

            let deviation = signedDeviationRadians(of: line, from: orientation)
            guard isStrictlyWithinDeviationLimit(deviation, limit: maxDeviationRadians) else {
                return nil
            }

            return AULineCandidate(
                line: line,
                orientation: orientation,
                signedDeviationRadians: deviation,
                length: length
            )
        }.prefix(maximumCount))

        let totalWeight = candidates.reduce(0.0) { $0 + $1.length }
        guard totalWeight > 0.0 else {
            return nil
        }

        let weightedDeviation = candidates.reduce(0.0) { partial, candidate in
            partial + candidate.signedDeviationRadians * candidate.length
        } / totalWeight

        return -weightedDeviation
    }

    static func estimateVerticalPerspective(from referenceLines: [AULineSegment], size: AUSize) -> Double? {
        estimatePerspective(from: referenceLines, orientation: .vertical, size: size)
    }

    static func estimateHorizontalPerspective(from referenceLines: [AULineSegment], size: AUSize) -> Double? {
        estimatePerspective(from: referenceLines, orientation: .horizontal, size: size)
    }

    static func quadOutputToSourceMatrix(
        from offsets: AUCornerOffsets,
        mode: AUQuadTransformMode,
        showCornerAdjuster: Bool,
        outputSize: AUSize,
        sourceSize: AUSize
    ) -> simd_float3x3 {
        switch mode {
        case .outputCorners:
            let outputQuad = quad(from: offsets, size: outputSize)
            return homography(from: outputQuad, to: AUQuad.fullFrame(sourceSize))

        case .innerStretch:
            guard !showCornerAdjuster else {
                return homography(from: AUQuad.fullFrame(outputSize), to: AUQuad.fullFrame(sourceSize))
            }

            let selectedInnerStretch = innerStretch(from: offsets, size: sourceSize)
            return homography(from: AUQuad.fullFrame(outputSize), to: selectedInnerStretch)
        }
    }

    static func quadSelectionToOutputRectMatrix(
        from offsets: AUCornerOffsets,
        outputSize: AUSize,
        sourceSize: AUSize
    ) -> simd_float3x3 {
        let outputQuad = innerStretchOutputHandles(from: offsets, outputSize: outputSize, sourceSize: sourceSize)
        return homography(from: outputQuad, to: AUQuad.fullFrame(outputSize))
    }

    static func innerStretchOutputHandles(
        from offsets: AUCornerOffsets,
        outputSize: AUSize,
        sourceSize: AUSize
    ) -> AUQuad {
        let selectedInnerStretch = innerStretch(from: offsets, size: sourceSize)
        return AUQuad(
            topLeft: scalePoint(selectedInnerStretch.topLeft, from: sourceSize, to: outputSize),
            topRight: scalePoint(selectedInnerStretch.topRight, from: sourceSize, to: outputSize),
            bottomRight: scalePoint(selectedInnerStretch.bottomRight, from: sourceSize, to: outputSize),
            bottomLeft: scalePoint(selectedInnerStretch.bottomLeft, from: sourceSize, to: outputSize)
        )
    }

    static func identityOutputToSourceMatrix(outputSize: AUSize, sourceSize: AUSize) -> simd_float3x3 {
        homography(from: AUQuad.fullFrame(outputSize), to: AUQuad.fullFrame(sourceSize))
    }

    static func autoCropOutputToSourceMatrix(
        _ outputToSource: simd_float3x3,
        outputSize: AUSize,
        sourceSize: AUSize,
        maximumScale: Double = 8.0
    ) -> simd_float3x3 {
        let scale = autoCropScale(
            for: outputToSource,
            outputSize: outputSize,
            sourceSize: sourceSize,
            maximumScale: maximumScale
        )
        guard scale > 1.000001 else {
            return outputToSource
        }

        return multiply(outputToSource, outputCenterUnzoomMatrix(scale: scale, size: outputSize))
    }

    static func autoCropScale(
        for outputToSource: simd_float3x3,
        outputSize: AUSize,
        sourceSize: AUSize,
        maximumScale: Double = 8.0
    ) -> Double {
        guard outputSize.width > 0.0,
              outputSize.height > 0.0,
              sourceSize.width > 0.0,
              sourceSize.height > 0.0,
              maximumScale > 1.0 else {
            return 1.0
        }

        if outputFrameMapsInsideSource(outputToSource, outputSize: outputSize, sourceSize: sourceSize) {
            return 1.0
        }

        let maxScale = max(1.0, maximumScale)
        var lower = 1.0
        var upper = 2.0
        while upper < maxScale {
            let candidate = multiply(outputToSource, outputCenterUnzoomMatrix(scale: upper, size: outputSize))
            if outputFrameMapsInsideSource(candidate, outputSize: outputSize, sourceSize: sourceSize) {
                break
            }
            lower = upper
            upper *= 2.0
        }
        upper = min(upper, maxScale)

        var candidate = multiply(outputToSource, outputCenterUnzoomMatrix(scale: upper, size: outputSize))
        guard outputFrameMapsInsideSource(candidate, outputSize: outputSize, sourceSize: sourceSize) else {
            return upper
        }

        for _ in 0..<24 {
            let middle = (lower + upper) / 2.0
            candidate = multiply(outputToSource, outputCenterUnzoomMatrix(scale: middle, size: outputSize))
            if outputFrameMapsInsideSource(candidate, outputSize: outputSize, sourceSize: sourceSize) {
                upper = middle
            } else {
                lower = middle
            }
        }

        return upper
    }

    private static func scalePoint(_ point: AUPoint, from sourceSize: AUSize, to outputSize: AUSize) -> AUPoint {
        AUPoint(
            x: point.x / max(sourceSize.width, 1.0) * outputSize.width,
            y: point.y / max(sourceSize.height, 1.0) * outputSize.height
        )
    }

    static func rotationScaleToFill(angleRadians: Double, size: AUSize) -> Double {
        let center = AUPoint(x: size.width / 2.0, y: size.height / 2.0)
        let corners = [
            AUPoint(x: 0.0, y: 0.0),
            AUPoint(x: size.width, y: 0.0),
            AUPoint(x: size.width, y: size.height),
            AUPoint(x: 0.0, y: size.height)
        ]

        let c = cos(-angleRadians)
        let s = sin(-angleRadians)
        var scale = 1.0

        for corner in corners {
            let dx = corner.x - center.x
            let dy = corner.y - center.y
            let rotatedX = c * dx - s * dy
            let rotatedY = s * dx + c * dy
            if size.width > 0.0 {
                scale = max(scale, abs(rotatedX) / (size.width / 2.0))
            }
            if size.height > 0.0 {
                scale = max(scale, abs(rotatedY) / (size.height / 2.0))
            }
        }

        return scale
    }

    static func rotationOutputToSource(angleRadians: Double, fillFrame: Bool, size: AUSize) -> simd_float3x3 {
        let scale = fillFrame ? rotationScaleToFill(angleRadians: angleRadians, size: size) : 1.0
        let center = AUPoint(x: size.width / 2.0, y: size.height / 2.0)
        let c = cos(-angleRadians) / scale
        let s = sin(-angleRadians) / scale

        let a = c
        let b = -s
        let d = s
        let e = c
        let tx = center.x - a * center.x - b * center.y
        let ty = center.y - d * center.x - e * center.y

        return matrix(a, b, tx, d, e, ty, 0.0, 0.0, 1.0)
    }

    private static func outputCenterUnzoomMatrix(scale: Double, size: AUSize) -> simd_float3x3 {
        let inverseScale = 1.0 / max(scale, 1.0)
        let centerX = size.width / 2.0
        let centerY = size.height / 2.0
        return matrix(
            inverseScale, 0.0, centerX - inverseScale * centerX,
            0.0, inverseScale, centerY - inverseScale * centerY,
            0.0, 0.0, 1.0
        )
    }

    private static func outputFrameMapsInsideSource(_ matrix: simd_float3x3, outputSize: AUSize, sourceSize: AUSize) -> Bool {
        let epsilon = 0.25
        let corners = [
            AUPoint(x: 0.0, y: 0.0),
            AUPoint(x: outputSize.width, y: 0.0),
            AUPoint(x: outputSize.width, y: outputSize.height),
            AUPoint(x: 0.0, y: outputSize.height)
        ]

        return corners.allSatisfy { corner in
            let mapped = transform(corner, by: matrix)
            return mapped.x.isFinite
                && mapped.y.isFinite
                && mapped.x >= -epsilon
                && mapped.y >= -epsilon
                && mapped.x <= sourceSize.width + epsilon
                && mapped.y <= sourceSize.height + epsilon
        }
    }

    static func homography(from output: AUQuad, to source: AUQuad) -> simd_float3x3 {
        let pairs = [
            (output.topLeft, source.topLeft),
            (output.topRight, source.topRight),
            (output.bottomRight, source.bottomRight),
            (output.bottomLeft, source.bottomLeft)
        ]

        var equations = Array(repeating: Array(repeating: 0.0, count: 9), count: 8)
        for (index, pair) in pairs.enumerated() {
            let x = pair.0.x
            let y = pair.0.y
            let u = pair.1.x
            let v = pair.1.y
            let row = index * 2

            equations[row][0] = x
            equations[row][1] = y
            equations[row][2] = 1.0
            equations[row][6] = -u * x
            equations[row][7] = -u * y
            equations[row][8] = u

            equations[row + 1][3] = x
            equations[row + 1][4] = y
            equations[row + 1][5] = 1.0
            equations[row + 1][6] = -v * x
            equations[row + 1][7] = -v * y
            equations[row + 1][8] = v
        }

        guard let solution = solve(equations) else {
            return matrix(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0)
        }

        return matrix(
            solution[0], solution[1], solution[2],
            solution[3], solution[4], solution[5],
            solution[6], solution[7], 1.0
        )
    }

    static func multiply(_ lhs: simd_float3x3, _ rhs: simd_float3x3) -> simd_float3x3 {
        lhs * rhs
    }

    static func transform(_ point: AUPoint, by matrix: simd_float3x3) -> AUPoint {
        let mapped = matrix * SIMD3<Float>(Float(point.x), Float(point.y), 1.0)
        let z = Double(mapped.z)
        guard abs(z) > 0.000001 else {
            return point
        }

        return AUPoint(
            x: Double(mapped.x) / z,
            y: Double(mapped.y) / z
        )
    }

    static func transform(_ line: AULineSegment, by matrix: simd_float3x3) -> AULineSegment {
        AULineSegment(
            start: transform(line.start, by: matrix),
            end: transform(line.end, by: matrix)
        )
    }

    private static func matrix(_ a: Double, _ b: Double, _ c: Double,
                               _ d: Double, _ e: Double, _ f: Double,
                               _ g: Double, _ h: Double, _ i: Double) -> simd_float3x3 {
        simd_float3x3(columns: (
            SIMD3<Float>(Float(a), Float(d), Float(g)),
            SIMD3<Float>(Float(b), Float(e), Float(h)),
            SIMD3<Float>(Float(c), Float(f), Float(i))
        ))
    }

    private static func objectPoint(for corner: AUQuadCorner, offsets: AUCornerOffsets, base: AUQuad, size: AUSize) -> AUPoint {
        let base = objectBasePoint(for: corner, in: base)
        let percent = percentOffset(for: corner, in: offsets)
        let pixels = pixelOffset(for: corner, in: offsets)
        return AUPoint(
            x: base.x + percent.x + pixels.x / size.width,
            y: base.y + percent.y + pixels.y / size.height
        )
    }

    private static func fullFrameObjectBase() -> AUQuad {
        AUQuad(
            topLeft: AUPoint(x: 0.0, y: 1.0),
            topRight: AUPoint(x: 1.0, y: 1.0),
            bottomRight: AUPoint(x: 1.0, y: 0.0),
            bottomLeft: AUPoint(x: 0.0, y: 0.0)
        )
    }

    private static func innerStretchObjectBase() -> AUQuad {
        AUQuad(
            topLeft: AUPoint(x: innerStretchInset, y: 1.0 - innerStretchInset),
            topRight: AUPoint(x: 1.0 - innerStretchInset, y: 1.0 - innerStretchInset),
            bottomRight: AUPoint(x: 1.0 - innerStretchInset, y: innerStretchInset),
            bottomLeft: AUPoint(x: innerStretchInset, y: innerStretchInset)
        )
    }

    private static func objectBasePoint(for corner: AUQuadCorner, in base: AUQuad) -> AUPoint {
        switch corner {
        case .topLeft:
            return base.topLeft
        case .topRight:
            return base.topRight
        case .bottomRight:
            return base.bottomRight
        case .bottomLeft:
            return base.bottomLeft
        }
    }

    private static func percentOffset(for corner: AUQuadCorner, in offsets: AUCornerOffsets) -> AUPoint {
        switch corner {
        case .topLeft:
            return offsets.topLeftPercent
        case .topRight:
            return offsets.topRightPercent
        case .bottomRight:
            return offsets.bottomRightPercent
        case .bottomLeft:
            return offsets.bottomLeftPercent
        }
    }

    private static func pixelOffset(for corner: AUQuadCorner, in offsets: AUCornerOffsets) -> AUPoint {
        switch corner {
        case .topLeft:
            return offsets.topLeftPixels
        case .topRight:
            return offsets.topRightPixels
        case .bottomRight:
            return offsets.bottomRightPixels
        case .bottomLeft:
            return offsets.bottomLeftPixels
        }
    }

    private static func solve(_ augmented: [[Double]]) -> [Double]? {
        var matrix = augmented
        let rowCount = 8
        let columnCount = 8

        for pivotColumn in 0..<columnCount {
            var pivotRow = pivotColumn
            var pivotValue = abs(matrix[pivotRow][pivotColumn])

            for row in (pivotColumn + 1)..<rowCount {
                let value = abs(matrix[row][pivotColumn])
                if value > pivotValue {
                    pivotValue = value
                    pivotRow = row
                }
            }

            if pivotValue < 0.000000001 {
                return nil
            }

            if pivotRow != pivotColumn {
                matrix.swapAt(pivotRow, pivotColumn)
            }

            let pivot = matrix[pivotColumn][pivotColumn]
            for column in pivotColumn...columnCount {
                matrix[pivotColumn][column] /= pivot
            }

            for row in 0..<rowCount where row != pivotColumn {
                let factor = matrix[row][pivotColumn]
                if factor == 0.0 {
                    continue
                }
                for column in pivotColumn...columnCount {
                    matrix[row][column] -= factor * matrix[pivotColumn][column]
                }
            }
        }

        return matrix.map { $0[columnCount] }
    }

    private static func estimatePerspective(from referenceLines: [AULineSegment], orientation: AUReferenceOrientation, size: AUSize) -> Double? {
        let usableLines = referenceLines.filter { $0.length > 1.0 }
        guard !usableLines.isEmpty, size.width > 0.0, size.height > 0.0 else {
            return nil
        }

        func objective(_ parameter: Double) -> Double {
            let sourceToOutput: simd_float3x3
            switch orientation {
            case .vertical:
                sourceToOutput = simd_inverse(uprightOutputToSourceMatrix(vertical: parameter, horizontal: 0.0, size: size))
            case .horizontal:
                sourceToOutput = simd_inverse(uprightOutputToSourceMatrix(vertical: 0.0, horizontal: parameter, size: size))
            }

            return usableLines.reduce(0.0) { partial, line in
                let transformed = transform(line, by: sourceToOutput)
                let deviation = signedDeviationRadians(of: transformed, from: orientation)
                return partial + deviation * deviation * line.length
            }
        }

        return minimize(objective, lowerBound: -1.0, upperBound: 1.0)
    }

    private static func signedDeviationRadians(of line: AULineSegment, from orientation: AUReferenceOrientation) -> Double {
        let angle = normalizedLineAngleRadians(
            atan2(line.end.y - line.start.y, line.end.x - line.start.x)
        )

        switch orientation {
        case .horizontal:
            return angle
        case .vertical:
            if angle >= 0.0 {
                return angle - .pi / 2.0
            }
            return angle + .pi / 2.0
        }
    }

    private static func isStrictlyWithinDeviationLimit(_ deviation: Double, limit: Double) -> Bool {
        abs(deviation) < max(0.0, limit - 0.0000000001)
    }

    private static func normalizedLineAngleRadians(_ angle: Double) -> Double {
        var result = angle
        while result <= -.pi / 2.0 {
            result += .pi
        }
        while result > .pi / 2.0 {
            result -= .pi
        }
        return result
    }

    private static func minimize(_ objective: (Double) -> Double, lowerBound: Double, upperBound: Double) -> Double {
        let inverseGoldenRatio = (sqrt(5.0) - 1.0) / 2.0
        var lower = lowerBound
        var upper = upperBound
        var x1 = upper - inverseGoldenRatio * (upper - lower)
        var x2 = lower + inverseGoldenRatio * (upper - lower)
        var f1 = objective(x1)
        var f2 = objective(x2)

        for _ in 0..<48 {
            if f1 > f2 {
                lower = x1
                x1 = x2
                f1 = f2
                x2 = lower + inverseGoldenRatio * (upper - lower)
                f2 = objective(x2)
            } else {
                upper = x2
                x2 = x1
                f2 = f1
                x1 = upper - inverseGoldenRatio * (upper - lower)
                f1 = objective(x1)
            }
        }

        return (lower + upper) / 2.0
    }
}
