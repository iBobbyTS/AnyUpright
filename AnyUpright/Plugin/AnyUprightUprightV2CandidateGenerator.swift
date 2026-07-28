//
//  AnyUprightUprightV2CandidateGenerator.swift
//  AnyUpright
//

import Foundation

struct AUUprightV2CameraPrior {
    var gravity: SIMD3<Double>
    var gravityUncertainty: Double
    var verticalFOVRadians: Double
    var verticalFOVUncertaintyRadians: Double
}

struct AUUprightV2CandidatePool {
    var candidates: [AUUprightV2Candidate]
    var preparedLineCount: Int
    var vpClusterCount: Int
}

private struct AUUprightV2PreparedLine {
    var segment: AUScaleLSDLineSegment
    var originalIndex: Int
    var coefficients: SIMD3<Double>
    var direction: SIMD2<Double>
    var quality: Double
    var cell: Int

    var midpoint: AUPoint {
        AUPoint(
            x: (segment.start.x + segment.end.x) * 0.5,
            y: (segment.start.y + segment.end.y) * 0.5
        )
    }
}

private struct AUUprightV2VPCluster {
    var ray: SIMD3<Double>
    var homogeneousPoint: SIMD3<Double>
    var supporters: [Int]
    var supportQuality: Double
    var meanResidualRadians: Double
    var coverage: Double
}

private struct AUUprightV2Combination {
    var verticalIndex: Int
    var horizontalIndex: Int?
    var intrinsics: AUUprightV2Matrix3
    var ordinal: Int
}

enum AnyUprightUprightV2CandidateGenerator {
    private static let gridSize = 4
    private static let supportThreshold = 2.5 * Double.pi / 180.0
    private static let clusterThreshold = 3.0 * Double.pi / 180.0
    private static let maximumHypotheses = 1024
    private static let maximumClusters = 64
    private static let maximumCropScale = 2.0
    private static let strengths = [0.0, 0.5, 0.75, 1.0]

    static func candidatePool(
        lines: [AUScaleLSDLineSegment],
        imageSize: AUSize,
        cameraPrior: AUUprightV2CameraPrior?
    ) -> AUUprightV2CandidatePool {
        let width = max(1, Int(imageSize.width.rounded()))
        let height = max(1, Int(imageSize.height.rounded()))
        let prepared = prepareLines(lines, width: width, height: height)
        guard prepared.count >= 2 else {
            return AUUprightV2CandidatePool(
                candidates: [score(
                    matrix: .identity,
                    cropScale: 1.0,
                    verticalStrength: 0.0,
                    horizontalStrength: 0.0,
                    focalScale: 1.0,
                    aspect: 1.0,
                    vertical: nil,
                    horizontal: nil,
                    prepared: prepared,
                    clusters: [],
                    intrinsics: nil,
                    prior: cameraPrior,
                    width: width,
                    height: height,
                    thirdAxis: 0.0
                )],
                preparedLineCount: prepared.count,
                vpClusterCount: 0
            )
        }

        let initialFOV = cameraPrior?.verticalFOVRadians ?? .pi / 3.0
        let initialIntrinsics = AnyUprightUprightV2Geometry.cameraIntrinsics(
            width: width,
            height: height,
            verticalFOV: initialFOV
        )
        var clusters = generateVPClusters(
            prepared,
            intrinsics: initialIntrinsics
        )
        if let cameraPrior,
           let guided = generatePriorGuidedCluster(
               prepared,
               intrinsics: initialIntrinsics,
               prior: cameraPrior
           ) {
            clusters = [guided] + clusters.filter {
                ((try? AnyUprightUprightV2Geometry.undirectedAngle(guided.ray, $0.ray)) ?? 0.0)
                    > clusterThreshold
            }
        }
        let candidates = discreteCandidates(
            prepared,
            clusters: clusters,
            width: width,
            height: height,
            prior: cameraPrior
        )
        return AUUprightV2CandidatePool(
            candidates: candidates,
            preparedLineCount: prepared.count,
            vpClusterCount: clusters.count
        )
    }

    private static func prepareLines(
        _ lines: [AUScaleLSDLineSegment],
        width: Int,
        height: Int
    ) -> [AUUprightV2PreparedLine] {
        let diagonal = hypot(Double(width), Double(height))
        let minimumLength = diagonal * 0.02
        let filtered = lines.enumerated().filter {
            lineLength($0.element) >= minimumLength && $0.element.score >= 0.0
        }
        guard !filtered.isEmpty else {
            return []
        }
        let maximumScore = max(1.0, filtered.map(\.element.score).max() ?? 1.0)
        let scoreScale = log1p(maximumScore)
        var prepared: [AUUprightV2PreparedLine] = []
        for (originalIndex, segment) in filtered {
            guard let coefficients = try? AnyUprightUprightV2Geometry.canonicalLine(
                start: segment.start,
                end: segment.end
            ), let direction = try? AnyUprightUprightV2Geometry.lineDirection(coefficients) else {
                continue
            }
            let scoreQuality = log1p(segment.score) / scoreScale
            let lengthQuality = sqrt(min(1.0, lineLength(segment) / diagonal))
            let midpoint = lineMidpoint(segment)
            let cellX = min(gridSize - 1, max(0, Int(midpoint.x / max(1.0, Double(width)) * Double(gridSize))))
            let cellY = min(gridSize - 1, max(0, Int(midpoint.y / max(1.0, Double(height)) * Double(gridSize))))
            prepared.append(AUUprightV2PreparedLine(
                segment: segment,
                originalIndex: originalIndex,
                coefficients: coefficients,
                direction: direction,
                quality: scoreQuality * lengthQuality,
                cell: cellY * gridSize + cellX
            ))
        }
        prepared.sort {
            if $0.quality == $1.quality {
                return $0.originalIndex < $1.originalIndex
            }
            return $0.quality > $1.quality
        }

        let angleThreshold = 2.0 * .pi / 180.0
        let offsetThreshold = diagonal * 0.01
        var cellCounts: [Int: Int] = [:]
        var kept: [AUUprightV2PreparedLine] = []
        for candidate in prepared {
            if cellCounts[candidate.cell, default: 0] >= 20 {
                continue
            }
            var duplicate = false
            for existing in kept {
                let angle = (try? AnyUprightUprightV2Geometry.undirectedAngle(
                    candidate.direction,
                    existing.direction
                )) ?? .infinity
                if angle > angleThreshold {
                    continue
                }
                let firstDistance = abs(
                    AnyUprightUprightV2Geometry.dot(
                        existing.coefficients,
                        SIMD3(candidate.midpoint.x, candidate.midpoint.y, 1.0)
                    )
                )
                let secondDistance = abs(
                    AnyUprightUprightV2Geometry.dot(
                        candidate.coefficients,
                        SIMD3(existing.midpoint.x, existing.midpoint.y, 1.0)
                    )
                )
                if max(firstDistance, secondDistance) > offsetThreshold {
                    continue
                }
                let overlap = (try? AnyUprightUprightV2Geometry.intervalOverlapRatio(
                    firstStart: candidate.segment.start,
                    firstEnd: candidate.segment.end,
                    secondStart: existing.segment.start,
                    secondEnd: existing.segment.end
                )) ?? 0.0
                if overlap >= 0.5 {
                    duplicate = true
                    break
                }
            }
            if duplicate {
                continue
            }
            kept.append(candidate)
            cellCounts[candidate.cell, default: 0] += 1
            if kept.count >= 256 {
                break
            }
        }
        return kept
    }

    private static func generateVPClusters(
        _ lines: [AUUprightV2PreparedLine],
        intrinsics: AUUprightV2Matrix3
    ) -> [AUUprightV2VPCluster] {
        struct Pair {
            var quality: Double
            var first: Int
            var second: Int
            var ray: SIMD3<Double>
        }
        var pairs: [Pair] = []
        for first in 0..<(lines.count - 1) {
            for second in (first + 1)..<lines.count {
                let point = AnyUprightUprightV2Geometry.cross(
                    lines[first].coefficients,
                    lines[second].coefficients
                )
                guard AnyUprightUprightV2Geometry.norm(point) > 1e-12,
                      let ray = try? AnyUprightUprightV2Geometry.canonicalRay(
                          AnyUprightUprightV2Geometry.vpToRay(point, intrinsics: intrinsics)
                      ) else {
                    continue
                }
                let midpointDistance = hypot(
                    lines[first].midpoint.x - lines[second].midpoint.x,
                    lines[first].midpoint.y - lines[second].midpoint.y
                )
                let separation = min(1.0, midpointDistance / 256.0)
                pairs.append(Pair(
                    quality: sqrt(max(0.0, lines[first].quality * lines[second].quality))
                        * (0.5 + 0.5 * separation),
                    first: first,
                    second: second,
                    ray: ray
                ))
            }
        }
        pairs.sort {
            if $0.quality != $1.quality {
                return $0.quality > $1.quality
            }
            if $0.first != $1.first {
                return $0.first < $1.first
            }
            return $0.second < $1.second
        }

        let planeNormals = lines.map { intrinsics.transposed * $0.coefficients }
        var hypotheses: [(cluster: AUUprightV2VPCluster, ordinal: Int)] = []
        for (ordinal, pair) in pairs.prefix(maximumHypotheses).enumerated() {
            var supporters = supporterIndexes(
                ray: pair.ray,
                planeNormals: planeNormals,
                threshold: supportThreshold
            )
            guard supporters.count >= 2,
                  let fitted = fitVP(lines: lines, supporters: supporters, intrinsics: intrinsics) else {
                continue
            }
            let residuals = residualsForRay(fitted.ray, planeNormals: planeNormals)
            supporters = residuals.indices.filter { residuals[$0] <= supportThreshold }
            guard supporters.count >= 2 else {
                continue
            }
            let supportQuality = supporters.reduce(0.0) {
                $0 + lines[$1].quality * max(0.0, 1.0 - residuals[$1] / supportThreshold)
            }
            let totalWeight = supporters.reduce(0.0) { $0 + lines[$1].quality }
            let meanResidual = supporters.reduce(0.0) {
                $0 + residuals[$1] * lines[$1].quality
            } / max(1e-12, totalWeight)
            let coverage = Double(Set(supporters.map { lines[$0].cell }).count)
                / Double(gridSize * gridSize)
            hypotheses.append((
                AUUprightV2VPCluster(
                    ray: fitted.ray,
                    homogeneousPoint: fitted.point,
                    supporters: supporters,
                    supportQuality: supportQuality,
                    meanResidualRadians: meanResidual,
                    coverage: coverage
                ),
                ordinal
            ))
        }
        hypotheses.sort {
            let firstScore = $0.cluster.supportQuality * (0.5 + $0.cluster.coverage)
            let secondScore = $1.cluster.supportQuality * (0.5 + $1.cluster.coverage)
            if firstScore != secondScore {
                return firstScore > secondScore
            }
            if $0.cluster.meanResidualRadians != $1.cluster.meanResidualRadians {
                return $0.cluster.meanResidualRadians < $1.cluster.meanResidualRadians
            }
            if $0.cluster.supporters.count != $1.cluster.supporters.count {
                return $0.cluster.supporters.count > $1.cluster.supporters.count
            }
            return $0.ordinal < $1.ordinal
        }
        var clusters: [AUUprightV2VPCluster] = []
        for hypothesis in hypotheses.map(\.cluster) {
            let duplicate = clusters.contains {
                ((try? AnyUprightUprightV2Geometry.undirectedAngle(hypothesis.ray, $0.ray)) ?? 0.0)
                    <= clusterThreshold
            }
            if !duplicate {
                clusters.append(hypothesis)
                if clusters.count >= maximumClusters {
                    break
                }
            }
        }
        return clusters
    }

    private static func generatePriorGuidedCluster(
        _ lines: [AUUprightV2PreparedLine],
        intrinsics: AUUprightV2Matrix3,
        prior: AUUprightV2CameraPrior
    ) -> AUUprightV2VPCluster? {
        guard lines.count >= 2,
              let initialRay = try? AnyUprightUprightV2Geometry.canonicalRay(prior.gravity) else {
            return nil
        }
        let planeNormals = lines.map { intrinsics.transposed * $0.coefficients }
        let broadThreshold = max(
            supportThreshold,
            min(10.0 * .pi / 180.0, max(4.0 * .pi / 180.0, prior.gravityUncertainty * 2.5))
        )
        var supporters = supporterIndexes(
            ray: initialRay,
            planeNormals: planeNormals,
            threshold: broadThreshold
        )
        guard supporters.count >= 2,
              var fitted = fitVP(lines: lines, supporters: supporters, intrinsics: intrinsics) else {
            return nil
        }
        let narrowThreshold = max(
            supportThreshold,
            min(5.0 * .pi / 180.0, prior.gravityUncertainty * 1.5)
        )
        var residuals = residualsForRay(fitted.ray, planeNormals: planeNormals)
        supporters = residuals.indices.filter { residuals[$0] <= narrowThreshold }
        guard supporters.count >= 2,
              let refitted = fitVP(lines: lines, supporters: supporters, intrinsics: intrinsics) else {
            return nil
        }
        fitted = refitted
        residuals = residualsForRay(fitted.ray, planeNormals: planeNormals)
        let supportQuality = supporters.reduce(0.0) {
            $0 + lines[$1].quality * max(0.0, 1.0 - residuals[$1] / max(1e-12, narrowThreshold))
        }
        let totalWeight = supporters.reduce(0.0) { $0 + lines[$1].quality }
        return AUUprightV2VPCluster(
            ray: fitted.ray,
            homogeneousPoint: fitted.point,
            supporters: supporters,
            supportQuality: supportQuality,
            meanResidualRadians: supporters.reduce(0.0) {
                $0 + residuals[$1] * lines[$1].quality
            } / max(1e-12, totalWeight),
            coverage: Double(Set(supporters.map { lines[$0].cell }).count)
                / Double(gridSize * gridSize)
        )
    }

    private static func fitVP(
        lines: [AUUprightV2PreparedLine],
        supporters: [Int],
        intrinsics: AUUprightV2Matrix3
    ) -> (ray: SIMD3<Double>, point: SIMD3<Double>)? {
        var normal = AUUprightV2Matrix3(Array(repeating: 0.0, count: 9))
        for index in supporters {
            let coefficient = lines[index].coefficients
            let weight = lines[index].quality
            let values = [coefficient.x, coefficient.y, coefficient.z]
            for row in 0..<3 {
                for column in 0..<3 {
                    normal[row, column] += weight * values[row] * values[column]
                }
            }
        }
        guard let point = try? AnyUprightUprightV2Geometry.smallestEigenvector(of: normal),
              let ray = try? AnyUprightUprightV2Geometry.canonicalRay(
                  AnyUprightUprightV2Geometry.vpToRay(point, intrinsics: intrinsics)
              ) else {
            return nil
        }
        return (ray, point)
    }

    private static func discreteCandidates(
        _ prepared: [AUUprightV2PreparedLine],
        clusters: [AUUprightV2VPCluster],
        width: Int,
        height: Int,
        prior: AUUprightV2CameraPrior?
    ) -> [AUUprightV2Candidate] {
        var candidates = [score(
            matrix: .identity,
            cropScale: 1.0,
            verticalStrength: 0.0,
            horizontalStrength: 0.0,
            focalScale: 1.0,
            aspect: 1.0,
            vertical: nil,
            horizontal: nil,
            prepared: prepared,
            clusters: clusters,
            intrinsics: nil,
            prior: prior,
            width: width,
            height: height,
            thirdAxis: 0.0
        )]
        var combinations = clusterCombinations(
            clusters,
            width: width,
            height: height,
            prior: prior
        )
        combinations.sort {
            let first = combinationQuality($0, clusters: clusters)
            let second = combinationQuality($1, clusters: clusters)
            return first == second ? $0.ordinal < $1.ordinal : first > second
        }
        for combination in combinations.prefix(16) {
            let vertical = clusters[combination.verticalIndex]
            let horizontal = combination.horizontalIndex.map { clusters[$0] }
            guard let verticalRay = refinedRay(vertical, intrinsics: combination.intrinsics) else {
                continue
            }
            let horizontalRay = horizontal.flatMap { refinedRay($0, intrinsics: combination.intrinsics) }
            for verticalStrength in strengths {
                for horizontalStrength in strengths {
                    if verticalStrength == 0.0 && horizontalStrength == 0.0 {
                        continue
                    }
                    if horizontalStrength > 0.0 && horizontal == nil {
                        continue
                    }
                    guard let rotation = try? AnyUprightUprightV2Geometry.correctionRotation(
                        verticalRay: verticalRay,
                        horizontalRay: horizontalRay,
                        verticalStrength: verticalStrength,
                        horizontalStrength: horizontalStrength
                    ), let initial = try? AnyUprightUprightV2Geometry.sourceToOutputHomography(
                        width: width,
                        height: height,
                        sourceIntrinsics: combination.intrinsics,
                        correction: rotation,
                        focalScale: 1.0,
                        aspect: 1.0
                    ), let framed = try? AnyUprightUprightV2Geometry.frameAndCropHomography(
                        initial,
                        width: width,
                        height: height,
                        maximumScale: maximumCropScale
                    ) else {
                        continue
                    }
                    let selectedHorizontal = horizontalStrength > 0.0 ? horizontal : nil
                    let thirdAxis = if horizontalStrength > 0.0,
                                       let horizontalIndex = combination.horizontalIndex {
                        thirdAxisPenalty(
                            verticalIndex: combination.verticalIndex,
                            horizontalIndex: horizontalIndex,
                            clusters: clusters,
                            intrinsics: combination.intrinsics,
                            prepared: prepared
                        )
                    } else {
                        0.0
                    }
                    candidates.append(score(
                        matrix: framed.matrix,
                        cropScale: framed.cropScale,
                        verticalStrength: verticalStrength,
                        horizontalStrength: horizontalStrength,
                        focalScale: 1.0,
                        aspect: 1.0,
                        vertical: vertical,
                        horizontal: selectedHorizontal,
                        prepared: prepared,
                        clusters: clusters,
                        intrinsics: combination.intrinsics,
                        prior: prior,
                        width: width,
                        height: height,
                        thirdAxis: thirdAxis
                    ))
                }
            }
        }
        if let prior {
            var gravity = prior.gravity
            if gravity.y < 0.0 {
                gravity = -gravity
            }
            let roll = atan2(gravity.x, gravity.y)
            let intrinsics = AnyUprightUprightV2Geometry.cameraIntrinsics(
                width: width,
                height: height,
                verticalFOV: prior.verticalFOVRadians
            )
            if let rotation = try? AnyUprightUprightV2Geometry.rotation(
                axis: SIMD3(0, 0, 1),
                angle: roll
            ), let initial = try? AnyUprightUprightV2Geometry.sourceToOutputHomography(
                width: width,
                height: height,
                sourceIntrinsics: intrinsics,
                correction: rotation,
                focalScale: 1.0,
                aspect: 1.0
            ), let framed = try? AnyUprightUprightV2Geometry.frameAndCropHomography(
                initial,
                width: width,
                height: height,
                maximumScale: maximumCropScale
            ) {
                candidates.append(score(
                    matrix: framed.matrix,
                    cropScale: framed.cropScale,
                    verticalStrength: 0.0,
                    horizontalStrength: 0.0,
                    focalScale: 1.0,
                    aspect: 1.0,
                    vertical: nil,
                    horizontal: nil,
                    prepared: prepared,
                    clusters: clusters,
                    intrinsics: intrinsics,
                    prior: prior,
                    width: width,
                    height: height,
                    thirdAxis: 0.0
                ))
            }
        } else if let rollCandidate = lineRollCandidate(
            prepared,
            clusters: clusters,
            width: width,
            height: height
        ) {
            candidates.append(rollCandidate)
        }
        return candidates
    }

    private static func clusterCombinations(
        _ clusters: [AUUprightV2VPCluster],
        width: Int,
        height: Int,
        prior: AUUprightV2CameraPrior?
    ) -> [AUUprightV2Combination] {
        var result: [AUUprightV2Combination] = []
        var ordinal = 0
        if let prior {
            let intrinsics = AnyUprightUprightV2Geometry.cameraIntrinsics(
                width: width,
                height: height,
                verticalFOV: prior.verticalFOVRadians
            )
            guard let gravity = try? AnyUprightUprightV2Geometry.normalized(prior.gravity) else {
                return []
            }
            let verticalRanked = clusters.indices.sorted {
                let firstAngle = refinedRay(clusters[$0], intrinsics: intrinsics)
                    .flatMap { try? AnyUprightUprightV2Geometry.undirectedAngle($0, gravity) } ?? .infinity
                let secondAngle = refinedRay(clusters[$1], intrinsics: intrinsics)
                    .flatMap { try? AnyUprightUprightV2Geometry.undirectedAngle($0, gravity) } ?? .infinity
                if firstAngle != secondAngle {
                    return firstAngle < secondAngle
                }
                return clusterQuality(clusters[$0]) > clusterQuality(clusters[$1])
            }.prefix(12)
            let horizontalRanked = clusters.indices.sorted {
                let first = refinedRay(clusters[$0], intrinsics: intrinsics)
                    .map { abs(AnyUprightUprightV2Geometry.dot($0, gravity)) } ?? .infinity
                let second = refinedRay(clusters[$1], intrinsics: intrinsics)
                    .map { abs(AnyUprightUprightV2Geometry.dot($0, gravity)) } ?? .infinity
                if first != second {
                    return first < second
                }
                return clusterQuality(clusters[$0]) > clusterQuality(clusters[$1])
            }.prefix(24)
            for verticalIndex in verticalRanked {
                guard let verticalRay = refinedRay(clusters[verticalIndex], intrinsics: intrinsics),
                      let angle = try? AnyUprightUprightV2Geometry.undirectedAngle(verticalRay, gravity),
                      angle <= max(8.0 * .pi / 180.0, min(30.0 * .pi / 180.0, prior.gravityUncertainty * 4.0)) else {
                    continue
                }
                result.append(AUUprightV2Combination(
                    verticalIndex: verticalIndex,
                    horizontalIndex: nil,
                    intrinsics: intrinsics,
                    ordinal: ordinal
                ))
                ordinal += 1
                for horizontalIndex in horizontalRanked where horizontalIndex != verticalIndex {
                    guard let horizontalRay = refinedRay(clusters[horizontalIndex], intrinsics: intrinsics),
                          abs(AnyUprightUprightV2Geometry.dot(verticalRay, horizontalRay))
                            <= sin(15.0 * .pi / 180.0) else {
                        continue
                    }
                    result.append(AUUprightV2Combination(
                        verticalIndex: verticalIndex,
                        horizontalIndex: horizontalIndex,
                        intrinsics: intrinsics,
                        ordinal: ordinal
                    ))
                    ordinal += 1
                }
            }
            return result
        }

        for first in clusters.indices {
            for second in clusters.indices where second > first {
                guard let focal = inferredFocal(
                    first: clusters[first].homogeneousPoint,
                    second: clusters[second].homogeneousPoint,
                    width: width,
                    height: height
                ) else {
                    continue
                }
                let fov = AnyUprightUprightV2Geometry.fovFromFocal(height: height, focal: focal)
                guard fov >= 25.0 * .pi / 180.0, fov <= 130.0 * .pi / 180.0 else {
                    continue
                }
                let intrinsics = AnyUprightUprightV2Geometry.cameraIntrinsics(
                    width: width,
                    height: height,
                    verticalFOV: fov
                )
                guard let firstRay = refinedRay(clusters[first], intrinsics: intrinsics),
                      let secondRay = refinedRay(clusters[second], intrinsics: intrinsics),
                      abs(AnyUprightUprightV2Geometry.dot(firstRay, secondRay))
                        <= sin(15.0 * .pi / 180.0) else {
                    continue
                }
                for (verticalIndex, horizontalIndex) in [(first, second), (second, first)] {
                    let point = clusters[verticalIndex].homogeneousPoint
                    if abs(point.z) > 1e-12 {
                        let x = point.x / point.z
                        let y = point.y / point.z
                        let dx = abs(x - (Double(width) - 1.0) * 0.5)
                        let dy = abs(y - (Double(height) - 1.0) * 0.5)
                        if dy < dx {
                            continue
                        }
                    }
                    result.append(AUUprightV2Combination(
                        verticalIndex: verticalIndex,
                        horizontalIndex: nil,
                        intrinsics: intrinsics,
                        ordinal: ordinal
                    ))
                    ordinal += 1
                    result.append(AUUprightV2Combination(
                        verticalIndex: verticalIndex,
                        horizontalIndex: horizontalIndex,
                        intrinsics: intrinsics,
                        ordinal: ordinal
                    ))
                    ordinal += 1
                }
            }
        }
        return result
    }

    private static func score(
        matrix: AUUprightV2Matrix3,
        cropScale: Double,
        verticalStrength: Double,
        horizontalStrength: Double,
        focalScale: Double,
        aspect: Double,
        vertical: AUUprightV2VPCluster?,
        horizontal: AUUprightV2VPCluster?,
        prepared: [AUUprightV2PreparedLine],
        clusters: [AUUprightV2VPCluster],
        intrinsics: AUUprightV2Matrix3?,
        prior: AUUprightV2CameraPrior?,
        width: Int,
        height: Int,
        thirdAxis: Double
    ) -> AUUprightV2Candidate {
        let qualities = prepared.map(\.quality)
        var alignment = prepared.isEmpty ? 0.0 : 20.0
        if let transformed = try? AnyUprightUprightV2Geometry.transformedLines(
            prepared.map(\.coefficients),
            by: matrix
        ) {
            let maximum = 30.0 * .pi / 180.0
            let delta = 2.0 * .pi / 180.0
            let valid = transformed.indices.compactMap { index -> (Double, Double)? in
                guard let line = transformed[index] else {
                    return nil
                }
                let residual = AnyUprightUprightV2Geometry.axisResidual(line)
                guard residual.isFinite, residual <= maximum else {
                    return nil
                }
                let normalized = residual / max(1e-12, delta)
                return (2.0 * (sqrt(1.0 + normalized * normalized) - 1.0), qualities[index])
            }
            if !valid.isEmpty {
                alignment = valid.reduce(0.0) { $0 + $1.0 * $1.1 }
                    / max(1e-12, valid.reduce(0.0) { $0 + $1.1 })
            }
        }

        let totalQuality = max(1e-12, qualities.reduce(0.0, +))
        let selected = [vertical, horizontal].compactMap { $0 }
        let consensus: Double
        let coverage: Double
        if selected.isEmpty {
            consensus = 0.75
            coverage = 0.75
        } else {
            consensus = 1.0 - min(1.0, selected.reduce(0.0) { $0 + $1.supportQuality } / totalQuality)
            coverage = 1.0 - selected.reduce(0.0) { $0 + $1.coverage } / Double(selected.count)
        }

        var orthogonality = 0.0
        if let vertical, let horizontal, let intrinsics,
           let verticalRay = refinedRay(vertical, intrinsics: intrinsics),
           let horizontalRay = refinedRay(horizontal, intrinsics: intrinsics) {
            orthogonality = abs(AnyUprightUprightV2Geometry.dot(verticalRay, horizontalRay))
                / sin(10.0 * .pi / 180.0)
        }

        var cameraPrior = 0.0
        if let prior {
            if let vertical, let intrinsics,
               let gravity = try? AnyUprightUprightV2Geometry.normalized(prior.gravity),
               let verticalRay = refinedRay(vertical, intrinsics: intrinsics),
               let angle = try? AnyUprightUprightV2Geometry.undirectedAngle(gravity, verticalRay) {
                cameraPrior += angle / max(5.0 * .pi / 180.0, prior.gravityUncertainty)
            }
            if let intrinsics,
               abs(focalScale - 1.0) > 1e-12 || abs(aspect - 1.0) > 1e-12 {
                let candidateFOV = AnyUprightUprightV2Geometry.fovFromFocal(
                    height: height,
                    focal: intrinsics[1, 1] * focalScale / max(1e-12, aspect)
                )
                cameraPrior += abs(candidateFOV - prior.verticalFOVRadians)
                    / max(3.0 * .pi / 180.0, prior.verticalFOVUncertaintyRadians)
            }
        }

        var crop = max(0.0, cropScale - 1.0)
        crop *= crop
        if cropScale > maximumCropScale {
            crop += 25.0
        }
        let jacobianStats = AnyUprightUprightV2Geometry.jacobianStatistics(
            matrix,
            width: width,
            height: height
        )
        var jacobian = jacobianStats.condition + 0.5 * jacobianStats.areaSpread
        if !jacobian.isFinite {
            jacobian = 100.0
        }
        var fovPenalty = 0.0
        if let intrinsics {
            let targetFOV = AnyUprightUprightV2Geometry.fovFromFocal(
                height: height,
                focal: intrinsics[1, 1] * focalScale / max(1e-12, aspect)
            )
            let low = 25.0 * .pi / 180.0
            let high = 130.0 * .pi / 180.0
            if targetFOV < low {
                fovPenalty = (low - targetFOV) / (10.0 * .pi / 180.0)
            } else if targetFOV > high {
                fovPenalty = (targetFOV - high) / (10.0 * .pi / 180.0)
            }
        }
        let identity = AnyUprightUprightV2Geometry.normalizedGridDisplacement(
            matrix,
            width: width,
            height: height
        )
        let verticalSupporters = vertical?.supporters.map { prepared[$0].originalIndex } ?? []
        let horizontalSupporters = horizontal?.supporters.map { prepared[$0].originalIndex } ?? []
        return AUUprightV2Candidate(
            sourceToOutput: matrix.values,
            cropScale: cropScale,
            verticalStrength: verticalStrength,
            horizontalStrength: horizontalStrength,
            focalScale: focalScale,
            aspect: aspect,
            terms: [
                alignment,
                consensus,
                coverage,
                orthogonality,
                thirdAxis,
                cameraPrior,
                crop,
                jacobian,
                fovPenalty,
                identity,
            ],
            verticalSupporters: verticalSupporters,
            horizontalSupporters: horizontalSupporters
        )
    }

    private static func lineRollCandidate(
        _ prepared: [AUUprightV2PreparedLine],
        clusters: [AUUprightV2VPCluster],
        width: Int,
        height: Int
    ) -> AUUprightV2Candidate? {
        guard !prepared.isEmpty else {
            return nil
        }
        var sine = 0.0
        var cosine = 0.0
        for line in prepared {
            let angle = atan2(line.direction.y, line.direction.x)
            let residual = positiveModulo(angle + .pi / 4.0, .pi / 2.0) - .pi / 4.0
            sine += line.quality * sin(2.0 * residual)
            cosine += line.quality * cos(2.0 * residual)
        }
        let correction = -0.5 * atan2(sine, cosine)
        let intrinsics = AnyUprightUprightV2Geometry.cameraIntrinsics(
            width: width,
            height: height,
            verticalFOV: .pi / 3.0
        )
        guard let rotation = try? AnyUprightUprightV2Geometry.rotation(
            axis: SIMD3(0, 0, 1),
            angle: correction
        ), let initial = try? AnyUprightUprightV2Geometry.sourceToOutputHomography(
            width: width,
            height: height,
            sourceIntrinsics: intrinsics,
            correction: rotation,
            focalScale: 1.0,
            aspect: 1.0
        ), let framed = try? AnyUprightUprightV2Geometry.frameAndCropHomography(
            initial,
            width: width,
            height: height,
            maximumScale: maximumCropScale
        ) else {
            return nil
        }
        return score(
            matrix: framed.matrix,
            cropScale: framed.cropScale,
            verticalStrength: 0.0,
            horizontalStrength: 0.0,
            focalScale: 1.0,
            aspect: 1.0,
            vertical: nil,
            horizontal: nil,
            prepared: prepared,
            clusters: clusters,
            intrinsics: intrinsics,
            prior: nil,
            width: width,
            height: height,
            thirdAxis: 0.0
        )
    }

    private static func thirdAxisPenalty(
        verticalIndex: Int,
        horizontalIndex: Int,
        clusters: [AUUprightV2VPCluster],
        intrinsics: AUUprightV2Matrix3,
        prepared: [AUUprightV2PreparedLine]
    ) -> Double {
        guard let vertical = refinedRay(clusters[verticalIndex], intrinsics: intrinsics),
              let horizontal = refinedRay(clusters[horizontalIndex], intrinsics: intrinsics),
              let third = try? AnyUprightUprightV2Geometry.normalized(
                  AnyUprightUprightV2Geometry.cross(vertical, horizontal)
              ) else {
            return 1.0
        }
        let totalQuality = max(1e-12, prepared.reduce(0.0) { $0 + $1.quality })
        let support = clusters.indices.filter {
            $0 != verticalIndex && $0 != horizontalIndex
        }.compactMap { index -> Double? in
            guard let ray = refinedRay(clusters[index], intrinsics: intrinsics),
                  let angle = try? AnyUprightUprightV2Geometry.undirectedAngle(ray, third),
                  angle <= 7.5 * .pi / 180.0 else {
                return nil
            }
            return clusters[index].supportQuality
        }.max() ?? 0.0
        return 1.0 - min(1.0, support / totalQuality)
    }

    private static func residualsForRay(
        _ ray: SIMD3<Double>,
        planeNormals: [SIMD3<Double>]
    ) -> [Double] {
        planeNormals.map {
            asin(min(1.0, max(0.0, abs(AnyUprightUprightV2Geometry.dot($0, ray))
                / max(1e-12, AnyUprightUprightV2Geometry.norm($0)))))
        }
    }

    private static func supporterIndexes(
        ray: SIMD3<Double>,
        planeNormals: [SIMD3<Double>],
        threshold: Double
    ) -> [Int] {
        let residuals = residualsForRay(ray, planeNormals: planeNormals)
        return residuals.indices.filter { residuals[$0] <= threshold }
    }

    private static func refinedRay(
        _ cluster: AUUprightV2VPCluster,
        intrinsics: AUUprightV2Matrix3
    ) -> SIMD3<Double>? {
        try? AnyUprightUprightV2Geometry.canonicalRay(
            AnyUprightUprightV2Geometry.vpToRay(
                cluster.homogeneousPoint,
                intrinsics: intrinsics
            )
        )
    }

    private static func inferredFocal(
        first: SIMD3<Double>,
        second: SIMD3<Double>,
        width: Int,
        height: Int
    ) -> Double? {
        let denominator = first.z * second.z
        guard abs(denominator) > 1e-12 else {
            return nil
        }
        let cx = (Double(width) - 1.0) * 0.5
        let cy = (Double(height) - 1.0) * 0.5
        let firstXY = SIMD2(first.x - cx * first.z, first.y - cy * first.z)
        let secondXY = SIMD2(second.x - cx * second.z, second.y - cy * second.z)
        let squared = -AnyUprightUprightV2Geometry.dot(firstXY, secondXY) / denominator
        guard squared.isFinite, squared > 1e-6 else {
            return nil
        }
        return sqrt(squared)
    }

    private static func clusterQuality(_ cluster: AUUprightV2VPCluster) -> Double {
        cluster.supportQuality * (0.5 + cluster.coverage)
    }

    private static func combinationQuality(
        _ combination: AUUprightV2Combination,
        clusters: [AUUprightV2VPCluster]
    ) -> Double {
        clusterQuality(clusters[combination.verticalIndex])
            + (combination.horizontalIndex.map { clusterQuality(clusters[$0]) } ?? 0.0)
    }

    private static func lineLength(_ line: AUScaleLSDLineSegment) -> Double {
        hypot(line.end.x - line.start.x, line.end.y - line.start.y)
    }

    private static func lineMidpoint(_ line: AUScaleLSDLineSegment) -> AUPoint {
        AUPoint(
            x: (line.start.x + line.end.x) * 0.5,
            y: (line.start.y + line.end.y) * 0.5
        )
    }

    private static func positiveModulo(_ value: Double, _ modulus: Double) -> Double {
        let result = value.truncatingRemainder(dividingBy: modulus)
        return result >= 0.0 ? result : result + modulus
    }
}
