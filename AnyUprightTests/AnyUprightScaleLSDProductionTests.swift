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
        try testLinesBecomeScoredObjectSpaceCandidates()
        try testAxisAngleFilterUsesReferenceAspectRatio()
        try testAxisAngleFilterRunsBeforeCandidateLimit()
        print("AnyUprightScaleLSDProductionTests passed")
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

    private static func testAxisAngleFilterUsesReferenceAspectRatio() throws {
        let candidates = AnyUprightScaleLSDPreprocessor.detectedCandidates(
            from: [
                AUScaleLSDLineSegment(
                    start: AUPoint(x: 0, y: 0),
                    end: AUPoint(x: 100, y: 100),
                    score: 10
                ),
                AUScaleLSDLineSegment(
                    start: AUPoint(x: 0, y: 0),
                    end: AUPoint(x: 50, y: 200),
                    score: 20
                ),
                AUScaleLSDLineSegment(
                    start: AUPoint(x: 0, y: 0),
                    end: AUPoint(x: 100, y: 200),
                    score: 100
                ),
            ],
            imageSize: AUSize(width: 512, height: 512),
            referenceImageSize: AUSize(width: 200, height: 100)
        )
        try require(candidates.count == 2, "lines outside the axis +/-30 degree cones should be rejected")
        try require(candidates[0].orientation == .horizontal, "reference aspect ratio should recover horizontal angle")
        try require(candidates[1].orientation == .vertical, "reference aspect ratio should recover vertical angle")
    }

    private static func testAxisAngleFilterRunsBeforeCandidateLimit() throws {
        var lines: [AUScaleLSDLineSegment] = []
        for index in 0..<12 {
            lines.append(AUScaleLSDLineSegment(
                start: AUPoint(x: 0, y: Double(index * 4)),
                end: AUPoint(x: 500, y: Double(index * 4 + 50)),
                score: Double(index + 1)
            ))
        }
        lines.append(
            AUScaleLSDLineSegment(
                start: AUPoint(x: 0, y: 0),
                end: AUPoint(x: 500, y: 500),
                score: 1_000
            )
        )
        let filtered = AnyUprightScaleLSDPreprocessor.detectedCandidates(
            from: lines,
            imageSize: AUSize(width: 512, height: 512)
        )
        let ranked = AnyUprightUprightCandidates.analysisCandidates(
            from: filtered,
            request: UprightAnalysisRequest(correctionMode: .horizontal, controlMode: .semiAutomatic)
        )
        try require(filtered.count == 12, "diagonal lines should be removed before ranking")
        try require(ranked.count == AnyUprightUprightCandidates.semiAutomaticLimitPerOrientation, "existing semi-auto count should remain unchanged")
        try require(ranked.allSatisfy { $0.orientation == UprightGuideOrientation.horizontal }, "only horizontal candidates should remain")
        try require(abs((ranked.first?.score ?? 0.0) - 1.0) < 1e-9, "filtered-out scores should not affect score normalization")
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else {
            throw ScaleLSDProductionTestFailure.failed(message)
        }
    }
}
