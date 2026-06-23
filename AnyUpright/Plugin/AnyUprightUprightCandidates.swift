//
//  AnyUprightUprightCandidates.swift
//  AnyUpright
//

import Foundation

let uprightCandidateOSCPartBase = 1000

struct UprightCandidateSpec {
    var visible: UInt32
    var selected: UInt32
    var orientation: UInt32
    var start: UInt32
    var end: UInt32
    var score: UInt32
    var group: UInt32
    var linePart: Int
}

enum UprightGuideOrientation: Int32 {
    case vertical = 0
    case horizontal = 1
}

struct UprightCandidateLine {
    var spec: UprightCandidateSpec
    var selected: Bool
    var orientation: UprightGuideOrientation
    var start: AUPoint
    var end: AUPoint
    var score: Double
}

struct UprightDetectedCandidate {
    var orientation: UprightGuideOrientation
    var start: AUPoint
    var end: AUPoint
    var score: Double
}

enum AnyUprightUprightCandidates {
    static let slotCount = 40
    static let specs: [UprightCandidateSpec] = (0..<slotCount).map { index in
        let base = UInt32(430 + index * 10)
        return UprightCandidateSpec(
            visible: base,
            selected: base + 1,
            orientation: base + 2,
            start: base + 3,
            end: base + 4,
            score: base + 5,
            group: base + 9,
            linePart: uprightCandidateOSCPartBase + index
        )
    }

    static func slotLimit(isFullMode: Bool) -> Int {
        isFullMode ? max(1, slotCount / 2) : slotCount
    }

    static func detectedCandidates(
        from candidates: [AULineCandidate],
        orientation: UprightGuideOrientation,
        size: AUSize
    ) -> [UprightDetectedCandidate] {
        candidates.map { candidate in
            let object = objectLine(from: candidate.line, size: size)
            return UprightDetectedCandidate(
                orientation: orientation,
                start: object.start,
                end: object.end,
                score: detectionScore(for: candidate, orientation: orientation, size: size)
            )
        }
    }

    static func displayCandidates(
        from candidates: [UprightCandidateLine],
        chooseFromDetections: Bool,
        threshold: Double
    ) -> [UprightCandidateLine] {
        guard chooseFromDetections else {
            return []
        }

        let clampedThreshold = min(1.0, max(0.0, threshold))
        return candidates.filter { $0.selected || $0.score >= clampedThreshold }
    }

    static func selectedImageLines(from candidates: [UprightCandidateLine], orientation: UprightGuideOrientation) -> [AULineSegment] {
        Array(
            candidates
                .filter { $0.selected && $0.orientation == orientation }
                .prefix(2)
                .map { imageLine(from: $0, size: AUSize(width: 1.0, height: 1.0)) }
        )
    }

    static func selectionValueAfterToggling(_ candidate: UprightCandidateLine, within candidates: [UprightCandidateLine], maximumSelectedPerOrientation: Int = 2) -> Bool {
        guard !candidate.selected else {
            return false
        }

        let selectedCount = candidates.filter {
            $0.selected && $0.orientation == candidate.orientation
        }.count
        return selectedCount < maximumSelectedPerOrientation
    }

    static func imageLine(from candidate: UprightCandidateLine, size: AUSize) -> AULineSegment {
        AULineSegment(
            start: AUPoint(x: candidate.start.x * size.width, y: (1.0 - candidate.start.y) * size.height),
            end: AUPoint(x: candidate.end.x * size.width, y: (1.0 - candidate.end.y) * size.height)
        )
    }

    static func objectLine(from imageLine: AULineSegment, size: AUSize) -> (start: AUPoint, end: AUPoint) {
        let width = max(1.0, size.width)
        let height = max(1.0, size.height)

        func convert(_ point: AUPoint) -> AUPoint {
            AUPoint(
                x: min(1.0, max(0.0, point.x / width)),
                y: min(1.0, max(0.0, 1.0 - point.y / height))
            )
        }

        return (convert(imageLine.start), convert(imageLine.end))
    }

    static func candidateIndex(for activePart: Int) -> Int? {
        let index = activePart - uprightCandidateOSCPartBase
        guard index >= 0, index < specs.count else {
            return nil
        }
        return index
    }

    static func distanceFromPointToSegment(_ point: AUPoint, start: AUPoint, end: AUPoint, size: AUSize) -> Double {
        let px = point.x * size.width
        let py = point.y * size.height
        let sx = start.x * size.width
        let sy = start.y * size.height
        let ex = end.x * size.width
        let ey = end.y * size.height
        let dx = ex - sx
        let dy = ey - sy
        let lengthSquared = dx * dx + dy * dy

        guard lengthSquared > 0.000001 else {
            return hypot(px - sx, py - sy)
        }

        let t = min(1.0, max(0.0, ((px - sx) * dx + (py - sy) * dy) / lengthSquared))
        let closestX = sx + t * dx
        let closestY = sy + t * dy
        return hypot(px - closestX, py - closestY)
    }

    private static func detectionScore(for candidate: AULineCandidate, orientation: UprightGuideOrientation, size: AUSize) -> Double {
        let maxDeviation = Double.pi / 6.0
        let angleScore = max(0.0, 1.0 - candidate.absoluteDeviationRadians / maxDeviation)
        let axis = orientation == .vertical ? max(1.0, size.height) : max(1.0, size.width)
        let lengthScore = min(1.0, candidate.length / max(1.0, axis * 0.45))
        return min(1.0, max(0.0, 0.35 * angleScore + 0.65 * lengthScore))
    }
}
