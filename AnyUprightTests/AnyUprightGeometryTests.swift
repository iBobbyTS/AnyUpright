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
        try testQuadObjectPointsKeepCanvasCornerDefinitions()
        try testQuadObjectDragPreservesPercentAndWritesPixelOffsets()
        try testQuadOutputCornersKeepTheirNamedPositions()
        try testQuadSourceDefaultsToCentralEightyPercent()
        try testQuadSourceObjectDragPreservesCentralBase()
        try testQuadSourceObjectSpacePixelsMatchFxPlugOSCEvents()
        try testQuadSourceRawCanvasDragFlipsObjectYBeforeWriting()
        try testQuadSourceRawCanvasHitPointsFollowVisibleSourceQuad()
        try testQuadSourceAdjusterPreviewAndApplyUseSameSelection()
        try testCanvasSurfaceMapperConvertsFxPlugOSCEvents()
        try testCanvasSurfaceMapperKeepsRawCanvasCandidatesDistinct()
        try testCanvasSurfaceMapperShowsFinalCutRawEventsCanLeaveFrame()
        try testOSCDragPartFallsBackToLocalHitWhenHostPartIsNone()
        try testQuadSourceModeShowsAdjusterBeforeApplyingWarp()
        try testQuadSourceMirrorModesSampleWithinSelectedQuad()
        try testHorizonFillScaleOnlyZoomsWhenNeeded()
        try testUprightVerticalAndHorizontalPerspectiveGenerateCenteredQuads()
        try testUprightPerspectiveKeepsFrameCenterAnchored()
        try testLineCandidateSelectionPrefersSmallestDeviation()
        try testLineCandidatesKeepAllNearAxisLinesForSemiAuto()
        try testLineCandidatesExcludeThirtyDegreeBoundary()
        try testHorizonCorrectionFromReferenceLine()
        try testDominantHorizonCorrectionPreservesDetectorRanking()
        try testRotationCorrectionFromVerticalReferenceLine()
        try testPerspectiveEstimatesRecoverSyntheticReferenceLines()
        try testDetectorFindsNearHorizontalAndVerticalLines()
        try testUprightCandidateSelectionLimitsToTwoAndConvertsCoordinates()
        try testUprightCandidateToggleSelectionStopsAtTwoPerOrientation()
        try testUprightCandidateObjectLineClampsAndFlipsY()
        try testUprightCandidateHitTestingUsesPixelDistance()
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

    static func testQuadObjectPointsKeepCanvasCornerDefinitions() throws {
        let size = AUSize(width: 200.0, height: 100.0)
        var offsets = AUCornerOffsets()
        offsets.topLeftPixels = AUPoint(x: -20.0, y: 30.0)
        offsets.topRightPixels = AUPoint(x: 10.0, y: 20.0)
        offsets.bottomRightPixels = AUPoint(x: 40.0, y: -15.0)
        offsets.bottomLeftPixels = AUPoint(x: -50.0, y: -25.0)

        let objectPoints = AnyUprightGeometry.quadObjectPoints(from: offsets, size: size)

        try assertEqual(objectPoints.topLeft, AUPoint(x: -0.10, y: 1.30), "object top-left")
        try assertEqual(objectPoints.topRight, AUPoint(x: 1.05, y: 1.20), "object top-right")
        try assertEqual(objectPoints.bottomRight, AUPoint(x: 1.20, y: -0.15), "object bottom-right")
        try assertEqual(objectPoints.bottomLeft, AUPoint(x: -0.25, y: -0.25), "object bottom-left")
        try assertTrue(objectPoints.topLeft.y > objectPoints.bottomLeft.y, "top-left handle should stay above bottom-left")
        try assertTrue(objectPoints.topLeft.x < objectPoints.topRight.x, "top-left handle should stay left of top-right")
    }

    static func testQuadObjectDragPreservesPercentAndWritesPixelOffsets() throws {
        let size = AUSize(width: 200.0, height: 100.0)
        var offsets = AUCornerOffsets()
        offsets.topLeftPercent = AUPoint(x: 0.10, y: -0.20)

        let pixels = AnyUprightGeometry.cornerPixelOffset(
            forObjectPoint: AUPoint(x: 0.35, y: 1.10),
            corner: .topLeft,
            offsets: offsets,
            size: size
        )
        offsets.topLeftPixels = pixels

        let objectPoints = AnyUprightGeometry.quadObjectPoints(from: offsets, size: size)
        let outputQuad = AnyUprightGeometry.quad(from: offsets, size: size)

        try assertEqual(pixels, AUPoint(x: 50.0, y: 30.0), "dragged top-left pixel offset")
        try assertEqual(objectPoints.topLeft, AUPoint(x: 0.35, y: 1.10), "dragged top-left object point")
        try assertEqual(outputQuad.topLeft, AUPoint(x: 70.0, y: -10.0), "dragged top-left output point")
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

    static func testQuadSourceDefaultsToCentralEightyPercent() throws {
        let size = AUSize(width: 200.0, height: 100.0)
        let offsets = AUCornerOffsets()
        let sourceQuad = AnyUprightGeometry.sourceQuad(from: offsets, size: size)
        let objectPoints = AnyUprightGeometry.sourceQuadObjectPoints(from: offsets, size: size)
        let appliedMatrix = AnyUprightGeometry.quadOutputToSourceMatrix(
            from: offsets,
            mode: .sourceQuad,
            showCornerAdjuster: false,
            outputSize: size,
            sourceSize: size
        )

        try assertEqual(sourceQuad.topLeft, AUPoint(x: 20.0, y: 10.0), "source default top-left")
        try assertEqual(sourceQuad.topRight, AUPoint(x: 180.0, y: 10.0), "source default top-right")
        try assertEqual(sourceQuad.bottomRight, AUPoint(x: 180.0, y: 90.0), "source default bottom-right")
        try assertEqual(sourceQuad.bottomLeft, AUPoint(x: 20.0, y: 90.0), "source default bottom-left")

        try assertEqual(objectPoints.topLeft, AUPoint(x: 0.10, y: 0.90), "source default object top-left")
        try assertEqual(objectPoints.topRight, AUPoint(x: 0.90, y: 0.90), "source default object top-right")
        try assertEqual(objectPoints.bottomRight, AUPoint(x: 0.90, y: 0.10), "source default object bottom-right")
        try assertEqual(objectPoints.bottomLeft, AUPoint(x: 0.10, y: 0.10), "source default object bottom-left")

        try assertMaps(appliedMatrix, AUPoint(x: 0.0, y: 0.0), to: sourceQuad.topLeft)
        try assertMaps(appliedMatrix, AUPoint(x: size.width, y: size.height), to: sourceQuad.bottomRight)
    }

    static func testQuadSourceObjectDragPreservesCentralBase() throws {
        let size = AUSize(width: 200.0, height: 100.0)
        var offsets = AUCornerOffsets()

        let percent = AnyUprightGeometry.sourceCornerPercentOffset(
            forObjectPoint: AUPoint(x: 0.20, y: 0.80),
            corner: .topLeft
        )
        offsets.topLeftPercent = percent

        let objectPoints = AnyUprightGeometry.sourceQuadObjectPoints(from: offsets, size: size)
        let sourceQuad = AnyUprightGeometry.sourceQuad(from: offsets, size: size)

        try assertEqual(percent, AUPoint(x: 0.10, y: -0.10), "source dragged top-left percent offset")
        try assertEqual(objectPoints.topLeft, AUPoint(x: 0.20, y: 0.80), "source dragged top-left object point")
        try assertEqual(sourceQuad.topLeft, AUPoint(x: 40.0, y: 20.0), "source dragged top-left source point")
    }

    static func testQuadSourceObjectSpacePixelsMatchFxPlugOSCEvents() throws {
        let size = AUSize(width: 200.0, height: 100.0)
        var offsets = AUCornerOffsets()
        let defaultObjectPoints = AnyUprightGeometry.sourceQuadObjectPoints(from: offsets, size: size)
        let defaultPixels = AnyUprightGeometry.objectPixelQuad(fromNormalizedObjectQuad: defaultObjectPoints, size: size)

        try assertEqual(defaultPixels.topLeft, AUPoint(x: 20.0, y: 90.0), "source object top-left pixel")
        try assertEqual(defaultPixels.topRight, AUPoint(x: 180.0, y: 90.0), "source object top-right pixel")
        try assertEqual(defaultPixels.bottomRight, AUPoint(x: 180.0, y: 10.0), "source object bottom-right pixel")
        try assertEqual(defaultPixels.bottomLeft, AUPoint(x: 20.0, y: 10.0), "source object bottom-left pixel")

        let draggedPixel = AUPoint(x: 45.0, y: 75.0)
        let draggedNormalized = AnyUprightGeometry.normalizedObjectPoint(fromObjectPixelPoint: draggedPixel, size: size)
        let percent = AnyUprightGeometry.sourceCornerPercentOffset(
            forObjectPoint: draggedNormalized,
            corner: .topLeft
        )

        offsets.topLeftPercent = percent
        let updatedObjectPixels = AnyUprightGeometry.objectPixelQuad(
            fromNormalizedObjectQuad: AnyUprightGeometry.sourceQuadObjectPoints(from: offsets, size: size),
            size: size
        )
        let updatedSourceQuad = AnyUprightGeometry.sourceQuad(from: offsets, size: size)
        try assertEqual(percent, AUPoint(x: 0.125, y: -0.15), "source object-space drag percent offset")
        try assertEqual(updatedObjectPixels.topLeft, draggedPixel, "source object-space drag target")
        try assertEqual(updatedSourceQuad.topLeft, AUPoint(x: 45.0, y: 25.0), "source quad should sample the Y-flipped image point matching the visible handle")
    }

    static func testQuadSourceRawCanvasDragFlipsObjectYBeforeWriting() throws {
        let size = AUSize(width: 200.0, height: 100.0)
        var offsets = AUCornerOffsets()
        let rawCanvasTopLeftObjectPoint = AUPoint(x: 0.225, y: 0.25)
        let correctedObjectPoint = AnyUprightGeometry.verticallyFlippedObjectPoint(rawCanvasTopLeftObjectPoint)
        let percent = AnyUprightGeometry.sourceCornerPercentOffset(
            forObjectPoint: correctedObjectPoint,
            corner: .topLeft
        )

        offsets.topLeftPercent = percent
        let sourceQuad = AnyUprightGeometry.sourceQuad(from: offsets, size: size)

        try assertEqual(correctedObjectPoint, AUPoint(x: 0.225, y: 0.75), "raw canvas source drag should flip object Y")
        try assertEqual(percent, AUPoint(x: 0.125, y: -0.15), "flipped raw canvas source percent")
        try assertEqual(sourceQuad.topLeft, AUPoint(x: 45.0, y: 25.0), "flipped raw canvas drag should update the visible top-left source point")
    }

    static func testQuadSourceRawCanvasHitPointsFollowVisibleSourceQuad() throws {
        let size = AUSize(width: 200.0, height: 100.0)
        var offsets = AUCornerOffsets()
        offsets.topLeftPercent = AUPoint(x: 0.125, y: -0.15)

        let objectPoints = AnyUprightGeometry.sourceQuadObjectPoints(from: offsets, size: size)
        let staleObjectPixels = AnyUprightGeometry.objectPixelQuad(fromNormalizedObjectQuad: objectPoints, size: size)
        let rawHitObjectPoints = AnyUprightGeometry.verticallyFlippedObjectQuad(objectPoints)
        let rawHitPixels = AnyUprightGeometry.objectPixelQuad(fromNormalizedObjectQuad: rawHitObjectPoints, size: size)
        let visibleSourceQuad = AnyUprightGeometry.sourceQuad(from: offsets, size: size)

        try assertEqual(visibleSourceQuad.topLeft, AUPoint(x: 45.0, y: 25.0), "visible moved source top-left")
        try assertEqual(staleObjectPixels.topLeft, AUPoint(x: 45.0, y: 75.0), "unflipped object-space hit point would stay at the stale invisible top-left")
        try assertEqual(rawHitPixels.topLeft, visibleSourceQuad.topLeft, "raw canvas hit point should follow moved visible top-left")
        try assertEqual(rawHitPixels.bottomLeft, visibleSourceQuad.bottomLeft, "raw canvas hit point should keep bottom-left aligned")
    }

    static func testQuadSourceAdjusterPreviewAndApplyUseSameSelection() throws {
        let outputSize = AUSize(width: 300.0, height: 150.0)
        let sourceSize = AUSize(width: 600.0, height: 300.0)
        var offsets = AUCornerOffsets()
        offsets.topLeftPercent = AUPoint(x: 0.10, y: -0.05)
        offsets.topRightPercent = AUPoint(x: -0.08, y: -0.02)
        offsets.bottomRightPercent = AUPoint(x: -0.12, y: 0.07)
        offsets.bottomLeftPercent = AUPoint(x: 0.04, y: 0.08)

        let selectedSourceQuad = AnyUprightGeometry.sourceQuad(from: offsets, size: sourceSize)
        let previewSelectionToRect = AnyUprightGeometry.quadSelectionToOutputRectMatrix(
            from: offsets,
            outputSize: outputSize,
            sourceSize: sourceSize
        )
        let appliedMatrix = AnyUprightGeometry.quadOutputToSourceMatrix(
            from: offsets,
            mode: .sourceQuad,
            showCornerAdjuster: false,
            outputSize: outputSize,
            sourceSize: sourceSize
        )

        let selectedOutputQuad = AUQuad(
            topLeft: AUPoint(x: selectedSourceQuad.topLeft.x / 2.0, y: selectedSourceQuad.topLeft.y / 2.0),
            topRight: AUPoint(x: selectedSourceQuad.topRight.x / 2.0, y: selectedSourceQuad.topRight.y / 2.0),
            bottomRight: AUPoint(x: selectedSourceQuad.bottomRight.x / 2.0, y: selectedSourceQuad.bottomRight.y / 2.0),
            bottomLeft: AUPoint(x: selectedSourceQuad.bottomLeft.x / 2.0, y: selectedSourceQuad.bottomLeft.y / 2.0)
        )

        try assertMaps(previewSelectionToRect, selectedOutputQuad.topLeft, to: AUPoint(x: 0.0, y: 0.0))
        try assertMaps(previewSelectionToRect, selectedOutputQuad.topRight, to: AUPoint(x: outputSize.width, y: 0.0))
        try assertMaps(previewSelectionToRect, selectedOutputQuad.bottomRight, to: AUPoint(x: outputSize.width, y: outputSize.height))
        try assertMaps(previewSelectionToRect, selectedOutputQuad.bottomLeft, to: AUPoint(x: 0.0, y: outputSize.height))

        try assertMaps(appliedMatrix, AUPoint(x: 0.0, y: 0.0), to: selectedSourceQuad.topLeft)
        try assertMaps(appliedMatrix, AUPoint(x: outputSize.width, y: 0.0), to: selectedSourceQuad.topRight)
        try assertMaps(appliedMatrix, AUPoint(x: outputSize.width, y: outputSize.height), to: selectedSourceQuad.bottomRight)
        try assertMaps(appliedMatrix, AUPoint(x: 0.0, y: outputSize.height), to: selectedSourceQuad.bottomLeft)
    }

    static func testCanvasSurfaceMapperConvertsFxPlugOSCEvents() throws {
        let canvasFrame = [
            AUPoint(x: 531.1, y: 791.2),
            AUPoint(x: 1811.1, y: 791.2),
            AUPoint(x: 1811.1, y: 71.2),
            AUPoint(x: 531.1, y: 71.2)
        ]
        let mapper = try unwrap(
            AUCanvasSurfaceMapper(canvasFrame: canvasFrame, surfaceSize: AUSize(width: 1670.0, height: 844.0)),
            "canvas mapper"
        )

        let canvasTopLeftHandle = AUPoint(x: 659.1, y: 719.2)
        let canvasBottomLeftHandle = AUPoint(x: 659.1, y: 143.2)
        let eventPoint = mapper.eventPoint(fromCanvasPoint: canvasTopLeftHandle)
        let bottomEventPoint = mapper.eventPoint(fromCanvasPoint: canvasBottomLeftHandle)
        let roundTrippedCanvas = mapper.canvasPoint(fromEventPoint: eventPoint)

        try assertApprox(eventPoint.x, 167.0, "top-left handle event x")
        try assertApprox(eventPoint.y, 84.4, "top-left handle event y")
        try assertApprox(bottomEventPoint.x, 167.0, "bottom-left handle event x")
        try assertApprox(bottomEventPoint.y, 759.6, "bottom-left handle event y")
        try assertTrue(eventPoint.y < bottomEventPoint.y, "surface-local mouse events should put visual top above visual bottom")
        try assertEqual(roundTrippedCanvas, canvasTopLeftHandle, "event point should map back to canvas point")
    }

    static func testCanvasSurfaceMapperKeepsRawCanvasCandidatesDistinct() throws {
        let canvasFrame = [
            AUPoint(x: 531.1, y: 791.2),
            AUPoint(x: 1811.1, y: 791.2),
            AUPoint(x: 1811.1, y: 71.2),
            AUPoint(x: 531.1, y: 71.2)
        ]
        let mapper = try unwrap(
            AUCanvasSurfaceMapper(canvasFrame: canvasFrame, surfaceSize: AUSize(width: 1670.0, height: 844.0)),
            "canvas mapper"
        )

        let finalCutCanvasEvent = AUPoint(x: 1811.1, y: 791.2)
        let motionSurfaceEvent = mapper.eventPoint(fromCanvasPoint: finalCutCanvasEvent)

        try assertEqual(finalCutCanvasEvent, AUPoint(x: 1811.1, y: 791.2), "raw FCP-style canvas event")
        try assertEqual(mapper.canvasPoint(fromEventPoint: motionSurfaceEvent), finalCutCanvasEvent, "mapped Motion-style event")
        try assertTrue(motionSurfaceEvent.x < finalCutCanvasEvent.x, "surface-local event should not be mistaken for raw canvas x")
        try assertTrue(motionSurfaceEvent.y < finalCutCanvasEvent.y, "surface-local event should not be mistaken for raw canvas y")
    }

    static func testCanvasSurfaceMapperShowsFinalCutRawEventsCanLeaveFrame() throws {
        let canvasFrame = [
            AUPoint(x: 531.1, y: 791.2),
            AUPoint(x: 1811.1, y: 791.2),
            AUPoint(x: 1811.1, y: 71.2),
            AUPoint(x: 531.1, y: 71.2)
        ]
        let mapper = try unwrap(
            AUCanvasSurfaceMapper(canvasFrame: canvasFrame, surfaceSize: AUSize(width: 1670.0, height: 844.0)),
            "canvas mapper"
        )

        let draggedOutsideCanvas = AUPoint(x: 1850.0, y: 830.0)
        let incorrectlyMapped = mapper.canvasPoint(fromEventPoint: draggedOutsideCanvas)

        try assertTrue(draggedOutsideCanvas.x > mapper.maxX, "raw FCP-style canvas drag can leave the object frame")
        try assertTrue(draggedOutsideCanvas.y > mapper.maxY, "raw FCP-style canvas drag can leave the object frame")
        try assertTrue(
            abs(incorrectlyMapped.x - draggedOutsideCanvas.x) > 50.0,
            "treating an outside raw canvas event as a surface-local event would jump the drag horizontally"
        )
        try assertTrue(
            abs(incorrectlyMapped.y - draggedOutsideCanvas.y) > 100.0,
            "treating an outside raw canvas event as a surface-local event would jump the drag vertically"
        )
    }

    static func testOSCDragPartFallsBackToLocalHitWhenHostPartIsNone() throws {
        let none = 0
        let hostHandle = 1
        let localQuad = 5

        try assertEqual(
            unwrap(resolveOSCDragPart(hostActivePart: hostHandle, localHitPart: localQuad, nonePart: none), "host drag part"),
            hostHandle,
            "host active part should win when it is nonzero"
        )
        try assertEqual(
            unwrap(resolveOSCDragPart(hostActivePart: none, localHitPart: localQuad, nonePart: none), "local drag part"),
            localQuad,
            "local quad hit should start a drag when Final Cut passes no active part"
        )
        try assertNil(
            resolveOSCDragPart(hostActivePart: none, localHitPart: none, nonePart: none),
            "no host part and no local hit should not start a drag"
        )
        try assertNil(
            resolveOSCDragPart(hostActivePart: none, localHitPart: nil, nonePart: none),
            "nil local hit should not start a drag"
        )
    }

    static func testQuadSourceModeShowsAdjusterBeforeApplyingWarp() throws {
        let size = AUSize(width: 200.0, height: 100.0)
        var offsets = AUCornerOffsets()
        offsets.topLeftPixels = AUPoint(x: 25.0, y: -10.0)
        offsets.topRightPixels = AUPoint(x: -15.0, y: -20.0)
        offsets.bottomRightPixels = AUPoint(x: -30.0, y: 15.0)
        offsets.bottomLeftPixels = AUPoint(x: 20.0, y: 25.0)

        let previewMatrix = AnyUprightGeometry.quadOutputToSourceMatrix(
            from: offsets,
            mode: .sourceQuad,
            showCornerAdjuster: true,
            outputSize: size,
            sourceSize: size
        )

        try assertMaps(previewMatrix, AUPoint(x: 30.0, y: 40.0), to: AUPoint(x: 30.0, y: 40.0))

        let sourceQuad = AnyUprightGeometry.sourceQuad(from: offsets, size: size)
        let appliedMatrix = AnyUprightGeometry.quadOutputToSourceMatrix(
            from: offsets,
            mode: .sourceQuad,
            showCornerAdjuster: false,
            outputSize: size,
            sourceSize: size
        )

        try assertMaps(appliedMatrix, AUPoint(x: 0.0, y: 0.0), to: sourceQuad.topLeft)
        try assertMaps(appliedMatrix, AUPoint(x: size.width, y: 0.0), to: sourceQuad.topRight)
        try assertMaps(appliedMatrix, AUPoint(x: size.width, y: size.height), to: sourceQuad.bottomRight)
        try assertMaps(appliedMatrix, AUPoint(x: 0.0, y: size.height), to: sourceQuad.bottomLeft)
    }

    static func testQuadSourceMirrorModesSampleWithinSelectedQuad() throws {
        let size = AUSize(width: 200.0, height: 100.0)
        let offsets = AUCornerOffsets()
        let sourceQuad = AnyUprightGeometry.sourceQuad(from: offsets, size: size)
        let selectionToRect = AnyUprightGeometry.quadSelectionToOutputRectMatrix(
            from: offsets,
            outputSize: size,
            sourceSize: size
        )
        let horizontalMirror = AnyUprightGeometry.quadOutputToSourceMatrix(
            from: offsets,
            mode: .sourceQuad,
            stretchMode: .mirrorHorizontal,
            showCornerAdjuster: false,
            outputSize: size,
            sourceSize: size
        )
        let verticalMirror = AnyUprightGeometry.quadOutputToSourceMatrix(
            from: offsets,
            mode: .sourceQuad,
            stretchMode: .mirrorVertical,
            showCornerAdjuster: false,
            outputSize: size,
            sourceSize: size
        )

        try assertMaps(selectionToRect, sourceQuad.topLeft, to: AUPoint(x: 0.0, y: 0.0))
        try assertMaps(selectionToRect, sourceQuad.bottomRight, to: AUPoint(x: size.width, y: size.height))

        try assertMaps(horizontalMirror, sourceQuad.topLeft, to: sourceQuad.topRight)
        try assertMaps(horizontalMirror, sourceQuad.topRight, to: sourceQuad.topLeft)
        try assertMaps(horizontalMirror, sourceQuad.bottomLeft, to: sourceQuad.bottomRight)
        try assertMaps(horizontalMirror, sourceQuad.bottomRight, to: sourceQuad.bottomLeft)

        try assertMaps(verticalMirror, sourceQuad.topLeft, to: sourceQuad.bottomLeft)
        try assertMaps(verticalMirror, sourceQuad.bottomLeft, to: sourceQuad.topLeft)
        try assertMaps(verticalMirror, sourceQuad.topRight, to: sourceQuad.bottomRight)
        try assertMaps(verticalMirror, sourceQuad.bottomRight, to: sourceQuad.topRight)
    }

    static func testHorizonFillScaleOnlyZoomsWhenNeeded() throws {
        let size = AUSize(width: 1920.0, height: 1080.0)

        try assertApprox(AnyUprightGeometry.rotationScaleToFill(angleRadians: 0.0, size: size), 1.0, "zero-degree fill scale")
        try assertTrue(AnyUprightGeometry.rotationScaleToFill(angleRadians: Double.pi / 18.0, size: size) > 1.0, "nonzero rotation should zoom to fill")
    }

    static func testUprightVerticalAndHorizontalPerspectiveGenerateCenteredQuads() throws {
        let size = AUSize(width: 200.0, height: 100.0)

        let positiveVertical = AnyUprightGeometry.uprightQuad(vertical: 0.5, horizontal: 0.0, size: size)
        try assertTrue(positiveVertical.topLeft.x > 0.0, "positive vertical top-left should move inward")
        try assertTrue(positiveVertical.topRight.x < size.width, "positive vertical top-right should move inward")
        try assertTrue(positiveVertical.bottomRight.x > size.width, "positive vertical bottom-right should move outward")
        try assertTrue(positiveVertical.bottomLeft.x < 0.0, "positive vertical bottom-left should move outward")
        try assertApprox(positiveVertical.topLeft.x, size.width - positiveVertical.topRight.x, "positive vertical top symmetry")
        try assertApprox(positiveVertical.bottomLeft.x, size.width - positiveVertical.bottomRight.x, "positive vertical bottom symmetry")

        let negativeVertical = AnyUprightGeometry.uprightQuad(vertical: -0.5, horizontal: 0.0, size: size)
        try assertTrue(negativeVertical.topLeft.x < 0.0, "negative vertical top-left should move outward")
        try assertTrue(negativeVertical.topRight.x > size.width, "negative vertical top-right should move outward")
        try assertTrue(negativeVertical.bottomRight.x < size.width, "negative vertical bottom-right should move inward")
        try assertTrue(negativeVertical.bottomLeft.x > 0.0, "negative vertical bottom-left should move inward")
        try assertApprox(negativeVertical.topLeft.x, size.width - negativeVertical.topRight.x, "negative vertical top symmetry")
        try assertApprox(negativeVertical.bottomLeft.x, size.width - negativeVertical.bottomRight.x, "negative vertical bottom symmetry")

        let positiveHorizontal = AnyUprightGeometry.uprightQuad(vertical: 0.0, horizontal: 0.5, size: size)
        try assertTrue(positiveHorizontal.topLeft.y < 0.0, "positive horizontal top-left should move outward")
        try assertTrue(positiveHorizontal.topRight.y > 0.0, "positive horizontal top-right should move inward")
        try assertTrue(positiveHorizontal.bottomRight.y < size.height, "positive horizontal bottom-right should move inward")
        try assertTrue(positiveHorizontal.bottomLeft.y > size.height, "positive horizontal bottom-left should move outward")
        try assertApprox(positiveHorizontal.topLeft.y, size.height - positiveHorizontal.bottomLeft.y, "positive horizontal left symmetry")
        try assertApprox(positiveHorizontal.topRight.y, size.height - positiveHorizontal.bottomRight.y, "positive horizontal right symmetry")

        let negativeHorizontal = AnyUprightGeometry.uprightQuad(vertical: 0.0, horizontal: -0.5, size: size)
        try assertTrue(negativeHorizontal.topLeft.y > 0.0, "negative horizontal top-left should move inward")
        try assertTrue(negativeHorizontal.topRight.y < 0.0, "negative horizontal top-right should move outward")
        try assertTrue(negativeHorizontal.bottomRight.y > size.height, "negative horizontal bottom-right should move outward")
        try assertTrue(negativeHorizontal.bottomLeft.y < size.height, "negative horizontal bottom-left should move inward")
        try assertApprox(negativeHorizontal.topLeft.y, size.height - negativeHorizontal.bottomLeft.y, "negative horizontal left symmetry")
        try assertApprox(negativeHorizontal.topRight.y, size.height - negativeHorizontal.bottomRight.y, "negative horizontal right symmetry")
    }

    static func testUprightPerspectiveKeepsFrameCenterAnchored() throws {
        let size = AUSize(width: 200.0, height: 100.0)
        let center = AUPoint(x: 100.0, y: 50.0)
        let cases = [
            AnyUprightGeometry.uprightQuad(vertical: 0.5, horizontal: 0.0, size: size),
            AnyUprightGeometry.uprightQuad(vertical: -0.5, horizontal: 0.0, size: size),
            AnyUprightGeometry.uprightQuad(vertical: 0.0, horizontal: 0.5, size: size),
            AnyUprightGeometry.uprightQuad(vertical: 0.0, horizontal: -0.5, size: size),
            AnyUprightGeometry.uprightQuad(vertical: 0.35, horizontal: -0.25, size: size)
        ]

        for quad in cases {
            let outputToSource = AnyUprightGeometry.homography(from: quad, to: AUQuad.fullFrame(size))
            try assertMaps(outputToSource, center, to: center)
        }
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

    static func testLineCandidatesKeepAllNearAxisLinesForSemiAuto() throws {
        let lines = [
            line(angleDegrees: 29.0, length: 100.0),
            line(angleDegrees: -25.0, length: 120.0),
            line(angleDegrees: 31.0, length: 200.0),
            line(angleDegrees: 5.0, length: 80.0)
        ]

        let candidates = AnyUprightGeometry.lineCandidates(
            from: lines,
            orientation: .horizontal,
            maxDeviationRadians: degreesToRadians(30.0),
            minimumLength: 20.0
        )

        try assertEqual(candidates.count, 3, "semi-auto candidate count")
        try assertApprox(candidates[0].absoluteDeviationRadians, degreesToRadians(5.0), "first semi-auto candidate")
        try assertApprox(candidates[1].absoluteDeviationRadians, degreesToRadians(25.0), "second semi-auto candidate")
        try assertApprox(candidates[2].absoluteDeviationRadians, degreesToRadians(29.0), "third semi-auto candidate")
    }

    static func testLineCandidatesExcludeThirtyDegreeBoundary() throws {
        let horizontal = AnyUprightGeometry.lineCandidates(
            from: [
                line(angleDegrees: 29.9, length: 100.0),
                line(angleDegrees: 30.0, length: 100.0)
            ],
            orientation: .horizontal,
            maxDeviationRadians: degreesToRadians(30.0),
            minimumLength: 20.0
        )
        try assertEqual(horizontal.count, 1, "horizontal <30 degree candidate count")
        try assertApprox(horizontal[0].absoluteDeviationRadians, degreesToRadians(29.9), "horizontal <30 degree candidate")

        let vertical = AnyUprightGeometry.lineCandidates(
            from: [
                line(angleDegrees: 60.0, length: 100.0),
                line(angleDegrees: 60.1, length: 100.0)
            ],
            orientation: .vertical,
            maxDeviationRadians: degreesToRadians(30.0),
            minimumLength: 20.0
        )
        try assertEqual(vertical.count, 1, "vertical <30 degree candidate count")
        try assertApprox(vertical[0].absoluteDeviationRadians, degreesToRadians(29.9), "vertical <30 degree candidate")
    }

    static func testHorizonCorrectionFromReferenceLine() throws {
        let correction = try unwrap(AnyUprightGeometry.horizonCorrectionRadians(from: [
            line(angleDegrees: 10.0, length: 200.0)
        ]), "horizon correction")

        try assertApprox(correction, degreesToRadians(-10.0), "horizon correction angle")
    }

    static func testDominantHorizonCorrectionPreservesDetectorRanking() throws {
        let correction = try unwrap(AnyUprightGeometry.dominantHorizonCorrectionRadians(from: [
            line(angleDegrees: 8.0, length: 200.0),
            line(angleDegrees: 7.0, length: 200.0),
            line(angleDegrees: 1.0, length: 200.0)
        ]), "dominant horizon correction")

        try assertApprox(correction, degreesToRadians(-7.5), "dominant horizon correction angle")
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

    static func testUprightCandidateSelectionLimitsToTwoAndConvertsCoordinates() throws {
        let specs = AnyUprightUprightCandidates.specs
        let candidates = [
            UprightCandidateLine(
                spec: specs[0],
                selected: true,
                orientation: .vertical,
                start: AUPoint(x: 0.20, y: 0.80),
                end: AUPoint(x: 0.20, y: 0.20)
            ),
            UprightCandidateLine(
                spec: specs[1],
                selected: true,
                orientation: .vertical,
                start: AUPoint(x: 0.40, y: 0.70),
                end: AUPoint(x: 0.40, y: 0.30)
            ),
            UprightCandidateLine(
                spec: specs[2],
                selected: true,
                orientation: .vertical,
                start: AUPoint(x: 0.60, y: 0.70),
                end: AUPoint(x: 0.60, y: 0.30)
            ),
            UprightCandidateLine(
                spec: specs[3],
                selected: true,
                orientation: .horizontal,
                start: AUPoint(x: 0.10, y: 0.25),
                end: AUPoint(x: 0.90, y: 0.25)
            )
        ]

        let selected = AnyUprightUprightCandidates.selectedImageLines(from: candidates, orientation: .vertical)

        try assertEqual(selected.count, 2, "selected candidate limit")
        try assertEqual(selected[0].start, AUPoint(x: 0.20, y: 0.20), "first selected candidate start")
        try assertEqual(selected[0].end, AUPoint(x: 0.20, y: 0.80), "first selected candidate end")
        try assertEqual(selected[1].start, AUPoint(x: 0.40, y: 0.30), "second selected candidate start")
        try assertEqual(selected[1].end, AUPoint(x: 0.40, y: 0.70), "second selected candidate end")
    }

    static func testUprightCandidateToggleSelectionStopsAtTwoPerOrientation() throws {
        let specs = AnyUprightUprightCandidates.specs
        let selectedA = UprightCandidateLine(
            spec: specs[0],
            selected: true,
            orientation: .vertical,
            start: AUPoint(x: 0.10, y: 0.20),
            end: AUPoint(x: 0.10, y: 0.80)
        )
        let selectedB = UprightCandidateLine(
            spec: specs[1],
            selected: true,
            orientation: .vertical,
            start: AUPoint(x: 0.30, y: 0.20),
            end: AUPoint(x: 0.30, y: 0.80)
        )
        let unselectedVertical = UprightCandidateLine(
            spec: specs[2],
            selected: false,
            orientation: .vertical,
            start: AUPoint(x: 0.50, y: 0.20),
            end: AUPoint(x: 0.50, y: 0.80)
        )
        let unselectedHorizontal = UprightCandidateLine(
            spec: specs[3],
            selected: false,
            orientation: .horizontal,
            start: AUPoint(x: 0.20, y: 0.50),
            end: AUPoint(x: 0.80, y: 0.50)
        )

        let candidates = [selectedA, selectedB, unselectedVertical, unselectedHorizontal]

        try assertTrue(
            !AnyUprightUprightCandidates.selectionValueAfterToggling(selectedA, within: candidates),
            "selected candidate toggles off"
        )
        try assertTrue(
            !AnyUprightUprightCandidates.selectionValueAfterToggling(unselectedVertical, within: candidates),
            "third vertical candidate should stay unselected"
        )
        try assertTrue(
            AnyUprightUprightCandidates.selectionValueAfterToggling(unselectedHorizontal, within: candidates),
            "different orientation can still be selected"
        )
    }

    static func testUprightCandidateObjectLineClampsAndFlipsY() throws {
        let imageLine = AULineSegment(
            start: AUPoint(x: -10.0, y: 20.0),
            end: AUPoint(x: 120.0, y: 220.0)
        )

        let objectLine = AnyUprightUprightCandidates.objectLine(
            from: imageLine,
            size: AUSize(width: 100.0, height: 200.0)
        )

        try assertEqual(objectLine.start, AUPoint(x: 0.0, y: 0.9), "object candidate start")
        try assertEqual(objectLine.end, AUPoint(x: 1.0, y: 0.0), "object candidate end")
    }

    static func testUprightCandidateHitTestingUsesPixelDistance() throws {
        let size = AUSize(width: 200.0, height: 100.0)
        let start = AUPoint(x: 0.25, y: 0.50)
        let end = AUPoint(x: 0.75, y: 0.50)

        let nearDistance = AnyUprightUprightCandidates.distanceFromPointToSegment(
            AUPoint(x: 0.50, y: 0.55),
            start: start,
            end: end,
            size: size
        )
        let outsideDistance = AnyUprightUprightCandidates.distanceFromPointToSegment(
            AUPoint(x: 0.10, y: 0.50),
            start: start,
            end: end,
            size: size
        )

        try assertApprox(nearDistance, 5.0, "candidate near hit distance")
        try assertApprox(outsideDistance, 30.0, "candidate endpoint hit distance")
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

    static func assertNil<T>(_ actual: T?, _ label: String) throws {
        if let actual {
            throw TestFailure.failed("\(label): expected nil, got \(actual)")
        }
    }
}
