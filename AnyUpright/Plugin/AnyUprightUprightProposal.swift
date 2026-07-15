//
//  AnyUprightUprightProposal.swift
//  AnyUpright
//

import Foundation
import simd

struct AUUprightProposalConfiguration: Equatable {
    var maximumCandidatesPerOrientation = 600
    var maximumHypothesisLinesPerOrientation = 600
    var maximumVanishingPointHypotheses = 256
    var maximumRankedPairHypotheses = 32
    var maximumAxisDeviationDegrees = 90.0
    var minimumLineLengthRatio = 0.08
    var minimumPairSeparationRatio = 0.12
    var supportDistanceRatio = 0.02
    var parallelSupportAngleDegrees = 3.0
    var maximumTransformResidualDegrees = 0.5
    var maximumAutoCropScale = 2.0
    var minimumImpliedHorizontalFOVDegrees = 25.0
    var maximumImpliedHorizontalFOVDegrees = 130.0
    var maximumManhattanFocalRelativeDeviation = 0.35
    var cameraPriorSupportDistanceRatio = 0.02
    var cameraPriorHorizonClusterDegrees = 3.0
    var cameraPriorOrthogonalityToleranceDegrees = 10.0
}

struct AUUprightProposalInputLine: Equatable {
    var line: AULineSegment
    var score: Double
}

struct AUUprightCameraPrior: Equatable {
    var gravity: SIMD3<Double>
    var verticalFOVRadians: Double
    var gravityUncertainty: Double
    var verticalFOVUncertaintyRadians: Double
}

struct AUUprightProposalPair: Equatable {
    var orientation: UprightGuideOrientation
    var firstIndex: Int
    var secondIndex: Int
    var vanishingPoint: AUPoint?
    var supportCount: Int
    var meanSupportResidualRatio: Double
    var score: Double
}

enum AUUprightProposalRejectionReason: String, Equatable {
    case invalidImageSize
    case missingVerticalPair
    case missingHorizontalPair
    case incompatibleVanishingPoints
    case invalidTransform
    case excessiveTransformResidual
    case excessiveCrop
}

struct AUUprightProposal {
    var verticalPair: AUUprightProposalPair?
    var horizontalPair: AUUprightProposalPair?
    var outputToSourceMatrix: simd_float3x3?
    var verticalResidualDegrees: Double?
    var horizontalResidualDegrees: Double?
    var autoCropScale: Double?
    var rejectionReason: AUUprightProposalRejectionReason?

    var accepted: Bool {
        rejectionReason == nil && outputToSourceMatrix != nil
    }
}

enum AnyUprightUprightProposalRanker {
    private struct RankedLine {
        var originalIndex: Int
        var line: AULineSegment
        var quality: Double
        var angleRadians: Double
    }

    private struct PairSeed {
        var first: RankedLine
        var second: RankedLine
        var vanishingPoint: AUPoint?
        var separation: Double
        var seedScore: Double
    }

    private struct SupportedLine {
        var candidate: RankedLine
        var residual: Double
    }

    private struct HorizonCluster {
        var vector: SIMD3<Double>
        var vanishingPoint: AUPoint
        var lines: [RankedLine]
    }

    static func makeProposal(
        lines: [AUUprightProposalInputLine],
        correctionMode: UprightCorrectionMode,
        imageSize: AUSize,
        cameraPrior: AUUprightCameraPrior? = nil,
        configuration: AUUprightProposalConfiguration = AUUprightProposalConfiguration()
    ) -> AUUprightProposal {
        guard imageSize.width > 1.0, imageSize.height > 1.0 else {
            return rejected(.invalidImageSize)
        }

        let verticalPairs: [AUUprightProposalPair]
        let horizontalPairs: [AUUprightProposalPair]
        if let cameraPrior {
            verticalPairs = correctionMode.includesVertical
                ? cameraPriorVerticalPair(
                    from: lines,
                    cameraPrior: cameraPrior,
                    imageSize: imageSize,
                    configuration: configuration
                ).map { [$0] } ?? []
                : []
            horizontalPairs = correctionMode.includesHorizontal
                ? cameraPriorHorizontalPairs(
                    from: lines,
                    cameraPrior: cameraPrior,
                    imageSize: imageSize,
                    configuration: configuration
                )
                : []
        } else {
            verticalPairs = correctionMode.includesVertical
                ? rankedPairs(
                    from: lines,
                    orientation: .vertical,
                    imageSize: imageSize,
                    configuration: configuration
                )
                : []
            horizontalPairs = correctionMode.includesHorizontal
                ? rankedPairs(
                    from: lines,
                    orientation: .horizontal,
                    imageSize: imageSize,
                    configuration: configuration
                )
                : []
        }

        let verticalPair: AUUprightProposalPair?
        let horizontalPair: AUUprightProposalPair?
        if correctionMode == .full {
            guard !verticalPairs.isEmpty else {
                return rejected(.missingVerticalPair)
            }
            guard !horizontalPairs.isEmpty else {
                return rejected(.missingHorizontalPair, verticalPair: verticalPairs.first)
            }
            let combination = if let cameraPrior {
                bestPriorFullCombination(
                    verticalPairs: verticalPairs,
                    horizontalPairs: horizontalPairs,
                    inputs: lines,
                    imageSize: imageSize,
                    cameraPrior: cameraPrior,
                    configuration: configuration
                )
            } else {
                bestFullCombination(
                    verticalPairs: verticalPairs,
                    horizontalPairs: horizontalPairs,
                    inputs: lines,
                    imageSize: imageSize,
                    configuration: configuration
                )
            }
            guard let combination else {
                return rejected(
                    .incompatibleVanishingPoints,
                    verticalPair: verticalPairs.first,
                    horizontalPair: horizontalPairs.first
                )
            }
            verticalPair = combination.vertical
            horizontalPair = combination.horizontal
        } else if correctionMode == .horizontal, let cameraPrior {
            verticalPair = nil
            guard let selected = bestPriorHorizontalPair(
                horizontalPairs: horizontalPairs,
                imageSize: imageSize,
                cameraPrior: cameraPrior,
                configuration: configuration
            ) else {
                return rejected(
                    .incompatibleVanishingPoints,
                    horizontalPair: horizontalPairs.first
                )
            }
            horizontalPair = selected
        } else {
            verticalPair = verticalPairs.first(where: {
                $0.vanishingPoint.map { vanishingPointIsOutsideImage($0, imageSize: imageSize) } ?? true
            })
            horizontalPair = horizontalPairs.first(where: {
                $0.vanishingPoint.map { vanishingPointIsOutsideImage($0, imageSize: imageSize) } ?? true
            })
        }

        if correctionMode.includesVertical && verticalPair == nil {
            return rejected(.missingVerticalPair, verticalPair: nil, horizontalPair: horizontalPair)
        }
        if correctionMode.includesHorizontal && horizontalPair == nil {
            return rejected(.missingHorizontalPair, verticalPair: verticalPair, horizontalPair: nil)
        }

        let verticalLines = selectedNormalizedLines(
            pair: verticalPair,
            inputs: lines,
            imageSize: imageSize
        )
        let horizontalLines = selectedNormalizedLines(
            pair: horizontalPair,
            inputs: lines,
            imageSize: imageSize
        )
        let mode: AUGuidedUprightMode
        switch correctionMode {
        case .vertical: mode = .vertical
        case .horizontal: mode = .horizontal
        case .full: mode = .full
        }

        let matrix = proposalMatrix(
            verticalLines: verticalLines,
            horizontalLines: horizontalLines,
            mode: mode,
            imageSize: imageSize
        )
        guard let matrix, matrixIsFiniteAndInvertible(matrix) else {
            return rejected(.invalidTransform, verticalPair: verticalPair, horizontalPair: horizontalPair)
        }

        let sourceToOutput = simd_inverse(matrix)
        let verticalResidual = maximumAxisResidualDegrees(
            normalizedLines: verticalLines,
            orientation: .vertical,
            sourceToOutput: sourceToOutput,
            imageSize: imageSize
        )
        let horizontalResidual = maximumAxisResidualDegrees(
            normalizedLines: horizontalLines,
            orientation: .horizontal,
            sourceToOutput: sourceToOutput,
            imageSize: imageSize
        )
        if max(verticalResidual ?? 0.0, horizontalResidual ?? 0.0) > configuration.maximumTransformResidualDegrees {
            return AUUprightProposal(
                verticalPair: verticalPair,
                horizontalPair: horizontalPair,
                outputToSourceMatrix: matrix,
                verticalResidualDegrees: verticalResidual,
                horizontalResidualDegrees: horizontalResidual,
                autoCropScale: nil,
                rejectionReason: .excessiveTransformResidual
            )
        }

        let cropScale = AnyUprightGeometry.autoCropScale(
            for: matrix,
            outputSize: imageSize,
            sourceSize: imageSize,
            maximumScale: configuration.maximumAutoCropScale
        )
        let cropped = AnyUprightGeometry.autoCropOutputToSourceMatrix(
            matrix,
            outputSize: imageSize,
            sourceSize: imageSize,
            maximumScale: configuration.maximumAutoCropScale
        )
        guard outputFrameMapsInsideSource(cropped, size: imageSize) else {
            return AUUprightProposal(
                verticalPair: verticalPair,
                horizontalPair: horizontalPair,
                outputToSourceMatrix: matrix,
                verticalResidualDegrees: verticalResidual,
                horizontalResidualDegrees: horizontalResidual,
                autoCropScale: cropScale,
                rejectionReason: .excessiveCrop
            )
        }

        return AUUprightProposal(
            verticalPair: verticalPair,
            horizontalPair: horizontalPair,
            outputToSourceMatrix: matrix,
            verticalResidualDegrees: verticalResidual,
            horizontalResidualDegrees: horizontalResidual,
            autoCropScale: cropScale,
            rejectionReason: nil
        )
    }

    private static func rankedPairs(
        from inputs: [AUUprightProposalInputLine],
        orientation: UprightGuideOrientation,
        imageSize: AUSize,
        configuration: AUUprightProposalConfiguration
    ) -> [AUUprightProposalPair] {
        let candidates = rankedLines(
            from: inputs,
            orientation: orientation,
            imageSize: imageSize,
            configuration: configuration
        )
        guard candidates.count >= 2 else {
            return []
        }

        let seedLines = Array(candidates.prefix(configuration.maximumHypothesisLinesPerOrientation))
        let perpendicular = orientation == .vertical ? imageSize.width : imageSize.height
        let minimumSeparation = perpendicular * configuration.minimumPairSeparationRatio
        var seeds: [PairSeed] = []
        seeds.reserveCapacity(seedLines.count * max(0, seedLines.count - 1) / 2)

        for firstOffset in 0..<(seedLines.count - 1) {
            for secondOffset in (firstOffset + 1)..<seedLines.count {
                let first = seedLines[firstOffset]
                let second = seedLines[secondOffset]
                let separation = pairSeparation(first.line, second.line, orientation: orientation)
                guard separation >= minimumSeparation else {
                    continue
                }
                let vanishingPoint = lineIntersection(first.line, second.line)
                if let vanishingPoint,
                   classify(vanishingPoint: vanishingPoint, imageSize: imageSize) != orientation {
                    continue
                }
                let separationQuality = min(1.0, separation / max(1.0, perpendicular * 0.4))
                seeds.append(PairSeed(
                    first: first,
                    second: second,
                    vanishingPoint: vanishingPoint,
                    separation: separation,
                    seedScore: first.quality + second.quality + separationQuality
                ))
            }
        }

        let uniqueSeeds = deduplicatedSeeds(
            seeds.sorted {
                if $0.seedScore == $1.seedScore {
                    if $0.first.originalIndex == $1.first.originalIndex {
                        return $0.second.originalIndex < $1.second.originalIndex
                    }
                    return $0.first.originalIndex < $1.first.originalIndex
                }
                return $0.seedScore > $1.seedScore
            },
            imageSize: imageSize,
            limit: configuration.maximumVanishingPointHypotheses
        )
        var hypotheses: [AUUprightProposalPair] = []

        for seed in uniqueSeeds {
            let hypothesis = pairHypothesis(
                first: seed.first,
                second: seed.second,
                vanishingPoint: seed.vanishingPoint,
                candidates: candidates,
                orientation: orientation,
                separation: seed.separation,
                imageSize: imageSize,
                configuration: configuration
            )
            guard let hypothesis else {
                continue
            }
            hypotheses.append(hypothesis)
        }
        let sorted = hypotheses.sorted(by: pairSortsBefore)
        var result: [AUUprightProposalPair] = []
        for hypothesis in sorted {
            if result.contains(where: {
                pairVanishingPointsAreSimilar($0, hypothesis, imageSize: imageSize)
            }) {
                continue
            }
            result.append(hypothesis)
            if result.count >= configuration.maximumRankedPairHypotheses {
                break
            }
        }
        return result
    }

    private static func rankedLines(
        from inputs: [AUUprightProposalInputLine],
        orientation: UprightGuideOrientation,
        imageSize: AUSize,
        configuration: AUUprightProposalConfiguration
    ) -> [RankedLine] {
        let axis = orientation == .vertical ? imageSize.height : imageSize.width
        let minimumLength = axis * configuration.minimumLineLengthRatio
        let maximumDeviation = radians(configuration.maximumAxisDeviationDegrees)
        let maximumScore = max(1.0, inputs.map { max(0.0, $0.score) }.max() ?? 1.0)

        return Array(
            inputs.enumerated().compactMap { offset, input -> RankedLine? in
                guard input.line.length >= minimumLength else {
                    return nil
                }
                let angle = normalizedLineAngle(input.line)
                let deviation = axisDeviation(angle, orientation: orientation)
                guard deviation <= maximumDeviation else {
                    return nil
                }
                let supportQuality = log1p(max(0.0, input.score)) / log1p(maximumScore)
                let lengthQuality = min(1.0, input.line.length / max(1.0, axis * 0.35))
                let quality = (0.5 + 0.5 * supportQuality)
                    * (0.25 + 0.75 * lengthQuality)
                return RankedLine(
                    originalIndex: offset,
                    line: input.line,
                    quality: quality,
                    angleRadians: angle
                )
            }.sorted {
                if $0.quality == $1.quality {
                    return $0.originalIndex < $1.originalIndex
                }
                return $0.quality > $1.quality
            }.prefix(configuration.maximumCandidatesPerOrientation)
        )
    }

    private static func pairHypothesis(
        first: RankedLine,
        second: RankedLine,
        vanishingPoint: AUPoint?,
        candidates: [RankedLine],
        orientation: UprightGuideOrientation,
        separation: Double,
        imageSize: AUSize,
        configuration: AUUprightProposalConfiguration
    ) -> AUUprightProposalPair? {
        let diagonal = hypot(imageSize.width, imageSize.height)
        let supportThreshold = diagonal * configuration.supportDistanceRatio
        var refinedVanishingPoint = vanishingPoint
        var supporters = supportedLines(
            candidates,
            vanishingPoint: vanishingPoint,
            parallelAngle: circularMeanLineAngle(first.angleRadians, second.angleRadians),
            supportThreshold: supportThreshold,
            configuration: configuration
        )
        if vanishingPoint != nil,
           let fitted = fitVanishingPoint(to: supporters) {
            refinedVanishingPoint = fitted
            supporters = supportedLines(
                candidates,
                vanishingPoint: fitted,
                parallelAngle: nil,
                supportThreshold: supportThreshold,
                configuration: configuration
            )
        }
        guard supporters.count >= 2 else {
            return nil
        }
        if let refinedVanishingPoint {
            guard classify(vanishingPoint: refinedVanishingPoint, imageSize: imageSize) == orientation else {
                return nil
            }
        }

        guard let representative = representativePair(
            from: supporters,
            vanishingPoint: refinedVanishingPoint,
            orientation: orientation,
            imageSize: imageSize,
            supportThreshold: supportThreshold,
            configuration: configuration
        ) else {
            return nil
        }

        let perpendicular = orientation == .vertical ? imageSize.width : imageSize.height
        let separationQuality = min(1.0, representative.separation / max(1.0, perpendicular * 0.4))
        let pairQuality = 0.5 * (representative.first.quality + representative.second.quality)
        let weightedSupport = supporters.reduce(0.0) { partial, supported in
            partial + supported.candidate.quality * max(0.0, 1.0 - supported.residual / supportThreshold)
        }
        let residualSum = supporters.reduce(0.0) { $0 + $1.residual / diagonal }
        let score = Double(supporters.count) * 4.0 + weightedSupport + pairQuality * 2.0 + separationQuality
        return AUUprightProposalPair(
            orientation: orientation,
            firstIndex: representative.first.originalIndex,
            secondIndex: representative.second.originalIndex,
            vanishingPoint: refinedVanishingPoint,
            supportCount: supporters.count,
            meanSupportResidualRatio: residualSum / Double(supporters.count),
            score: score
        )
    }

    private static func supportedLines(
        _ candidates: [RankedLine],
        vanishingPoint: AUPoint?,
        parallelAngle: Double?,
        supportThreshold: Double,
        configuration: AUUprightProposalConfiguration
    ) -> [SupportedLine] {
        candidates.compactMap { candidate in
            let residual: Double
            if let vanishingPoint {
                residual = infiniteLineDistance(from: vanishingPoint, to: candidate.line)
            } else if let parallelAngle {
                residual = angleDistance(candidate.angleRadians, parallelAngle)
                    / max(1e-9, radians(configuration.parallelSupportAngleDegrees))
                    * supportThreshold
            } else {
                return nil
            }
            guard residual <= supportThreshold else {
                return nil
            }
            return SupportedLine(candidate: candidate, residual: residual)
        }
    }

    private static func fitVanishingPoint(to supporters: [SupportedLine]) -> AUPoint? {
        guard supporters.count >= 2 else {
            return nil
        }
        var aa = 0.0
        var ab = 0.0
        var bb = 0.0
        var ac = 0.0
        var bc = 0.0
        for supported in supporters {
            guard let coefficients = normalizedLineCoefficients(supported.candidate.line) else {
                continue
            }
            let weight = supported.candidate.quality
            aa += weight * coefficients.a * coefficients.a
            ab += weight * coefficients.a * coefficients.b
            bb += weight * coefficients.b * coefficients.b
            ac += weight * coefficients.a * coefficients.c
            bc += weight * coefficients.b * coefficients.c
        }
        let determinant = aa * bb - ab * ab
        guard abs(determinant) > 1e-10 else {
            return nil
        }
        let x = (ab * bc - bb * ac) / determinant
        let y = (ab * ac - aa * bc) / determinant
        guard x.isFinite, y.isFinite else {
            return nil
        }
        return AUPoint(x: x, y: y)
    }

    private static func representativePair(
        from supporters: [SupportedLine],
        vanishingPoint: AUPoint?,
        orientation: UprightGuideOrientation,
        imageSize: AUSize,
        supportThreshold: Double,
        configuration: AUUprightProposalConfiguration
    ) -> (first: RankedLine, second: RankedLine, separation: Double)? {
        let perpendicular = orientation == .vertical ? imageSize.width : imageSize.height
        let minimumSeparation = perpendicular * configuration.minimumPairSeparationRatio
        let pool = Array(
            supporters.sorted {
                let lhs = $0.candidate.quality * max(0.0, 1.0 - $0.residual / supportThreshold)
                let rhs = $1.candidate.quality * max(0.0, 1.0 - $1.residual / supportThreshold)
                if lhs == rhs {
                    return $0.candidate.originalIndex < $1.candidate.originalIndex
                }
                return lhs > rhs
            }.prefix(64)
        )
        guard pool.count >= 2 else {
            return nil
        }

        var best: (first: RankedLine, second: RankedLine, separation: Double, score: Double)?
        for firstIndex in 0..<(pool.count - 1) {
            for secondIndex in (firstIndex + 1)..<pool.count {
                let first = pool[firstIndex].candidate
                let second = pool[secondIndex].candidate
                let separation = pairSeparation(first.line, second.line, orientation: orientation)
                guard separation >= minimumSeparation else {
                    continue
                }
                let intersectionQuality: Double
                if let vanishingPoint {
                    guard let intersection = lineIntersection(first.line, second.line) else {
                        continue
                    }
                    let distance = hypot(intersection.x - vanishingPoint.x, intersection.y - vanishingPoint.y)
                    intersectionQuality = max(0.0, 1.0 - distance / max(1.0, supportThreshold * 4.0))
                } else {
                    intersectionQuality = max(
                        0.0,
                        1.0 - angleDistance(first.angleRadians, second.angleRadians)
                            / max(1e-9, radians(configuration.parallelSupportAngleDegrees))
                    )
                }
                let separationQuality = min(1.0, separation / max(1.0, perpendicular * 0.4))
                let score = first.quality + second.quality + separationQuality * 2.0 + intersectionQuality * 2.0
                if best == nil || score > best!.score {
                    best = (first, second, separation, score)
                }
            }
        }
        return best.map { ($0.first, $0.second, $0.separation) }
    }

    private static func normalizedLineCoefficients(
        _ line: AULineSegment
    ) -> (a: Double, b: Double, c: Double)? {
        let a = line.start.y - line.end.y
        let b = line.end.x - line.start.x
        let c = line.start.x * line.end.y - line.end.x * line.start.y
        let norm = hypot(a, b)
        guard norm > 1e-9 else {
            return nil
        }
        return (a / norm, b / norm, c / norm)
    }

    private static func vanishingPointIsOutsideImage(_ point: AUPoint, imageSize: AUSize) -> Bool {
        point.x < 0.0 || point.x > imageSize.width || point.y < 0.0 || point.y > imageSize.height
    }

    private static func deduplicatedSeeds(
        _ seeds: [PairSeed],
        imageSize: AUSize,
        limit: Int
    ) -> [PairSeed] {
        var result: [PairSeed] = []
        result.reserveCapacity(limit)
        for seed in seeds {
            let duplicate = result.contains { existing in
                vanishingPointHypothesesAreSimilar(seed, existing, imageSize: imageSize)
            }
            if !duplicate {
                result.append(seed)
                if result.count >= limit {
                    break
                }
            }
        }
        return result
    }

    private static func vanishingPointHypothesesAreSimilar(
        _ first: PairSeed,
        _ second: PairSeed,
        imageSize: AUSize
    ) -> Bool {
        switch (first.vanishingPoint, second.vanishingPoint) {
        case let (.some(lhs), .some(rhs)):
            let lhsVector = normalizedVanishingPointVector(lhs, imageSize: imageSize)
            let rhsVector = normalizedVanishingPointVector(rhs, imageSize: imageSize)
            return simd_dot(lhsVector, rhsVector) >= cos(Float(radians(2.0)))
        case (nil, nil):
            let lhs = circularMeanLineAngle(first.first.angleRadians, first.second.angleRadians)
            let rhs = circularMeanLineAngle(second.first.angleRadians, second.second.angleRadians)
            return angleDistance(lhs, rhs) <= radians(2.0)
        default:
            return false
        }
    }

    private static func normalizedVanishingPointVector(
        _ point: AUPoint,
        imageSize: AUSize
    ) -> SIMD3<Float> {
        let diagonal = max(1.0, hypot(imageSize.width, imageSize.height))
        let vector = SIMD3<Float>(
            Float((point.x - imageSize.width * 0.5) / diagonal),
            Float((point.y - imageSize.height * 0.5) / diagonal),
            1.0
        )
        return simd_normalize(vector)
    }

    private static func proposalMatrix(
        verticalLines: [AULineSegment],
        horizontalLines: [AULineSegment],
        mode: AUGuidedUprightMode,
        imageSize: AUSize
    ) -> simd_float3x3? {
        if let matrix = AnyUprightGeometry.guidedManualOutputToSourceMatrix(
            verticalLines: verticalLines,
            horizontalLines: horizontalLines,
            mode: mode,
            size: imageSize
        ) {
            return matrix
        }

        // Exactly parallel references describe rotation without finite
        // perspective. Keep both selected lines, but use one from each family
        // for the existing rotation/affine fallback.
        return AnyUprightGeometry.guidedManualOutputToSourceMatrix(
            verticalLines: Array(verticalLines.prefix(1)),
            horizontalLines: Array(horizontalLines.prefix(1)),
            mode: mode,
            size: imageSize
        )
    }

    private static func selectedNormalizedLines(
        pair: AUUprightProposalPair?,
        inputs: [AUUprightProposalInputLine],
        imageSize: AUSize
    ) -> [AULineSegment] {
        guard let pair else {
            return []
        }
        return [pair.firstIndex, pair.secondIndex].map { index in
            let line = inputs[index].line
            return AULineSegment(
                start: AUPoint(x: line.start.x / imageSize.width, y: line.start.y / imageSize.height),
                end: AUPoint(x: line.end.x / imageSize.width, y: line.end.y / imageSize.height)
            )
        }
    }

    private static func maximumAxisResidualDegrees(
        normalizedLines: [AULineSegment],
        orientation: UprightGuideOrientation,
        sourceToOutput: simd_float3x3,
        imageSize: AUSize
    ) -> Double? {
        guard !normalizedLines.isEmpty else {
            return nil
        }
        return normalizedLines.map { line in
            let imageLine = AULineSegment(
                start: AUPoint(x: line.start.x * imageSize.width, y: line.start.y * imageSize.height),
                end: AUPoint(x: line.end.x * imageSize.width, y: line.end.y * imageSize.height)
            )
            let transformed = AnyUprightGeometry.transform(imageLine, by: sourceToOutput)
            let angle = normalizedLineAngle(transformed)
            return degrees(axisDeviation(angle, orientation: orientation))
        }.max()
    }

    private static func pairSortsBefore(_ lhs: AUUprightProposalPair, _ rhs: AUUprightProposalPair) -> Bool {
        if lhs.score != rhs.score {
            return lhs.score > rhs.score
        }
        if lhs.firstIndex != rhs.firstIndex {
            return lhs.firstIndex < rhs.firstIndex
        }
        return lhs.secondIndex < rhs.secondIndex
    }

    private static func pairVanishingPointsAreSimilar(
        _ first: AUUprightProposalPair,
        _ second: AUUprightProposalPair,
        imageSize: AUSize
    ) -> Bool {
        switch (first.vanishingPoint, second.vanishingPoint) {
        case let (.some(lhs), .some(rhs)):
            let lhsVector = normalizedVanishingPointVector(lhs, imageSize: imageSize)
            let rhsVector = normalizedVanishingPointVector(rhs, imageSize: imageSize)
            return simd_dot(lhsVector, rhsVector) >= cos(Float(radians(1.0)))
        case (nil, nil):
            return true
        default:
            return false
        }
    }

    private static func pairsApplyingCameraPrior(
        _ pairs: [AUUprightProposalPair],
        orientation: UprightGuideOrientation,
        cameraPrior: AUUprightCameraPrior,
        imageSize: AUSize
    ) -> [AUUprightProposalPair] {
        guard let intrinsics = cameraIntrinsics(cameraPrior: cameraPrior, imageSize: imageSize) else {
            return pairs
        }
        let uncertaintyAngle = max(
            radians(8.0),
            min(radians(25.0), cameraPrior.gravityUncertainty * 3.0)
        )
        let priorVertical = normalizedPriorVerticalVector(
            cameraPrior: cameraPrior,
            intrinsics: intrinsics,
            imageSize: imageSize
        )
        return pairs.compactMap { pair -> AUUprightProposalPair? in
            guard let vanishingPoint = pair.vanishingPoint else {
                return nil
            }
            let residual: Double
            switch orientation {
            case .vertical:
                let candidate = normalizedVanishingPointVector(vanishingPoint, imageSize: imageSize)
                residual = acos(Double(min(1.0, max(-1.0, abs(simd_dot(candidate, priorVertical))))))
            case .horizontal:
                let ray = SIMD3<Double>(
                    (vanishingPoint.x - intrinsics.cx) / intrinsics.fx,
                    (vanishingPoint.y - intrinsics.cy) / intrinsics.fy,
                    1.0
                )
                residual = asin(min(1.0, abs(simd_dot(simd_normalize(ray), simd_normalize(cameraPrior.gravity)))))
            }
            guard residual <= uncertaintyAngle else {
                return nil
            }
            var adjusted = pair
            adjusted.score += max(0.0, 1.0 - residual / uncertaintyAngle) * 200.0
            return adjusted
        }.sorted(by: pairSortsBefore)
    }

    private static func cameraPriorVerticalPair(
        from inputs: [AUUprightProposalInputLine],
        cameraPrior: AUUprightCameraPrior,
        imageSize: AUSize,
        configuration: AUUprightProposalConfiguration
    ) -> AUUprightProposalPair? {
        guard let intrinsics = cameraIntrinsics(cameraPrior: cameraPrior, imageSize: imageSize),
              abs(cameraPrior.gravity.z) > 1e-6 else {
            return nil
        }
        let priorVP = AUPoint(
            x: intrinsics.cx + intrinsics.fx * cameraPrior.gravity.x / cameraPrior.gravity.z,
            y: intrinsics.cy + intrinsics.fy * cameraPrior.gravity.y / cameraPrior.gravity.z
        )
        guard priorVP.x.isFinite, priorVP.y.isFinite else {
            return nil
        }
        var priorConfiguration = configuration
        priorConfiguration.minimumLineLengthRatio = 0.015
        let candidates = rankedLines(
            from: inputs,
            orientation: .vertical,
            imageSize: imageSize,
            configuration: priorConfiguration
        )
        let threshold = hypot(imageSize.width, imageSize.height) * configuration.cameraPriorSupportDistanceRatio
        let supporters = supportedLines(
            candidates,
            vanishingPoint: priorVP,
            parallelAngle: nil,
            supportThreshold: threshold,
            configuration: configuration
        )
        guard supporters.count >= 2 else {
            return nil
        }
        return pairClosestToPrior(
            supporters: supporters,
            priorVanishingPoint: priorVP,
            orientation: .vertical,
            imageSize: imageSize,
            supportThreshold: threshold,
            configuration: priorConfiguration
        )
    }

    private static func pairClosestToPrior(
        supporters: [SupportedLine],
        priorVanishingPoint: AUPoint,
        orientation: UprightGuideOrientation,
        imageSize: AUSize,
        supportThreshold: Double,
        configuration: AUUprightProposalConfiguration
    ) -> AUUprightProposalPair? {
        let perpendicular = orientation == .vertical ? imageSize.width : imageSize.height
        let minimumSeparation = perpendicular * configuration.minimumPairSeparationRatio
        let pool = Array(supporters.sorted {
            if $0.candidate.quality == $1.candidate.quality {
                return $0.candidate.originalIndex < $1.candidate.originalIndex
            }
            return $0.candidate.quality > $1.candidate.quality
        }.prefix(128))
        var best: (first: RankedLine, second: RankedLine, vp: AUPoint, score: Double)?
        for firstIndex in 0..<(max(0, pool.count - 1)) {
            for secondIndex in (firstIndex + 1)..<pool.count {
                let first = pool[firstIndex].candidate
                let second = pool[secondIndex].candidate
                let separation = pairSeparation(first.line, second.line, orientation: orientation)
                guard separation >= minimumSeparation,
                      let intersection = lineIntersection(first.line, second.line) else {
                    continue
                }
                let distance = hypot(
                    intersection.x - priorVanishingPoint.x,
                    intersection.y - priorVanishingPoint.y
                )
                let firstResidual = infiniteLineDistance(from: priorVanishingPoint, to: first.line)
                let secondResidual = infiniteLineDistance(from: priorVanishingPoint, to: second.line)
                let lineResidual = max(firstResidual, secondResidual)
                let priorQuality = max(0.0, 1.0 - lineResidual / max(1.0, supportThreshold))
                let intersectionQuality = max(0.0, 1.0 - distance / max(1.0, supportThreshold * 2.0))
                let separationQuality = min(1.0, separation / max(1.0, perpendicular * 0.4))
                let score = priorQuality * 1_000.0
                    + intersectionQuality * 20.0
                    + first.quality
                    + second.quality
                    + separationQuality * 2.0
                if best == nil || score > best!.score {
                    best = (first, second, intersection, score)
                }
            }
        }
        guard let best else {
            return nil
        }
        let finalSupporters = supporters.filter {
            infiniteLineDistance(from: best.vp, to: $0.candidate.line) <= supportThreshold
        }
        return AUUprightProposalPair(
            orientation: orientation,
            firstIndex: best.first.originalIndex,
            secondIndex: best.second.originalIndex,
            vanishingPoint: best.vp,
            supportCount: finalSupporters.count,
            meanSupportResidualRatio: finalSupporters.isEmpty
                ? 0.0
                : finalSupporters.reduce(0.0) {
                    $0 + infiniteLineDistance(from: best.vp, to: $1.candidate.line)
                        / hypot(imageSize.width, imageSize.height)
                } / Double(finalSupporters.count),
            score: best.score + Double(finalSupporters.count) * 4.0
        )
    }

    private static func cameraPriorHorizontalPairs(
        from inputs: [AUUprightProposalInputLine],
        cameraPrior: AUUprightCameraPrior,
        imageSize: AUSize,
        configuration: AUUprightProposalConfiguration
    ) -> [AUUprightProposalPair] {
        guard let intrinsics = cameraIntrinsics(cameraPrior: cameraPrior, imageSize: imageSize) else {
            return []
        }
        let gravity = cameraPrior.gravity
        let horizon = (
            a: gravity.x / intrinsics.fx,
            b: gravity.y / intrinsics.fy,
            c: gravity.z - gravity.x * intrinsics.cx / intrinsics.fx - gravity.y * intrinsics.cy / intrinsics.fy
        )
        var priorConfiguration = configuration
        priorConfiguration.minimumLineLengthRatio = 0.015
        let candidates = rankedLines(
            from: inputs,
            orientation: .horizontal,
            imageSize: imageSize,
            configuration: priorConfiguration
        )
        let clusterCosine = cos(radians(configuration.cameraPriorHorizonClusterDegrees))
        var clusters: [HorizonCluster] = []
        for candidate in candidates {
            guard let vanishingPoint = intersection(of: candidate.line, and: horizon) else {
                continue
            }
            let vector = cameraRay(for: vanishingPoint, intrinsics: intrinsics)
            if let index = clusters.indices.max(by: {
                simd_dot(clusters[$0].vector, vector) < simd_dot(clusters[$1].vector, vector)
            }), simd_dot(clusters[index].vector, vector) >= clusterCosine {
                clusters[index].lines.append(candidate)
            } else {
                clusters.append(HorizonCluster(vector: vector, vanishingPoint: vanishingPoint, lines: [candidate]))
            }
        }

        priorConfiguration.supportDistanceRatio = configuration.cameraPriorSupportDistanceRatio
        let hypotheses = clusters.compactMap { cluster -> AUUprightProposalPair? in
            guard cluster.lines.count >= 2 else {
                return nil
            }
            return pairHypothesis(
                first: cluster.lines[0],
                second: cluster.lines[1],
                vanishingPoint: cluster.vanishingPoint,
                candidates: candidates,
                orientation: .horizontal,
                separation: 0.0,
                imageSize: imageSize,
                configuration: priorConfiguration
            )
        }
        return pairsApplyingCameraPrior(
            hypotheses.sorted(by: pairSortsBefore),
            orientation: .horizontal,
            cameraPrior: cameraPrior,
            imageSize: imageSize
        )
    }

    private static func bestPriorHorizontalPair(
        horizontalPairs: [AUUprightProposalPair],
        imageSize: AUSize,
        cameraPrior: AUUprightCameraPrior,
        configuration: AUUprightProposalConfiguration
    ) -> AUUprightProposalPair? {
        guard let intrinsics = cameraIntrinsics(cameraPrior: cameraPrior, imageSize: imageSize) else {
            return nil
        }
        var best: (pair: AUUprightProposalPair, score: Double)?
        for primaryIndex in horizontalPairs.indices {
            let primary = horizontalPairs[primaryIndex]
            guard let primaryVP = primary.vanishingPoint else {
                continue
            }
            let primaryRay = cameraRay(for: primaryVP, intrinsics: intrinsics)
            for verifierIndex in horizontalPairs.indices where verifierIndex != primaryIndex {
                let verifier = horizontalPairs[verifierIndex]
                guard let verifierVP = verifier.vanishingPoint,
                      Set([
                          primary.firstIndex,
                          primary.secondIndex,
                          verifier.firstIndex,
                          verifier.secondIndex,
                      ]).count == 4 else {
                    continue
                }
                let verifierRay = cameraRay(for: verifierVP, intrinsics: intrinsics)
                guard horizontalRaysAreOrthogonal(
                    primaryRay,
                    verifierRay,
                    toleranceDegrees: configuration.cameraPriorOrthogonalityToleranceDegrees
                ) else {
                    continue
                }
                let score = primary.score + verifier.score
                if best == nil || score > best!.score {
                    best = (primary, score)
                }
            }
        }
        return best?.pair
    }

    private static func intersection(
        of segment: AULineSegment,
        and line: (a: Double, b: Double, c: Double)
    ) -> AUPoint? {
        guard let segmentLine = normalizedLineCoefficients(segment) else {
            return nil
        }
        let x = segmentLine.b * line.c - segmentLine.c * line.b
        let y = segmentLine.c * line.a - segmentLine.a * line.c
        let z = segmentLine.a * line.b - segmentLine.b * line.a
        guard abs(z) > 1e-9 else {
            return nil
        }
        let point = AUPoint(x: x / z, y: y / z)
        return point.x.isFinite && point.y.isFinite ? point : nil
    }

    private static func bestPriorFullCombination(
        verticalPairs: [AUUprightProposalPair],
        horizontalPairs: [AUUprightProposalPair],
        inputs: [AUUprightProposalInputLine],
        imageSize: AUSize,
        cameraPrior: AUUprightCameraPrior,
        configuration: AUUprightProposalConfiguration
    ) -> (vertical: AUUprightProposalPair, horizontal: AUUprightProposalPair)? {
        guard let intrinsics = cameraIntrinsics(cameraPrior: cameraPrior, imageSize: imageSize) else {
            return nil
        }
        var best: (vertical: AUUprightProposalPair, horizontal: AUUprightProposalPair, score: Double)?
        for vertical in verticalPairs.prefix(12) {
            for horizontalIndex in horizontalPairs.indices.prefix(24) {
                let horizontal = horizontalPairs[horizontalIndex]
                guard let horizontalVP = horizontal.vanishingPoint else {
                    continue
                }
                let selectedIndexes = [
                    vertical.firstIndex,
                    vertical.secondIndex,
                    horizontal.firstIndex,
                    horizontal.secondIndex,
                ]
                guard Set(selectedIndexes).count == 4 else {
                    continue
                }
                let verticalLines = selectedNormalizedLines(
                    pair: vertical,
                    inputs: inputs,
                    imageSize: imageSize
                )
                let horizontalLines = selectedNormalizedLines(
                    pair: horizontal,
                    inputs: inputs,
                    imageSize: imageSize
                )
                guard let matrix = proposalMatrix(
                    verticalLines: verticalLines,
                    horizontalLines: horizontalLines,
                    mode: .full,
                    imageSize: imageSize
                ), matrixIsFiniteAndInvertible(matrix) else {
                    continue
                }
                let cropScale = AnyUprightGeometry.autoCropScale(
                    for: matrix,
                    outputSize: imageSize,
                    sourceSize: imageSize,
                    maximumScale: configuration.maximumAutoCropScale
                )
                let cropped = AnyUprightGeometry.autoCropOutputToSourceMatrix(
                    matrix,
                    outputSize: imageSize,
                    sourceSize: imageSize,
                    maximumScale: configuration.maximumAutoCropScale
                )
                guard outputFrameMapsInsideSource(cropped, size: imageSize) else {
                    continue
                }
                let cropQuality = max(
                    0.0,
                    1.0 - (cropScale - 1.0) / max(1e-9, configuration.maximumAutoCropScale - 1.0)
                )
                let horizontalRay = cameraRay(for: horizontalVP, intrinsics: intrinsics)
                for verifierIndex in horizontalPairs.indices.prefix(24) where verifierIndex != horizontalIndex {
                    let verifier = horizontalPairs[verifierIndex]
                    guard let verifierVP = verifier.vanishingPoint,
                          Set(selectedIndexes + [verifier.firstIndex, verifier.secondIndex]).count == 6 else {
                        continue
                    }
                    let verifierRay = cameraRay(for: verifierVP, intrinsics: intrinsics)
                    guard horizontalRaysAreOrthogonal(
                        horizontalRay,
                        verifierRay,
                        toleranceDegrees: configuration.cameraPriorOrthogonalityToleranceDegrees
                    ) else {
                        continue
                    }
                    let score = vertical.score + horizontal.score + verifier.score + cropQuality * 8.0
                    if best == nil || score > best!.score {
                        best = (vertical, horizontal, score)
                    }
                }
            }
        }
        return best.map { ($0.vertical, $0.horizontal) }
    }

    private static func cameraIntrinsics(
        cameraPrior: AUUprightCameraPrior,
        imageSize: AUSize
    ) -> (fx: Double, fy: Double, cx: Double, cy: Double)? {
        guard cameraPrior.verticalFOVRadians.isFinite,
              cameraPrior.verticalFOVRadians > radians(5.0),
              cameraPrior.verticalFOVRadians < radians(175.0) else {
            return nil
        }
        let fy = imageSize.height * 0.5 / tan(cameraPrior.verticalFOVRadians * 0.5)
        guard fy.isFinite, fy > 1.0 else {
            return nil
        }
        return (fy, fy, imageSize.width * 0.5, imageSize.height * 0.5)
    }

    private static func cameraRay(
        for vanishingPoint: AUPoint,
        intrinsics: (fx: Double, fy: Double, cx: Double, cy: Double)
    ) -> SIMD3<Double> {
        simd_normalize(SIMD3<Double>(
            (vanishingPoint.x - intrinsics.cx) / intrinsics.fx,
            (vanishingPoint.y - intrinsics.cy) / intrinsics.fy,
            1.0
        ))
    }

    private static func horizontalRaysAreOrthogonal(
        _ first: SIMD3<Double>,
        _ second: SIMD3<Double>,
        toleranceDegrees: Double
    ) -> Bool {
        abs(simd_dot(first, second)) <= sin(radians(toleranceDegrees))
    }

    private static func normalizedPriorVerticalVector(
        cameraPrior: AUUprightCameraPrior,
        intrinsics: (fx: Double, fy: Double, cx: Double, cy: Double),
        imageSize: AUSize
    ) -> SIMD3<Float> {
        let diagonal = max(1.0, hypot(imageSize.width, imageSize.height))
        let vector = SIMD3<Float>(
            Float(intrinsics.fx * cameraPrior.gravity.x / diagonal),
            Float(intrinsics.fy * cameraPrior.gravity.y / diagonal),
            Float(cameraPrior.gravity.z)
        )
        return simd_normalize(vector)
    }

    private static func bestFullCombination(
        verticalPairs: [AUUprightProposalPair],
        horizontalPairs: [AUUprightProposalPair],
        inputs: [AUUprightProposalInputLine],
        imageSize: AUSize,
        configuration: AUUprightProposalConfiguration
    ) -> (vertical: AUUprightProposalPair, horizontal: AUUprightProposalPair)? {
        let center = AUPoint(x: imageSize.width * 0.5, y: imageSize.height * 0.5)
        var best: (vertical: AUUprightProposalPair, horizontal: AUUprightProposalPair, score: Double)?
        for vertical in verticalPairs {
            guard let verticalVP = vertical.vanishingPoint else {
                continue
            }
            guard vanishingPointIsOutsideImage(verticalVP, imageSize: imageSize),
                  abs(verticalVP.x - center.x) <= imageSize.width * 0.35 else {
                continue
            }
            let verticalRadius = hypot(verticalVP.x - center.x, verticalVP.y - center.y)
            let verticalAlignment = abs(verticalVP.y - center.y) / max(1e-9, verticalRadius)
            for primaryIndex in horizontalPairs.indices {
                let horizontal = horizontalPairs[primaryIndex]
                guard let horizontalVP = horizontal.vanishingPoint else {
                    continue
                }
                let selectedIndexes = [
                    vertical.firstIndex,
                    vertical.secondIndex,
                    horizontal.firstIndex,
                    horizontal.secondIndex,
                ]
                guard Set(selectedIndexes).count == 4 else {
                    continue
                }
                let verticalLines = selectedNormalizedLines(
                    pair: vertical,
                    inputs: inputs,
                    imageSize: imageSize
                )
                let horizontalLines = selectedNormalizedLines(
                    pair: horizontal,
                    inputs: inputs,
                    imageSize: imageSize
                )
                guard let matrix = proposalMatrix(
                    verticalLines: verticalLines,
                    horizontalLines: horizontalLines,
                    mode: .full,
                    imageSize: imageSize
                ), matrixIsFiniteAndInvertible(matrix) else {
                    continue
                }
                let cropScale = AnyUprightGeometry.autoCropScale(
                    for: matrix,
                    outputSize: imageSize,
                    sourceSize: imageSize,
                    maximumScale: configuration.maximumAutoCropScale
                )
                let cropped = AnyUprightGeometry.autoCropOutputToSourceMatrix(
                    matrix,
                    outputSize: imageSize,
                    sourceSize: imageSize,
                    maximumScale: configuration.maximumAutoCropScale
                )
                guard outputFrameMapsInsideSource(cropped, size: imageSize) else {
                    continue
                }

                for verifierIndex in horizontalPairs.indices where verifierIndex != primaryIndex {
                    let verifier = horizontalPairs[verifierIndex]
                    guard let verifierVP = verifier.vanishingPoint,
                          !pairVanishingPointsAreSimilar(horizontal, verifier, imageSize: imageSize) else {
                        continue
                    }
                    let focalValues = [
                        manhattanFocalSquared(verticalVP, horizontalVP, center: center),
                        manhattanFocalSquared(verticalVP, verifierVP, center: center),
                        manhattanFocalSquared(horizontalVP, verifierVP, center: center),
                    ]
                    guard focalValues.allSatisfy({ $0 > 1.0 }) else {
                        continue
                    }
                    let meanFocalSquared = focalValues.reduce(0.0, +) / 3.0
                    let focalDeviation = focalValues.map {
                        abs($0 - meanFocalSquared) / meanFocalSquared
                    }.max() ?? .infinity
                    guard focalDeviation <= configuration.maximumManhattanFocalRelativeDeviation else {
                        continue
                    }
                    let focal = sqrt(meanFocalSquared)
                    let impliedFOV = degrees(2.0 * atan(imageSize.width / (2.0 * focal)))
                    guard impliedFOV >= configuration.minimumImpliedHorizontalFOVDegrees,
                          impliedFOV <= configuration.maximumImpliedHorizontalFOVDegrees else {
                        continue
                    }

                    let cropQuality = max(
                        0.0,
                        1.0 - (cropScale - 1.0) / max(1e-9, configuration.maximumAutoCropScale - 1.0)
                    )
                    let consistencyQuality = max(
                        0.0,
                        1.0 - focalDeviation / configuration.maximumManhattanFocalRelativeDeviation
                    )
                    let score = vertical.score + horizontal.score + verifier.score
                        + verticalAlignment * 20.0
                        + consistencyQuality * 100.0
                        + cropQuality * 8.0
                    if best == nil || score > best!.score {
                        best = (vertical, horizontal, score)
                    }
                }
            }
        }
        return best.map { ($0.vertical, $0.horizontal) }
    }

    private static func manhattanFocalSquared(
        _ first: AUPoint,
        _ second: AUPoint,
        center: AUPoint
    ) -> Double {
        -(
            (first.x - center.x) * (second.x - center.x)
                + (first.y - center.y) * (second.y - center.y)
        )
    }

    private static func pairSeparation(
        _ first: AULineSegment,
        _ second: AULineSegment,
        orientation: UprightGuideOrientation
    ) -> Double {
        switch orientation {
        case .vertical:
            return abs(first.midpoint.x - second.midpoint.x)
        case .horizontal:
            return abs(first.midpoint.y - second.midpoint.y)
        }
    }

    private static func lineIntersection(_ first: AULineSegment, _ second: AULineSegment) -> AUPoint? {
        let x1 = first.start.x
        let y1 = first.start.y
        let x2 = first.end.x
        let y2 = first.end.y
        let x3 = second.start.x
        let y3 = second.start.y
        let x4 = second.end.x
        let y4 = second.end.y
        let denominator = (x1 - x2) * (y3 - y4) - (y1 - y2) * (x3 - x4)
        guard abs(denominator) > 1e-8 else {
            return nil
        }
        let firstCross = x1 * y2 - y1 * x2
        let secondCross = x3 * y4 - y3 * x4
        let x = (firstCross * (x3 - x4) - (x1 - x2) * secondCross) / denominator
        let y = (firstCross * (y3 - y4) - (y1 - y2) * secondCross) / denominator
        guard x.isFinite, y.isFinite else {
            return nil
        }
        return AUPoint(x: x, y: y)
    }

    private static func infiniteLineDistance(from point: AUPoint, to line: AULineSegment) -> Double {
        let dx = line.end.x - line.start.x
        let dy = line.end.y - line.start.y
        let denominator = max(1e-9, hypot(dx, dy))
        return abs(dy * point.x - dx * point.y + line.end.x * line.start.y - line.end.y * line.start.x) / denominator
    }

    private static func classify(
        vanishingPoint: AUPoint,
        imageSize: AUSize
    ) -> UprightGuideOrientation? {
        let dx = abs(vanishingPoint.x - imageSize.width * 0.5)
        let dy = abs(vanishingPoint.y - imageSize.height * 0.5)
        if dy > dx * 1.25 {
            return .vertical
        }
        if dx > dy * 1.25 {
            return .horizontal
        }
        return nil
    }

    private static func normalizedLineAngle(_ line: AULineSegment) -> Double {
        var angle = atan2(line.end.y - line.start.y, line.end.x - line.start.x)
        while angle <= -.pi / 2.0 { angle += .pi }
        while angle > .pi / 2.0 { angle -= .pi }
        return angle
    }

    private static func axisDeviation(
        _ angle: Double,
        orientation: UprightGuideOrientation
    ) -> Double {
        switch orientation {
        case .vertical:
            return abs(.pi / 2.0 - abs(angle))
        case .horizontal:
            return abs(angle)
        }
    }

    private static func angleDistance(_ lhs: Double, _ rhs: Double) -> Double {
        var difference = lhs - rhs
        while difference <= -.pi / 2.0 { difference += .pi }
        while difference > .pi / 2.0 { difference -= .pi }
        return abs(difference)
    }

    private static func circularMeanLineAngle(_ lhs: Double, _ rhs: Double) -> Double {
        0.5 * atan2(sin(2.0 * lhs) + sin(2.0 * rhs), cos(2.0 * lhs) + cos(2.0 * rhs))
    }

    private static func matrixIsFiniteAndInvertible(_ matrix: simd_float3x3) -> Bool {
        let values = [
            matrix.columns.0.x, matrix.columns.0.y, matrix.columns.0.z,
            matrix.columns.1.x, matrix.columns.1.y, matrix.columns.1.z,
            matrix.columns.2.x, matrix.columns.2.y, matrix.columns.2.z,
        ]
        return values.allSatisfy(\.isFinite) && abs(simd_determinant(matrix)) > 1e-8
    }

    private static func outputFrameMapsInsideSource(_ matrix: simd_float3x3, size: AUSize) -> Bool {
        let epsilon = 0.25
        let corners = [
            AUPoint(x: 0.0, y: 0.0),
            AUPoint(x: size.width, y: 0.0),
            AUPoint(x: size.width, y: size.height),
            AUPoint(x: 0.0, y: size.height),
        ]
        return corners.allSatisfy { corner in
            let mapped = AnyUprightGeometry.transform(corner, by: matrix)
            return mapped.x.isFinite
                && mapped.y.isFinite
                && mapped.x >= -epsilon
                && mapped.x <= size.width + epsilon
                && mapped.y >= -epsilon
                && mapped.y <= size.height + epsilon
        }
    }

    private static func rejected(
        _ reason: AUUprightProposalRejectionReason,
        verticalPair: AUUprightProposalPair? = nil,
        horizontalPair: AUUprightProposalPair? = nil
    ) -> AUUprightProposal {
        AUUprightProposal(
            verticalPair: verticalPair,
            horizontalPair: horizontalPair,
            outputToSourceMatrix: nil,
            verticalResidualDegrees: nil,
            horizontalResidualDegrees: nil,
            autoCropScale: nil,
            rejectionReason: reason
        )
    }

    private static func radians(_ degrees: Double) -> Double {
        degrees * .pi / 180.0
    }

    private static func degrees(_ radians: Double) -> Double {
        radians * 180.0 / .pi
    }
}
