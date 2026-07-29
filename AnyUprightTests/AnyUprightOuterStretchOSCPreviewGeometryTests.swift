import Foundation

private enum TestFailure: Error {
    case failed(String)
}

private func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else {
        throw TestFailure.failed(message)
    }
}

@main
struct AnyUprightOuterStretchOSCPreviewGeometryTests {
    static func main() throws {
        let fullFrameObjectCorners = AUStretchCorners(
            topLeft: AUPoint(x: 0.0, y: 1.0),
            topRight: AUPoint(x: 1.0, y: 1.0),
            bottomRight: AUPoint(x: 1.0, y: 0.0),
            bottomLeft: AUPoint(x: 0.0, y: 0.0)
        )
        try require(
            !AUOuterStretchOSCPreviewRenderPolicy.allowsStaleFallback(
                objectCorners: fullFrameObjectCorners
            ),
            "an in-canvas undo state must not reuse an exterior preview"
        )
        try require(
            AUOuterStretchOSCPreviewRenderPolicy.shouldInvalidateCache(
                objectCorners: fullFrameObjectCorners
            ),
            "an in-canvas state must end the previous exterior preview lifecycle"
        )
        for outsideCorner in [
            AUPoint(x: -0.1, y: 1.0),
            AUPoint(x: 1.1, y: 1.0),
            AUPoint(x: 0.0, y: 1.1),
            AUPoint(x: 0.0, y: -0.1),
            AUPoint(x: -Double.ulpOfOne, y: 1.0)
        ] {
            let corners = AUStretchCorners(
                topLeft: outsideCorner,
                topRight: fullFrameObjectCorners.topRight,
                bottomRight: fullFrameObjectCorners.bottomRight,
                bottomLeft: fullFrameObjectCorners.bottomLeft
            )
            try require(
                AUOuterStretchOSCPreviewRenderPolicy.allowsStaleFallback(
                    objectCorners: corners
                ),
                "an exterior current state must allow a transition preview"
            )
            try require(
                !AUOuterStretchOSCPreviewRenderPolicy.shouldInvalidateCache(
                    objectCorners: corners
                ),
                "an exterior current state must retain its transition preview"
            )
        }

        try require(
            AUOuterStretchOSCPreviewRenderPolicy.shouldEncode(
                outputSize: AUSize(width: 112.0, height: 84.0)
            ),
            "the small Motion interaction render must encode a preview"
        )
        try require(
            AUOuterStretchOSCPreviewRenderPolicy.shouldEncode(
                outputSize: AUSize(width: 512.0, height: 512.0)
            ),
            "a 512x512 output must encode a preview"
        )
        try require(
            AUOuterStretchOSCPreviewRenderPolicy.shouldEncode(
                outputSize: AUSize(width: 2880.0, height: 2160.0)
            ),
            "the full-size Motion render must encode a preview"
        )
        try require(
            !AUOuterStretchOSCPreviewRenderPolicy.shouldEncode(
                outputSize: AUSize(width: 0.0, height: 2160.0)
            ),
            "an empty output must not encode a preview"
        )
        try require(
            AUOuterStretchOSCPreviewRenderPolicy.shouldReplace(
                candidateOutputSize: AUSize(width: 2880.0, height: 2160.0),
                existingOutputSize: AUSize(width: 112.0, height: 84.0),
                hasMatchingSignature: false
            ),
            "a full-size preview must replace a proxy-size preview"
        )
        try require(
            !AUOuterStretchOSCPreviewRenderPolicy.shouldReplace(
                candidateOutputSize: AUSize(width: 112.0, height: 84.0),
                existingOutputSize: AUSize(width: 2880.0, height: 2160.0),
                hasMatchingSignature: false
            ),
            "a proxy-size preview for a new signature must not replace a full-size preview"
        )
        try require(
            AUOuterStretchOSCPreviewRenderPolicy.shouldReplace(
                candidateOutputSize: AUSize(width: 2880.0, height: 2160.0),
                existingOutputSize: AUSize(width: 2880.0, height: 2160.0),
                hasMatchingSignature: false
            ),
            "a full-size preview for a new signature must replace stale geometry"
        )
        try require(
            !AUOuterStretchOSCPreviewRenderPolicy.shouldReplace(
                candidateOutputSize: AUSize(width: 2880.0, height: 2160.0),
                existingOutputSize: AUSize(width: 2880.0, height: 2160.0),
                hasMatchingSignature: true
            ),
            "an equal-quality duplicate must not replace the current preview"
        )

        let layout = AUOuterStretchOSCPreviewLayout.make(
            corners: AUStretchCorners(
                topLeft: AUPoint(x: -100.0, y: -100.0),
                topRight: AUPoint(x: 2880.0, y: 0.0),
                bottomRight: AUPoint(x: 3000.0, y: 2160.0),
                bottomLeft: AUPoint(x: 0.0, y: 2300.0)
            ),
            outputSize: AUSize(width: 2880.0, height: 2160.0)
        )
        try require(
            layout?.textureWidth == 3100 && layout?.textureHeight == 2400,
            "the OSC texture must preserve the full physical preview bounds"
        )
        print("AnyUprightOuterStretchOSCPreviewGeometryTests passed")
    }
}
