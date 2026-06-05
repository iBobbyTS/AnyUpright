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
        try testQuadSourceModeCanPreviewHandlesBeforeApplyingWarp()
        try testHorizonFillScaleOnlyZoomsWhenNeeded()
        try testUprightVerticalAndHorizontalPerspectiveGenerateCenteredQuads()
        try testLineCandidateSelectionPrefersSmallestDeviation()
        try testHorizonCorrectionFromReferenceLine()
        try testRotationCorrectionFromVerticalReferenceLine()
        try testPerspectiveEstimatesRecoverSyntheticReferenceLines()
        try testDetectorFindsNearHorizontalAndVerticalLines()
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

    static func testQuadSourceModeCanPreviewHandlesBeforeApplyingWarp() throws {
        let size = AUSize(width: 200.0, height: 100.0)
        var offsets = AUCornerOffsets()
        offsets.topLeftPixels = AUPoint(x: 25.0, y: -10.0)
        offsets.topRightPixels = AUPoint(x: -15.0, y: -20.0)
        offsets.bottomRightPixels = AUPoint(x: -30.0, y: 15.0)
        offsets.bottomLeftPixels = AUPoint(x: 20.0, y: 25.0)

        let previewMatrix = AnyUprightGeometry.quadOutputToSourceMatrix(
            from: offsets,
            mode: .sourceQuad,
            applySourceQuad: false,
            outputSize: size,
            sourceSize: size
        )

        try assertMaps(previewMatrix, AUPoint(x: 30.0, y: 40.0), to: AUPoint(x: 30.0, y: 40.0))

        let sourceQuad = AnyUprightGeometry.quad(from: offsets, size: size)
        let appliedMatrix = AnyUprightGeometry.quadOutputToSourceMatrix(
            from: offsets,
            mode: .sourceQuad,
            applySourceQuad: true,
            outputSize: size,
            sourceSize: size
        )

        try assertMaps(appliedMatrix, AUPoint(x: 0.0, y: 0.0), to: sourceQuad.topLeft)
        try assertMaps(appliedMatrix, AUPoint(x: size.width, y: 0.0), to: sourceQuad.topRight)
        try assertMaps(appliedMatrix, AUPoint(x: size.width, y: size.height), to: sourceQuad.bottomRight)
        try assertMaps(appliedMatrix, AUPoint(x: 0.0, y: size.height), to: sourceQuad.bottomLeft)
    }

    static func testHorizonFillScaleOnlyZoomsWhenNeeded() throws {
        let size = AUSize(width: 1920.0, height: 1080.0)

        try assertApprox(AnyUprightGeometry.rotationScaleToFill(angleRadians: 0.0, size: size), 1.0, "zero-degree fill scale")
        try assertTrue(AnyUprightGeometry.rotationScaleToFill(angleRadians: Double.pi / 18.0, size: size) > 1.0, "nonzero rotation should zoom to fill")
    }

    static func testUprightVerticalAndHorizontalPerspectiveGenerateCenteredQuads() throws {
        let size = AUSize(width: 200.0, height: 100.0)

        let positiveVertical = AnyUprightGeometry.uprightQuad(vertical: 0.5, horizontal: 0.0, size: size)
        try assertEqual(positiveVertical.topLeft, AUPoint(x: 12.5, y: 0.0), "positive vertical top-left")
        try assertEqual(positiveVertical.topRight, AUPoint(x: 187.5, y: 0.0), "positive vertical top-right")
        try assertEqual(positiveVertical.bottomRight, AUPoint(x: 212.5, y: 100.0), "positive vertical bottom-right")
        try assertEqual(positiveVertical.bottomLeft, AUPoint(x: -12.5, y: 100.0), "positive vertical bottom-left")

        let negativeVertical = AnyUprightGeometry.uprightQuad(vertical: -0.5, horizontal: 0.0, size: size)
        try assertEqual(negativeVertical.topLeft, AUPoint(x: -12.5, y: 0.0), "negative vertical top-left")
        try assertEqual(negativeVertical.topRight, AUPoint(x: 212.5, y: 0.0), "negative vertical top-right")
        try assertEqual(negativeVertical.bottomRight, AUPoint(x: 187.5, y: 100.0), "negative vertical bottom-right")
        try assertEqual(negativeVertical.bottomLeft, AUPoint(x: 12.5, y: 100.0), "negative vertical bottom-left")

        let positiveHorizontal = AnyUprightGeometry.uprightQuad(vertical: 0.0, horizontal: 0.5, size: size)
        try assertEqual(positiveHorizontal.topLeft, AUPoint(x: 0.0, y: -12.5), "positive horizontal top-left")
        try assertEqual(positiveHorizontal.topRight, AUPoint(x: 200.0, y: 12.5), "positive horizontal top-right")
        try assertEqual(positiveHorizontal.bottomRight, AUPoint(x: 200.0, y: 87.5), "positive horizontal bottom-right")
        try assertEqual(positiveHorizontal.bottomLeft, AUPoint(x: 0.0, y: 112.5), "positive horizontal bottom-left")

        let negativeHorizontal = AnyUprightGeometry.uprightQuad(vertical: 0.0, horizontal: -0.5, size: size)
        try assertEqual(negativeHorizontal.topLeft, AUPoint(x: 0.0, y: 12.5), "negative horizontal top-left")
        try assertEqual(negativeHorizontal.topRight, AUPoint(x: 200.0, y: -12.5), "negative horizontal top-right")
        try assertEqual(negativeHorizontal.bottomRight, AUPoint(x: 200.0, y: 112.5), "negative horizontal bottom-right")
        try assertEqual(negativeHorizontal.bottomLeft, AUPoint(x: 0.0, y: 87.5), "negative horizontal bottom-left")
    }

    static func testLineCandidateSelectionPrefersSmallestDeviation() throws {
        let lines = [
            line(angleDegrees: 18.0, length: 180.0),
            line(angleDegrees: 2.0, length: 80.0),
            line(angleDegrees: 45.0, length: 300.0),
            line(angleDegrees: 88.0, length: 200.0)
        ]

        let horizontal = AnyUprightGeometry.lineCandidates(from: lines, orientation: .horizontal, minimumLength: 20.0)
        try assertEqual(horizontal.count, 2, "horizontal candidate count")
        try assertApprox(horizontal[0].absoluteDeviationRadians, degreesToRadians(2.0), "smallest horizontal deviation")
        try assertApprox(horizontal[1].absoluteDeviationRadians, degreesToRadians(18.0), "second horizontal deviation")

        let vertical = AnyUprightGeometry.bestReferenceLines(from: lines, orientation: .vertical, maximumCount: 1)
        try assertEqual(vertical.count, 1, "vertical reference count")
        try assertEqual(vertical[0].end, lines[3].end, "best vertical reference")
    }

    static func testHorizonCorrectionFromReferenceLine() throws {
        let correction = try unwrap(AnyUprightGeometry.horizonCorrectionRadians(from: [
            line(angleDegrees: 10.0, length: 200.0)
        ]), "horizon correction")

        try assertApprox(correction, degreesToRadians(-10.0), "horizon correction angle")
    }

    static func testRotationCorrectionFromVerticalReferenceLine() throws {
        let correction = try unwrap(AnyUprightGeometry.rotationCorrectionRadians(from: [
            line(angleDegrees: 80.0, length: 200.0)
        ], orientation: .vertical), "vertical rotation correction")

        try assertApprox(correction, degreesToRadians(10.0), "vertical correction angle")
    }

    static func testPerspectiveEstimatesRecoverSyntheticReferenceLines() throws {
        let size = AUSize(width: 200.0, height: 100.0)

        let expectedVertical = 0.4
        let verticalOutput = AULineSegment(
            start: AUPoint(x: 45.0, y: 10.0),
            end: AUPoint(x: 45.0, y: 90.0)
        )
        let verticalOutputToSource = AnyUprightGeometry.homography(
            from: AnyUprightGeometry.uprightQuad(vertical: expectedVertical, horizontal: 0.0, size: size),
            to: AUQuad.fullFrame(size)
        )
        let verticalSource = AnyUprightGeometry.transform(verticalOutput, by: verticalOutputToSource)
        let verticalEstimate = try unwrap(
            AnyUprightGeometry.estimateVerticalPerspective(from: [verticalSource], size: size),
            "vertical perspective estimate"
        )
        try assertApprox(verticalEstimate, expectedVertical, "vertical perspective estimate", accuracy: 0.02)

        let expectedHorizontal = -0.35
        let horizontalOutput = AULineSegment(
            start: AUPoint(x: 20.0, y: 35.0),
            end: AUPoint(x: 180.0, y: 35.0)
        )
        let horizontalOutputToSource = AnyUprightGeometry.homography(
            from: AnyUprightGeometry.uprightQuad(vertical: 0.0, horizontal: expectedHorizontal, size: size),
            to: AUQuad.fullFrame(size)
        )
        let horizontalSource = AnyUprightGeometry.transform(horizontalOutput, by: horizontalOutputToSource)
        let horizontalEstimate = try unwrap(
            AnyUprightGeometry.estimateHorizontalPerspective(from: [horizontalSource], size: size),
            "horizontal perspective estimate"
        )
        try assertApprox(horizontalEstimate, expectedHorizontal, "horizontal perspective estimate", accuracy: 0.02)
    }

    static func testDetectorFindsNearHorizontalAndVerticalLines() throws {
        let horizontalImage = slopedHorizontalEdgeImage(width: 120, height: 80)
        let horizontalLines = AnyUprightLineDetection.detectLineSegments(
            in: horizontalImage,
            options: AULineDetectionOptions(
                orientation: .horizontal,
                edgeThreshold: 20.0,
                voteThreshold: 25,
                maxLines: 5
            )
        )
        let horizontalCandidates = AnyUprightGeometry.lineCandidates(from: horizontalLines, orientation: .horizontal, minimumLength: 60.0)
        try assertTrue(!horizontalCandidates.isEmpty, "horizontal detector should find at least one candidate")
        try assertTrue(horizontalCandidates[0].absoluteDeviationRadians <= degreesToRadians(15.0), "detected horizontal angle should be a near-horizontal candidate")

        let verticalImage = slopedVerticalEdgeImage(width: 100, height: 120)
        let verticalLines = AnyUprightLineDetection.detectLineSegments(
            in: verticalImage,
            options: AULineDetectionOptions(
                orientation: .vertical,
                edgeThreshold: 20.0,
                voteThreshold: 25,
                maxLines: 5
            )
        )
        let verticalCandidates = AnyUprightGeometry.lineCandidates(from: verticalLines, orientation: .vertical, minimumLength: 60.0)
        try assertTrue(!verticalCandidates.isEmpty, "vertical detector should find at least one candidate")
        try assertTrue(verticalCandidates[0].absoluteDeviationRadians <= degreesToRadians(15.0), "detected vertical angle should be a near-vertical candidate")
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

    static func line(angleDegrees: Double, length: Double) -> AULineSegment {
        let radians = degreesToRadians(angleDegrees)
        return AULineSegment(
            start: AUPoint(x: 0.0, y: 0.0),
            end: AUPoint(x: cos(radians) * length, y: sin(radians) * length)
        )
    }

    static func degreesToRadians(_ degrees: Double) -> Double {
        degrees * .pi / 180.0
    }

    static func slopedHorizontalEdgeImage(width: Int, height: Int) -> AUGrayscaleImage {
        var image = AUGrayscaleImage(width: width, height: height, pixels: Array(repeating: 0, count: width * height))
        for y in 0..<height {
            for x in 0..<width {
                let boundary = 25.0 + tan(degreesToRadians(10.0)) * Double(x - 8)
                if Double(y) >= boundary {
                    image.pixels[y * width + x] = 255
                }
            }
        }
        return image
    }

    static func slopedVerticalEdgeImage(width: Int, height: Int) -> AUGrayscaleImage {
        var image = AUGrayscaleImage(width: width, height: height, pixels: Array(repeating: 0, count: width * height))
        for y in 0..<height {
            for x in 0..<width {
                let boundary = 56.0 + tan(degreesToRadians(7.0)) * Double(y - 8)
                if Double(x) >= boundary {
                    image.pixels[y * width + x] = 255
                }
            }
        }
        return image
    }

    static func unwrap<T>(_ value: T?, _ label: String) throws -> T {
        guard let value else {
            throw TestFailure.failed("\(label): expected value, got nil")
        }
        return value
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

    static func assertEqual(_ actual: Int, _ expected: Int, _ label: String) throws {
        guard actual == expected else {
            throw TestFailure.failed("\(label): expected \(expected), got \(actual)")
        }
    }
}
