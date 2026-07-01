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
        try testQuadInnerStretchDefaultsToCentralEightyPercent()
        try testQuadInnerStretchObjectDragPreservesCentralBase()
        try testDetectedInnerStretchOffsetsUseImageCoordinates()
        try testDetectedInnerStretchObjectConversionUsesImageCoordinates()
        try testDetectedSourceLineObjectConversionUsesImageCoordinates()
        try testLineIntersectionFindsDetectedCorner()
        try testDetectionPointSelectionOrdersInnerStretchCorners()
        try testDetectionLineSelectionBuildsQuadFromIntersections()
        try testDetectionLineSelectionRejectsInvalidInputs()
        try testDetectionSelectionStateFiltersByPrimitiveKind()
        try testDetectionScoresNormalizeToUnitRange()
        try testQuadInnerStretchFullFrameSelectionHasNoDYDrift()
        try testQuadInnerStretchObjectSpacePixelsMatchFxPlugOSCEvents()
        try testQuadInnerStretchOSCPixelDragDoesNotFlipYAgain()
        try testQuadInnerStretchRawCanvasDragFlipsObjectYBeforeWriting()
        try testQuadInnerStretchRawCanvasLayerMatchesSourcePreview()
        try testDistanceToQuadEdgeUsesOutputPixelSegments()
        try testQuadInnerStretchAdjusterPreviewAndApplyUseSameSelection()
        try testQuadInnerStretchOutputHandlesStayInImageSpace()
        try testQuadInnerStretchOutputHandlesMayLeaveVideoFrame()
        try testCanvasSurfaceMapperConvertsFxPlugOSCEvents()
        try testCanvasSurfaceMapperKeepsRawCanvasCandidatesDistinct()
        try testCanvasSurfaceMapperShowsFinalCutRawEventsCanLeaveFrame()
        try testInitialOSCHitResolutionDoesNotAddMappedLayerForRawCanvasEvents()
        try testInitialOSCHitResolutionKeepsRawCanvasForVisibleControlsOutsideFrame()
        try testFinalCutHostDisablesMappedSurfaceOSCHitFallback()
        try testInitialOSCHitResolutionRejectsMappedGhostAboveVisibleControls()
        try testHostCanvasPixelsStayAbsoluteForOSCOverlay()
        try testOSCSurfacePixelsFlipYOnlyAtMetalVertexBoundary()
        try testAspectFitPixelSurfaceMapperKeepsHitTestingInsideVideoFrame()
        try testOSCDragPartFallsBackToLocalHitWhenHostPartIsNone()
        try testOSCDisplayPartKeepsDragHighlightedWhenHoverStops()
        try testOutputCoordinatesKeepHostTilePaddingImageRelative()
        try testInputTextureCoordinatesRespectHostTilePadding()
        try testInnerStretchEditPreviewRequestsDestinationTile()
        try testUprightStableIdealizedImageSizeUsesPixelTransformScale()
        try testUprightStableIdealizedImageSizeUsesPixelTransformCenterRounding()
        try testUprightStableIdealizedImageSizeMergesMotionPreviewRounding()
        try testUprightStableIdealizedImageSizeMergesMotionPanRounding()
        try testQuadInnerStretchModeShowsAdjusterBeforeApplyingWarp()
        try testHorizonFillScaleOnlyZoomsWhenNeeded()
        try testAutoCropScalesWarpedOutputIntoSourceFrame()
        try testAutoCropDoesNotForceMaximumScaleWhenNoCropCanFill()
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
        try testSupportedLineDetectorReturnsFiniteSegments()
        try testUprightCandidateSelectionLimitsToTwoAndConvertsCoordinates()
        try testUprightAutomaticSelectionChoosesTopTwoIncludedCandidates()
        try testUprightCandidateToggleSelectionStopsAtTwoPerOrientation()
        try testUprightCandidateDisplayHonorsControlAndCorrectionMode()
        try testUprightCandidateObjectLineClampsAndFlipsY()
        try testUprightManualGuideImageLineFlipsObjectY()
        try testUprightCandidateHitTestingUsesPixelDistance()
        try testUprightCorrectionValuesDeriveFromCurrentReferences()
        try testVerticalUprightCorrectionStraightensReferenceLines()
        try testMotionManualVerticalGuidesUseObjectY()
        try testVerticalUprightCorrectionKeepsNormalizedGuideMeaningAcrossAspectRatios()
        try testHorizontalUprightCorrectionKeepsNormalizedGuideMeaningAcrossAspectRatios()
        try testUprightAppliedCorrectionIsStableAcrossPreviewOutputSizes()
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

    static func testQuadInnerStretchDefaultsToCentralEightyPercent() throws {
        let size = AUSize(width: 200.0, height: 100.0)
        let offsets = AUCornerOffsets()
        let innerStretch = AnyUprightGeometry.innerStretch(from: offsets, size: size)
        let objectPoints = AnyUprightGeometry.innerStretchObjectPoints(from: offsets, size: size)
        let appliedMatrix = AnyUprightGeometry.quadOutputToSourceMatrix(
            from: offsets,
            mode: .innerStretch,
            showCornerAdjuster: false,
            outputSize: size,
            sourceSize: size
        )

        try assertEqual(innerStretch.topLeft, AUPoint(x: 20.0, y: 10.0), "source default top-left")
        try assertEqual(innerStretch.topRight, AUPoint(x: 180.0, y: 10.0), "source default top-right")
        try assertEqual(innerStretch.bottomRight, AUPoint(x: 180.0, y: 90.0), "source default bottom-right")
        try assertEqual(innerStretch.bottomLeft, AUPoint(x: 20.0, y: 90.0), "source default bottom-left")

        try assertEqual(objectPoints.topLeft, AUPoint(x: 0.10, y: 0.90), "source default object top-left")
        try assertEqual(objectPoints.topRight, AUPoint(x: 0.90, y: 0.90), "source default object top-right")
        try assertEqual(objectPoints.bottomRight, AUPoint(x: 0.90, y: 0.10), "source default object bottom-right")
        try assertEqual(objectPoints.bottomLeft, AUPoint(x: 0.10, y: 0.10), "source default object bottom-left")

        try assertMaps(appliedMatrix, AUPoint(x: 0.0, y: 0.0), to: innerStretch.topLeft)
        try assertMaps(appliedMatrix, AUPoint(x: size.width, y: 0.0), to: innerStretch.topRight)
        try assertMaps(appliedMatrix, AUPoint(x: size.width, y: size.height), to: innerStretch.bottomRight)
        try assertMaps(appliedMatrix, AUPoint(x: 0.0, y: size.height), to: innerStretch.bottomLeft)
    }

    static func testQuadInnerStretchObjectDragPreservesCentralBase() throws {
        let size = AUSize(width: 200.0, height: 100.0)
        var offsets = AUCornerOffsets()

        let percent = AnyUprightGeometry.sourceCornerPercentOffset(
            forObjectPoint: AUPoint(x: 0.20, y: 0.80),
            corner: .topLeft
        )
        offsets.topLeftPercent = percent

        let objectPoints = AnyUprightGeometry.innerStretchObjectPoints(from: offsets, size: size)
        let innerStretch = AnyUprightGeometry.innerStretch(from: offsets, size: size)

        try assertEqual(percent, AUPoint(x: 0.10, y: -0.10), "source dragged top-left percent offset")
        try assertEqual(objectPoints.topLeft, AUPoint(x: 0.20, y: 0.80), "source dragged top-left object point")
        try assertEqual(innerStretch.topLeft, AUPoint(x: 40.0, y: 20.0), "source dragged top-left source point")
    }

    static func testDetectedInnerStretchOffsetsUseImageCoordinates() throws {
        let size = AUSize(width: 200.0, height: 100.0)
        let normalizedLowerLeftQuad = AUQuad(
            topLeft: AUPoint(x: 0.20, y: 0.80),
            topRight: AUPoint(x: 0.85, y: 0.70),
            bottomRight: AUPoint(x: 0.90, y: 0.15),
            bottomLeft: AUPoint(x: 0.15, y: 0.10)
        )
        let detectedInnerStretch = AnyUprightGeometry.imageQuad(
            fromNormalizedLowerLeftQuad: normalizedLowerLeftQuad,
            size: size
        )
        let offsets = AnyUprightGeometry.innerStretchOffsets(forInnerStretch: detectedInnerStretch, size: size)
        let innerStretch = AnyUprightGeometry.innerStretch(from: offsets, size: size)
        let objectPoints = AnyUprightGeometry.innerStretchObjectPoints(from: offsets, size: size)

        try assertEqual(detectedInnerStretch.topLeft, AUPoint(x: 40.0, y: 20.0), "detected top-left image point")
        try assertEqual(detectedInnerStretch.topRight, AUPoint(x: 170.0, y: 30.0), "detected top-right image point")
        try assertEqual(detectedInnerStretch.bottomRight, AUPoint(x: 180.0, y: 85.0), "detected bottom-right image point")
        try assertEqual(detectedInnerStretch.bottomLeft, AUPoint(x: 30.0, y: 90.0), "detected bottom-left image point")
        try assertEqual(innerStretch.topLeft, detectedInnerStretch.topLeft, "inner stretch top-left writeback")
        try assertEqual(innerStretch.topRight, detectedInnerStretch.topRight, "inner stretch top-right writeback")
        try assertEqual(innerStretch.bottomRight, detectedInnerStretch.bottomRight, "inner stretch bottom-right writeback")
        try assertEqual(innerStretch.bottomLeft, detectedInnerStretch.bottomLeft, "inner stretch bottom-left writeback")
        try assertEqual(objectPoints.topLeft, AUPoint(x: 0.20, y: 0.80), "object top-left after detection")
        try assertEqual(objectPoints.bottomLeft, AUPoint(x: 0.15, y: 0.10), "object bottom-left after detection")
    }

    static func testDetectedInnerStretchObjectConversionUsesImageCoordinates() throws {
        let size = AUSize(width: 200.0, height: 100.0)
        let imageQuad = AUQuad(
            topLeft: AUPoint(x: 40.0, y: 20.0),
            topRight: AUPoint(x: 170.0, y: 30.0),
            bottomRight: AUPoint(x: 180.0, y: 85.0),
            bottomLeft: AUPoint(x: 30.0, y: 90.0)
        )

        let objectQuad = AnyUprightGeometry.normalizedObjectQuad(fromImageQuad: imageQuad, size: size)

        try assertEqual(objectQuad.topLeft, AUPoint(x: 0.20, y: 0.80), "top-left object point")
        try assertEqual(objectQuad.topRight, AUPoint(x: 0.85, y: 0.70), "top-right object point")
        try assertEqual(objectQuad.bottomRight, AUPoint(x: 0.90, y: 0.15), "bottom-right object point")
        try assertEqual(objectQuad.bottomLeft, AUPoint(x: 0.15, y: 0.10), "bottom-left object point")
    }

    static func testDetectionScoresNormalizeToUnitRange() throws {
        let scores = AnyUprightGeometry.normalizedScores([10.0, 5.0, -2.0, .infinity])

        try assertEqual(scores.count, 4, "normalized score count")
        try assertApprox(scores[0], 1.0, "maximum score")
        try assertApprox(scores[1], 0.5, "half score")
        try assertApprox(scores[2], 0.0, "negative score clamps to zero")
        try assertApprox(scores[3], 0.0, "non-finite score clamps to zero")
        let zeroScores = AnyUprightGeometry.normalizedScores([0.0, 0.0])
        try assertApprox(zeroScores[0], 0.0, "first zero score")
        try assertApprox(zeroScores[1], 0.0, "second zero score")
    }

    static func testDetectedSourceLineObjectConversionUsesImageCoordinates() throws {
        let size = AUSize(width: 200.0, height: 100.0)
        let imageLine = AULineSegment(
            start: AUPoint(x: 20.0, y: 10.0),
            end: AUPoint(x: 180.0, y: 85.0)
        )

        let objectLine = AnyUprightGeometry.normalizedObjectLine(fromImageLine: imageLine, size: size)

        try assertEqual(objectLine.start, AUPoint(x: 0.10, y: 0.90), "line start object point")
        try assertEqual(objectLine.end, AUPoint(x: 0.90, y: 0.15), "line end object point")
    }

    static func testLineIntersectionFindsDetectedCorner() throws {
        let vertical = AULineSegment(start: AUPoint(x: 40.0, y: 5.0), end: AUPoint(x: 50.0, y: 95.0))
        let horizontal = AULineSegment(start: AUPoint(x: 10.0, y: 30.0), end: AUPoint(x: 110.0, y: 20.0))

        let point = try unwrap(AnyUprightGeometry.intersection(of: vertical, and: horizontal), "line intersection")

        try assertApprox(point.x, 42.42, "corner x", accuracy: 0.01)
        try assertApprox(point.y, 26.76, "corner y", accuracy: 0.01)
    }

    static func testDetectionPointSelectionOrdersInnerStretchCorners() throws {
        let size = AUSize(width: 200.0, height: 100.0)
        let points = [
            AUPoint(x: 0.90, y: 0.15),
            AUPoint(x: 0.20, y: 0.80),
            AUPoint(x: 0.15, y: 0.10),
            AUPoint(x: 0.85, y: 0.70)
        ]

        let quad = try unwrap(AnyUprightGeometry.imageQuad(fromNormalizedObjectPoints: points, size: size), "ordered detection point quad")
        let offsets = AnyUprightGeometry.innerStretchOffsets(forInnerStretch: quad, size: size)
        let innerStretch = AnyUprightGeometry.innerStretch(from: offsets, size: size)

        try assertEqual(quad.topLeft, AUPoint(x: 40.0, y: 20.0), "ordered point top-left")
        try assertEqual(quad.topRight, AUPoint(x: 170.0, y: 30.0), "ordered point top-right")
        try assertEqual(quad.bottomRight, AUPoint(x: 180.0, y: 85.0), "ordered point bottom-right")
        try assertEqual(quad.bottomLeft, AUPoint(x: 30.0, y: 90.0), "ordered point bottom-left")
        try assertEqual(innerStretch.topLeft, quad.topLeft, "point selection writeback top-left")
        try assertEqual(innerStretch.topRight, quad.topRight, "point selection writeback top-right")
        try assertEqual(innerStretch.bottomRight, quad.bottomRight, "point selection writeback bottom-right")
        try assertEqual(innerStretch.bottomLeft, quad.bottomLeft, "point selection writeback bottom-left")
    }

    static func testDetectionLineSelectionBuildsQuadFromIntersections() throws {
        let size = AUSize(width: 200.0, height: 100.0)
        let imageLines = [
            AULineSegment(start: AUPoint(x: 35.0, y: 20.0), end: AUPoint(x: 175.0, y: 30.0)),
            AULineSegment(start: AUPoint(x: 30.0, y: 90.0), end: AUPoint(x: 185.0, y: 85.0)),
            AULineSegment(start: AUPoint(x: 40.0, y: 18.0), end: AUPoint(x: 30.0, y: 92.0)),
            AULineSegment(start: AUPoint(x: 170.0, y: 28.0), end: AUPoint(x: 180.0, y: 88.0))
        ]
        let objectLines = imageLines.map { AnyUprightGeometry.normalizedObjectLine(fromImageLine: $0, size: size) }

        let quad = try unwrap(AnyUprightGeometry.imageQuad(fromNormalizedObjectLines: objectLines, size: size), "line intersection quad")
        let offsets = AnyUprightGeometry.innerStretchOffsets(forInnerStretch: quad, size: size)
        let innerStretch = AnyUprightGeometry.innerStretch(from: offsets, size: size)

        try assertTrue(AnyUprightGeometry.isConvexImageQuad(quad), "line selection should create a convex quad")
        try assertApprox(innerStretch.topLeft.x, quad.topLeft.x, "line writeback top-left x")
        try assertApprox(innerStretch.topRight.y, quad.topRight.y, "line writeback top-right y")
        try assertApprox(innerStretch.bottomRight.x, quad.bottomRight.x, "line writeback bottom-right x")
        try assertApprox(innerStretch.bottomLeft.y, quad.bottomLeft.y, "line writeback bottom-left y")
    }

    static func testDetectionLineSelectionRejectsInvalidInputs() throws {
        let size = AUSize(width: 200.0, height: 100.0)
        let parallelLines = [
            AULineSegment(start: AUPoint(x: 20.0, y: 20.0), end: AUPoint(x: 180.0, y: 20.0)),
            AULineSegment(start: AUPoint(x: 20.0, y: 40.0), end: AUPoint(x: 180.0, y: 40.0)),
            AULineSegment(start: AUPoint(x: 20.0, y: 60.0), end: AUPoint(x: 180.0, y: 60.0)),
            AULineSegment(start: AUPoint(x: 20.0, y: 80.0), end: AUPoint(x: 180.0, y: 80.0))
        ].map { AnyUprightGeometry.normalizedObjectLine(fromImageLine: $0, size: size) }

        try assertNil(AnyUprightGeometry.imageQuad(fromNormalizedObjectLines: parallelLines, size: size), "four horizontal lines cannot form a quad")
        try assertNil(AnyUprightGeometry.imageQuad(fromNormalizedObjectLines: Array(parallelLines.prefix(3)), size: size), "three lines cannot form a quad")
        try assertNil(
            AnyUprightGeometry.orderedImageQuad(from: [
                AUPoint(x: 10.0, y: 10.0),
                AUPoint(x: 10.0, y: 10.0),
                AUPoint(x: 100.0, y: 100.0),
                AUPoint(x: 20.0, y: 90.0)
            ]),
            "duplicate points cannot form a quad"
        )
    }

    static func testDetectionSelectionStateFiltersByPrimitiveKind() throws {
        var selection = AUQuadDetectionSelectionState()
        let corner = AUQuadDetectionPrimitiveID(kind: .corner, index: 3)
        let edge = AUQuadDetectionPrimitiveID(kind: .edge, index: 2)

        selection.toggle(corner)
        try assertTrue(selection.shouldShowCorner(index: 4), "selecting a point should keep other points visible")
        try assertTrue(!selection.shouldShowEdge(index: 2), "selecting a point should hide lines")
        selection.toggle(edge)
        try assertTrue(selection.selectedEdgeIndexes.isEmpty, "hidden edge selection should be ignored while points are selected")
        selection.toggle(corner)
        try assertTrue(selection.isEmpty, "repeating the same point should cancel selection")
        try assertTrue(selection.shouldShowCorner(index: 4), "empty selection should show points")
        try assertTrue(selection.shouldShowEdge(index: 2), "empty selection should show lines")

        selection.toggle(edge)
        try assertTrue(!selection.shouldShowCorner(index: 3), "selecting a line should hide points")
        try assertTrue(selection.shouldShowEdge(index: 8), "selecting a line should keep other lines visible")
    }

    static func testQuadInnerStretchFullFrameSelectionHasNoDYDrift() throws {
        let size = AUSize(width: 200.0, height: 100.0)
        let offsets = fullFrameSourceOffsets()
        let innerStretch = AnyUprightGeometry.innerStretch(from: offsets, size: size)
        let objectPoints = AnyUprightGeometry.innerStretchObjectPoints(from: offsets, size: size)
        let outputHandles = AnyUprightGeometry.innerStretchOutputHandles(
            from: offsets,
            outputSize: size,
            sourceSize: size
        )
        let appliedMatrix = AnyUprightGeometry.quadOutputToSourceMatrix(
            from: offsets,
            mode: .innerStretch,
            showCornerAdjuster: false,
            outputSize: size,
            sourceSize: size
        )

        try assertEqual(innerStretch.topLeft, AUPoint(x: 0.0, y: 0.0), "full-frame top-left")
        try assertEqual(innerStretch.topRight, AUPoint(x: size.width, y: 0.0), "full-frame top-right")
        try assertEqual(innerStretch.bottomRight, AUPoint(x: size.width, y: size.height), "full-frame bottom-right")
        try assertEqual(innerStretch.bottomLeft, AUPoint(x: 0.0, y: size.height), "full-frame bottom-left")

        try assertEqual(objectPoints.topLeft, AUPoint(x: 0.0, y: 1.0), "full-frame object top-left")
        try assertEqual(objectPoints.bottomLeft, AUPoint(x: 0.0, y: 0.0), "full-frame object bottom-left")
        try assertEqual(outputHandles.topLeft, AUPoint(x: 0.0, y: 0.0), "full-frame output handle top-left")
        try assertEqual(outputHandles.bottomLeft, AUPoint(x: 0.0, y: size.height), "full-frame output handle bottom-left")

        try assertMaps(appliedMatrix, AUPoint(x: 0.0, y: 0.0), to: AUPoint(x: 0.0, y: 0.0))
        try assertMaps(appliedMatrix, AUPoint(x: size.width, y: 0.0), to: AUPoint(x: size.width, y: 0.0))
        try assertMaps(appliedMatrix, AUPoint(x: size.width, y: size.height), to: AUPoint(x: size.width, y: size.height))
        try assertMaps(appliedMatrix, AUPoint(x: 0.0, y: size.height), to: AUPoint(x: 0.0, y: size.height))
        try assertMaps(appliedMatrix, AUPoint(x: size.width / 2.0, y: size.height / 2.0), to: AUPoint(x: size.width / 2.0, y: size.height / 2.0))
    }

    static func testQuadInnerStretchObjectSpacePixelsMatchFxPlugOSCEvents() throws {
        let size = AUSize(width: 200.0, height: 100.0)
        var offsets = AUCornerOffsets()
        let defaultObjectPoints = AnyUprightGeometry.innerStretchObjectPoints(from: offsets, size: size)
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
            fromNormalizedObjectQuad: AnyUprightGeometry.innerStretchObjectPoints(from: offsets, size: size),
            size: size
        )
        let updatedInnerStretch = AnyUprightGeometry.innerStretch(from: offsets, size: size)
        try assertEqual(percent, AUPoint(x: 0.125, y: -0.15), "source object-space drag percent offset")
        try assertEqual(updatedObjectPixels.topLeft, draggedPixel, "source object-space drag target")
        try assertEqual(updatedInnerStretch.topLeft, AUPoint(x: 45.0, y: 25.0), "inner stretch should sample the Y-flipped image point matching the visible handle")
    }

    static func testQuadInnerStretchOSCPixelDragDoesNotFlipYAgain() throws {
        let size = AUSize(width: 200.0, height: 100.0)
        var offsets = AUCornerOffsets()
        let visualTopLeftOSCPixel = AUPoint(x: 45.0, y: 75.0)
        let objectPoint = AnyUprightGeometry.normalizedSourceObjectPoint(
            fromOSCPixelPoint: visualTopLeftOSCPixel,
            outputSize: size
        )
        let percent = AnyUprightGeometry.sourceCornerPercentOffset(
            forObjectPoint: objectPoint,
            corner: .topLeft
        )

        offsets.topLeftPercent = percent
        let innerStretch = AnyUprightGeometry.innerStretch(from: offsets, size: size)

        try assertEqual(objectPoint, AUPoint(x: 0.225, y: 0.75), "osc pixel drag object point")
        try assertEqual(percent, AUPoint(x: 0.125, y: -0.15), "osc pixel drag percent")
        try assertEqual(innerStretch.topLeft, AUPoint(x: 45.0, y: 25.0), "osc pixel drag should not flip Y a second time")
    }

    static func testQuadInnerStretchRawCanvasDragFlipsObjectYBeforeWriting() throws {
        let size = AUSize(width: 200.0, height: 100.0)
        var offsets = AUCornerOffsets()
        let rawCanvasTopLeftObjectPoint = AUPoint(x: 0.225, y: 0.25)
        let correctedObjectPoint = AnyUprightGeometry.verticallyFlippedObjectPoint(rawCanvasTopLeftObjectPoint)
        let percent = AnyUprightGeometry.sourceCornerPercentOffset(
            forObjectPoint: correctedObjectPoint,
            corner: .topLeft
        )

        offsets.topLeftPercent = percent
        let innerStretch = AnyUprightGeometry.innerStretch(from: offsets, size: size)

        try assertEqual(correctedObjectPoint, AUPoint(x: 0.225, y: 0.75), "raw canvas source drag should flip object Y")
        try assertEqual(percent, AUPoint(x: 0.125, y: -0.15), "flipped raw canvas source percent")
        try assertEqual(innerStretch.topLeft, AUPoint(x: 45.0, y: 25.0), "flipped raw canvas drag should update the visible top-left source point")
    }

    static func testQuadInnerStretchRawCanvasLayerMatchesSourcePreview() throws {
        let size = AUSize(width: 200.0, height: 100.0)
        var offsets = AUCornerOffsets()
        offsets.topLeftPercent = AUPoint(x: 0.125, y: -0.15)

        let objectPoints = AnyUprightGeometry.innerStretchObjectPoints(from: offsets, size: size)
        let objectCanvasPixels = AnyUprightGeometry.objectPixelQuad(fromNormalizedObjectQuad: objectPoints, size: size)
        let rawCanvasObjectPoints = AnyUprightGeometry.verticallyFlippedObjectQuad(objectPoints)
        let rawCanvasPixels = AnyUprightGeometry.objectPixelQuad(fromNormalizedObjectQuad: rawCanvasObjectPoints, size: size)
        let sourcePreviewHandles = AnyUprightGeometry.innerStretchOutputHandles(
            from: offsets,
            outputSize: size,
            sourceSize: size
        )

        try assertEqual(objectCanvasPixels.topLeft, AUPoint(x: 45.0, y: 75.0), "object/canvas top-left keeps FxPlug object-space Y")
        try assertEqual(sourcePreviewHandles.topLeft, AUPoint(x: 45.0, y: 25.0), "source preview top-left crosses the Y-axis boundary")
        try assertEqual(rawCanvasPixels.topLeft, sourcePreviewHandles.topLeft, "raw Final Cut canvas layer should match the source preview handle")
        try assertTrue(
            objectCanvasPixels.topLeft.y != rawCanvasPixels.topLeft.y,
            "raw canvas hit testing should pick the source-preview layer instead of adding an object-space second layer"
        )
    }

    static func testPixelQuadFlipMapsOutputHandlesToOSCRenderTargetCoordinates() throws {
        let size = AUSize(width: 200.0, height: 100.0)
        let innerStretch = AnyUprightGeometry.innerStretchOutputHandles(
            from: AUCornerOffsets(),
            outputSize: size,
            sourceSize: size
        )
        let oscQuad = AnyUprightGeometry.verticallyFlippedPixelQuad(innerStretch, size: size)

        try assertEqual(innerStretch.topLeft, AUPoint(x: 20.0, y: 10.0), "source top-left")
        try assertEqual(oscQuad.topLeft, AUPoint(x: 20.0, y: 90.0), "osc top-left")
        try assertEqual(oscQuad.bottomLeft, AUPoint(x: 20.0, y: 10.0), "osc bottom-left")
    }

    static func testDistanceToQuadEdgeUsesOutputPixelSegments() throws {
        let quad = AUQuad(
            topLeft: AUPoint(x: 20.0, y: 10.0),
            topRight: AUPoint(x: 180.0, y: 10.0),
            bottomRight: AUPoint(x: 150.0, y: 90.0),
            bottomLeft: AUPoint(x: 20.0, y: 90.0)
        )

        try assertApprox(AnyUprightGeometry.distanceToQuadEdge(from: AUPoint(x: 100.0, y: 13.0), quad: quad), 3.0, "top edge distance")
        try assertApprox(AnyUprightGeometry.distanceToQuadEdge(from: AUPoint(x: 150.0, y: 14.0), quad: quad), 4.0, "top edge distance near slanted side")
        try assertApprox(AnyUprightGeometry.distanceToQuadEdge(from: AUPoint(x: 165.0, y: 50.0), quad: quad), 0.0, "slanted edge distance")
    }

    static func testQuadInnerStretchAdjusterPreviewAndApplyUseSameSelection() throws {
        let outputSize = AUSize(width: 300.0, height: 150.0)
        let sourceSize = AUSize(width: 600.0, height: 300.0)
        var offsets = AUCornerOffsets()
        offsets.topLeftPercent = AUPoint(x: 0.10, y: -0.05)
        offsets.topRightPercent = AUPoint(x: -0.08, y: -0.02)
        offsets.bottomRightPercent = AUPoint(x: -0.12, y: 0.07)
        offsets.bottomLeftPercent = AUPoint(x: 0.04, y: 0.08)

        let selectedInnerStretch = AnyUprightGeometry.innerStretch(from: offsets, size: sourceSize)
        let previewSelectionToRect = AnyUprightGeometry.quadSelectionToOutputRectMatrix(
            from: offsets,
            outputSize: outputSize,
            sourceSize: sourceSize
        )
        let appliedMatrix = AnyUprightGeometry.quadOutputToSourceMatrix(
            from: offsets,
            mode: .innerStretch,
            showCornerAdjuster: false,
            outputSize: outputSize,
            sourceSize: sourceSize
        )

        let selectedOutputQuad = AUQuad(
            topLeft: AUPoint(x: selectedInnerStretch.topLeft.x / 2.0, y: selectedInnerStretch.topLeft.y / 2.0),
            topRight: AUPoint(x: selectedInnerStretch.topRight.x / 2.0, y: selectedInnerStretch.topRight.y / 2.0),
            bottomRight: AUPoint(x: selectedInnerStretch.bottomRight.x / 2.0, y: selectedInnerStretch.bottomRight.y / 2.0),
            bottomLeft: AUPoint(x: selectedInnerStretch.bottomLeft.x / 2.0, y: selectedInnerStretch.bottomLeft.y / 2.0)
        )

        try assertMaps(previewSelectionToRect, selectedOutputQuad.topLeft, to: AUPoint(x: 0.0, y: 0.0))
        try assertMaps(previewSelectionToRect, selectedOutputQuad.topRight, to: AUPoint(x: outputSize.width, y: 0.0))
        try assertMaps(previewSelectionToRect, selectedOutputQuad.bottomRight, to: AUPoint(x: outputSize.width, y: outputSize.height))
        try assertMaps(previewSelectionToRect, selectedOutputQuad.bottomLeft, to: AUPoint(x: 0.0, y: outputSize.height))

        try assertMaps(appliedMatrix, AUPoint(x: 0.0, y: 0.0), to: selectedInnerStretch.topLeft)
        try assertMaps(appliedMatrix, AUPoint(x: outputSize.width, y: 0.0), to: selectedInnerStretch.topRight)
        try assertMaps(appliedMatrix, AUPoint(x: outputSize.width, y: outputSize.height), to: selectedInnerStretch.bottomRight)
        try assertMaps(appliedMatrix, AUPoint(x: 0.0, y: outputSize.height), to: selectedInnerStretch.bottomLeft)
    }

    static func testQuadInnerStretchOutputHandlesStayInImageSpace() throws {
        let outputSize = AUSize(width: 300.0, height: 150.0)
        let sourceSize = AUSize(width: 600.0, height: 300.0)
        var offsets = AUCornerOffsets()
        offsets.topLeftPixels = AUPoint(x: 40.0, y: -30.0)
        offsets.topRightPixels = AUPoint(x: -90.0, y: 20.0)
        offsets.bottomRightPixels = AUPoint(x: -120.0, y: -45.0)
        offsets.bottomLeftPixels = AUPoint(x: 25.0, y: 60.0)

        let handles = AnyUprightGeometry.innerStretchOutputHandles(
            from: offsets,
            outputSize: outputSize,
            sourceSize: sourceSize
        )
        let selectionToRect = AnyUprightGeometry.quadSelectionToOutputRectMatrix(
            from: offsets,
            outputSize: outputSize,
            sourceSize: sourceSize
        )

        try assertMaps(selectionToRect, handles.topLeft, to: AUPoint(x: 0.0, y: 0.0))
        try assertMaps(selectionToRect, handles.topRight, to: AUPoint(x: outputSize.width, y: 0.0))
        try assertMaps(selectionToRect, handles.bottomRight, to: AUPoint(x: outputSize.width, y: outputSize.height))
        try assertMaps(selectionToRect, handles.bottomLeft, to: AUPoint(x: 0.0, y: outputSize.height))
        try assertTrue(handles.topLeft != AUPoint(x: 0.0, y: 0.0), "fixed-size handles should be centered in output image space, not rect space")
    }

    static func testQuadInnerStretchOutputHandlesMayLeaveVideoFrame() throws {
        let outputSize = AUSize(width: 300.0, height: 150.0)
        let sourceSize = AUSize(width: 600.0, height: 300.0)
        var offsets = AUCornerOffsets()
        offsets.topLeftPercent = AUPoint(x: -0.25, y: 0.20)
        offsets.topRightPercent = AUPoint(x: 0.30, y: 0.10)
        offsets.bottomRightPercent = AUPoint(x: 0.20, y: -0.25)
        offsets.bottomLeftPercent = AUPoint(x: -0.15, y: -0.30)

        let handles = AnyUprightGeometry.innerStretchOutputHandles(
            from: offsets,
            outputSize: outputSize,
            sourceSize: sourceSize
        )
        let selectionToRect = AnyUprightGeometry.quadSelectionToOutputRectMatrix(
            from: offsets,
            outputSize: outputSize,
            sourceSize: sourceSize
        )

        try assertTrue(handles.topLeft.x < 0.0, "top-left handle should be allowed outside the left video edge")
        try assertTrue(handles.topRight.x > outputSize.width, "top-right handle should be allowed outside the right video edge")
        try assertTrue(handles.bottomRight.y > outputSize.height, "bottom-right handle should be allowed below the video edge")
        try assertTrue(handles.bottomLeft.y > outputSize.height, "bottom-left handle should be allowed below the video edge")
        try assertMaps(selectionToRect, handles.topLeft, to: AUPoint(x: 0.0, y: 0.0))
        try assertMaps(selectionToRect, handles.bottomRight, to: AUPoint(x: outputSize.width, y: outputSize.height))
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

    static func testInitialOSCHitResolutionDoesNotAddMappedLayerForRawCanvasEvents() throws {
        let finalCutCanvasFrame = [
            AUPoint(x: 0.0, y: 1181.86),
            AUPoint(x: 2184.0, y: 1181.86),
            AUPoint(x: 2184.0, y: 30.14),
            AUPoint(x: 0.0, y: 30.14)
        ]
        let finalCutHoverEvent = AUPoint(x: 1725.4, y: 891.8)

        try assertTrue(
            !shouldIncludeMappedSurfaceOSCCandidate(forInitialEventPoint: finalCutHoverEvent, canvasFrame: finalCutCanvasFrame),
            "raw Final Cut canvas events inside the canvas frame should not also test a mapped-surface layer"
        )

        let motionCanvasFrame = [
            AUPoint(x: 531.1, y: 791.2),
            AUPoint(x: 1811.1, y: 791.2),
            AUPoint(x: 1811.1, y: 71.2),
            AUPoint(x: 531.1, y: 71.2)
        ]
        let mapper = try unwrap(
            AUCanvasSurfaceMapper(canvasFrame: motionCanvasFrame, surfaceSize: AUSize(width: 1670.0, height: 844.0)),
            "canvas mapper"
        )
        let motionSurfaceEvent = mapper.eventPoint(fromCanvasPoint: AUPoint(x: 659.1, y: 719.2))

        try assertTrue(
            shouldIncludeMappedSurfaceOSCCandidate(forInitialEventPoint: motionSurfaceEvent, canvasFrame: motionCanvasFrame),
            "surface-local events outside the host canvas frame should still use mapped-surface hit testing"
        )
    }

    static func testInitialOSCHitResolutionKeepsRawCanvasForVisibleControlsOutsideFrame() throws {
        let finalCutCanvasFrame = [
            AUPoint(x: 580.0, y: 876.0),
            AUPoint(x: 1604.0, y: 876.0),
            AUPoint(x: 1604.0, y: 336.0),
            AUPoint(x: 580.0, y: 336.0)
        ]
        let finalCutVisibleInnerStretch = [
            AUPoint(x: 788.4, y: 523.9),
            AUPoint(x: 1273.2, y: 511.1),
            AUPoint(x: 1305.4, y: 1043.7),
            AUPoint(x: 797.7, y: 821.0)
        ]
        let finalCutBottomRightHandle = AUPoint(x: 1305.4, y: 1043.7)

        try assertTrue(
            !isPointInsideAxisAlignedFrame(finalCutBottomRightHandle, frame: finalCutCanvasFrame),
            "regression point should sit outside the object canvas frame"
        )
        try assertTrue(
            !shouldIncludeMappedSurfaceOSCCandidate(
                forInitialEventPoint: finalCutBottomRightHandle,
                canvasFrame: finalCutCanvasFrame,
                visibleControlPoints: finalCutVisibleInnerStretch,
                hitPadding: 24.0
            ),
            "visible Final Cut controls outside the video frame should keep raw-canvas hit testing"
        )

        let motionCanvasFrame = [
            AUPoint(x: 531.1, y: 791.2),
            AUPoint(x: 1811.1, y: 791.2),
            AUPoint(x: 1811.1, y: 71.2),
            AUPoint(x: 531.1, y: 71.2)
        ]
        let motionVisibleInnerStretch = [
            AUPoint(x: 659.1, y: 719.2),
            AUPoint(x: 1683.1, y: 719.2),
            AUPoint(x: 1683.1, y: 143.2),
            AUPoint(x: 659.1, y: 143.2)
        ]
        let mapper = try unwrap(
            AUCanvasSurfaceMapper(canvasFrame: motionCanvasFrame, surfaceSize: AUSize(width: 1670.0, height: 844.0)),
            "canvas mapper"
        )
        let motionSurfaceEvent = mapper.eventPoint(fromCanvasPoint: motionVisibleInnerStretch[0])
        let mappedMotionCanvasPoint = mapper.canvasPoint(fromEventPoint: motionSurfaceEvent)

        try assertTrue(
            shouldIncludeMappedSurfaceOSCCandidate(
                forInitialEventPoint: motionSurfaceEvent,
                mappedCanvasPoint: mappedMotionCanvasPoint,
                canvasFrame: motionCanvasFrame,
                visibleControlPoints: motionVisibleInnerStretch,
                hitPadding: 24.0
            ),
            "Motion-style surface-local events should still map through the surface mapper"
        )
    }

    static func testInitialOSCHitResolutionRejectsMappedGhostAboveVisibleControls() throws {
        let finalCutCanvasFrame = [
            AUPoint(x: 580.0, y: 876.0),
            AUPoint(x: 1604.0, y: 876.0),
            AUPoint(x: 1604.0, y: 336.0),
            AUPoint(x: 580.0, y: 336.0)
        ]
        let finalCutVisibleInnerStretch = [
            AUPoint(x: 778.5, y: 526.0),
            AUPoint(x: 1268.2, y: 513.3),
            AUPoint(x: 1273.2, y: 879.4),
            AUPoint(x: 790.8, y: 817.8)
        ]
        let staleObjectCanvasQuad = AUQuad(
            topLeft: AUPoint(x: 778.5, y: 686.0),
            topRight: AUPoint(x: 1268.2, y: 698.7),
            bottomRight: AUPoint(x: 1273.2, y: 332.6),
            bottomLeft: AUPoint(x: 790.8, y: 394.2)
        )
        let visibleQuad = AUQuad(
            topLeft: finalCutVisibleInnerStretch[0],
            topRight: finalCutVisibleInnerStretch[1],
            bottomRight: finalCutVisibleInnerStretch[2],
            bottomLeft: finalCutVisibleInnerStretch[3]
        )
        let mapper = try unwrap(
            AUCanvasSurfaceMapper(canvasFrame: finalCutCanvasFrame, surfaceSize: AUSize(width: 2184.0, height: 1212.0)),
            "canvas mapper"
        )
        let rawEventAboveVisibleFrame = AUPoint(x: 1451.3, y: 921.7)
        let incorrectlyMappedCanvasPoint = mapper.canvasPoint(fromEventPoint: rawEventAboveVisibleFrame)

        try assertTrue(
            !isPointInsideAxisAlignedFrame(rawEventAboveVisibleFrame, frame: finalCutCanvasFrame),
            "regression event should sit above the object canvas frame"
        )
        try assertTrue(
            AnyUprightGeometry.distanceToQuadEdge(from: incorrectlyMappedCanvasPoint, quad: staleObjectCanvasQuad) < 14.0,
            "old storage/object hit layer would treat the mapped point as an edge hit"
        )
        try assertTrue(
            AnyUprightGeometry.distanceToQuadEdge(from: incorrectlyMappedCanvasPoint, quad: visibleQuad) > 24.0,
            "mapped point is not near the visible Inner Stretch control layer"
        )
        try assertTrue(
            !shouldIncludeMappedSurfaceOSCCandidate(
                forInitialEventPoint: rawEventAboveVisibleFrame,
                mappedCanvasPoint: incorrectlyMappedCanvasPoint,
                canvasFrame: finalCutCanvasFrame,
                visibleControlPoints: finalCutVisibleInnerStretch,
                hitPadding: 24.0
            ),
            "raw Final Cut events above the visible controls should not be folded into a hidden mapped hit layer"
        )
    }

    static func testFinalCutHostDisablesMappedSurfaceOSCHitFallback() throws {
        let finalCutCanvasFrame = [
            AUPoint(x: 580.0, y: 876.0),
            AUPoint(x: 1604.0, y: 876.0),
            AUPoint(x: 1604.0, y: 336.0),
            AUPoint(x: 580.0, y: 336.0)
        ]
        let finalCutVisibleInnerStretch = [
            AUPoint(x: 778.5, y: 526.0),
            AUPoint(x: 1268.2, y: 513.3),
            AUPoint(x: 1273.2, y: 879.4),
            AUPoint(x: 790.8, y: 817.8)
        ]
        let mapper = try unwrap(
            AUCanvasSurfaceMapper(canvasFrame: finalCutCanvasFrame, surfaceSize: AUSize(width: 2184.0, height: 1212.0)),
            "canvas mapper"
        )
        let motionStyleEvent = mapper.eventPoint(fromCanvasPoint: finalCutVisibleInnerStretch[0])
        let mappedCanvasPoint = mapper.canvasPoint(fromEventPoint: motionStyleEvent)

        try assertTrue(
            shouldUseMappedSurfaceOSCEvent(
                forInitialEventPoint: motionStyleEvent,
                mappedCanvasPoint: mappedCanvasPoint,
                canvasFrame: finalCutCanvasFrame,
                visibleControlPoints: finalCutVisibleInnerStretch,
                hitPadding: 24.0,
                hostBundleIdentifier: "com.apple.Motion"
            ),
            "Motion host should keep the mapped-surface compatibility path"
        )
        try assertTrue(
            !shouldUseMappedSurfaceOSCEvent(
                forInitialEventPoint: motionStyleEvent,
                mappedCanvasPoint: mappedCanvasPoint,
                canvasFrame: finalCutCanvasFrame,
                visibleControlPoints: finalCutVisibleInnerStretch,
                hitPadding: 24.0,
                hostBundleIdentifier: "com.apple.FinalCutApp"
            ),
            "Final Cut host should not fold raw canvas events into a hidden mapped hit layer"
        )
    }

    static func testHostCanvasPixelsStayAbsoluteForOSCOverlay() throws {
        let surfaceSize = AUSize(width: 2184.0, height: 1212.0)
        let fitTopLeft = oscSurfacePixel(
            fromHostCanvasPixel: AUPoint(x: 218.4, y: 1066.69),
            surfaceSize: surfaceSize
        )
        let centeredTopLeft = oscSurfacePixel(
            fromHostCanvasPixel: AUPoint(x: -546.4, y: 1470.0),
            surfaceSize: surfaceSize
        )
        let pannedUpTopLeft = oscSurfacePixel(
            fromHostCanvasPixel: AUPoint(x: -1502.4, y: 996.0),
            surfaceSize: surfaceSize
        )
        let pannedDownTopLeft = oscSurfacePixel(
            fromHostCanvasPixel: AUPoint(x: -1502.4, y: 1944.0),
            surfaceSize: surfaceSize
        )
        let horizontalPannedTopLeft = oscSurfacePixel(
            fromHostCanvasPixel: AUPoint(x: -1163.49, y: 1944.0),
            surfaceSize: surfaceSize
        )
        let farOutsideBottomRight = oscSurfacePixel(
            fromHostCanvasPixel: AUPoint(x: 2600.0, y: 1800.0),
            surfaceSize: surfaceSize
        )

        try assertEqual(fitTopLeft, AUPoint(x: 218.4, y: 1066.69), "fit overlay should stay in host canvas pixels")
        try assertEqual(centeredTopLeft, AUPoint(x: -546.4, y: 1470.0), "centered zoom overlay should stay in host canvas pixels")
        try assertEqual(pannedUpTopLeft, AUPoint(x: -1502.4, y: 996.0), "vertical pan should keep host canvas pixels")
        try assertEqual(pannedDownTopLeft, AUPoint(x: -1502.4, y: 1944.0), "vertical pan should keep host canvas pixels")
        try assertApprox(horizontalPannedTopLeft.x, -1163.49, "horizontal pan should keep host canvas x")
        try assertApprox(horizontalPannedTopLeft.y, 1944.0, "horizontal pan should not perturb host canvas y")
        try assertEqual(farOutsideBottomRight, AUPoint(x: 2600.0, y: 1800.0), "overlay should remain direct")
    }

    static func testOSCSurfacePixelsFlipYOnlyAtMetalVertexBoundary() throws {
        let surfaceSize = AUSize(width: 2184.0, height: 1212.0)
        let canvasPoint = AUPoint(x: -1502.4, y: 996.0)
        let surfacePoint = oscSurfacePixel(fromHostCanvasPixel: canvasPoint, surfaceSize: surfaceSize)
        let metalPoint = oscMetalCenteredPixel(fromSurfacePixel: surfacePoint, surfaceSize: surfaceSize)
        let roundTrippedSurfacePoint = oscSurfacePixel(fromMetalCenteredPixel: metalPoint, surfaceSize: surfaceSize)

        try assertEqual(surfacePoint, canvasPoint, "canvas to OSC surface should stay direct")
        try assertEqual(metalPoint, AUPoint(x: -2594.4, y: -390.0), "Metal overlay vertices should flip Y at the viewport boundary")
        try assertEqual(roundTrippedSurfacePoint, surfacePoint, "Metal centered conversion should round-trip to the same OSC surface pixel")
    }

    static func testAspectFitPixelSurfaceMapperKeepsHitTestingInsideVideoFrame() throws {
        let mapper = try unwrap(
            AUAspectFitPixelSurfaceMapper(
                coordinateSize: AUSize(width: 3840.0, height: 2160.0),
                surfaceSize: AUSize(width: 2000.0, height: 900.0)
            ),
            "aspect-fit pixel mapper"
        )

        let videoRightEdgeEvent = mapper.eventPoint(fromCoordinatePoint: AUPoint(x: 3840.0, y: 1080.0))
        let outsideLetterboxEvent = AUPoint(x: videoRightEdgeEvent.x + 30.0, y: videoRightEdgeEvent.y)
        let outsideOutputPoint = mapper.coordinatePoint(fromEventPoint: outsideLetterboxEvent)
        let roundTrippedTopLeft = mapper.coordinatePoint(
            fromEventPoint: mapper.eventPoint(fromCoordinatePoint: AUPoint(x: 384.0, y: 1944.0))
        )

        try assertApprox(mapper.coordinateFrame.minX, -480.0, "wide surface fitted min x")
        try assertApprox(mapper.coordinateFrame.maxX, 4320.0, "wide surface fitted max x")
        try assertApprox(videoRightEdgeEvent.x, 1800.0, "video right edge event x")
        try assertTrue(outsideOutputPoint.x > 3840.0, "right-side letterbox event should map outside output pixels")
        try assertEqual(roundTrippedTopLeft, AUPoint(x: 384.0, y: 1944.0), "aspect-fit mapper should round-trip OSC pixel coordinates")
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

    static func testOSCDisplayPartKeepsDragHighlightedWhenHoverStops() throws {
        let none = 0
        let hoverHandle = 1
        let dragEdge = 6

        try assertEqual(
            resolveOSCDisplayPart(hoverPart: hoverHandle, dragPart: nil, nonePart: none),
            hoverHandle,
            "hover part should display when not dragging"
        )
        try assertEqual(
            resolveOSCDisplayPart(hoverPart: none, dragPart: dragEdge, nonePart: none),
            dragEdge,
            "drag part should stay highlighted even when hover events stop during drag"
        )
        try assertEqual(
            resolveOSCDisplayPart(hoverPart: hoverHandle, dragPart: dragEdge, nonePart: none),
            dragEdge,
            "active drag part should override stale hover part"
        )
        try assertEqual(
            resolveOSCDisplayPart(hoverPart: none, dragPart: none, nonePart: none),
            none,
            "no hover and no drag should not display a highlight"
        )
    }

    static func testOutputCoordinatesKeepHostTilePaddingImageRelative() throws {
        let bounds = AnyUprightGeometry.outputCoordinateBounds(
            for: AUPixelBounds(left: -1321, bottom: -481, right: 2521, top: 1681),
            imageBounds: AUPixelBounds(left: -1320, bottom: -480, right: 2520, top: 1680)
        )

        try assertApprox(bounds.left, -1.0, "padded tile output left")
        try assertApprox(bounds.right, 3841.0, "padded tile output right")
        try assertApprox(bounds.top, -1.0, "padded tile output top")
        try assertApprox(bounds.bottom, 2161.0, "padded tile output bottom")
    }

    static func testInputTextureCoordinatesRespectHostTilePadding() throws {
        let mapping = AnyUprightGeometry.textureCoordinateMapping(
            for: AUPixelBounds(left: -1320, bottom: -480, right: 2520, top: 1680),
            tileBounds: AUPixelBounds(left: -1321, bottom: -481, right: 2521, top: 1681),
            textureSize: AUSize(width: 3842.0, height: 2162.0)
        )

        try assertEqual(mapping.imageOriginInTexture, AUPoint(x: 1.0, y: 1.0), "source image origin inside padded input texture")
        try assertApprox(mapping.textureSize.width, 3842.0, "padded input texture width")
        try assertApprox(mapping.textureSize.height, 2162.0, "padded input texture height")
    }

    static func testInnerStretchEditPreviewRequestsDestinationTile() throws {
        let imageBounds = AUPixelBounds(left: -1320, bottom: -480, right: 2520, top: 1680)
        let paddedDestinationTile = AUPixelBounds(left: -1321, bottom: -481, right: 2521, top: 1681)

        try assertEqual(
            AnyUprightGeometry.sourceTileBounds(
                for: imageBounds,
                destinationTileBounds: paddedDestinationTile,
                usesIdentityPreview: true
            ),
            paddedDestinationTile,
            "identity source preview should request the same padded tile as the destination"
        )
        try assertEqual(
            AnyUprightGeometry.sourceTileBounds(
                for: imageBounds,
                destinationTileBounds: paddedDestinationTile,
                usesIdentityPreview: false
            ),
            imageBounds,
            "warp modes still need the full source image"
        )
    }

    static func testUprightStableIdealizedImageSizeUsesPixelTransformScale() throws {
        let size = try unwrap(
            AnyUprightGeometry.stableIdealizedImageSize(
                imageBounds: AUPixelBounds(left: 0, bottom: 0, right: 112, top: 84),
                pixelTransformScaleX: 0.019608,
                pixelTransformScaleY: 0.019608
            ),
            "stable idealized size"
        )

        try assertApprox(size.width, 5712.0, "idealized width")
        try assertApprox(size.height, 4284.0, "idealized height")
    }

    static func testUprightStableIdealizedImageSizeUsesPixelTransformCenterRounding() throws {
        let size = try unwrap(
            AnyUprightGeometry.stableIdealizedImageSize(
                imageBounds: AUPixelBounds(left: 180, bottom: 5, right: 1093, top: 689),
                pixelTransformScaleX: 0.159664,
                pixelTransformScaleY: 0.159664,
                pixelTransformTranslateX: 636.999992,
                pixelTransformTranslateY: 346.999996
            ),
            "center-rounded stable idealized size"
        )

        try assertApprox(size.width, 5712.0, "center-rounded idealized width")
        try assertApprox(size.height, 4284.0, "center-rounded idealized height")
    }

    static func testUprightStableIdealizedImageSizeMergesMotionPreviewRounding() throws {
        let cached = try unwrap(
            AnyUprightGeometry.stableIdealizedImageSize(
                imageBounds: AUPixelBounds(left: 0, bottom: 0, right: 112, top: 84),
                pixelTransformScaleX: 0.019608,
                pixelTransformScaleY: 0.019608
            ),
            "cached stable idealized size"
        )
        let roundedPreview = try unwrap(
            AnyUprightGeometry.stableIdealizedImageSize(
                imageBounds: AUPixelBounds(left: 180, bottom: 5, right: 1093, top: 689),
                pixelTransformScaleX: 0.159664,
                pixelTransformScaleY: 0.159664
            ),
            "rounded preview stable idealized size"
        )

        try assertApprox(roundedPreview.width, 5712.0, "rounded preview width before merge")
        try assertApprox(roundedPreview.height, 4284.0, "rounded preview height before merge")

        let merged = AnyUprightGeometry.mergedStableIdealizedImageSize(cached: cached, candidate: roundedPreview)
        try assertApprox(merged.width, 5712.0, "merged stable width")
        try assertApprox(merged.height, 4284.0, "merged stable height")
    }

    static func testUprightStableIdealizedImageSizeMergesMotionPanRounding() throws {
        let sourceSize = AUSize(width: 5712.0, height: 4284.0)
        let panRoundedPreview = try unwrap(
            AnyUprightGeometry.stableIdealizedImageSize(
                imageBounds: AUPixelBounds(left: 129, bottom: 77, right: 1570, top: 1158),
                pixelTransformScaleX: 0.252101,
                pixelTransformScaleY: 0.252101,
                pixelTransformTranslateX: 849.250336,
                pixelTransformTranslateY: 617.899994
            ),
            "pan-rounded preview stable idealized size"
        )

        try assertApprox(panRoundedPreview.width, 5712.0, "pan-rounded preview width before merge")
        try assertApprox(panRoundedPreview.height, 4284.0, "pan-rounded preview height before merge")

        let merged = AnyUprightGeometry.mergedStableIdealizedImageSize(
            cached: sourceSize,
            candidate: panRoundedPreview
        )
        try assertApprox(merged.width, 5712.0, "merged pan-rounded stable width")
        try assertApprox(merged.height, 4284.0, "merged pan-rounded stable height")
    }

    static func testQuadInnerStretchModeShowsAdjusterBeforeApplyingWarp() throws {
        let size = AUSize(width: 200.0, height: 100.0)
        var offsets = AUCornerOffsets()
        offsets.topLeftPixels = AUPoint(x: 25.0, y: -10.0)
        offsets.topRightPixels = AUPoint(x: -15.0, y: -20.0)
        offsets.bottomRightPixels = AUPoint(x: -30.0, y: 15.0)
        offsets.bottomLeftPixels = AUPoint(x: 20.0, y: 25.0)

        let previewMatrix = AnyUprightGeometry.quadOutputToSourceMatrix(
            from: offsets,
            mode: .innerStretch,
            showCornerAdjuster: true,
            outputSize: size,
            sourceSize: size
        )

        try assertMaps(previewMatrix, AUPoint(x: 30.0, y: 40.0), to: AUPoint(x: 30.0, y: 40.0))

        let innerStretch = AnyUprightGeometry.innerStretch(from: offsets, size: size)
        let appliedMatrix = AnyUprightGeometry.quadOutputToSourceMatrix(
            from: offsets,
            mode: .innerStretch,
            showCornerAdjuster: false,
            outputSize: size,
            sourceSize: size
        )

        try assertMaps(appliedMatrix, AUPoint(x: 0.0, y: 0.0), to: innerStretch.topLeft)
        try assertMaps(appliedMatrix, AUPoint(x: size.width, y: 0.0), to: innerStretch.topRight)
        try assertMaps(appliedMatrix, AUPoint(x: size.width, y: size.height), to: innerStretch.bottomRight)
        try assertMaps(appliedMatrix, AUPoint(x: 0.0, y: size.height), to: innerStretch.bottomLeft)
    }

    static func testHorizonFillScaleOnlyZoomsWhenNeeded() throws {
        let size = AUSize(width: 1920.0, height: 1080.0)

        try assertApprox(AnyUprightGeometry.rotationScaleToFill(angleRadians: 0.0, size: size), 1.0, "zero-degree fill scale")
        try assertTrue(AnyUprightGeometry.rotationScaleToFill(angleRadians: Double.pi / 18.0, size: size) > 1.0, "nonzero rotation should zoom to fill")
    }

    static func testAutoCropScalesWarpedOutputIntoSourceFrame() throws {
        let size = AUSize(width: 1920.0, height: 1080.0)
        let correction = AnyUprightGeometry.rotationOutputToSource(
            angleRadians: degreesToRadians(10.0),
            fillFrame: false,
            size: size
        )

        let scale = AnyUprightGeometry.autoCropScale(for: correction, outputSize: size, sourceSize: size)
        let cropped = AnyUprightGeometry.autoCropOutputToSourceMatrix(correction, outputSize: size, sourceSize: size)

        try assertTrue(scale > 1.0, "non-identity correction should require auto-crop zoom")
        try assertOutputFrameMapsInsideSource(cropped, outputSize: size, sourceSize: size, label: "auto-cropped correction")
    }

    static func testAutoCropDoesNotForceMaximumScaleWhenNoCropCanFill() throws {
        let size = AUSize(width: 200.0, height: 100.0)
        let impossible = simd_float3x3(columns: (
            SIMD3<Float>(1.0, 0.0, 0.0),
            SIMD3<Float>(0.0, 1.0, 0.0),
            SIMD3<Float>(500.0, 0.0, 1.0)
        ))

        let scale = AnyUprightGeometry.autoCropScale(
            for: impossible,
            outputSize: size,
            sourceSize: size,
            maximumScale: 8.0
        )
        let cropped = AnyUprightGeometry.autoCropOutputToSourceMatrix(
            impossible,
            outputSize: size,
            sourceSize: size,
            maximumScale: 8.0
        )

        try assertApprox(scale, 1.0, "impossible auto-crop should not force max zoom")
        try assertMaps(cropped, AUPoint(x: 0.0, y: 0.0), to: AUPoint(x: 500.0, y: 0.0))
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

    static func testSupportedLineDetectorReturnsFiniteSegments() throws {
        let image = horizontalSegmentImage(width: 120, height: 80)
        let lines = AnyUprightLineDetection.detectSupportedLineSegments(
            in: image,
            options: AULineDetectionOptions(
                orientation: .horizontal,
                edgeThreshold: 20.0,
                voteThreshold: 12,
                maxLines: 4
            )
        )

        let line = try unwrap(lines.first, "supported horizontal segment")

        try assertTrue(line.line.length > 35.0, "supported segment should keep the visible edge span")
        try assertTrue(line.line.length < 90.0, "supported segment should not expand to the full image width")
        try assertTrue(line.score > 0.0, "supported segment should carry a positive score")
    }

    static func testUprightCandidateSelectionLimitsToTwoAndConvertsCoordinates() throws {
        let specs = AnyUprightUprightCandidates.specs
        let candidates = [
            uprightCandidateLine(
                spec: specs[0],
                selected: true,
                orientation: .vertical,
                start: AUPoint(x: 0.20, y: 0.80),
                end: AUPoint(x: 0.20, y: 0.20)
            ),
            uprightCandidateLine(
                spec: specs[1],
                selected: true,
                orientation: .vertical,
                start: AUPoint(x: 0.40, y: 0.70),
                end: AUPoint(x: 0.40, y: 0.30)
            ),
            uprightCandidateLine(
                spec: specs[2],
                selected: true,
                orientation: .vertical,
                start: AUPoint(x: 0.60, y: 0.70),
                end: AUPoint(x: 0.60, y: 0.30)
            ),
            uprightCandidateLine(
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

    static func testUprightAutomaticSelectionChoosesTopTwoIncludedCandidates() throws {
        let candidates = [
            UprightDetectedCandidate(
                orientation: .vertical,
                start: AUPoint(x: 0.1, y: 0.2),
                end: AUPoint(x: 0.1, y: 0.8),
                score: 0.4
            ),
            UprightDetectedCandidate(
                orientation: .horizontal,
                start: AUPoint(x: 0.2, y: 0.4),
                end: AUPoint(x: 0.8, y: 0.4),
                score: 0.9
            ),
            UprightDetectedCandidate(
                orientation: .vertical,
                start: AUPoint(x: 0.3, y: 0.2),
                end: AUPoint(x: 0.3, y: 0.8),
                score: 0.8
            ),
            UprightDetectedCandidate(
                orientation: .horizontal,
                start: AUPoint(x: 0.2, y: 0.6),
                end: AUPoint(x: 0.8, y: 0.6),
                score: 0.7
            )
        ]

        let full = AnyUprightUprightCandidates.automaticSelectedIndexes(from: candidates, correctionMode: .full)
        let vertical = AnyUprightUprightCandidates.automaticSelectedIndexes(from: candidates, correctionMode: .vertical)

        try assertTrue(full == Set([1, 2]), "full automatic should choose top two included scores overall")
        try assertTrue(vertical == Set([0, 2]), "vertical automatic should choose top two vertical scores")
    }

    static func testUprightCandidateToggleSelectionStopsAtTwoPerOrientation() throws {
        let specs = AnyUprightUprightCandidates.specs
        let selectedA = uprightCandidateLine(
            spec: specs[0],
            selected: true,
            orientation: .vertical,
            start: AUPoint(x: 0.10, y: 0.20),
            end: AUPoint(x: 0.10, y: 0.80)
        )
        let selectedB = uprightCandidateLine(
            spec: specs[1],
            selected: true,
            orientation: .vertical,
            start: AUPoint(x: 0.30, y: 0.20),
            end: AUPoint(x: 0.30, y: 0.80)
        )
        let unselectedVertical = uprightCandidateLine(
            spec: specs[2],
            selected: false,
            orientation: .vertical,
            start: AUPoint(x: 0.50, y: 0.20),
            end: AUPoint(x: 0.50, y: 0.80)
        )
        let unselectedHorizontal = uprightCandidateLine(
            spec: specs[3],
            selected: false,
            orientation: .horizontal,
            start: AUPoint(x: 0.20, y: 0.50),
            end: AUPoint(x: 0.80, y: 0.50)
        )

        let candidates = [selectedA, selectedB, unselectedVertical, unselectedHorizontal]

        try assertTrue(
            !AnyUprightUprightCandidates.selectionValueAfterToggling(selectedA, within: candidates, correctionMode: .full),
            "selected candidate toggles off"
        )
        try assertTrue(
            !AnyUprightUprightCandidates.selectionValueAfterToggling(unselectedVertical, within: candidates, correctionMode: .full),
            "third vertical candidate should stay unselected"
        )
        try assertTrue(
            AnyUprightUprightCandidates.selectionValueAfterToggling(unselectedHorizontal, within: candidates, correctionMode: .full),
            "different orientation can still be selected"
        )
        try assertTrue(
            !AnyUprightUprightCandidates.selectionValueAfterToggling(unselectedHorizontal, within: candidates, correctionMode: .vertical),
            "excluded orientation should stay unselected"
        )
    }

    static func testUprightCandidateDisplayHonorsControlAndCorrectionMode() throws {
        let specs = AnyUprightUprightCandidates.specs
        let lowScore = uprightCandidateLine(
            spec: specs[0],
            selected: false,
            orientation: .vertical,
            start: AUPoint(x: 0.1, y: 0.2),
            end: AUPoint(x: 0.1, y: 0.8),
            score: 0.3
        )
        let selectedLowScore = uprightCandidateLine(
            spec: specs[1],
            selected: true,
            orientation: .vertical,
            start: AUPoint(x: 0.2, y: 0.2),
            end: AUPoint(x: 0.2, y: 0.8),
            score: 0.1
        )
        let highScore = uprightCandidateLine(
            spec: specs[2],
            selected: false,
            orientation: .horizontal,
            start: AUPoint(x: 0.2, y: 0.5),
            end: AUPoint(x: 0.8, y: 0.5),
            score: 0.8
        )
        let candidates = [lowScore, selectedLowScore, highScore]

        try assertEqual(
            AnyUprightUprightCandidates.displayCandidates(from: candidates, controlMode: .manual, correctionMode: .full).count,
            0,
            "manual mode hides detected candidates"
        )

        let semiVertical = AnyUprightUprightCandidates.displayCandidates(
            from: candidates,
            controlMode: .semiAutomatic,
            correctionMode: .vertical
        )
        try assertEqual(semiVertical.count, 2, "semi-auto vertical shows analyzed vertical candidates")
        try assertTrue(semiVertical.allSatisfy { $0.orientation == .vertical }, "semi-auto vertical hides horizontal candidates")

        let semiFull = AnyUprightUprightCandidates.displayCandidates(
            from: candidates,
            controlMode: .semiAutomatic,
            correctionMode: .full
        )
        try assertEqual(semiFull.count, 3, "semi-auto full shows all included analyzed candidates")

        let automatic = AnyUprightUprightCandidates.displayCandidates(
            from: candidates,
            controlMode: .automatic,
            correctionMode: .full
        )
        try assertEqual(automatic.count, 1, "automatic display shows only persisted selected candidates")
        try assertTrue(automatic.contains { $0.spec.linePart == selectedLowScore.spec.linePart }, "selected candidate remains visible")
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

    static func testUprightManualGuideImageLineFlipsObjectY() throws {
        let manualLine = AULineSegment(
            start: AUPoint(x: 0.2, y: 0.3),
            end: AUPoint(x: 0.4, y: 0.8)
        )

        let imageLine = AnyUprightUprightCandidates.imageLine(
            fromManualGuide: manualLine,
            size: AUSize(width: 100.0, height: 200.0)
        )

        try assertEqual(imageLine.start, AUPoint(x: 20.0, y: 140.0), "manual guide image start")
        try assertEqual(imageLine.end, AUPoint(x: 40.0, y: 40.0), "manual guide image end")
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

    static func testUprightCorrectionValuesDeriveFromCurrentReferences() throws {
        let size = AUSize(width: 1.0, height: 1.0)
        let expectedVertical = 0.35
        let expectedHorizontal = -0.25
        let verticalOutput = AULineSegment(
            start: AUPoint(x: 0.35, y: 0.15),
            end: AUPoint(x: 0.35, y: 0.85)
        )
        let horizontalOutput = AULineSegment(
            start: AUPoint(x: 0.15, y: 0.40),
            end: AUPoint(x: 0.85, y: 0.40)
        )
        let verticalOutputToSource = AnyUprightGeometry.homography(
            from: AnyUprightGeometry.uprightQuad(vertical: expectedVertical, horizontal: 0.0, size: size),
            to: AUQuad.fullFrame(size)
        )
        let horizontalOutputToSource = AnyUprightGeometry.homography(
            from: AnyUprightGeometry.uprightQuad(vertical: 0.0, horizontal: expectedHorizontal, size: size),
            to: AUQuad.fullFrame(size)
        )
        let verticalSource = AnyUprightGeometry.transform(verticalOutput, by: verticalOutputToSource)
        let horizontalSource = AnyUprightGeometry.transform(horizontalOutput, by: horizontalOutputToSource)

        let full = AnyUprightUprightCandidates.correctionValues(
            verticalLines: [verticalSource],
            horizontalLines: [horizontalSource],
            correctionMode: .full
        )
        let verticalOnly = AnyUprightUprightCandidates.correctionValues(
            verticalLines: [verticalSource],
            horizontalLines: [horizontalSource],
            correctionMode: .vertical
        )

        try assertApprox(full.verticalPerspective, expectedVertical, "full vertical reference correction", accuracy: 0.02)
        try assertApprox(full.horizontalPerspective, expectedHorizontal, "full horizontal reference correction", accuracy: 0.02)
        try assertApprox(verticalOnly.verticalPerspective, expectedVertical, "vertical mode keeps vertical reference", accuracy: 0.02)
        try assertApprox(verticalOnly.horizontalPerspective, 0.0, "vertical mode ignores horizontal reference")
    }

    static func testVerticalUprightCorrectionStraightensReferenceLines() throws {
        let size = AUSize(width: 1000.0, height: 1000.0)
        let sourceLines = [
            AULineSegment(
                start: AUPoint(x: 240.0, y: 140.0),
                end: AUPoint(x: 300.0, y: 840.0)
            ),
            AULineSegment(
                start: AUPoint(x: 760.0, y: 140.0),
                end: AUPoint(x: 700.0, y: 840.0)
            )
        ]
        let normalizedLines = sourceLines.map { line in
            AULineSegment(
                start: AUPoint(x: line.start.x / size.width, y: line.start.y / size.height),
                end: AUPoint(x: line.end.x / size.width, y: line.end.y / size.height)
            )
        }
        let correction = AnyUprightUprightCandidates.correctionValues(
            verticalLines: normalizedLines,
            horizontalLines: [],
            correctionMode: .vertical
        )
        let outputToSource = AnyUprightGeometry.uprightOutputToSourceMatrix(
            vertical: correction.verticalPerspective,
            horizontal: 0.0,
            size: size
        )
        let sourceToOutput = simd_inverse(outputToSource)
        let correctedLines = sourceLines.map {
            AnyUprightGeometry.transform($0, by: sourceToOutput)
        }

        try assertTrue(
            meanVerticalDeviation(correctedLines) < meanVerticalDeviation(sourceLines) * 0.25,
            "vertical upright correction should make selected vertical references substantially straighter"
        )
    }

    static func testMotionManualVerticalGuidesUseObjectY() throws {
        let manualGuideLines = [
            AULineSegment(
                start: AUPoint(x: 0.12000582870687918, y: 0.4439647351031818),
                end: AUPoint(x: 0.079615545853546854, y: 0.7493946548715269)
            ),
            AULineSegment(
                start: AUPoint(x: 0.79611260802409756, y: 0.4675621403700746),
                end: AUPoint(x: 0.87551399334079938, y: 0.78371711509750985)
            )
        ]
        let imageLines = manualGuideLines.map {
            AULineSegment(
                start: AUPoint(x: $0.start.x, y: 1.0 - $0.start.y),
                end: AUPoint(x: $0.end.x, y: 1.0 - $0.end.y)
            )
        }

        let manualCorrection = AnyUprightUprightCandidates.correctionValues(
            verticalLines: imageLines,
            horizontalLines: [],
            correctionMode: .vertical
        )
        let unflippedCorrection = AnyUprightUprightCandidates.correctionValues(
            verticalLines: manualGuideLines,
            horizontalLines: [],
            correctionMode: .vertical
        )

        try assertTrue(manualCorrection.verticalPerspective > 0.0, "manual object-space guides produce positive vertical correction")
        try assertTrue(unflippedCorrection.verticalPerspective < 0.0, "image-space interpretation would produce the old opposite sign")

        let size = AUSize(width: 1920.0, height: 1080.0)
        let sourceLines = imageLines.map {
            AULineSegment(
                start: AUPoint(x: $0.start.x * size.width, y: $0.start.y * size.height),
                end: AUPoint(x: $0.end.x * size.width, y: $0.end.y * size.height)
            )
        }
        let sourceToOutput = simd_inverse(AnyUprightGeometry.uprightOutputToSourceMatrix(
            vertical: manualCorrection.verticalPerspective,
            horizontal: 0.0,
            size: size
        ))
        let oldSourceToOutput = simd_inverse(AnyUprightGeometry.uprightOutputToSourceMatrix(
            vertical: unflippedCorrection.verticalPerspective,
            horizontal: 0.0,
            size: size
        ))
        let correctedLines = sourceLines.map {
            AnyUprightGeometry.transform($0, by: sourceToOutput)
        }
        let oldCorrectedLines = sourceLines.map {
            AnyUprightGeometry.transform($0, by: oldSourceToOutput)
        }
        let originalDeviation = meanVerticalDeviation(sourceLines)
        let correctedDeviation = meanVerticalDeviation(correctedLines)
        let oldCorrectedDeviation = meanVerticalDeviation(oldCorrectedLines)

        try assertTrue(
            correctedDeviation < originalDeviation * 0.50,
            "manual object-space guide correction should make Motion guide lines substantially more vertical"
        )
        try assertTrue(
            oldCorrectedDeviation > originalDeviation,
            "old image-space Y interpretation should worsen the current Motion guide lines"
        )
    }

    static func testVerticalUprightCorrectionKeepsNormalizedGuideMeaningAcrossAspectRatios() throws {
        let correction = AnyUprightUprightCandidates.correctionValues(
            verticalLines: [
                AULineSegment(
                    start: AUPoint(x: 0.11908, y: 0.55827),
                    end: AUPoint(x: 0.06161, y: 0.17369)
                ),
                AULineSegment(
                    start: AUPoint(x: 0.79465, y: 0.54537),
                    end: AUPoint(x: 0.86840, y: 0.22969)
                )
            ],
            horizontalLines: [],
            correctionMode: .vertical
        )

        for size in [
            AUSize(width: 1000.0, height: 1000.0),
            AUSize(width: 1920.0, height: 1080.0),
            AUSize(width: 4032.0, height: 3024.0),
            AUSize(width: 3024.0, height: 4032.0)
        ] {
            let sourceLines = [
                AULineSegment(
                    start: AUPoint(x: 0.11908 * size.width, y: 0.55827 * size.height),
                    end: AUPoint(x: 0.06161 * size.width, y: 0.17369 * size.height)
                ),
                AULineSegment(
                    start: AUPoint(x: 0.79465 * size.width, y: 0.54537 * size.height),
                    end: AUPoint(x: 0.86840 * size.width, y: 0.22969 * size.height)
                )
            ]
            let sourceToOutput = simd_inverse(AnyUprightGeometry.uprightOutputToSourceMatrix(
                vertical: correction.verticalPerspective,
                horizontal: 0.0,
                size: size
            ))
            let correctedLines = sourceLines.map {
                AnyUprightGeometry.transform($0, by: sourceToOutput)
            }

            try assertTrue(
                meanVerticalDeviation(correctedLines) < meanVerticalDeviation(sourceLines) * 0.40,
                "vertical correction should retain normalized guide meaning for \(size)"
            )
        }
    }

    static func testHorizontalUprightCorrectionKeepsNormalizedGuideMeaningAcrossAspectRatios() throws {
        let correction = AnyUprightUprightCandidates.correctionValues(
            verticalLines: [],
            horizontalLines: [
                AULineSegment(
                    start: AUPoint(x: 0.16700, y: 0.26500),
                    end: AUPoint(x: 0.84100, y: 0.19800)
                ),
                AULineSegment(
                    start: AUPoint(x: 0.18200, y: 0.76200),
                    end: AUPoint(x: 0.82500, y: 0.82900)
                )
            ],
            correctionMode: .horizontal
        )

        for size in [
            AUSize(width: 1000.0, height: 1000.0),
            AUSize(width: 1920.0, height: 1080.0),
            AUSize(width: 4032.0, height: 3024.0),
            AUSize(width: 3024.0, height: 4032.0)
        ] {
            let sourceLines = [
                AULineSegment(
                    start: AUPoint(x: 0.16700 * size.width, y: 0.26500 * size.height),
                    end: AUPoint(x: 0.84100 * size.width, y: 0.19800 * size.height)
                ),
                AULineSegment(
                    start: AUPoint(x: 0.18200 * size.width, y: 0.76200 * size.height),
                    end: AUPoint(x: 0.82500 * size.width, y: 0.82900 * size.height)
                )
            ]
            let sourceToOutput = simd_inverse(AnyUprightGeometry.uprightOutputToSourceMatrix(
                vertical: 0.0,
                horizontal: correction.horizontalPerspective,
                size: size
            ))
            let correctedLines = sourceLines.map {
                AnyUprightGeometry.transform($0, by: sourceToOutput)
            }

            try assertTrue(
                meanHorizontalDeviation(correctedLines) < meanHorizontalDeviation(sourceLines) * 0.40,
                "horizontal correction should retain normalized guide meaning for \(size)"
            )
        }
    }

    static func testUprightAppliedCorrectionIsStableAcrossPreviewOutputSizes() throws {
        let sourceSize = AUSize(width: 1920.0, height: 1080.0)
        let vertical = -0.37
        let horizontal = 0.12
        let rotation = degreesToRadians(2.0)
        let reference = AnyUprightGeometry.uprightAppliedOutputToSourceMatrix(
            vertical: vertical,
            horizontal: horizontal,
            rotationRadians: rotation,
            fillFrame: true,
            outputSize: sourceSize,
            sourceSize: sourceSize
        )
        let normalizedSamples = [
            AUPoint(x: 0.0, y: 0.0),
            AUPoint(x: 1.0, y: 0.0),
            AUPoint(x: 1.0, y: 1.0),
            AUPoint(x: 0.0, y: 1.0),
            AUPoint(x: 0.5, y: 0.5),
            AUPoint(x: 0.18, y: 0.31),
            AUPoint(x: 0.82, y: 0.69)
        ]

        for outputSize in [
            AUSize(width: 960.0, height: 540.0),
            AUSize(width: 854.0, height: 480.0),
            AUSize(width: 853.0, height: 480.0),
            AUSize(width: 641.0, height: 360.0),
            AUSize(width: 640.0, height: 361.0)
        ] {
            let matrix = AnyUprightGeometry.uprightAppliedOutputToSourceMatrix(
                vertical: vertical,
                horizontal: horizontal,
                rotationRadians: rotation,
                fillFrame: true,
                outputSize: outputSize,
                sourceSize: sourceSize
            )

            for sample in normalizedSamples {
                let referenceOutput = AUPoint(
                    x: sample.x * sourceSize.width,
                    y: sample.y * sourceSize.height
                )
                let previewOutput = AUPoint(
                    x: sample.x * outputSize.width,
                    y: sample.y * outputSize.height
                )
                let expected = AnyUprightGeometry.transform(referenceOutput, by: reference)
                let actual = AnyUprightGeometry.transform(previewOutput, by: matrix)

                try assertApprox(actual.x, expected.x, "upright preview-size stable x for \(outputSize) sample \(sample)", accuracy: 0.02)
                try assertApprox(actual.y, expected.y, "upright preview-size stable y for \(outputSize) sample \(sample)", accuracy: 0.02)
            }
        }
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

    static func assertOutputFrameMapsInsideSource(_ matrix: simd_float3x3, outputSize: AUSize, sourceSize: AUSize, label: String) throws {
        let corners = [
            AUPoint(x: 0.0, y: 0.0),
            AUPoint(x: outputSize.width, y: 0.0),
            AUPoint(x: outputSize.width, y: outputSize.height),
            AUPoint(x: 0.0, y: outputSize.height)
        ]

        for corner in corners {
            let mapped = AnyUprightGeometry.transform(corner, by: matrix)
            try assertTrue(
                mapped.x >= -0.5
                    && mapped.y >= -0.5
                    && mapped.x <= sourceSize.width + 0.5
                    && mapped.y <= sourceSize.height + 0.5,
                "\(label) maps \(corner) inside source, got \(mapped)"
            )
        }
    }

    static func meanVerticalDeviation(_ lines: [AULineSegment]) -> Double {
        guard !lines.isEmpty else {
            return 0.0
        }

        let total = lines.reduce(0.0) { partial, line in
            let dx = abs(line.end.x - line.start.x)
            let dy = abs(line.end.y - line.start.y)
            return partial + atan2(dx, max(dy, 0.000001))
        }
        return total / Double(lines.count)
    }

    static func meanHorizontalDeviation(_ lines: [AULineSegment]) -> Double {
        guard !lines.isEmpty else {
            return 0.0
        }

        let total = lines.reduce(0.0) { partial, line in
            let dx = abs(line.end.x - line.start.x)
            let dy = abs(line.end.y - line.start.y)
            return partial + atan2(dy, max(dx, 0.000001))
        }
        return total / Double(lines.count)
    }

    static func assertEqual(_ actual: AUPoint, _ expected: AUPoint, _ label: String) throws {
        try assertApprox(actual.x, expected.x, "\(label) x")
        try assertApprox(actual.y, expected.y, "\(label) y")
    }

    static func assertEqual(_ actual: AUPixelBounds, _ expected: AUPixelBounds, _ label: String) throws {
        guard actual == expected else {
            throw TestFailure.failed("\(label): expected \(expected), got \(actual)")
        }
    }

    static func fullFrameSourceOffsets() -> AUCornerOffsets {
        AUCornerOffsets(
            topLeftPercent: AUPoint(x: -0.10, y: 0.10),
            topRightPercent: AUPoint(x: 0.10, y: 0.10),
            bottomRightPercent: AUPoint(x: 0.10, y: -0.10),
            bottomLeftPercent: AUPoint(x: -0.10, y: -0.10)
        )
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

    static func horizontalSegmentImage(width: Int, height: Int) -> AUGrayscaleImage {
        var image = AUGrayscaleImage(width: width, height: height, pixels: Array(repeating: 0, count: width * height))
        for y in 24..<56 {
            for x in 32..<88 {
                image.pixels[y * width + x] = 255
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

    static func uprightCandidateLine(
        spec: UprightCandidateSpec,
        selected: Bool,
        orientation: UprightGuideOrientation,
        start: AUPoint,
        end: AUPoint,
        score: Double = 1.0
    ) -> UprightCandidateLine {
        UprightCandidateLine(
            spec: spec,
            selected: selected,
            orientation: orientation,
            start: start,
            end: end,
            score: score
        )
    }
}
