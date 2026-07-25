//
//  AnyUprightGeoCalibCoreMLCacheTests.swift
//  AnyUprightTests
//

import Foundation

private enum CoreMLCacheTestFailure: Error, CustomStringConvertible {
    case failed(String)

    var description: String {
        switch self {
        case .failed(let message):
            return message
        }
    }
}

@main
struct AnyUprightGeoCalibCoreMLCacheTests {
    static func main() throws {
        try testBundledModelShapeSpecs()
        print("AnyUprightGeoCalibCoreMLCacheTests passed")
    }

    private static func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ label: String) throws {
        guard actual == expected else {
            throw CoreMLCacheTestFailure.failed("\(label): expected \(expected), got \(actual)")
        }
    }

    private static func testBundledModelShapeSpecs() throws {
        let repoPath = CommandLine.arguments.dropFirst().first ?? "/Users/ibobby/Projects/AnyUpright"
        let modelRoot = URL(fileURLWithPath: repoPath).appendingPathComponent("AnyUpright/Plugin/GeoCalibCoreML")
        let expectedModels: [(String, [Int])] = [
            ("neural_forward_320x416.mlmodelc", [1, 3, 320, 416]),
            ("neural_forward_416x320.mlmodelc", [1, 3, 416, 320]),
            ("neural_forward_320x544.mlmodelc", [1, 3, 320, 544]),
            ("neural_forward_544x320.mlmodelc", [1, 3, 544, 320]),
            ("neural_forward_320x320.mlmodelc", [1, 3, 320, 320]),
            ("neural_forward_320x480.mlmodelc", [1, 3, 320, 480]),
            ("neural_forward_480x320.mlmodelc", [1, 3, 480, 320]),
            ("neural_forward_320x736.mlmodelc", [1, 3, 320, 736]),
        ]

        for (modelName, expectedShape) in expectedModels {
            let session = try AUGeoCalibCoreMLNeuralInferenceSession(
                modelURL: modelRoot.appendingPathComponent(modelName, isDirectory: true)
            )
            try assertEqual(session.supportedInputShape, expectedShape, "\(modelName) input shape")
        }
    }
}
