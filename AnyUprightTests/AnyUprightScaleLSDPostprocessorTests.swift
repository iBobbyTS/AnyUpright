import Foundation

private enum ScaleLSDPostprocessorTestFailure: Error, CustomStringConvertible {
    case failed(String)

    var description: String {
        switch self {
        case .failed(let message):
            return message
        }
    }
}

private struct Fixture: Decodable {
    var denseTensor: String
    var denseShape: [Int]
    var imageWidth: Int
    var imageHeight: Int
    var lines: [ExpectedLine]

    enum CodingKeys: String, CodingKey {
        case denseTensor = "dense_tensor"
        case denseShape = "dense_shape"
        case imageWidth = "image_width"
        case imageHeight = "image_height"
        case lines
    }
}

private struct ExpectedLine: Decodable {
    var x1: Double
    var y1: Double
    var x2: Double
    var y2: Double
    var score: Double
}

@main
struct AnyUprightScaleLSDPostprocessorTests {
    static func main() throws {
        try verifySpatialSearchMatchesLinearReference()
        if CommandLine.arguments.dropFirst().first == "--synthetic-only" {
            print("AnyUprightScaleLSDPostprocessorTests passed synthetic equivalence")
            return
        }

        let defaultFixture = "/Volumes/4T/temp/AnyUprightResearchWorkspace/model_tests/scalelsd/coreml_conversion/postprocess_fixture.json"
        let fixtureURL = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? defaultFixture)
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: fixtureURL))
        let dense = try readFloatTensor(
            fixtureURL.deletingLastPathComponent().appendingPathComponent(fixture.denseTensor),
            expectedCount: fixture.denseShape.reduce(1, *)
        )
        let actual = try AnyUprightScaleLSDPostprocessor.decode(
            denseLogits: dense,
            shape: fixture.denseShape,
            imageWidth: fixture.imageWidth,
            imageHeight: fixture.imageHeight
        )
        guard actual.count == fixture.lines.count else {
            throw ScaleLSDPostprocessorTestFailure.failed("line count: expected \(fixture.lines.count), got \(actual.count)")
        }

        var maximumCoordinateDifference = 0.0
        for (index, pair) in zip(actual, fixture.lines).enumerated() {
            let differences = [
                abs(pair.0.start.x - pair.1.x1),
                abs(pair.0.start.y - pair.1.y1),
                abs(pair.0.end.x - pair.1.x2),
                abs(pair.0.end.y - pair.1.y2),
            ]
            maximumCoordinateDifference = max(maximumCoordinateDifference, differences.max() ?? 0)
            guard differences.allSatisfy({ $0 <= 1e-3 }) else {
                throw ScaleLSDPostprocessorTestFailure.failed("line \(index) coordinate mismatch: \(differences)")
            }
            guard pair.0.score == pair.1.score else {
                throw ScaleLSDPostprocessorTestFailure.failed("line \(index) score: expected \(pair.1.score), got \(pair.0.score)")
            }
        }

        var noJunctionLogits = [Float](repeating: 0, count: 9)
        noJunctionLogits[5] = 10
        noJunctionLogits[6] = -10
        let empty = try AnyUprightScaleLSDPostprocessor.decode(
            denseLogits: noJunctionLogits,
            shape: [1, 9, 1, 1],
            imageWidth: 1,
            imageHeight: 1
        )
        guard empty.isEmpty else {
            throw ScaleLSDPostprocessorTestFailure.failed("low-confidence fixture should produce no lines")
        }

        do {
            _ = try AnyUprightScaleLSDPostprocessor.decode(
                denseLogits: [],
                shape: [1, 9, 2, 2],
                imageWidth: 2,
                imageHeight: 2
            )
            throw ScaleLSDPostprocessorTestFailure.failed("invalid element count did not throw")
        } catch is AUScaleLSDPostprocessError {
            // Expected.
        }

        print("AnyUprightScaleLSDPostprocessorTests passed; lines=\(actual.count) maxCoordinateDiff=\(maximumCoordinateDifference)")
    }

    private static func verifySpatialSearchMatchesLinearReference() throws {
        let cases = [
            (width: 16, height: 16, seed: UInt64(0x1234), maximumJunctions: 64),
            (width: 24, height: 18, seed: UInt64(0xBEEF), maximumJunctions: 96),
            (width: 32, height: 24, seed: UInt64(0xC0FFEE), maximumJunctions: 128),
        ]

        for testCase in cases {
            let shape = [1, 9, testCase.height, testCase.width]
            let dense = deterministicDenseLogits(count: shape.reduce(1, *), seed: testCase.seed)
            var configuration = AUScaleLSDPostprocessConfiguration()
            configuration.maximumJunctions = testCase.maximumJunctions
            configuration.junctionHeatmapThreshold = 0.02
            configuration.lineSupportThreshold = 0

            let spatial = try AnyUprightScaleLSDPostprocessor.decode(
                denseLogits: dense,
                shape: shape,
                imageWidth: testCase.width * 2,
                imageHeight: testCase.height * 3,
                configuration: configuration,
                nearestJunctionSearch: .spatialGrid
            )
            let linear = try AnyUprightScaleLSDPostprocessor.decode(
                denseLogits: dense,
                shape: shape,
                imageWidth: testCase.width * 2,
                imageHeight: testCase.height * 3,
                configuration: configuration,
                nearestJunctionSearch: .linearReference
            )
            guard spatial == linear else {
                throw ScaleLSDPostprocessorTestFailure.failed(
                    "spatial search mismatch for \(testCase.width)x\(testCase.height) seed \(testCase.seed)"
                )
            }
        }

        let shape = [1, 9, 8, 8]
        let dense = deterministicDenseLogits(count: shape.reduce(1, *), seed: 0xFACE)
        var zeroThresholdConfiguration = AUScaleLSDPostprocessConfiguration()
        zeroThresholdConfiguration.junctionToLineSquaredDistanceThreshold = 0
        zeroThresholdConfiguration.lineSupportThreshold = 0
        let zeroThresholdSpatial = try AnyUprightScaleLSDPostprocessor.decode(
            denseLogits: dense,
            shape: shape,
            imageWidth: 8,
            imageHeight: 8,
            configuration: zeroThresholdConfiguration,
            nearestJunctionSearch: .spatialGrid
        )
        let zeroThresholdLinear = try AnyUprightScaleLSDPostprocessor.decode(
            denseLogits: dense,
            shape: shape,
            imageWidth: 8,
            imageHeight: 8,
            configuration: zeroThresholdConfiguration,
            nearestJunctionSearch: .linearReference
        )
        guard zeroThresholdSpatial == zeroThresholdLinear else {
            throw ScaleLSDPostprocessorTestFailure.failed("zero-distance threshold mismatch")
        }
    }

    private static func deterministicDenseLogits(count: Int, seed: UInt64) -> [Float] {
        var state = seed
        return (0..<count).map { _ in
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            let mantissa = UInt32(truncatingIfNeeded: state >> 40)
            let unit = Float(mantissa) / Float(0x00FF_FFFF)
            return unit * 8 - 4
        }
    }

    private static func readFloatTensor(_ url: URL, expectedCount: Int) throws -> [Float] {
        let data = try Data(contentsOf: url)
        let expectedBytes = expectedCount * MemoryLayout<Float>.stride
        guard data.count == expectedBytes else {
            throw ScaleLSDPostprocessorTestFailure.failed("\(url.lastPathComponent): expected \(expectedBytes) bytes, got \(data.count)")
        }
        var values = [Float](repeating: 0, count: expectedCount)
        _ = values.withUnsafeMutableBytes { destination in
            data.copyBytes(to: destination)
        }
        return values
    }
}
