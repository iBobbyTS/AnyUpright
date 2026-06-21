//
//  AnyUprightGeoCalibRuntimeBundleTests.swift
//  AnyUprightTests
//

import Foundation

enum GeoCalibRuntimeBundleTestFailure: Error, CustomStringConvertible {
    case failed(String)

    var description: String {
        switch self {
        case .failed(let message):
            return message
        }
    }
}

@main
struct AnyUprightGeoCalibRuntimeBundleTests {
    static func main() throws {
        let defaultBundlePath = "AnyUpright/Plugin/GeoCalibRuntime"
        let bundlePath = CommandLine.arguments.dropFirst().first ?? defaultBundlePath
        let bundle = try AUGeoCalibRuntimeBundle(rootURL: URL(fileURLWithPath: bundlePath))

        guard bundle.manifest.runtimeFileCount == 754 else {
            throw GeoCalibRuntimeBundleTestFailure.failed("expected 754 runtime tensors, got \(bundle.manifest.runtimeFileCount)")
        }
        guard bundle.runtimeTensorPaths.count == 754 else {
            throw GeoCalibRuntimeBundleTestFailure.failed("expected 754 referenced tensor paths, got \(bundle.runtimeTensorPaths.count)")
        }
        guard bundle.manifest.neuralForward.upHead.head == "up" else {
            throw GeoCalibRuntimeBundleTestFailure.failed("expected up head manifest")
        }
        guard bundle.manifest.neuralForward.latitudeHead.head == "latitude" else {
            throw GeoCalibRuntimeBundleTestFailure.failed("expected latitude head manifest")
        }

        let byteCount = try bundle.validateRuntimeTensors(readContents: true)
        guard byteCount == 115_965_716 else {
            throw GeoCalibRuntimeBundleTestFailure.failed("expected 115965716 runtime bytes, got \(byteCount)")
        }

        let manifestData = try Data(contentsOf: URL(fileURLWithPath: bundlePath).appendingPathComponent("manifest.json"))
        if let manifestJSON = try JSONSerialization.jsonObject(with: manifestData) as? [String: Any],
           manifestJSON["entries"] != nil {
            throw GeoCalibRuntimeBundleTestFailure.failed("runtime manifest must not contain fixture entries")
        }

        print("AnyUprightGeoCalibRuntimeBundleTests passed")
    }
}
