//
//  AnyUprightStretchOSCEventResolver.swift
//  AnyUpright
//

import Foundation
import AppKit
import CoreImage
import IOSurface
import Vision

enum StretchOSCPart: Int {
    case none = 0
    case topLeft = 1
    case topRight = 2
    case bottomRight = 3
    case bottomLeft = 4
    case stretch = 5
    case topEdge = 6
    case rightEdge = 7
    case bottomEdge = 8
    case leftEdge = 9
}

struct StretchOSCDragState {
    var part: StretchOSCPart
    var lastCanvasPoint: AUPoint
    var eventCoordinateMode: StretchOSCEventCoordinateMode
}

enum StretchOSCEventCoordinateMode {
    case rawCanvas
    case mappedSurface
}

extension StretchOSCEventCoordinateMode: CustomStringConvertible {
    var description: String {
        switch self {
        case .rawCanvas:
            return "rawCanvas"
        case .mappedSurface:
            return "mappedSurface"
        }
    }
}

struct StretchOSCEventResolution {
    var canvasPoint: AUPoint
    var coordinateMode: StretchOSCEventCoordinateMode
}

struct StretchOSCHitGeometry {
    var handles: [AUOSCHandle]
    var stretch: [AUPoint]
}

extension AnyUprightInnerStretchOSCPlugIn {
    func stretchCanvasPoints(from objectPoints: AUStretchCorners) -> AUStretchCorners {
        AUStretchCorners(
            topLeft: canvasPoint(fromObjectPoint: objectPoints.topLeft),
            topRight: canvasPoint(fromObjectPoint: objectPoints.topRight),
            bottomRight: canvasPoint(fromObjectPoint: objectPoints.bottomRight),
            bottomLeft: canvasPoint(fromObjectPoint: objectPoints.bottomLeft)
        )
    }

    func hitGeometry(from state: AnyUprightParameterState, size: AUSize, mode: AUStretchTransformMode) -> StretchOSCHitGeometry {
        let objectPoints = stretchObjectPoints(from: state, size: size, mode: mode)
        let canvasPoints = stretchCanvasPoints(from: objectPoints)
        let handles = [
            AUOSCHandle(point: canvasPoints.topLeft, part: StretchOSCPart.topLeft.rawValue),
            AUOSCHandle(point: canvasPoints.topRight, part: StretchOSCPart.topRight.rawValue),
            AUOSCHandle(point: canvasPoints.bottomRight, part: StretchOSCPart.bottomRight.rawValue),
            AUOSCHandle(point: canvasPoints.bottomLeft, part: StretchOSCPart.bottomLeft.rawValue)
        ]

        return StretchOSCHitGeometry(
            handles: handles,
            stretch: [canvasPoints.topLeft, canvasPoints.topRight, canvasPoints.bottomRight, canvasPoints.bottomLeft]
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
        stretch: [AUPoint],
        canvasFrame: [AUPoint],
        rawCanvasHitPadding: Double,
        preferredMode: StretchOSCEventCoordinateMode?
    ) -> (part: StretchOSCPart, resolution: StretchOSCEventResolution)? {
        let resolutions = eventResolutions(
            fromEventPoint: eventPoint,
            canvasFrame: canvasFrame,
            visibleControlPoints: stretch,
            rawCanvasHitPadding: rawCanvasHitPadding,
            preferredMode: preferredMode
        )
        let hitRadius = 24.0
        var closestHandleHit: (part: StretchOSCPart, resolution: StretchOSCEventResolution, distance: Double)?

        for candidate in hitCandidates(for: resolutions, handles: handles, stretch: stretch) {
            let resolution = candidate.resolution
            for handle in candidate.handles {
                let dx = resolution.canvasPoint.x - handle.point.x
                let dy = resolution.canvasPoint.y - handle.point.y
                let distance = hypot(dx, dy)
                if distance <= hitRadius,
                   let part = StretchOSCPart(rawValue: handle.part) {
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
        var closestEdgeHit: (part: StretchOSCPart, resolution: StretchOSCEventResolution, distance: Double)?
        for candidate in hitCandidates(for: resolutions, handles: handles, stretch: stretch) {
            let resolution = candidate.resolution
            let edges: [(StretchOSCPart, AUPoint, AUPoint)] = [
                (.topEdge, candidate.stretch[0], candidate.stretch[1]),
                (.rightEdge, candidate.stretch[1], candidate.stretch[2]),
                (.bottomEdge, candidate.stretch[3], candidate.stretch[2]),
                (.leftEdge, candidate.stretch[0], candidate.stretch[3])
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

        for candidate in hitCandidates(for: resolutions, handles: handles, stretch: stretch) {
            if isPoint(candidate.resolution.canvasPoint, insideStretch: candidate.stretch) {
                return (.stretch, candidate.resolution)
            }
        }

        return nil
    }

    func hitCandidates(
        for resolutions: [StretchOSCEventResolution],
        handles: [AUOSCHandle],
        stretch: [AUPoint]
    ) -> [(resolution: StretchOSCEventResolution, handles: [AUOSCHandle], stretch: [AUPoint])] {
        resolutions.map { resolution in
            // FxPlug CANVAS callbacks and the points passed to the OSC renderer
            // share this Y-up layer. The renderer/host composition owns the
            // display-space crossing.
            return (resolution, handles, stretch)
        }
    }

    func eventResolutions(
        fromEventPoint eventPoint: AUPoint,
        canvasFrame: [AUPoint],
        visibleControlPoints: [AUPoint],
        rawCanvasHitPadding: Double,
        preferredMode: StretchOSCEventCoordinateMode?
    ) -> [StretchOSCEventResolution] {
        let raw = StretchOSCEventResolution(canvasPoint: eventPoint, coordinateMode: .rawCanvas)
        guard let mapper = eventMapper(for: canvasFrame) else {
            return [raw]
        }

        let mapped = StretchOSCEventResolution(canvasPoint: mapper.canvasPoint(fromEventPoint: eventPoint), coordinateMode: .mappedSurface)
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
            visibleControlPoints: visibleControlPoints,
            hitPadding: rawCanvasHitPadding,
            hostBundleIdentifier: AnyUprightHostContext.hostBundleIdentifier
        )
            ? [mapped]
            : [raw]
    }

    func resolvedCanvasPoint(
        fromEventPoint eventPoint: AUPoint,
        canvasFrame: [AUPoint],
        visibleControlPoints: [AUPoint],
        rawCanvasHitPadding: Double,
        preferredMode: StretchOSCEventCoordinateMode?
    ) -> StretchOSCEventResolution {
        return eventResolutions(
            fromEventPoint: eventPoint,
            canvasFrame: canvasFrame,
            visibleControlPoints: visibleControlPoints,
            rawCanvasHitPadding: rawCanvasHitPadding,
            preferredMode: preferredMode
        ).first
            ?? StretchOSCEventResolution(canvasPoint: eventPoint, coordinateMode: .rawCanvas)
    }

    func validDragPart(from rawValue: Int) -> StretchOSCPart? {
        guard let part = StretchOSCPart(rawValue: rawValue), part != .none else {
            return nil
        }
        return part
    }

    func corners(forEdgePart part: StretchOSCPart) -> [AUStretchCorner]? {
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

    func dragObjectPoint(from resolution: StretchOSCEventResolution, mode: AUStretchTransformMode, sourceSize: AUSize) -> AUPoint {
        let objectPoint = objectPoint(fromCanvasPoint: resolution.canvasPoint)
        return innerStretchDragPoint(from: objectPoint, mode: mode, coordinateMode: resolution.coordinateMode)
    }

    func innerStretchDragPoint(from point: AUPoint, mode: AUStretchTransformMode, coordinateMode: StretchOSCEventCoordinateMode) -> AUPoint {
        // Canvas conversion already returns FxPlug's Y-up object coordinates.
        // Parameter writeback must not apply another Y conversion.
        point
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

    func isPoint(_ point: AUPoint, insideStretch stretch: [AUPoint]) -> Bool {
        guard stretch.count == 4 else {
            return false
        }

        var hasPositive = false
        var hasNegative = false
        for index in 0..<stretch.count {
            let current = stretch[index]
            let next = stretch[(index + 1) % stretch.count]
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
