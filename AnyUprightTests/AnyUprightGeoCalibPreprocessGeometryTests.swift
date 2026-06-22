//
//  AnyUprightGeoCalibPreprocessGeometryTests.swift
//  AnyUprightTests
//

import Foundation

private enum PreprocessGeometryTestFailure: Error, CustomStringConvertible {
    case failed(String)

    var description: String {
        switch self {
        case .failed(let message):
            return message
        }
    }
}

@main
enum AnyUprightGeoCalibPreprocessGeometryTests {
    static func main() throws {
        try testLaMARLandscapeShape()
        try testLaMARPortraitShape()
        try testSixteenByNineShape()
        try testClosestShapeSelection()
        try testFixedTwoPointThreeFiveCrop()
        try testInvalidDimensions()
        print("AnyUprightGeoCalibPreprocessGeometryTests passed")
    }

    private static func testLaMARLandscapeShape() throws {
        let geometry = try AUGeoCalibPreprocessGeometry(sourceWidth: 1920, sourceHeight: 1440)
        try assertEqual(geometry.resizedWidth, 426, "landscape resized width")
        try assertEqual(geometry.resizedHeight, 320, "landscape resized height")
        try assertEqual(geometry.cropWidth, 416, "landscape crop width")
        try assertEqual(geometry.cropHeight, 320, "landscape crop height")
        try assertEqual(geometry.cropLeft, 5, "landscape crop left")
        try assertEqual(geometry.cropTop, 0, "landscape crop top")
        try assertEqual(geometry.inputShape, [1, 3, 320, 416], "landscape input shape")
        try assertApprox(Double(geometry.scales.x), 426.0 / 1920.0, "landscape x scale")
        try assertApprox(Double(geometry.scales.y), 320.0 / 1440.0, "landscape y scale")
        try assertEqual(geometry.kernelX.count, 7, "landscape kernelX size")
        try assertEqual(geometry.kernelY.count, 7, "landscape kernelY size")
        try assertKernelSumsToOne(geometry.kernelX, "landscape kernelX")
        try assertKernelSumsToOne(geometry.kernelY, "landscape kernelY")
    }

    private static func testLaMARPortraitShape() throws {
        let geometry = try AUGeoCalibPreprocessGeometry(sourceWidth: 1440, sourceHeight: 1920)
        try assertEqual(geometry.resizedWidth, 320, "portrait resized width")
        try assertEqual(geometry.resizedHeight, 426, "portrait resized height")
        try assertEqual(geometry.cropWidth, 320, "portrait crop width")
        try assertEqual(geometry.cropHeight, 416, "portrait crop height")
        try assertEqual(geometry.cropLeft, 0, "portrait crop left")
        try assertEqual(geometry.cropTop, 5, "portrait crop top")
        try assertEqual(geometry.inputShape, [1, 3, 416, 320], "portrait input shape")
    }

    private static func testSixteenByNineShape() throws {
        let shape = try AUGeoCalibInputShapeSpec.closest(toWidth: 3840, height: 2160)
        try assertEqual(shape.label, "16:9", "16:9 closest shape")
        let geometry = try AUGeoCalibPreprocessGeometry(
            sourceWidth: 3840,
            sourceHeight: 2160,
            targetInputShape: shape.inputShape
        )
        try assertEqual(geometry.resizedWidth, 568, "16:9 resized width")
        try assertEqual(geometry.resizedHeight, 320, "16:9 resized height")
        try assertEqual(geometry.cropWidth, 544, "16:9 crop width")
        try assertEqual(geometry.cropHeight, 320, "16:9 crop height")
        try assertEqual(geometry.cropLeft, 12, "16:9 crop left")
        try assertEqual(geometry.cropTop, 0, "16:9 crop top")
        try assertEqual(geometry.inputShape, [1, 3, 320, 544], "16:9 input shape")
    }

    private static func testClosestShapeSelection() throws {
        let wide = try AUGeoCalibInputShapeSpec.closest(toWidth: 2100, height: 1000)
        try assertEqual(wide.label, "2.35:1", "2.1:1 should select nearest wide model")

        let square = try AUGeoCalibInputShapeSpec.closest(toWidth: 1200, height: 1100)
        try assertEqual(square.label, "1:1", "near-square should select square model")
    }

    private static func testFixedTwoPointThreeFiveCrop() throws {
        let geometry = try AUGeoCalibPreprocessGeometry(
            sourceWidth: 2100,
            sourceHeight: 1000,
            targetInputShape: [1, 3, 320, 736]
        )
        try assertEqual(geometry.resizedWidth, 736, "2.35 resized width")
        try assertEqual(geometry.resizedHeight, 350, "2.35 resized height")
        try assertEqual(geometry.cropWidth, 736, "2.35 crop width")
        try assertEqual(geometry.cropHeight, 320, "2.35 crop height")
        try assertEqual(geometry.cropLeft, 0, "2.35 crop left")
        try assertEqual(geometry.cropTop, 15, "2.35 crop top")
        try assertEqual(geometry.inputShape, [1, 3, 320, 736], "2.35 input shape")
    }

    private static func testInvalidDimensions() throws {
        do {
            _ = try AUGeoCalibPreprocessGeometry(sourceWidth: 0, sourceHeight: 1080)
            throw PreprocessGeometryTestFailure.failed("zero width should fail")
        } catch AUGeoCalibPreprocessError.invalidImage {
            return
        }
    }

    private static func assertKernelSumsToOne(_ kernel: [Float], _ label: String) throws {
        try assertApprox(Double(kernel.reduce(0, +)), 1.0, "\(label) sum", accuracy: 1e-6)
    }

    private static func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ label: String) throws {
        guard actual == expected else {
            throw PreprocessGeometryTestFailure.failed("\(label): expected \(expected), got \(actual)")
        }
    }

    private static func assertApprox(_ actual: Double, _ expected: Double, _ label: String, accuracy: Double = 1e-7) throws {
        guard abs(actual - expected) <= accuracy else {
            throw PreprocessGeometryTestFailure.failed("\(label): expected \(expected), got \(actual)")
        }
    }
}
