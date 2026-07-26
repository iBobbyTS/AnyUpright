//
//  AnyUprightScaleLSDPreprocessor.swift
//  AnyUpright
//

import Foundation

enum AnyUprightScaleLSDPreprocessor {
    private static let maximumAxisDeviationRadians = Double.pi / 6.0

    static func detectedCandidates(
        from lines: [AUScaleLSDLineSegment],
        imageSize: AUSize,
        referenceImageSize: AUSize? = nil
    ) -> [UprightDetectedCandidate] {
        let referenceSize = referenceImageSize ?? imageSize
        let orientedLines = lines.compactMap { line -> (AUScaleLSDLineSegment, UprightGuideOrientation, AUPoint, AUPoint)? in
            let object = AnyUprightUprightCandidates.objectLine(
                from: AULineSegment(start: line.start, end: line.end),
                size: imageSize
            )
            guard let orientation = guideOrientation(
                from: object.start,
                to: object.end,
                referenceImageSize: referenceSize
            ) else {
                return nil
            }
            return (line, orientation, object.start, object.end)
        }
        let maximumScore = max(1.0, orientedLines.map { $0.0.score }.max() ?? 1.0)
        let scoreScale = log1p(maximumScore)
        return orientedLines.map { line, orientation, start, end in
            return UprightDetectedCandidate(
                orientation: orientation,
                start: start,
                end: end,
                score: scoreScale > 0.0 ? log1p(max(0.0, line.score)) / scoreScale : 0.0
            )
        }
    }

    private static func guideOrientation(
        from start: AUPoint,
        to end: AUPoint,
        referenceImageSize: AUSize
    ) -> UprightGuideOrientation? {
        let dx = abs(end.x - start.x) * max(1.0, referenceImageSize.width)
        let dy = abs(end.y - start.y) * max(1.0, referenceImageSize.height)
        guard hypot(dx, dy) > 0.000001 else {
            return nil
        }
        if atan2(dy, dx) <= maximumAxisDeviationRadians {
            return .horizontal
        }
        if atan2(dx, dy) <= maximumAxisDeviationRadians {
            return .vertical
        }
        return nil
    }
}
