//
//  AnyUprightUprightV2Ranker.swift
//  AnyUpright
//

import Foundation

private extension AUScaleLSDLineSegment {
    var length: Double {
        hypot(end.x - start.x, end.y - start.y)
    }

    var midpoint: AUPoint {
        AUPoint(x: (start.x + end.x) * 0.5, y: (start.y + end.y) * 0.5)
    }
}

struct AUUprightV2Candidate: Equatable {
    var sourceToOutput: [Double]
    var cropScale: Double
    var verticalStrength: Double
    var horizontalStrength: Double
    var focalScale: Double
    var aspect: Double
    var terms: [Double]
    var verticalSupporters: [Int]
    var horizontalSupporters: [Int]

    init(
        sourceToOutput: [Double],
        cropScale: Double,
        verticalStrength: Double,
        horizontalStrength: Double,
        focalScale: Double,
        aspect: Double,
        terms: [Double],
        verticalSupporters: [Int],
        horizontalSupporters: [Int]
    ) {
        self.sourceToOutput = sourceToOutput
        self.cropScale = cropScale
        self.verticalStrength = verticalStrength
        self.horizontalStrength = horizontalStrength
        self.focalScale = focalScale
        self.aspect = aspect
        self.terms = terms
        self.verticalSupporters = verticalSupporters
        self.horizontalSupporters = horizontalSupporters
    }
}

struct AUUprightV2RankedSelection {
    var candidate: AUUprightV2Candidate
    var rankScore: Double
    var riskProbability: Double
    var pairCount: Int
}

enum AUUprightV2RankerError: Error {
    case invalidCandidate
    case invalidFeatures
}

enum AnyUprightUprightV2Ranker {
    static let energyWeights = [
        3.269085149614088,
        9.09972522486533,
        0.5996729742121445,
        2.778347387841852,
        0.38975067964593785,
        1.7209597748713872,
        3.1626423177036864,
        0.5353833291131055,
        0.31426088544295105,
        1.3892677976012975,
    ]

    static func select(
        candidates: [AUUprightV2Candidate],
        lines: [AUScaleLSDLineSegment],
        imageSize: AUSize,
        preparedLineCount: Int,
        vpClusterCount: Int,
        applyRiskGate: Bool = true
    ) throws -> AUUprightV2RankedSelection? {
        let pairs = uniqueFullCandidates(candidates)
        guard let bestEnergy = pairs.first.map(energy) else {
            return nil
        }
        var best: AUUprightV2RankedSelection?
        for (rank, candidate) in pairs.enumerated() {
            let features = try features(
                candidate: candidate,
                lines: lines,
                imageSize: imageSize,
                preparedLineCount: preparedLineCount,
                vpClusterCount: vpClusterCount,
                frozenRank: rank,
                candidateCount: pairs.count,
                bestEnergy: bestEnergy
            )
            let prediction = try AUUprightV2Models.predictions(features: features)
            if best == nil || prediction.rank > best!.rankScore {
                best = AUUprightV2RankedSelection(
                    candidate: candidate,
                    rankScore: prediction.rank,
                    riskProbability: prediction.risk,
                    pairCount: pairs.count
                )
            }
        }
        guard let best else {
            return nil
        }
        guard !applyRiskGate || best.riskProbability <= AUUprightV2Models.riskThreshold else {
            return nil
        }
        return best
    }

    static func features(
        candidate: AUUprightV2Candidate,
        lines: [AUScaleLSDLineSegment],
        imageSize: AUSize,
        preparedLineCount: Int,
        vpClusterCount: Int,
        frozenRank: Int,
        candidateCount: Int,
        bestEnergy: Double
    ) throws -> [Double] {
        guard candidate.terms.count == energyWeights.count,
              candidate.sourceToOutput.count == 9,
              imageSize.width > 0.0,
              imageSize.height > 0.0 else {
            throw AUUprightV2RankerError.invalidCandidate
        }
        let vertical = supporterFeatures(
            indexes: candidate.verticalSupporters,
            lines: lines,
            imageSize: imageSize,
            vertical: true
        )
        let horizontal = supporterFeatures(
            indexes: candidate.horizontalSupporters,
            lines: lines,
            imageSize: imageSize,
            vertical: false
        )
        let minimumCount = min(vertical.count, horizontal.count)
        let maximumCount = max(vertical.count, horizontal.count)
        let countRatio = Double(minimumCount) / Double(max(1, maximumCount))
        let minimumLength = min(vertical.totalLength, horizontal.totalLength)
        let maximumLength = max(vertical.totalLength, horizontal.totalLength)
        let lengthRatio = minimumLength / max(1e-12, maximumLength)
        let overlap = Set(candidate.verticalSupporters).intersection(candidate.horizontalSupporters).count
        let weightedEnergy = energy(candidate)
        let rawFeatures = candidate.terms + [
            candidate.verticalStrength,
            candidate.horizontalStrength,
            candidate.cropScale,
            weightedEnergy,
            weightedEnergy - bestEnergy,
            Double(frozenRank) / Double(max(1, candidateCount - 1)),
            Double(preparedLineCount) / 512.0,
            Double(vpClusterCount) / 64.0,
        ] + vertical.values + horizontal.values + [
            countRatio,
            lengthRatio,
            Double(overlap) / Double(max(1, minimumCount)),
            hypot(vertical.center.x - horizontal.center.x, vertical.center.y - horizontal.center.y),
        ] + intersectionFeatures(
            vertical.lines,
            horizontal.lines,
            imageSize: imageSize
        )
        let features = rawFeatures.map { Double(Float($0)) }
        guard features.count == AUUprightV2Models.expectedFeatureNames.count,
              features.allSatisfy(\.isFinite) else {
            throw AUUprightV2RankerError.invalidFeatures
        }
        return features
    }

    static func uniqueFullCandidates(
        _ candidates: [AUUprightV2Candidate]
    ) -> [AUUprightV2Candidate] {
        struct Key: Hashable {
            var vertical: [Int]
            var horizontal: [Int]
        }
        var representatives: [Key: AUUprightV2Candidate] = [:]
        for candidate in candidates where candidate.horizontalStrength > 0.0 {
            let key = Key(
                vertical: candidate.verticalSupporters.sorted(),
                horizontal: candidate.horizontalSupporters.sorted()
            )
            if let previous = representatives[key], energy(previous) <= energy(candidate) {
                continue
            }
            representatives[key] = candidate
        }
        return representatives.values.sorted {
            let lhs = energy($0)
            let rhs = energy($1)
            if lhs == rhs {
                if $0.verticalSupporters.lexicographicallyPrecedes($1.verticalSupporters) {
                    return true
                }
                if $1.verticalSupporters.lexicographicallyPrecedes($0.verticalSupporters) {
                    return false
                }
                return $0.horizontalSupporters.lexicographicallyPrecedes($1.horizontalSupporters)
            }
            return lhs < rhs
        }
    }

    static func energy(_ candidate: AUUprightV2Candidate) -> Double {
        zip(candidate.terms, energyWeights).reduce(0.0) {
            $0 + $1.0 * $1.1
        }
    }

    private struct SupporterSummary {
        var values: [Double]
        var count: Int
        var totalLength: Double
        var center: AUPoint
        var lines: [AUScaleLSDLineSegment]
    }

    private static func supporterFeatures(
        indexes: [Int],
        lines: [AUScaleLSDLineSegment],
        imageSize: AUSize,
        vertical: Bool
    ) -> SupporterSummary {
        let selected = indexes.compactMap { lines.indices.contains($0) ? lines[$0] : nil }
        guard !selected.isEmpty else {
            return SupporterSummary(
                values: Array(repeating: 0.0, count: 12),
                count: 0,
                totalLength: 0.0,
                center: AUPoint(x: 0.0, y: 0.0),
                lines: []
            )
        }
        let width = max(1.0, imageSize.width)
        let height = max(1.0, imageSize.height)
        let diagonal = max(1.0, hypot(width, height))
        let lengths = selected.map(\.length)
        let scores = selected.map(\.score)
        let midpoints = selected.map {
            AUPoint(x: $0.midpoint.x / width, y: $0.midpoint.y / height)
        }
        let points = selected.flatMap { [$0.start, $0.end] }
        let cells = Set(midpoints.map {
            min(3, max(0, Int($0.x * 4))) * 4 + min(3, max(0, Int($0.y * 4)))
        })
        let axisAlignment = mean(selected.map { line in
            let length = max(1e-12, line.length)
            return abs(vertical
                ? (line.end.y - line.start.y) / length
                : (line.end.x - line.start.x) / length)
        })
        let center = AUPoint(
            x: mean(midpoints.map(\.x)),
            y: mean(midpoints.map(\.y))
        )
        let totalLength = lengths.reduce(0.0, +)
        return SupporterSummary(
            values: [
                min(1.0, Double(selected.count) / 128.0),
                totalLength / (diagonal * 32.0),
                mean(lengths) / diagonal,
                mean(scores),
                center.x,
                center.y,
                standardDeviation(midpoints.map(\.x)),
                standardDeviation(midpoints.map(\.y)),
                Double(cells.count) / 16.0,
                ((points.map(\.x).max() ?? 0.0) - (points.map(\.x).min() ?? 0.0)) / width,
                ((points.map(\.y).max() ?? 0.0) - (points.map(\.y).min() ?? 0.0)) / height,
                axisAlignment,
            ],
            count: selected.count,
            totalLength: totalLength,
            center: center,
            lines: selected
        )
    }

    private static func intersectionFeatures(
        _ vertical: [AUScaleLSDLineSegment],
        _ horizontal: [AUScaleLSDLineSegment],
        imageSize: AUSize
    ) -> [Double] {
        let first = vertical.sorted {
            $0.length * $0.score > $1.length * $1.score
        }.prefix(24)
        let second = horizontal.sorted {
            $0.length * $0.score > $1.length * $1.score
        }.prefix(24)
        let requested = first.count * second.count
        let width = max(1.0, imageSize.width)
        let height = max(1.0, imageSize.height)
        var points: [AUPoint] = []
        points.reserveCapacity(requested)
        for verticalLine in first {
            for horizontalLine in second {
                guard let point = intersection(verticalLine, horizontalLine) else {
                    continue
                }
                points.append(AUPoint(x: point.x / width, y: point.y / height))
            }
        }
        guard !points.isEmpty else {
            return Array(repeating: 0.0, count: 5)
        }
        let inside = points.filter {
            $0.x >= 0.0 && $0.x <= 1.0 && $0.y >= 0.0 && $0.y <= 1.0
        }.count
        let xs = points.map { min(3.0, max(-2.0, $0.x)) }
        let ys = points.map { min(3.0, max(-2.0, $0.y)) }
        let center = AUPoint(x: median(points.map(\.x)), y: median(points.map(\.y)))
        return [
            Double(points.count) / Double(max(1, requested)),
            Double(inside) / Double(points.count),
            standardDeviation(xs),
            standardDeviation(ys),
            hypot(center.x - 0.5, center.y - 0.5),
        ]
    }

    private static func intersection(
        _ first: AUScaleLSDLineSegment,
        _ second: AUScaleLSDLineSegment
    ) -> AUPoint? {
        let firstCoefficients = coefficients(first)
        let secondCoefficients = coefficients(second)
        let x = firstCoefficients.b * secondCoefficients.c
            - firstCoefficients.c * secondCoefficients.b
        let y = firstCoefficients.c * secondCoefficients.a
            - firstCoefficients.a * secondCoefficients.c
        let z = firstCoefficients.a * secondCoefficients.b
            - firstCoefficients.b * secondCoefficients.a
        guard abs(z) > 1e-9 else {
            return nil
        }
        let point = AUPoint(x: x / z, y: y / z)
        return point.x.isFinite && point.y.isFinite ? point : nil
    }

    private static func coefficients(
        _ line: AUScaleLSDLineSegment
    ) -> (a: Double, b: Double, c: Double) {
        (
            line.start.y - line.end.y,
            line.end.x - line.start.x,
            line.start.x * line.end.y - line.start.y * line.end.x
        )
    }

    private static func mean(_ values: [Double]) -> Double {
        values.isEmpty ? 0.0 : values.reduce(0.0, +) / Double(values.count)
    }

    private static func standardDeviation(_ values: [Double]) -> Double {
        guard !values.isEmpty else {
            return 0.0
        }
        let center = mean(values)
        return sqrt(values.reduce(0.0) { $0 + ($1 - center) * ($1 - center) } / Double(values.count))
    }

    private static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else {
            return 0.0
        }
        let ordered = values.sorted()
        let middle = ordered.count / 2
        if ordered.count.isMultiple(of: 2) {
            return (ordered[middle - 1] + ordered[middle]) * 0.5
        }
        return ordered[middle]
    }
}
