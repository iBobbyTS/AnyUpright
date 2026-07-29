//
//  AnyUprightStretchOSCEventPolicyTests.swift
//  AnyUprightTests
//

import Foundation

private enum StretchOSCEventPolicyTestFailure: Error {
    case failed(String)
}

@main
private enum AnyUprightStretchOSCEventPolicyTests {
    static func main() throws {
        let canvasFrame = [
            AUPoint(x: 531.1, y: 791.2),
            AUPoint(x: 1811.1, y: 791.2),
            AUPoint(x: 1811.1, y: 71.2),
            AUPoint(x: 531.1, y: 71.2)
        ]
        let visibleControls = [
            AUPoint(x: 659.1, y: 719.2),
            AUPoint(x: 1683.1, y: 719.2),
            AUPoint(x: 1683.1, y: 143.2),
            AUPoint(x: 659.1, y: 143.2)
        ]
        let mapper = try requireValue(
            AUCanvasSurfaceMapper(
                canvasFrame: canvasFrame,
                surfaceSize: AUSize(width: 1670.0, height: 844.0)
            ),
            "canvas mapper"
        )

        // This is a raw CANVAS point in the left black bar. The legacy
        // surface-local interpretation folds it into the visible quad.
        let offFrameRawPoint = AUPoint(x: 400.0, y: 400.0)
        let incorrectlyMappedPoint = mapper.canvasPoint(fromEventPoint: offFrameRawPoint)
        try require(
            !isPointInsideAxisAlignedFrame(offFrameRawPoint, frame: canvasFrame),
            "fixture point must remain outside the canvas frame"
        )
        try require(
            isPointInsideAxisAlignedFrame(incorrectlyMappedPoint, frame: visibleControls),
            "legacy mapping must reproduce the invisible hit layer"
        )
        try require(
            !shouldUseMappedSurfaceOSCEvent(
                forInitialEventPoint: offFrameRawPoint,
                mappedCanvasPoint: incorrectlyMappedPoint,
                canvasFrame: canvasFrame,
                visibleControlPoints: visibleControls,
                hitPadding: 24.0,
                hostBundleIdentifier: "com.apple.MotionAppApp"
            ),
            "Motion must preserve the off-frame raw CANVAS point"
        )
        try require(
            !shouldUseMappedSurfaceOSCEvent(
                forInitialEventPoint: offFrameRawPoint,
                mappedCanvasPoint: incorrectlyMappedPoint,
                canvasFrame: canvasFrame,
                visibleControlPoints: visibleControls,
                hitPadding: 24.0,
                hostBundleIdentifier: "com.apple.Motion"
            ),
            "legacy Motion identifiers must also use raw CANVAS points"
        )
        try require(
            !shouldUseMappedSurfaceOSCEvent(
                forInitialEventPoint: offFrameRawPoint,
                mappedCanvasPoint: incorrectlyMappedPoint,
                canvasFrame: canvasFrame,
                visibleControlPoints: visibleControls,
                hitPadding: 24.0,
                hostBundleIdentifier: nil
            ),
            "missing host identity must fail closed to raw CANVAS points"
        )

        print("AnyUprightStretchOSCEventPolicyTests passed")
    }

    private static func require(_ condition: Bool, _ message: String) throws {
        guard condition else {
            throw StretchOSCEventPolicyTestFailure.failed(message)
        }
    }

    private static func requireValue<T>(_ value: T?, _ label: String) throws -> T {
        guard let value else {
            throw StretchOSCEventPolicyTestFailure.failed("Missing \(label)")
        }
        return value
    }
}
