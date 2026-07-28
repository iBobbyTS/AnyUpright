//
//  AnyUprightUprightV2CandidateGeneratorTests.swift
//  AnyUprightTests
//

import Foundation

private struct GeneratorFixturePoint: Decodable {
    let x: Double
    let y: Double
}

private struct GeneratorFixtureLine: Decodable {
    let start: GeneratorFixturePoint
    let end: GeneratorFixturePoint
    let score: Double

    var line: AUScaleLSDLineSegment {
        AUScaleLSDLineSegment(
            start: AUPoint(x: start.x, y: start.y),
            end: AUPoint(x: end.x, y: end.y),
            score: score
        )
    }
}

private struct GeneratorFixturePrior: Decodable {
    let gravity: [Double]
    let gravityUncertainty: Double
    let verticalFOVRadians: Double
    let verticalFOVUncertaintyRadians: Double

    enum CodingKeys: String, CodingKey {
        case gravity
        case gravityUncertainty = "gravity_uncertainty"
        case verticalFOVRadians = "vertical_fov_radians"
        case verticalFOVUncertaintyRadians = "vertical_fov_uncertainty_radians"
    }

    var prior: AUUprightV2CameraPrior {
        AUUprightV2CameraPrior(
            gravity: SIMD3(gravity[0], gravity[1], gravity[2]),
            gravityUncertainty: gravityUncertainty,
            verticalFOVRadians: verticalFOVRadians,
            verticalFOVUncertaintyRadians: verticalFOVUncertaintyRadians
        )
    }
}

private struct GeneratorFixtureCandidate: Decodable {
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
}

private struct GeneratorFixtureSample: Decodable {
    let label: String
    let width: Double
    let height: Double
    let prior: GeneratorFixturePrior?
    let preparedLineCount: Int
    let vpClusterCount: Int
    let lines: [GeneratorFixtureLine]
    let candidates: [GeneratorFixtureCandidate]

    enum CodingKeys: String, CodingKey {
        case label
        case width
        case height
        case prior
        case preparedLineCount = "prepared_line_count"
        case vpClusterCount = "vp_cluster_count"
        case lines
        case candidates
    }
}

private struct GeneratorFixtureRoot: Decodable {
    let samples: [GeneratorFixtureSample]
}

private func generatorRequire(
    _ condition: @autoclosure () -> Bool,
    _ message: @autoclosure () -> String
) {
    guard condition() else {
        fatalError(message())
    }
}

private func generatorRequireClose(
    _ actual: Double,
    _ expected: Double,
    tolerance: Double,
    _ context: String
) {
    let allowed = tolerance * max(1.0, abs(expected))
    generatorRequire(
        abs(actual - expected) <= allowed,
        "\(context): expected \(expected), got \(actual), diff \(abs(actual - expected)), allowed \(allowed)"
    )
}

@main
private enum AnyUprightUprightV2CandidateGeneratorTests {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            fatalError("usage: test fixture.json")
        }
        let fixture = try JSONDecoder().decode(
            GeneratorFixtureRoot.self,
            from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
        )
        for sample in fixture.samples {
            let pool = AnyUprightUprightV2CandidateGenerator.candidatePool(
                lines: sample.lines.map(\.line),
                imageSize: AUSize(width: sample.width, height: sample.height),
                cameraPrior: sample.prior?.prior
            )
            generatorRequire(
                pool.preparedLineCount == sample.preparedLineCount,
                "\(sample.label): prepared lines \(pool.preparedLineCount) != \(sample.preparedLineCount)"
            )
            generatorRequire(
                pool.vpClusterCount == sample.vpClusterCount,
                "\(sample.label): VP clusters \(pool.vpClusterCount) != \(sample.vpClusterCount)"
            )
            generatorRequire(
                pool.candidates.count == sample.candidates.count,
                "\(sample.label): candidates \(pool.candidates.count) != \(sample.candidates.count)"
            )
            for index in pool.candidates.indices {
                let actual = pool.candidates[index]
                let expected = sample.candidates[index]
                generatorRequireClose(
                    actual.verticalStrength,
                    expected.verticalStrength,
                    tolerance: 1e-12,
                    "\(sample.label) candidate \(index) vertical strength"
                )
                generatorRequireClose(
                    actual.horizontalStrength,
                    expected.horizontalStrength,
                    tolerance: 1e-12,
                    "\(sample.label) candidate \(index) horizontal strength"
                )
                generatorRequire(
                    actual.verticalSupporters == expected.verticalSupporters,
                    "\(sample.label) candidate \(index) vertical supporters"
                )
                generatorRequire(
                    actual.horizontalSupporters == expected.horizontalSupporters,
                    "\(sample.label) candidate \(index) horizontal supporters"
                )
                for matrixIndex in actual.sourceToOutput.indices {
                    generatorRequireClose(
                        actual.sourceToOutput[matrixIndex],
                        expected.sourceToOutput[matrixIndex],
                        tolerance: 2e-5,
                        "\(sample.label) candidate \(index) matrix \(matrixIndex)"
                    )
                }
                generatorRequireClose(
                    actual.cropScale,
                    expected.cropScale,
                    tolerance: 2e-6,
                    "\(sample.label) candidate \(index) crop scale"
                )
                for termIndex in actual.terms.indices {
                    generatorRequireClose(
                        actual.terms[termIndex],
                        expected.terms[termIndex],
                        tolerance: 2e-5,
                        "\(sample.label) candidate \(index) term \(termIndex)"
                    )
                }
            }
        }
        print("AnyUprightUprightV2CandidateGeneratorTests passed (\(fixture.samples.count) samples)")
    }
}
