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
        try testExpiryPolicyWindows()
        try testBundledModelShapeSpecs()
        print("AnyUprightGeoCalibCoreMLCacheTests passed")
    }

    private static func testExpiryPolicyWindows() throws {
        let second: UInt64 = 1_000_000_000
        var policy = AUGeoCalibCoreMLCacheExpiryPolicy()

        let pluginAddedDeadline = policy.markPluginAdded(at: 100 * second)
        try assertEqual(pluginAddedDeadline, 115 * second, "plugin add should schedule 15s unload")

        let firstAnalysis = policy.markAnalysisStarted(at: 110 * second)
        try assertEqual(firstAnalysis.analysisCountInWindow, 1, "first analysis count")
        try assertEqual(firstAnalysis.windowNanos, 30 * second, "first analysis window")
        try assertEqual(firstAnalysis.deadlineNanos, 140 * second, "first analysis should extend unload to 30s")

        let secondAnalysis = policy.markAnalysisStarted(at: 120 * second)
        try assertEqual(secondAnalysis.analysisCountInWindow, 2, "second analysis count")
        try assertEqual(secondAnalysis.windowNanos, 60 * second, "second analysis should promote to 60s")
        try assertEqual(secondAnalysis.deadlineNanos, 180 * second, "second analysis should extend unload to 60s")

        let laterPluginAdded = policy.markPluginAdded(at: 125 * second)
        try assertEqual(laterPluginAdded, 180 * second, "plugin add should not shorten a longer analysis window")

        let analysisAfterOriginalWindow = policy.markAnalysisStarted(at: 150 * second)
        try assertEqual(analysisAfterOriginalWindow.analysisCountInWindow, 1, "analysis after original 30s count window should reset")
        try assertEqual(analysisAfterOriginalWindow.windowNanos, 30 * second, "reset count window should use single-analysis retention")
        try assertEqual(analysisAfterOriginalWindow.deadlineNanos, 180 * second, "reset count window should not shorten existing 60s retention")

        policy.didUnload()
        let analysisAfterUnload = policy.markAnalysisStarted(at: 181 * second)
        try assertEqual(analysisAfterUnload.analysisCountInWindow, 1, "analysis after unload should start a fresh window")
        try assertEqual(analysisAfterUnload.windowNanos, 30 * second, "fresh analysis window after unload")
        try assertEqual(analysisAfterUnload.deadlineNanos, 211 * second, "fresh analysis should schedule 30s unload")
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
