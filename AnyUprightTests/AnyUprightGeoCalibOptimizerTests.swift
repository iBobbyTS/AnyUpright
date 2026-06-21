//
//  AnyUprightGeoCalibOptimizerTests.swift
//  AnyUprightTests
//

import Foundation

enum GeoCalibOptimizerTestFailure: Error, CustomStringConvertible {
    case failed(String)

    var description: String {
        switch self {
        case .failed(let message):
            return message
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

@main
struct AnyUprightGeoCalibOptimizerTests {
    static func main() throws {
        let defaultFixturePath = "/Users/ibobby/Temp/AnyUprightAlgorithmWorkDirectory/fixtures/geocalib_optimizer_3"
        let fixturePath = CommandLine.arguments.dropFirst().first ?? defaultFixturePath
        let fixtureURL = URL(fileURLWithPath: fixturePath)
        let manifestURL = fixtureURL.appendingPathComponent("manifest.json")
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw GeoCalibOptimizerTestFailure.failed("missing optimizer fixture manifest at \(manifestURL.path)")
        }

        let manifest = try JSONDecoder().decode(
            OptimizerFixtureManifest.self,
            from: Data(contentsOf: manifestURL)
        )

        for entry in manifest.entries {
            let fields = try loadFields(entry: entry, fixtureURL: fixtureURL)
            let result = try AUGeoCalibOptimizer.optimize(fields: fields)

            try assertApproxArray(
                result.cameraData,
                try readTensor(entry: entry, key: "camera_data", fixtureURL: fixtureURL).values,
                label: "\(entry.filename) camera_data",
                absTolerance: 2e-4,
                relativeTolerance: 1e-5,
                rmseTolerance: 5e-5
            )
            try assertApproxArray(
                result.gravityData,
                try readTensor(entry: entry, key: "gravity_data", fixtureURL: fixtureURL).values,
                label: "\(entry.filename) gravity_data",
                absTolerance: 1e-6,
                relativeTolerance: 1e-5,
                rmseTolerance: 1e-6
            )
            try assertApproxArray(
                [Float(result.stopAt)],
                try readTensor(entry: entry, key: "stop_at", fixtureURL: fixtureURL).values,
                label: "\(entry.filename) stop_at",
                absTolerance: 0,
                relativeTolerance: 0,
                rmseTolerance: 0
            )
            try assertScalar(
                result.finalCost,
                try readScalar(entry: entry, key: "final_cost", fixtureURL: fixtureURL),
                label: "\(entry.filename) final_cost",
                tolerance: 1e-10
            )
            try assertScalar(
                result.rollUncertaintyRadians,
                try readScalar(entry: entry, key: "roll_uncertainty", fixtureURL: fixtureURL),
                label: "\(entry.filename) roll_uncertainty",
                tolerance: 1e-8
            )
            try assertScalar(
                result.pitchUncertaintyRadians,
                try readScalar(entry: entry, key: "pitch_uncertainty", fixtureURL: fixtureURL),
                label: "\(entry.filename) pitch_uncertainty",
                tolerance: 1e-8
            )
            try assertScalar(
                result.verticalFOVUncertaintyRadians,
                try readScalar(entry: entry, key: "vfov_uncertainty", fixtureURL: fixtureURL),
                label: "\(entry.filename) vfov_uncertainty",
                tolerance: 1e-8
            )
            try assertApproxArray(
                result.covariance,
                try readTensor(entry: entry, key: "covariance", fixtureURL: fixtureURL).values,
                label: "\(entry.filename) covariance",
                absTolerance: 3e-3,
                relativeTolerance: 1e-5,
                rmseTolerance: 1e-3
            )
        }

        print("AnyUprightGeoCalibOptimizerTests passed")
    }

    private static func loadFields(entry: OptimizerFixtureEntry, fixtureURL: URL) throws -> AUGeoCalibDenseFields {
        let up = try readTensor(entry: entry, key: "up_field", fixtureURL: fixtureURL)
        let upConfidence = try readTensor(entry: entry, key: "up_confidence", fixtureURL: fixtureURL)
        let latitude = try readTensor(entry: entry, key: "latitude_field", fixtureURL: fixtureURL)
        let latitudeConfidence = try readTensor(entry: entry, key: "latitude_confidence", fixtureURL: fixtureURL)
        let scales = try readTensor(entry: entry, key: "scales", fixtureURL: fixtureURL)

        guard up.shape.count == 4, up.shape[0] == 1, up.shape[1] == 2 else {
            throw GeoCalibOptimizerTestFailure.failed("\(entry.filename) invalid up_field shape \(up.shape)")
        }
        guard scales.values.count == 2 else {
            throw GeoCalibOptimizerTestFailure.failed("\(entry.filename) invalid scales shape \(scales.shape)")
        }
        return AUGeoCalibDenseFields(
            width: up.shape[3],
            height: up.shape[2],
            upFieldNCHW: up.values,
            upConfidenceNCHW: upConfidence.values,
            latitudeFieldNCHW: latitude.values,
            latitudeConfidenceNCHW: latitudeConfidence.values,
            scales: SIMD2<Float>(scales.values[0], scales.values[1])
        )
    }

    private static func readScalar(entry: OptimizerFixtureEntry, key: String, fixtureURL: URL) throws -> Double {
        let tensor = try readTensor(entry: entry, key: key, fixtureURL: fixtureURL)
        guard tensor.values.count == 1 else {
            throw GeoCalibOptimizerTestFailure.failed("\(entry.filename) \(key) is not scalar")
        }
        return Double(tensor.values[0])
    }

    private static func readTensor(entry: OptimizerFixtureEntry, key: String, fixtureURL: URL) throws -> (values: [Float], shape: [Int]) {
        guard let name = entry.tensors[key],
              let shape = entry.shapes[key] else {
            throw GeoCalibOptimizerTestFailure.failed("\(entry.filename) missing tensor \(key)")
        }
        let expectedCount = shape.reduce(1, *)
        let url = fixtureURL.appendingPathComponent(name)
        let data = try Data(contentsOf: url)
        let expectedBytes = expectedCount * MemoryLayout<Float>.stride
        guard data.count == expectedBytes else {
            throw GeoCalibOptimizerTestFailure.failed("\(name) has \(data.count) bytes, expected \(expectedBytes)")
        }
        var values = [Float](repeating: 0, count: expectedCount)
        _ = values.withUnsafeMutableBytes { destination in
            data.copyBytes(to: destination)
        }
        return (values, shape)
    }

    private static func assertScalar(_ actual: Double, _ expected: Double, label: String, tolerance: Double) throws {
        guard abs(actual - expected) <= tolerance else {
            throw GeoCalibOptimizerTestFailure.failed("\(label): expected \(expected), got \(actual)")
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
            throw GeoCalibOptimizerTestFailure.failed("\(label): count mismatch \(actual.count) vs \(expected.count)")
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
            throw GeoCalibOptimizerTestFailure.failed(
                "\(label): maxAbs=\(maxAbs), maxRelative=\(maxRelative), rmse=\(rmse)"
            )
        }
    }
}
