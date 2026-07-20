import Foundation

private enum ScaleLSDProductionTestFailure: Error, CustomStringConvertible {
    case failed(String)

    var description: String {
        switch self {
        case .failed(let message): return message
        }
    }
}

@main
struct AnyUprightScaleLSDProductionTests {
    static func main() throws {
        try testConstantRGBAConvertsToNormalizedGrayscale()
        try testInvalidRGBAIsRejected()
        try testLinesBecomeScoredObjectSpaceCandidates()
        print("AnyUprightScaleLSDProductionTests passed")
    }

    private static func testConstantRGBAConvertsToNormalizedGrayscale() throws {
        let image = AUScaleLSDRGBAImage(
            width: 1,
            height: 1,
            pixels: [255, 0, 0, 255]
        )
        let input = try requireValue(
            AnyUprightScaleLSDPreprocessor.normalizedGrayscaleNCHW(from: image),
            "valid RGBA should produce an input tensor"
        )
        try require(input.count == 512 * 512, "ScaleLSD input should be fixed 512x512")
        try require(input.allSatisfy { abs($0 - 0.299) < 1e-5 }, "red pixels should use the expected grayscale weight")
    }

    private static func testInvalidRGBAIsRejected() throws {
        let input = AnyUprightScaleLSDPreprocessor.normalizedGrayscaleNCHW(
            from: AUScaleLSDRGBAImage(width: 2, height: 2, pixels: [0, 0, 0, 255])
        )
        try require(input == nil, "invalid RGBA byte count should be rejected")
    }

    private static func testLinesBecomeScoredObjectSpaceCandidates() throws {
        let lines = [
            AUScaleLSDLineSegment(
                start: AUPoint(x: 20, y: 10),
                end: AUPoint(x: 20, y: 90),
                score: 20
            ),
            AUScaleLSDLineSegment(
                start: AUPoint(x: 10, y: 70),
                end: AUPoint(x: 90, y: 70),
                score: 80
            ),
        ]
        let candidates = AnyUprightScaleLSDPreprocessor.detectedCandidates(
            from: lines,
            imageSize: AUSize(width: 100, height: 100)
        )
        try require(candidates.count == 2, "both ScaleLSD lines should become candidates")
        try require(candidates[0].orientation == .vertical, "taller line should be vertical")
        try require(candidates[1].orientation == .horizontal, "wider line should be horizontal")
        try require(candidates[1].score > candidates[0].score, "support-score ordering should be preserved")
        try require(abs(candidates[0].start.y - 0.9) < 1e-9, "image Y should convert once to object-space Y")
        try require(abs(candidates[1].score - 1.0) < 1e-9, "highest support score should normalize to one")
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else {
            throw ScaleLSDProductionTestFailure.failed(message)
        }
    }

    private static func requireValue<T>(_ value: T?, _ message: String) throws -> T {
        guard let value else {
            throw ScaleLSDProductionTestFailure.failed(message)
        }
        return value
    }
}
