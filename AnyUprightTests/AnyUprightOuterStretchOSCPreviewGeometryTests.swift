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
            "the configured preview limit must be inclusive"
        )
        try require(
            !AUOuterStretchOSCPreviewRenderPolicy.shouldEncode(
                outputSize: AUSize(width: 2880.0, height: 2160.0)
            ),
            "the full-size Motion render must not replace the low-resolution preview"
        )
        print("AnyUprightOuterStretchOSCPreviewGeometryTests passed")
    }
}
