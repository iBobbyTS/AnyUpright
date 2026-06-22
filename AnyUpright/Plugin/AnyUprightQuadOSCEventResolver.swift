//
//  AnyUprightQuadOSCEventResolver.swift
//  AnyUpright
//

import Foundation
import AppKit
import CoreImage
import IOSurface
import Vision

enum QuadOSCPart: Int {
    case none = 0
    case topLeft = 1
    case topRight = 2
    case bottomRight = 3
    case bottomLeft = 4
    case quad = 5
    case topEdge = 6
    case rightEdge = 7
    case bottomEdge = 8
    case leftEdge = 9
}

struct QuadOSCDragState {
    var part: QuadOSCPart
    var lastCanvasPoint: AUPoint
    var eventCoordinateMode: QuadOSCEventCoordinateMode
}

enum QuadOSCEventCoordinateMode {
    case rawCanvas
    case mappedSurface
}

extension QuadOSCEventCoordinateMode: CustomStringConvertible {
    var description: String {
        switch self {
        case .rawCanvas:
            return "rawCanvas"
        case .mappedSurface:
            return "mappedSurface"
        }
    }
}

struct QuadOSCEventResolution {
    var canvasPoint: AUPoint
    var coordinateMode: QuadOSCEventCoordinateMode
}

struct QuadOSCHitGeometry {
    var handles: [AUOSCHandle]
    var quad: [AUPoint]
    var rawCanvasHandles: [AUOSCHandle]
    var rawCanvasQuad: [AUPoint]
    var usesRawCanvasHitLayer: Bool
}

extension AnyUprightInnerStretchOSCPlugIn {
    func quadCanvasPoints(from objectPoints: AUQuad) -> AUQuad {
        AUQuad(
            topLeft: canvasPoint(fromObjectPoint: objectPoints.topLeft),
            topRight: canvasPoint(fromObjectPoint: objectPoints.topRight),
            bottomRight: canvasPoint(fromObjectPoint: objectPoints.bottomRight),
            bottomLeft: canvasPoint(fromObjectPoint: objectPoints.bottomLeft)
        )
    }

    func rawHitTestCanvasPoints(from objectPoints: AUQuad, mode: AUQuadTransformMode) -> AUQuad {
        switch mode {
        case .outputCorners:
            return quadCanvasPoints(from: objectPoints)
        case .sourceQuad:
            // Inner Stretch's render preview is top-origin image/output geometry; raw Final Cut canvas events need that same visible layer.
            return quadCanvasPoints(from: AnyUprightGeometry.verticallyFlippedObjectQuad(objectPoints))
        }
    }

    func hitGeometry(from state: AnyUprightParameterState, size: AUSize, mode: AUQuadTransformMode) -> QuadOSCHitGeometry {
        let objectPoints = quadObjectPoints(from: state, size: size, mode: mode)
        let canvasPoints = quadCanvasPoints(from: objectPoints)
        let rawCanvasPoints = rawHitTestCanvasPoints(from: objectPoints, mode: mode)
        let handles = [
            AUOSCHandle(point: canvasPoints.topLeft, part: QuadOSCPart.topLeft.rawValue),
            AUOSCHandle(point: canvasPoints.topRight, part: QuadOSCPart.topRight.rawValue),
            AUOSCHandle(point: canvasPoints.bottomRight, part: QuadOSCPart.bottomRight.rawValue),
            AUOSCHandle(point: canvasPoints.bottomLeft, part: QuadOSCPart.bottomLeft.rawValue)
        ]
        let rawHandles = [
            AUOSCHandle(point: rawCanvasPoints.topLeft, part: QuadOSCPart.topLeft.rawValue),
            AUOSCHandle(point: rawCanvasPoints.topRight, part: QuadOSCPart.topRight.rawValue),
            AUOSCHandle(point: rawCanvasPoints.bottomRight, part: QuadOSCPart.bottomRight.rawValue),
            AUOSCHandle(point: rawCanvasPoints.bottomLeft, part: QuadOSCPart.bottomLeft.rawValue)
        ]

        return QuadOSCHitGeometry(
            handles: handles,
            quad: [canvasPoints.topLeft, canvasPoints.topRight, canvasPoints.bottomRight, canvasPoints.bottomLeft],
            rawCanvasHandles: rawHandles,
            rawCanvasQuad: [rawCanvasPoints.topLeft, rawCanvasPoints.topRight, rawCanvasPoints.bottomRight, rawCanvasPoints.bottomLeft],
            usesRawCanvasHitLayer: mode == .sourceQuad
        )
    }

    func objectCanvasFrame() -> [AUPoint] {
        [
            canvasPoint(fromObjectPoint: AUPoint(x: 0.0, y: 1.0)),
            canvasPoint(fromObjectPoint: AUPoint(x: 1.0, y: 1.0)),
            canvasPoint(fromObjectPoint: AUPoint(x: 1.0, y: 0.0)),
            canvasPoint(fromObjectPoint: AUPoint(x: 0.0, y: 0.0))
        ]
    }

    func canvasPoint(fromObjectPoint point: AUPoint) -> AUPoint {
        convertPoint(point, from: kFxDrawingCoordinates_OBJECT, to: kFxDrawingCoordinates_CANVAS)
    }

    func objectPoint(fromCanvasPoint point: AUPoint) -> AUPoint {
        convertPoint(point, from: kFxDrawingCoordinates_CANVAS, to: kFxDrawingCoordinates_OBJECT)
    }

    func convertPoint(_ point: AUPoint, from fromSpace: Int, to toSpace: Int) -> AUPoint {
        guard let oscAPI = _apiManager.api(for: FxOnScreenControlAPI_v4.self) as? FxOnScreenControlAPI_v4 else {
            return point
        }

        var x = 0.0
        var y = 0.0
        oscAPI.convertPoint(
            fromSpace: FxDrawingCoordinates(fromSpace),
            fromX: point.x,
            fromY: point.y,
            toSpace: FxDrawingCoordinates(toSpace),
            toX: &x,
            toY: &y
        )
        return AUPoint(x: x, y: y)
    }

    func eventMapper(for canvasFrame: [AUPoint]) -> AUCanvasSurfaceMapper? {
        let surfaceSize = currentSurfaceSize()
        guard surfaceSize.width > 1.0, surfaceSize.height > 1.0 else {
            return nil
        }

        return AUCanvasSurfaceMapper(canvasFrame: canvasFrame, surfaceSize: surfaceSize)
    }

    func hitTestPart(
        forEventPoint eventPoint: AUPoint,
        handles: [AUOSCHandle],
        quad: [AUPoint],
        rawCanvasHandles: [AUOSCHandle],
        rawCanvasQuad: [AUPoint],
        useRawCanvasHitLayer: Bool,
        canvasFrame: [AUPoint],
        rawCanvasHitPadding: Double,
        preferredMode: QuadOSCEventCoordinateMode?
    ) -> (part: QuadOSCPart, resolution: QuadOSCEventResolution)? {
        let resolutions = eventResolutions(
            fromEventPoint: eventPoint,
            canvasFrame: canvasFrame,
            rawCanvasQuad: rawCanvasQuad,
            rawCanvasHitPadding: rawCanvasHitPadding,
            preferredMode: preferredMode
        )
        let hitRadius = 24.0
        var closestHandleHit: (part: QuadOSCPart, resolution: QuadOSCEventResolution, distance: Double)?

        for candidate in hitCandidates(for: resolutions, handles: handles, quad: quad, rawCanvasHandles: rawCanvasHandles, rawCanvasQuad: rawCanvasQuad, useRawCanvasHitLayer: useRawCanvasHitLayer) {
            let resolution = candidate.resolution
            for handle in candidate.handles {
                let dx = resolution.canvasPoint.x - handle.point.x
                let dy = resolution.canvasPoint.y - handle.point.y
                let distance = hypot(dx, dy)
                if distance <= hitRadius,
                   let part = QuadOSCPart(rawValue: handle.part) {
                    if closestHandleHit == nil || distance < closestHandleHit!.distance {
                        closestHandleHit = (part, resolution, distance)
                    }
                }
            }
        }

        if let closestHandleHit {
            return (closestHandleHit.part, closestHandleHit.resolution)
        }

        let edgeHitRadius = 14.0
        var closestEdgeHit: (part: QuadOSCPart, resolution: QuadOSCEventResolution, distance: Double)?
        for candidate in hitCandidates(for: resolutions, handles: handles, quad: quad, rawCanvasHandles: rawCanvasHandles, rawCanvasQuad: rawCanvasQuad, useRawCanvasHitLayer: useRawCanvasHitLayer) {
            let resolution = candidate.resolution
            let edges: [(QuadOSCPart, AUPoint, AUPoint)] = [
                (.topEdge, candidate.quad[0], candidate.quad[1]),
                (.rightEdge, candidate.quad[1], candidate.quad[2]),
                (.bottomEdge, candidate.quad[3], candidate.quad[2]),
                (.leftEdge, candidate.quad[0], candidate.quad[3])
            ]
            for edge in edges {
                let distance = distance(from: resolution.canvasPoint, toSegmentStart: edge.1, end: edge.2)
                if distance <= edgeHitRadius {
                    if closestEdgeHit == nil || distance < closestEdgeHit!.distance {
                        closestEdgeHit = (edge.0, resolution, distance)
                    }
                }
            }
        }

        if let closestEdgeHit {
            return (closestEdgeHit.part, closestEdgeHit.resolution)
        }

        for candidate in hitCandidates(for: resolutions, handles: handles, quad: quad, rawCanvasHandles: rawCanvasHandles, rawCanvasQuad: rawCanvasQuad, useRawCanvasHitLayer: useRawCanvasHitLayer) {
            if isPoint(candidate.resolution.canvasPoint, insideQuad: candidate.quad) {
                return (.quad, candidate.resolution)
            }
        }

        return nil
    }

    func hitCandidates(
        for resolutions: [QuadOSCEventResolution],
        handles: [AUOSCHandle],
        quad: [AUPoint],
        rawCanvasHandles: [AUOSCHandle],
        rawCanvasQuad: [AUPoint],
        useRawCanvasHitLayer: Bool
    ) -> [(resolution: QuadOSCEventResolution, handles: [AUOSCHandle], quad: [AUPoint])] {
        resolutions.map { resolution in
            if resolution.coordinateMode == .rawCanvas || useRawCanvasHitLayer {
                return (resolution, rawCanvasHandles, rawCanvasQuad)
            }
            return (resolution, handles, quad)
        }
    }

    func eventResolutions(
        fromEventPoint eventPoint: AUPoint,
        canvasFrame: [AUPoint],
        rawCanvasQuad: [AUPoint],
        rawCanvasHitPadding: Double,
        preferredMode: QuadOSCEventCoordinateMode?
    ) -> [QuadOSCEventResolution] {
        let raw = QuadOSCEventResolution(canvasPoint: eventPoint, coordinateMode: .rawCanvas)
        guard let mapper = eventMapper(for: canvasFrame) else {
            return [raw]
        }

        let mapped = QuadOSCEventResolution(canvasPoint: mapper.canvasPoint(fromEventPoint: eventPoint), coordinateMode: .mappedSurface)
        if let preferredMode {
            switch preferredMode {
            case .rawCanvas:
                return [raw]
            case .mappedSurface:
                return [mapped]
            }
        }

        return shouldUseMappedSurfaceOSCEvent(
            forInitialEventPoint: eventPoint,
            mappedCanvasPoint: mapped.canvasPoint,
            canvasFrame: canvasFrame,
            visibleControlPoints: rawCanvasQuad,
            hitPadding: rawCanvasHitPadding,
            hostBundleIdentifier: AnyUprightHostContext.hostBundleIdentifier
        )
            ? [mapped]
            : [raw]
    }

    func resolvedCanvasPoint(
        fromEventPoint eventPoint: AUPoint,
        canvasFrame: [AUPoint],
        rawCanvasQuad: [AUPoint],
        rawCanvasHitPadding: Double,
        preferredMode: QuadOSCEventCoordinateMode?
    ) -> QuadOSCEventResolution {
        return eventResolutions(
            fromEventPoint: eventPoint,
            canvasFrame: canvasFrame,
            rawCanvasQuad: rawCanvasQuad,
            rawCanvasHitPadding: rawCanvasHitPadding,
            preferredMode: preferredMode
        ).first
            ?? QuadOSCEventResolution(canvasPoint: eventPoint, coordinateMode: .rawCanvas)
    }

    func validDragPart(from rawValue: Int) -> QuadOSCPart? {
        guard let part = QuadOSCPart(rawValue: rawValue), part != .none else {
            return nil
        }
        return part
    }

    func corners(forEdgePart part: QuadOSCPart) -> [AUQuadCorner]? {
        switch part {
        case .topEdge:
            return [.topLeft, .topRight]
        case .rightEdge:
            return [.topRight, .bottomRight]
        case .bottomEdge:
            return [.bottomLeft, .bottomRight]
        case .leftEdge:
            return [.topLeft, .bottomLeft]
        default:
            return nil
        }
    }

    func dragObjectPoint(from resolution: QuadOSCEventResolution, mode: AUQuadTransformMode, sourceSize: AUSize) -> AUPoint {
        let rawObjectPoint = objectPoint(fromCanvasPoint: resolution.canvasPoint)
        return sourceQuadDragPoint(from: rawObjectPoint, mode: mode, coordinateMode: resolution.coordinateMode)
    }

    func sourceQuadDragPoint(from point: AUPoint, mode: AUQuadTransformMode, coordinateMode: QuadOSCEventCoordinateMode) -> AUPoint {
        guard mode == .sourceQuad,
              coordinateMode == .rawCanvas else {
            return point
        }

        return AnyUprightGeometry.verticallyFlippedObjectPoint(point)
    }

    func distance(from point: AUPoint, toSegmentStart start: AUPoint, end: AUPoint) -> Double {
        let vx = end.x - start.x
        let vy = end.y - start.y
        let lengthSquared = vx * vx + vy * vy
        guard lengthSquared > 0.0 else {
            return hypot(point.x - start.x, point.y - start.y)
        }

        let t = max(0.0, min(1.0, ((point.x - start.x) * vx + (point.y - start.y) * vy) / lengthSquared))
        let closest = AUPoint(x: start.x + t * vx, y: start.y + t * vy)
        return hypot(point.x - closest.x, point.y - closest.y)
    }

    func isPoint(_ point: AUPoint, insideQuad quad: [AUPoint]) -> Bool {
        guard quad.count == 4 else {
            return false
        }

        var hasPositive = false
        var hasNegative = false
        for index in 0..<quad.count {
            let current = quad[index]
            let next = quad[(index + 1) % quad.count]
            let cross = (next.x - current.x) * (point.y - current.y) - (next.y - current.y) * (point.x - current.x)
            hasPositive = hasPositive || cross > 0.0
            hasNegative = hasNegative || cross < 0.0
            if hasPositive && hasNegative {
                return false
            }
        }
        return true
    }
}
