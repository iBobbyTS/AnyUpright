//
//  AnyUprightGeoCalibEndToEndTests.swift
//  AnyUprightTests
//

import Foundation

enum GeoCalibEndToEndTestFailure: Error, CustomStringConvertible {
    case failed(String)

    var description: String {
        switch self {
        case .failed(let message):
            return message
        }
    }
}

@main
struct AnyUprightGeoCalibEndToEndTests {
    static func main() throws {
        let neuralFixturePath = CommandLine.arguments.dropFirst().first ?? "/Users/ibobby/Temp/AnyUprightAlgorithmWorkDirectory/fixtures/geocalib_neural_forward_3"
        let optimizerFixturePath = CommandLine.arguments.dropFirst().dropFirst().first ?? "/Users/ibobby/Temp/AnyUprightAlgorithmWorkDirectory/fixtures/geocalib_optimizer_3"
        let runtimeBundlePath = CommandLine.arguments.dropFirst().dropFirst().dropFirst().first ?? "AnyUpright/Plugin/GeoCalibRuntime"
        let metalSourcePath = CommandLine.arguments.dropFirst().dropFirst().dropFirst().dropFirst().first ?? "AnyUpright/Plugin/AnyUprightGeoCalib.metal"

        let neuralFixtureURL = URL(fileURLWithPath: neuralFixturePath)
        let optimizerFixtureURL = URL(fileURLWithPath: optimizerFixturePath)
        let runtimeBundle = try AUGeoCalibRuntimeBundle(rootURL: URL(fileURLWithPath: runtimeBundlePath))
        let metalSource = URL(fileURLWithPath: metalSourcePath)
        let neuralManifest = try JSONDecoder().decode(
            Manifest.self,
            from: Data(contentsOf: neuralFixtureURL.appendingPathComponent("manifest.json"))
        )
        let optimizerManifest = try JSONDecoder().decode(
            OptimizerFixtureManifest.self,
            from: Data(contentsOf: optimizerFixtureURL.appendingPathComponent("manifest.json"))
        )
        let optimizerEntries = Dictionary(uniqueKeysWithValues: optimizerManifest.entries.map { ($0.filename, $0) })

        for entry in neuralManifest.entries {
            guard let optimizerEntry = optimizerEntries[entry.filename] else {
                throw GeoCalibEndToEndTestFailure.failed("missing optimizer fixture for \(entry.filename)")
            }

            let input = try readEntryTensor(entry, key: "input_rgb", fixtures: neuralFixtureURL)
            let output = try AUGeoCalibNeuralInference.run(
                inputRGB: input.values,
                inputShape: input.shape,
                runtimeBundle: runtimeBundle,
                metalSource: metalSource
            )
            guard output.fieldShape.count == 4,
                  output.fieldShape[0] == 1,
                  output.fieldShape[1] == 2,
                  output.confidenceShape == [1, 1, output.fieldShape[2], output.fieldShape[3]] else {
                throw GeoCalibEndToEndTestFailure.failed("\(entry.filename) invalid neural output shapes")
            }

            let scales = try readOptimizerTensor(entry: optimizerEntry, key: "scales", fixtureURL: optimizerFixtureURL)
            let fields = AUGeoCalibDenseFields(
                width: output.fieldShape[3],
                height: output.fieldShape[2],
                upFieldNCHW: output.upField,
                upConfidenceNCHW: output.upConfidence,
                latitudeFieldNCHW: output.latitudeField,
                latitudeConfidenceNCHW: output.latitudeConfidence,
                scales: SIMD2<Float>(scales.values[0], scales.values[1])
            )
            let result = try AUGeoCalibOptimizer.optimize(fields: fields)

            try assertApproxArray(
                result.cameraData,
                try readOptimizerTensor(entry: optimizerEntry, key: "camera_data", fixtureURL: optimizerFixtureURL).values,
                label: "\(entry.filename) camera_data",
                absTolerance: 2e-4,
                relativeTolerance: 1e-5,
                rmseTolerance: 5e-5
            )
            try assertApproxArray(
                result.gravityData,
                try readOptimizerTensor(entry: optimizerEntry, key: "gravity_data", fixtureURL: optimizerFixtureURL).values,
                label: "\(entry.filename) gravity_data",
                absTolerance: 1e-6,
                relativeTolerance: 1e-5,
                rmseTolerance: 1e-6
            )
            try assertScalar(
                result.rollUncertaintyRadians,
                try readOptimizerScalar(entry: optimizerEntry, key: "roll_uncertainty", fixtureURL: optimizerFixtureURL),
                label: "\(entry.filename) roll_uncertainty",
                tolerance: 1e-8
            )
            try assertScalar(
                result.verticalFOVUncertaintyRadians,
                try readOptimizerScalar(entry: optimizerEntry, key: "vfov_uncertainty", fixtureURL: optimizerFixtureURL),
                label: "\(entry.filename) vfov_uncertainty",
                tolerance: 1e-8
            )
        }

        print("AnyUprightGeoCalibEndToEndTests passed")
    }

    private static func readOptimizerScalar(entry: OptimizerFixtureEntry, key: String, fixtureURL: URL) throws -> Double {
        let tensor = try readOptimizerTensor(entry: entry, key: key, fixtureURL: fixtureURL)
        guard tensor.values.count == 1 else {
            throw GeoCalibEndToEndTestFailure.failed("\(entry.filename) \(key) is not scalar")
        }
        return Double(tensor.values[0])
    }

    private static func readOptimizerTensor(entry: OptimizerFixtureEntry, key: String, fixtureURL: URL) throws -> (values: [Float], shape: [Int]) {
        guard let name = entry.tensors[key],
              let shape = entry.shapes[key] else {
            throw GeoCalibEndToEndTestFailure.failed("\(entry.filename) missing optimizer tensor \(key)")
        }
        let data = try Data(contentsOf: fixtureURL.appendingPathComponent(name))
        let expectedBytes = shape.reduce(1, *) * MemoryLayout<Float>.stride
        guard data.count == expectedBytes else {
            throw GeoCalibEndToEndTestFailure.failed("\(name) has \(data.count) bytes, expected \(expectedBytes)")
        }
        var values = [Float](repeating: 0, count: expectedBytes / MemoryLayout<Float>.stride)
        _ = values.withUnsafeMutableBytes { destination in
            data.copyBytes(to: destination)
        }
        return (values, shape)
    }

    private static func assertScalar(_ actual: Double, _ expected: Double, label: String, tolerance: Double) throws {
        guard abs(actual - expected) <= tolerance else {
            throw GeoCalibEndToEndTestFailure.failed("\(label): expected \(expected), got \(actual)")
        }
    }

    private static func assertApproxArray(
        _ actual: [Float],
        _ expected: [Float],
        label: String,
        absTolerance: Float,
        relativeTolerance: Float,
        rmseTolerance: Float
    ) throws {
        guard actual.count == expected.count else {
            throw GeoCalibEndToEndTestFailure.failed("\(label): count mismatch \(actual.count) vs \(expected.count)")
        }
        var maxAbs: Float = 0
        var maxRelative: Float = 0
        var squared = 0.0
        for index in actual.indices {
            let diff = abs(actual[index] - expected[index])
            maxAbs = max(maxAbs, diff)
            maxRelative = max(maxRelative, diff / max(1, abs(expected[index])))
            squared += Double(diff * diff)
        }
        let rmse = Float(sqrt(squared / Double(max(1, actual.count))))
        guard maxAbs <= absTolerance,
              maxRelative <= relativeTolerance,
              rmse <= rmseTolerance else {
            throw GeoCalibEndToEndTestFailure.failed(
                "\(label): maxAbs=\(maxAbs), maxRelative=\(maxRelative), rmse=\(rmse)"
            )
        }
    }
}

private struct OptimizerFixtureManifest: Decodable {
    let entries: [OptimizerFixtureEntry]
}

private struct OptimizerFixtureEntry: Decodable {
    let filename: String
    let tensors: [String: String]
    let shapes: [String: [Int]]

    enum CodingKeys: String, CodingKey {
        case filename = "fname"
        case tensors
        case shapes
    }
}
