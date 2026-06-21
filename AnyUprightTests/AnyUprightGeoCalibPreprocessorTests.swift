//
//  AnyUprightGeoCalibPreprocessorTests.swift
//  AnyUprightTests
//

import Foundation

private struct PreprocessorFixtureManifest: Decodable {
    let entries: [PreprocessorFixtureEntry]
}

private struct PreprocessorFixtureEntry: Decodable {
    let name: String
    let input: String
    let inputShape: [Int]
    let output: String
    let outputShape: [Int]
    let scales: String

    enum CodingKeys: String, CodingKey {
        case name
        case input
        case inputShape = "input_shape"
        case output
        case outputShape = "output_shape"
        case scales
    }
}

private enum PreprocessorTestFailure: Error, CustomStringConvertible {
    case failed(String)

    var description: String {
        switch self {
        case .failed(let message):
            return message
        }
    }
}

@main
struct AnyUprightGeoCalibPreprocessorTests {
    static func main() throws {
        let fixturePath = CommandLine.arguments.dropFirst().first ??
            "/Users/ibobby/Temp/AnyUprightAlgorithmWorkDirectory/fixtures/geocalib_preprocessor_synthetic"
        let fixtureURL = URL(fileURLWithPath: fixturePath)
        let manifest = try JSONDecoder().decode(
            PreprocessorFixtureManifest.self,
            from: Data(contentsOf: fixtureURL.appendingPathComponent("manifest.json"))
        )

        for entry in manifest.entries {
            guard entry.inputShape.count == 4,
                  entry.inputShape[0] == 1,
                  entry.inputShape[1] == 3 else {
                throw PreprocessorTestFailure.failed("\(entry.name) invalid input shape")
            }
            let input = try readFloatTensor(url: fixtureURL.appendingPathComponent(entry.input), shape: entry.inputShape)
            let expectedOutput = try readFloatTensor(url: fixtureURL.appendingPathComponent(entry.output), shape: entry.outputShape)
            let expectedScales = try readFloatTensor(url: fixtureURL.appendingPathComponent(entry.scales), shape: [2])

            let result = try AUGeoCalibImagePreprocessor.preprocessRGB(
                input,
                width: entry.inputShape[3],
                height: entry.inputShape[2]
            )

            try assertEqual(result.inputShape, entry.outputShape, "\(entry.name) output shape")
            try assertApproxArray(
                result.inputRGBNCHW,
                expectedOutput,
                label: "\(entry.name) output",
                absTolerance: 5e-5,
                rmseTolerance: 5e-6
            )
            try assertApproxArray(
                [result.scales.x, result.scales.y],
                expectedScales,
                label: "\(entry.name) scales",
                absTolerance: 1e-7,
                rmseTolerance: 1e-7
            )
        }

        print("AnyUprightGeoCalibPreprocessorTests passed")
    }

    private static func readFloatTensor(url: URL, shape: [Int]) throws -> [Float] {
        let data = try Data(contentsOf: url)
        let expectedCount = shape.reduce(1, *)
        let expectedBytes = expectedCount * MemoryLayout<Float>.stride
        guard data.count == expectedBytes else {
            throw PreprocessorTestFailure.failed("\(url.lastPathComponent) has \(data.count) bytes, expected \(expectedBytes)")
        }
        var values = [Float](repeating: 0, count: expectedCount)
        _ = values.withUnsafeMutableBytes { data.copyBytes(to: $0) }
        return values
    }

    private static func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ label: String) throws {
        guard actual == expected else {
            throw PreprocessorTestFailure.failed("\(label): expected \(expected), got \(actual)")
        }
    }

    private static func assertApproxArray(
        _ actual: [Float],
        _ expected: [Float],
        label: String,
        absTolerance: Float,
        rmseTolerance: Float
    ) throws {
        guard actual.count == expected.count else {
            throw PreprocessorTestFailure.failed("\(label): count mismatch \(actual.count) vs \(expected.count)")
        }
        var maxAbs: Float = 0
        var squared = 0.0
        for index in actual.indices {
            let diff = abs(actual[index] - expected[index])
            maxAbs = max(maxAbs, diff)
            squared += Double(diff * diff)
        }
        let rmse = Float(sqrt(squared / Double(max(1, actual.count))))
        guard maxAbs <= absTolerance, rmse <= rmseTolerance else {
            throw PreprocessorTestFailure.failed("\(label): maxAbs=\(maxAbs), rmse=\(rmse)")
        }
    }
}
