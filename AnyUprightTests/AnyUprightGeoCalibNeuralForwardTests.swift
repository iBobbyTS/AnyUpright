//
//  AnyUprightGeoCalibNeuralForwardTests.swift
//  AnyUprightTests
//

import Foundation

enum GeoCalibNeuralForwardTestFailure: Error, CustomStringConvertible {
    case failed(String)

    var description: String {
        switch self {
        case .failed(let message):
            return message
        }
    }
}

@main
struct AnyUprightGeoCalibNeuralForwardTests {
    static func main() throws {
        let defaultFixturePath = "/Users/ibobby/Temp/AnyUprightAlgorithmWorkDirectory/fixtures/geocalib_neural_forward_3"
        let fixturePath = CommandLine.arguments.dropFirst().first ?? defaultFixturePath
        let metalSourcePath = CommandLine.arguments.dropFirst().dropFirst().first ?? "AnyUpright/Plugin/AnyUprightGeoCalib.metal"
        let outputPath = CommandLine.arguments.dropFirst().dropFirst().dropFirst().first ?? "/tmp/AnyUprightGeoCalibNeuralForwardSummary.json"

        var options = Options()
        options.fixtures = URL(fileURLWithPath: fixturePath)
        options.metalSource = URL(fileURLWithPath: metalSourcePath)
        options.outputJSON = URL(fileURLWithPath: outputPath)
        options.absTolerance = 1e-4
        options.relativeTolerance = 1e-4
        options.rmseTolerance = 1e-5

        let summary = try verify(options: options)
        guard summary.fixtureCount == 3 else {
            throw GeoCalibNeuralForwardTestFailure.failed("expected 3 neural-forward fixtures, got \(summary.fixtureCount)")
        }
        guard summary.failedCount == 0 else {
            throw GeoCalibNeuralForwardTestFailure.failed("neural-forward verification failed: \(summary.failures)")
        }
        guard let upField = summary.stages["neural.up_field"],
              upField.maxAbsDifference <= 1e-5 else {
            throw GeoCalibNeuralForwardTestFailure.failed("missing or loose up_field verification")
        }
        guard let latitudeField = summary.stages["neural.latitude_field"],
              latitudeField.maxAbsDifference <= 1e-5 else {
            throw GeoCalibNeuralForwardTestFailure.failed("missing or loose latitude_field verification")
        }

        print("AnyUprightGeoCalibNeuralForwardTests passed")
    }
}
