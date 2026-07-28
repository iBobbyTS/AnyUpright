//
//  AnyUprightUprightV2GuideSelector.swift
//  AnyUpright
//

import Foundation

struct AUUprightV2GuideSelection {
    var guides: [UprightDetectedCandidate]
    var selected: Bool
    var preparedLineCount: Int
    var vpClusterCount: Int
    var candidateCount: Int
    var pairCount: Int
    var rankScore: Double?
    var riskProbability: Double?
    var verticalSupporterCount: Int
    var horizontalSupporterCount: Int
}

enum AnyUprightUprightV2GuideSelector {
    static func select(
        lines: [AUScaleLSDLineSegment],
        imageSize: AUSize,
        cameraPrior: AUUprightV2CameraPrior?
    ) throws -> AUUprightV2GuideSelection {
        let pool = AnyUprightUprightV2CandidateGenerator.candidatePool(
            lines: lines,
            imageSize: imageSize,
            cameraPrior: cameraPrior
        )
        guard let selection = try AnyUprightUprightV2Ranker.select(
            candidates: pool.candidates,
            lines: lines,
            imageSize: imageSize,
            preparedLineCount: pool.preparedLineCount,
            vpClusterCount: pool.vpClusterCount
        ) else {
            return AUUprightV2GuideSelection(
                guides: [],
                selected: false,
                preparedLineCount: pool.preparedLineCount,
                vpClusterCount: pool.vpClusterCount,
                candidateCount: pool.candidates.count,
                pairCount: 0,
                rankScore: nil,
                riskProbability: nil,
                verticalSupporterCount: 0,
                horizontalSupporterCount: 0
            )
        }
        let vertical = representativeCandidates(
            supporterIndexes: selection.candidate.verticalSupporters,
            orientation: .vertical,
            lines: lines,
            imageSize: imageSize
        )
        let horizontal = representativeCandidates(
            supporterIndexes: selection.candidate.horizontalSupporters,
            orientation: .horizontal,
            lines: lines,
            imageSize: imageSize
        )
        return AUUprightV2GuideSelection(
            guides: vertical + horizontal,
            selected: true,
            preparedLineCount: pool.preparedLineCount,
            vpClusterCount: pool.vpClusterCount,
            candidateCount: pool.candidates.count,
            pairCount: selection.pairCount,
            rankScore: selection.rankScore,
            riskProbability: selection.riskProbability,
            verticalSupporterCount: selection.candidate.verticalSupporters.count,
            horizontalSupporterCount: selection.candidate.horizontalSupporters.count
        )
    }

    static func representativeCandidates(
        supporterIndexes: [Int],
        orientation: UprightGuideOrientation,
        lines: [AUScaleLSDLineSegment],
        imageSize: AUSize
    ) -> [UprightDetectedCandidate] {
        let valid = Array(Set(supporterIndexes)).sorted().filter(lines.indices.contains)
        guard !valid.isEmpty else {
            return []
        }
        let diagonal = max(1.0, hypot(imageSize.width, imageSize.height))
        let maximumScore = max(1.0, lines.map(\.score).max() ?? 1.0)
        let scoreScale = log1p(maximumScore)

        func quality(_ index: Int) -> Double {
            let line = lines[index]
            let length = hypot(line.end.x - line.start.x, line.end.y - line.start.y)
            return (log1p(max(0.0, line.score)) / scoreScale)
                * sqrt(min(1.0, length / diagonal))
        }

        var selected = [valid.max {
            let lhs = quality($0)
            let rhs = quality($1)
            return lhs == rhs ? $0 > $1 : lhs < rhs
        }!]
        if valid.count > 1 {
            let first = selected[0]
            let firstLine = lines[first]
            let firstMidpoint = AUPoint(
                x: (firstLine.start.x + firstLine.end.x) * 0.5,
                y: (firstLine.start.y + firstLine.end.y) * 0.5
            )
            if let second = valid.filter({ $0 != first }).max(by: { lhs, rhs in
                func utility(_ index: Int) -> Double {
                    let line = lines[index]
                    let midpoint = AUPoint(
                        x: (line.start.x + line.end.x) * 0.5,
                        y: (line.start.y + line.end.y) * 0.5
                    )
                    let separation = min(
                        1.0,
                        hypot(midpoint.x - firstMidpoint.x, midpoint.y - firstMidpoint.y) / diagonal
                    )
                    return quality(index) * (0.5 + 0.5 * separation)
                }
                let left = utility(lhs)
                let right = utility(rhs)
                return left == right ? lhs > rhs : left < right
            }) {
                selected.append(second)
            }
        }
        return selected.enumerated().map { rank, index in
            let line = lines[index]
            let object = AnyUprightUprightCandidates.objectLine(
                from: AULineSegment(start: line.start, end: line.end),
                size: imageSize
            )
            return UprightDetectedCandidate(
                orientation: orientation,
                start: object.start,
                end: object.end,
                score: 1.0 - Double(rank) * 0.001
            )
        }
    }
}
