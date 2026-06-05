//
//  AnyUprightGeometryTests.swift
//  AnyUprightTests
//

import Foundation
import simd

enum TestFailure: Error, CustomStringConvertible {
    case failed(String)

    var description: String {
        switch self {
        case .failed(let message):
            return message
        }
    }
}

@main
struct AnyUprightGeometryTests {
    static func main() throws {
        try testIdentityHomographyMapsPointsToThemselves()
        try testCornerOffsetsCombinePercentAndPixels()
        try testQuadOutputCornersKeepTheirNamedPositions()
        try testHorizonFillScaleOnlyZoomsWhenNeeded()
        try testUprightVerticalAndHorizontalPerspectiveGenerateExpectedCornerInsets()
        try testZeroRotationMatrixIsIdentity()
        print("AnyUprightGeometryTests passed")
    }

    static func testIdentityHomographyMapsPointsToThemselves() throws {
        let size = AUSize(width: 1920.0, height: 1080.0)
        let matrix = AnyUprightGeometry.homography(from: AUQuad.fullFrame(size), to: AUQuad.fullFrame(size))

        try assertMaps(matrix, AUPoint(x: 0.0, y: 0.0), to: AUPoint(x: 0.0, y: 0.0))
        try assertMaps(matrix, AUPoint(x: 1920.0, y: 0.0), to: AUPoint(x: 1920.0, y: 0.0))
        try assertMaps(matrix, AUPoint(x: 960.0, y: 540.0), to: AUPoint(x: 960.0, y: 540.0))
    }

    static func testCornerOffsetsCombinePercentAndPixels() throws {
        let size = AUSize(width: 200.0, height: 100.0)
        let offsets = AUCornerOffsets(
            topLeftPercent: AUPoint(x: 0.10, y: 0.20),
            topRightPercent: AUPoint(x: -0.10, y: 0.10),
            bottomRightPercent: AUPoint(x: 0.05, y: -0.10),
            bottomLeftPercent: AUPoint(x: -0.05, y: -0.20),
            topLeftPixels: AUPoint(x: 5.0, y: 10.0),
            topRightPixels: AUPoint(x: -5.0, y: 0.0),
            bottomRightPixels: AUPoint(x: 10.0, y: -5.0),
            bottomLeftPixels: AUPoint(x: -10.0, y: 5.0)
        )

        let quad = AnyUprightGeometry.quad(from: offsets, size: size)

        try assertEqual(quad.topLeft, AUPoint(x: 25.0, y: -30.0), "top-left offset")
        try assertEqual(quad.topRight, AUPoint(x: 175.0, y: -10.0), "top-right offset")
        try assertEqual(quad.bottomRight, AUPoint(x: 220.0, y: 115.0), "bottom-right offset")
        try assertEqual(quad.bottomLeft, AUPoint(x: -20.0, y: 115.0), "bottom-left offset")
    }

    static func testQuadOutputCornersKeepTheirNamedPositions() throws {
        let size = AUSize(width: 200.0, height: 100.0)
        var offsets = AUCornerOffsets()
        offsets.topLeftPixels = AUPoint(x: -20.0, y: 10.0)
        offsets.topRightPixels = AUPoint(x: 30.0, y: 15.0)
        offsets.bottomRightPixels = AUPoint(x: 40.0, y: -25.0)
        offsets.bottomLeftPixels = AUPoint(x: -50.0, y: -35.0)

        let outputQuad = AnyUprightGeometry.quad(from: offsets, size: size)
        let matrix = AnyUprightGeometry.homography(from: outputQuad, to: AUQuad.fullFrame(size))

        try assertEqual(outputQuad.topLeft, AUPoint(x: -20.0, y: -10.0), "top-left output corner")
        try assertEqual(outputQuad.topRight, AUPoint(x: 230.0, y: -15.0), "top-right output corner")
        try assertEqual(outputQuad.bottomRight, AUPoint(x: 240.0, y: 125.0), "bottom-right output corner")
        try assertEqual(outputQuad.bottomLeft, AUPoint(x: -50.0, y: 135.0), "bottom-left output corner")

        try assertMaps(matrix, outputQuad.topLeft, to: AUPoint(x: 0.0, y: 0.0))
        try assertMaps(matrix, outputQuad.topRight, to: AUPoint(x: size.width, y: 0.0))
        try assertMaps(matrix, outputQuad.bottomRight, to: AUPoint(x: size.width, y: size.height))
        try assertMaps(matrix, outputQuad.bottomLeft, to: AUPoint(x: 0.0, y: size.height))
    }

    static func testHorizonFillScaleOnlyZoomsWhenNeeded() throws {
        let size = AUSize(width: 1920.0, height: 1080.0)

        try assertApprox(AnyUprightGeometry.rotationScaleToFill(angleRadians: 0.0, size: size), 1.0, "zero-degree fill scale")
        try assertTrue(AnyUprightGeometry.rotationScaleToFill(angleRadians: Double.pi / 18.0, size: size) > 1.0, "nonzero rotation should zoom to fill")
    }

    static func testUprightVerticalAndHorizontalPerspectiveGenerateExpectedCornerInsets() throws {
        let size = AUSize(width: 200.0, height: 100.0)

        let vertical = AnyUprightGeometry.uprightQuad(vertical: 0.5, horizontal: 0.0, size: size)
        try assertTrue(vertical.topLeft.x > 0.0, "vertical positive should inset top-left")
        try assertTrue(vertical.topRight.x < size.width, "vertical positive should inset top-right")
        try assertApprox(vertical.bottomLeft.x, 0.0, "vertical positive should keep bottom-left")
        try assertApprox(vertical.bottomRight.x, size.width, "vertical positive should keep bottom-right")

        let horizontal = AnyUprightGeometry.uprightQuad(vertical: 0.0, horizontal: 0.5, size: size)
        try assertTrue(horizontal.topRight.y > 0.0, "horizontal positive should inset right top")
        try assertTrue(horizontal.bottomRight.y < size.height, "horizontal positive should inset right bottom")
        try assertApprox(horizontal.topLeft.y, 0.0, "horizontal positive should keep left top")
        try assertApprox(horizontal.bottomLeft.y, size.height, "horizontal positive should keep left bottom")
    }

    static func testZeroRotationMatrixIsIdentity() throws {
        let size = AUSize(width: 200.0, height: 100.0)
        let matrix = AnyUprightGeometry.rotationOutputToSource(angleRadians: 0.0, fillFrame: false, size: size)

        try assertMaps(matrix, AUPoint(x: 15.0, y: 25.0), to: AUPoint(x: 15.0, y: 25.0))
        try assertMaps(matrix, AUPoint(x: 200.0, y: 100.0), to: AUPoint(x: 200.0, y: 100.0))
    }

    static func assertMaps(_ matrix: simd_float3x3, _ point: AUPoint, to expected: AUPoint) throws {
        let mapped = matrix * SIMD3<Float>(Float(point.x), Float(point.y), 1.0)
        let x = Double(mapped.x / mapped.z)
        let y = Double(mapped.y / mapped.z)

        try assertApprox(x, expected.x, "mapped x for \(point)")
        try assertApprox(y, expected.y, "mapped y for \(point)")
    }

    static func assertEqual(_ actual: AUPoint, _ expected: AUPoint, _ label: String) throws {
        try assertApprox(actual.x, expected.x, "\(label) x")
        try assertApprox(actual.y, expected.y, "\(label) y")
    }

    static func assertApprox(_ actual: Double, _ expected: Double, _ label: String, accuracy: Double = 0.001) throws {
        guard abs(actual - expected) <= accuracy else {
            throw TestFailure.failed("\(label): expected \(expected), got \(actual)")
        }
    }

    static func assertTrue(_ condition: Bool, _ label: String) throws {
        guard condition else {
            throw TestFailure.failed(label)
        }
    }
}
