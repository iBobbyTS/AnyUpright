//
//  AnyUprightUprightV2RankerTests.swift
//  AnyUprightTests
//

import Foundation

private struct FixturePoint: Decodable {
    let x: Double
    let y: Double
}

private struct FixtureLine: Decodable {
    let start: FixturePoint
    let end: FixturePoint
    let score: Double

    var line: AUScaleLSDLineSegment {
        AUScaleLSDLineSegment(
            start: AUPoint(x: start.x, y: start.y),
            end: AUPoint(x: end.x, y: end.y),
            score: score
        )
    }
}

private struct FixtureCandidate: Decodable {
    let sourceToOutput: [Double]
    let cropScale: Double
    let verticalStrength: Double
    let horizontalStrength: Double
    let focalScale: Double
    let aspect: Double
    let terms: [Double]
    let verticalSupporters: [Int]
    let horizontalSupporters: [Int]

    enum CodingKeys: String, CodingKey {
        case sourceToOutput = "source_to_output"
        case cropScale = "crop_scale"
        case verticalStrength = "vertical_strength"
        case horizontalStrength = "horizontal_strength"
        case focalScale = "focal_scale"
        case aspect
        case terms
        case verticalSupporters = "vertical_supporters"
        case horizontalSupporters = "horizontal_supporters"
    }

    var candidate: AUUprightV2Candidate {
        AUUprightV2Candidate(
            sourceToOutput: sourceToOutput,
            cropScale: cropScale,
            verticalStrength: verticalStrength,
            horizontalStrength: horizontalStrength,
            focalScale: focalScale,
            aspect: aspect,
            terms: terms,
            verticalSupporters: verticalSupporters,
            horizontalSupporters: horizontalSupporters
        )
    }
}

private struct FixtureFeatureCase: Decodable {
    let candidate: FixtureCandidate
    let expectedFeatures: [Double]
    let expectedPairScore: Double
    let expectedRiskProbability: Double
    let frozenRank: Int

    enum CodingKeys: String, CodingKey {
        case candidate
        case expectedFeatures = "expected_features"
        case expectedPairScore = "expected_pair_score"
        case expectedRiskProbability = "expected_risk_probability"
        case frozenRank = "frozen_rank"
    }
}

private struct FixtureSample: Decodable {
    let stem: String
    let width: Double
    let height: Double
    let lines: [FixtureLine]
    let allCandidates: [FixtureCandidate]
    let preparedLineCount: Int
    let vpClusterCount: Int
    let candidateCount: Int
    let bestEnergy: Double
    let featureCases: [FixtureFeatureCase]
    let expectedAccepted: Bool
    let expectedPairScore: Double
    let expectedRiskProbability: Double
    let expectedVerticalSupporters: [Int]
    let expectedHorizontalSupporters: [Int]

    enum CodingKeys: String, CodingKey {
        case stem
        case width
        case height
        case lines
        case allCandidates = "all_candidates"
        case preparedLineCount = "prepared_line_count"
        case vpClusterCount = "vp_cluster_count"
        case candidateCount = "candidate_count"
        case bestEnergy = "best_energy"
        case featureCases = "feature_cases"
        case expectedAccepted = "expected_accepted"
        case expectedPairScore = "expected_pair_score"
        case expectedRiskProbability = "expected_risk_probability"
        case expectedVerticalSupporters = "expected_vertical_supporters"
        case expectedHorizontalSupporters = "expected_horizontal_supporters"
    }
}

private struct FixtureRoot: Decodable {
    let riskThreshold: Double
    let samples: [FixtureSample]

    enum CodingKeys: String, CodingKey {
        case riskThreshold = "risk_threshold"
        case samples
    }
}

private func require(
    _ condition: @autoclosure () -> Bool,
    _ message: @autoclosure () -> String
) {
    guard condition() else {
        fatalError(message())
    }
}

private func requireClose(
    _ actual: Double,
    _ expected: Double,
    tolerance: Double,
    _ context: String
) {
    require(
        abs(actual - expected) <= tolerance,
        "\(context): expected \(expected), got \(actual), diff \(abs(actual - expected))"
    )
}

@main
private enum AnyUprightUprightV2RankerTests {
    static func main() throws {
        guard CommandLine.arguments.count == 4 else {
            fatalError("usage: test pair-ranker.txt risk-model.txt fixture.json")
        }
        let pairURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let riskURL = URL(fileURLWithPath: CommandLine.arguments[2])
        let fixtureURL = URL(fileURLWithPath: CommandLine.arguments[3])
        let pairModel = try AUUprightV2TreeModel(contentsOf: pairURL)
        let riskModel = try AUUprightV2TreeModel(contentsOf: riskURL)
        let fixture = try JSONDecoder().decode(FixtureRoot.self, from: Data(contentsOf: fixtureURL))

        requireClose(
            fixture.riskThreshold,
            AUUprightV2Models.riskThreshold,
            tolerance: 1e-15,
            "risk threshold"
        )

        for sample in fixture.samples {
            let lines = sample.lines.map(\.line)
            let size = AUSize(width: sample.width, height: sample.height)
            for featureCase in sample.featureCases {
                let features = try AnyUprightUprightV2Ranker.features(
                    candidate: featureCase.candidate.candidate,
                    lines: lines,
                    imageSize: size,
                    preparedLineCount: sample.preparedLineCount,
                    vpClusterCount: sample.vpClusterCount,
                    frozenRank: featureCase.frozenRank,
                    candidateCount: sample.candidateCount,
                    bestEnergy: sample.bestEnergy
                )
                require(features.count == featureCase.expectedFeatures.count, "\(sample.stem): feature count")
                for index in features.indices {
                    requireClose(
                        features[index],
                        featureCase.expectedFeatures[index],
                        tolerance: 2e-5,
                        "\(sample.stem): feature \(index)"
                    )
                }
                requireClose(
                    try pairModel.prediction(features: features),
                    featureCase.expectedPairScore,
                    tolerance: 1e-12,
                    "\(sample.stem): feature-case pair score"
                )
                requireClose(
                    try riskModel.prediction(features: features),
                    featureCase.expectedRiskProbability,
                    tolerance: 1e-12,
                    "\(sample.stem): feature-case risk probability"
                )
            }

            let selected = try AnyUprightUprightV2Ranker.select(
                candidates: sample.allCandidates.map(\.candidate),
                lines: lines,
                imageSize: size,
                preparedLineCount: sample.preparedLineCount,
                vpClusterCount: sample.vpClusterCount
            )
            require((selected != nil) == sample.expectedAccepted, "\(sample.stem): accepted result")
            if let selected {
                requireClose(
                    selected.rankScore,
                    sample.expectedPairScore,
                    tolerance: 1e-12,
                    "\(sample.stem): selected pair score"
                )
                requireClose(
                    selected.riskProbability,
                    sample.expectedRiskProbability,
                    tolerance: 1e-12,
                    "\(sample.stem): selected risk probability"
                )
                require(
                    selected.candidate.verticalSupporters == sample.expectedVerticalSupporters,
                    "\(sample.stem): selected vertical supporters"
                )
                require(
                    selected.candidate.horizontalSupporters == sample.expectedHorizontalSupporters,
                    "\(sample.stem): selected horizontal supporters"
                )
            }
        }

        print("AnyUprightUprightV2RankerTests passed (\(fixture.samples.count) samples)")
    }
}
