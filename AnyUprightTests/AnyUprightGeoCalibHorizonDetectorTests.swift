//
//  AnyUprightGeoCalibHorizonDetectorTests.swift
//  AnyUprightTests
//

import Foundation
import CoreImage

private enum HorizonDetectorTestFailure: Error, CustomStringConvertible {
    case failed(String)

    var description: String {
        switch self {
        case .failed(let message):
            return message
        }
    }
}

@main
struct AnyUprightGeoCalibHorizonDetectorTests {
    static func main() throws {
        try testGatePolicy()
        try testVerifierRollSignMatchesGeoCalibConvention()
        try testDetectorMatchesPythonOptimizerFixture()
        print("AnyUprightGeoCalibHorizonDetectorTests passed")
    }

    private static func testGatePolicy() throws {
        let accepted = AUGeoCalibHorizonDetector.gate(
            rollRadians: degreesToRadians(4.0),
            rollUncertaintyRadians: degreesToRadians(3.0),
            verifierEstimates: [
                AUGeoCalibHorizonVerifierEstimate(name: "axis_hough", rollRadians: degreesToRadians(5.0), confidence: 1, sampleCount: 1),
                AUGeoCalibHorizonVerifierEstimate(name: "gradient_axis", rollRadians: nil, confidence: 0, sampleCount: 0),
            ]
        )
        try assertTrue(accepted.accepted, "uncertainty threshold should be inclusive and one verifier should not be required")

        let uncertain = AUGeoCalibHorizonDetector.gate(
            rollRadians: degreesToRadians(4.0),
            rollUncertaintyRadians: degreesToRadians(3.01),
            verifierEstimates: []
        )
        try assertFalse(uncertain.accepted, "uncertainty above 3 deg should reject")
        try assertTrue(uncertain.reasons.contains("roll_uncertainty_gt_3deg"), "uncertainty reason")

        let twoDisagreements = AUGeoCalibHorizonDetector.gate(
            rollRadians: degreesToRadians(1.0),
            rollUncertaintyRadians: degreesToRadians(0.5),
            verifierEstimates: [
                AUGeoCalibHorizonVerifierEstimate(name: "axis_hough", rollRadians: degreesToRadians(14.0), confidence: 1, sampleCount: 1),
                AUGeoCalibHorizonVerifierEstimate(name: "axis_lsd", rollRadians: degreesToRadians(-15.0), confidence: 1, sampleCount: 1),
                AUGeoCalibHorizonVerifierEstimate(name: "gradient_axis", rollRadians: degreesToRadians(2.0), confidence: 1, sampleCount: 1),
            ]
        )
        try assertFalse(twoDisagreements.accepted, "two verifier disagreements should reject")
        try assertTrue(twoDisagreements.reasons.contains("two_verifier_disagreements_gt_10deg"), "verifier reason")

        let productCap = AUGeoCalibHorizonDetector.gate(
            rollRadians: degreesToRadians(-46.0),
            rollUncertaintyRadians: degreesToRadians(0.5),
            verifierEstimates: []
        )
        try assertFalse(productCap.accepted, "correction over 45 deg should reject")
        try assertTrue(productCap.reasons.contains("correction_gt_45deg"), "product cap reason")
    }

    private static func testVerifierRollSignMatchesGeoCalibConvention() throws {
        let imagePath = CommandLine.arguments.dropFirst().dropFirst().dropFirst().dropFirst().dropFirst().dropFirst().first ??
            "/Users/ibobby/Temp/AnyUprightAlgorithmWorkDirectory/data/lamar2k/images/257834199224.jpg"
        let image = try loadGrayscaleImage(URL(fileURLWithPath: imagePath), maxDimension: 640)
        let expectedRoll = degreesToRadians(13.884569908021062)
        let axisHough = AUGeoCalibHorizonVerifiers.axisHough(in: image)
        let gradientAxis = AUGeoCalibHorizonVerifiers.gradientAxis(in: image)

        try assertVerifierClose(axisHough, expectedRoll: expectedRoll, maxDifferenceDegrees: 10.0)
        try assertVerifierClose(gradientAxis, expectedRoll: expectedRoll, maxDifferenceDegrees: 10.0)
    }

    private static func testDetectorMatchesPythonOptimizerFixture() throws {
        let neuralFixturePath = CommandLine.arguments.dropFirst().first ??
            "/Users/ibobby/Temp/AnyUprightAlgorithmWorkDirectory/fixtures/geocalib_neural_forward_3"
        let optimizerFixturePath = CommandLine.arguments.dropFirst().dropFirst().first ??
            "/Users/ibobby/Temp/AnyUprightAlgorithmWorkDirectory/fixtures/geocalib_optimizer_3"
        let runtimeBundlePath = CommandLine.arguments.dropFirst().dropFirst().dropFirst().first ??
            "AnyUpright/Plugin/GeoCalibRuntime"
        let metalSourcePath = CommandLine.arguments.dropFirst().dropFirst().dropFirst().dropFirst().first ??
            "AnyUpright/Plugin/AnyUprightGeoCalib.metal"
        let metalLibraryPath = CommandLine.arguments.dropFirst().dropFirst().dropFirst().dropFirst().dropFirst().first

        let neuralFixtureURL = URL(fileURLWithPath: neuralFixturePath)
        let optimizerFixtureURL = URL(fileURLWithPath: optimizerFixturePath)
        let runtimeBundle = try AUGeoCalibRuntimeBundle(rootURL: URL(fileURLWithPath: runtimeBundlePath))
        let metalSource = URL(fileURLWithPath: metalSourcePath)
        let shouldRunMetalSource = metalSourcePath != "-"
        let neuralManifest = try JSONDecoder().decode(
            Manifest.self,
            from: Data(contentsOf: neuralFixtureURL.appendingPathComponent("manifest.json"))
        )
        let optimizerManifest = try JSONDecoder().decode(
            HorizonOptimizerFixtureManifest.self,
            from: Data(contentsOf: optimizerFixtureURL.appendingPathComponent("manifest.json"))
        )
        let optimizerEntries = Dictionary(uniqueKeysWithValues: optimizerManifest.entries.map { ($0.filename, $0) })

        for (entryIndex, entry) in neuralManifest.entries.enumerated() {
            guard let optimizerEntry = optimizerEntries[entry.filename] else {
                throw HorizonDetectorTestFailure.failed("missing optimizer fixture for \(entry.filename)")
            }
            let input = try readEntryTensor(entry, key: "input_rgb", fixtures: neuralFixtureURL)
            let scales = try readOptimizerTensor(entry: optimizerEntry, key: "scales", fixtureURL: optimizerFixtureURL)
            let preprocessed = AUGeoCalibPreprocessedImage(
                inputRGBNCHW: input.values,
                inputShape: input.shape,
                scales: SIMD2<Float>(scales.values[0], scales.values[1])
            )
            if shouldRunMetalSource {
                let result = try AUGeoCalibHorizonDetector.detect(
                    preprocessedImage: preprocessed,
                    runtimeBundle: runtimeBundle,
                    metalSource: metalSource,
                    verifierEstimates: []
                )
                try assertDetectorResult(
                    result,
                    optimizerEntry: optimizerEntry,
                    labelPrefix: entry.filename
                )
            }

            if (entryIndex == 0 || !shouldRunMetalSource), let metalLibraryPath {
                let libraryResult = try AUGeoCalibHorizonDetector.detect(
                    preprocessedImage: preprocessed,
                    runtimeBundle: runtimeBundle,
                    metalLibraryURL: URL(fileURLWithPath: metalLibraryPath),
                    verifierEstimates: []
                )
                try assertDetectorResult(
                    libraryResult,
                    optimizerEntry: optimizerEntry,
                    labelPrefix: "\(entry.filename) metallib"
                )
            }
        }
    }

    private static func assertDetectorResult(
        _ result: AUGeoCalibHorizonDetectionResult,
        optimizerEntry: HorizonOptimizerFixtureEntry,
        labelPrefix: String
    ) throws {
        try assertApprox(
            result.rollRadians,
            degreesToRadians(optimizerEntry.predRollDegrees),
            "\(labelPrefix) roll",
            tolerance: 1e-6
        )
        try assertApprox(
            result.correctionRadians,
            -degreesToRadians(optimizerEntry.predRollDegrees),
            "\(labelPrefix) correction sign",
            tolerance: 1e-6
        )
        try assertApprox(
            result.rollUncertaintyRadians,
            degreesToRadians(optimizerEntry.rollUncertaintyDegrees),
            "\(labelPrefix) roll uncertainty",
            tolerance: 1e-8
        )
        try assertTrue(result.accepted, "\(labelPrefix) should pass uncertainty-only gate in fixture")
    }

    private static func readOptimizerTensor(
        entry: HorizonOptimizerFixtureEntry,
        key: String,
        fixtureURL: URL
    ) throws -> (values: [Float], shape: [Int]) {
        guard let name = entry.tensors[key],
              let shape = entry.shapes[key] else {
            throw HorizonDetectorTestFailure.failed("\(entry.filename) missing optimizer tensor \(key)")
        }
        let data = try Data(contentsOf: fixtureURL.appendingPathComponent(name))
        let expectedBytes = shape.reduce(1, *) * MemoryLayout<Float>.stride
        guard data.count == expectedBytes else {
            throw HorizonDetectorTestFailure.failed("\(name) has \(data.count) bytes, expected \(expectedBytes)")
        }
        var values = [Float](repeating: 0, count: expectedBytes / MemoryLayout<Float>.stride)
        _ = values.withUnsafeMutableBytes { data.copyBytes(to: $0) }
        return (values, shape)
    }

    private static func assertApprox(_ actual: Double, _ expected: Double, _ label: String, tolerance: Double) throws {
        guard abs(actual - expected) <= tolerance else {
            throw HorizonDetectorTestFailure.failed("\(label): expected \(expected), got \(actual)")
        }
    }

    private static func assertVerifierClose(
        _ estimate: AUGeoCalibHorizonVerifierEstimate,
        expectedRoll: Double,
        maxDifferenceDegrees: Double
    ) throws {
        guard let roll = estimate.rollRadians else {
            throw HorizonDetectorTestFailure.failed("\(estimate.name) did not produce a roll estimate")
        }
        let difference = abs(wrapRadiansForTest(roll - expectedRoll)) * 180.0 / Double.pi
        guard difference <= maxDifferenceDegrees else {
            throw HorizonDetectorTestFailure.failed("\(estimate.name) roll sign/convention mismatch: diff \(difference) deg")
        }
    }

    private static func loadGrayscaleImage(_ url: URL, maxDimension: Int) throws -> AUGrayscaleImage {
        guard let sourceImage = CIImage(contentsOf: url) else {
            throw HorizonDetectorTestFailure.failed("could not load verifier image \(url.path)")
        }

        let sourceWidth = max(1, Int(sourceImage.extent.width.rounded()))
        let sourceHeight = max(1, Int(sourceImage.extent.height.rounded()))
        let scale = min(1.0, Double(maxDimension) / Double(max(sourceWidth, sourceHeight)))
        let width = max(1, Int(round(Double(sourceWidth) * scale)))
        let height = max(1, Int(round(Double(sourceHeight) * scale)))
        let image = sourceImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        var rgba = Array(repeating: UInt8(0), count: width * height * 4)

        CIContext(options: nil).render(
            image,
            toBitmap: &rgba,
            rowBytes: width * 4,
            bounds: CGRect(x: 0, y: 0, width: width, height: height),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )

        var gray = Array(repeating: UInt8(0), count: width * height)
        for index in 0..<(width * height) {
            let base = index * 4
            let red = Double(rgba[base])
            let green = Double(rgba[base + 1])
            let blue = Double(rgba[base + 2])
            gray[index] = UInt8(min(255.0, max(0.0, red * 0.299 + green * 0.587 + blue * 0.114)))
        }
        return AUGrayscaleImage(width: width, height: height, pixels: gray)
    }

    private static func wrapRadiansForTest(_ angle: Double) -> Double {
        var wrapped = (angle + Double.pi).truncatingRemainder(dividingBy: 2.0 * Double.pi)
        if wrapped < 0 {
            wrapped += 2.0 * Double.pi
        }
        return wrapped - Double.pi
    }

    private static func assertTrue(_ condition: Bool, _ label: String) throws {
        guard condition else {
            throw HorizonDetectorTestFailure.failed(label)
        }
    }

    private static func assertFalse(_ condition: Bool, _ label: String) throws {
        guard !condition else {
            throw HorizonDetectorTestFailure.failed(label)
        }
    }

    private static func degreesToRadians(_ degrees: Double) -> Double {
        degrees * .pi / 180.0
    }
}

private struct HorizonOptimizerFixtureManifest: Decodable {
    let entries: [HorizonOptimizerFixtureEntry]
}

private struct HorizonOptimizerFixtureEntry: Decodable {
    let filename: String
    let predRollDegrees: Double
    let rollUncertaintyDegrees: Double
    let tensors: [String: String]
    let shapes: [String: [Int]]

    enum CodingKeys: String, CodingKey {
        case filename = "fname"
        case predRollDegrees = "pred_roll_deg"
        case rollUncertaintyDegrees = "roll_uncertainty_deg"
        case tensors
        case shapes
    }
}
