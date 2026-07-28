import Foundation

private enum UprightV2GuideSelectorTestFailure: Error, CustomStringConvertible {
    case failed(String)

    var description: String {
        switch self {
        case .failed(let message): return message
        }
    }
}

@main
struct AnyUprightUprightV2GuideSelectorTests {
    static func main() throws {
        try testSelectionPolicies()
        try testRepresentativeLinesBalanceQualityAndCoverage()
        try testSemiAutomaticRepresentativeLimit()
        try testInvalidAndDuplicateSupportersAreIgnored()
        print("AnyUprightUprightV2GuideSelectorTests passed")
    }

    private static func testSelectionPolicies() throws {
        let semi = AnyUprightUprightV2GuideSelector.selectionPolicy(
            for: UprightAnalysisRequest(correctionMode: .full, controlMode: .semiAutomatic)
        )
        try require(
            semi?.maximumGuidesPerOrientation == AnyUprightUprightCandidates.semiAutomaticLimitPerOrientation,
            "Semi Auto Full should use the existing per-orientation candidate limit"
        )
        try require(semi?.applyRiskGate == false, "Semi Auto Full should expose a risky best family for manual review")

        let automatic = AnyUprightUprightV2GuideSelector.selectionPolicy(
            for: UprightAnalysisRequest(correctionMode: .full, controlMode: .automatic)
        )
        try require(
            automatic?.maximumGuidesPerOrientation == AnyUprightUprightCandidates.automaticLimitPerOrientation,
            "Full Auto should retain its two-guide limit"
        )
        try require(automatic?.applyRiskGate == true, "Full Auto should retain the risk gate")

        try require(
            AnyUprightUprightV2GuideSelector.selectionPolicy(
                for: UprightAnalysisRequest(correctionMode: .vertical, controlMode: .semiAutomatic)
            ) == nil,
            "single-direction Semi Auto should retain the score-only selector"
        )
        try require(
            AnyUprightUprightV2GuideSelector.selectionPolicy(
                for: UprightAnalysisRequest(correctionMode: .full, controlMode: .manual)
            ) == nil,
            "Manual should not run V2 candidate selection"
        )
    }

    private static func testRepresentativeLinesBalanceQualityAndCoverage() throws {
        let lines = [
            AUScaleLSDLineSegment(
                start: AUPoint(x: 10, y: 10),
                end: AUPoint(x: 10, y: 90),
                score: 100
            ),
            AUScaleLSDLineSegment(
                start: AUPoint(x: 12, y: 10),
                end: AUPoint(x: 12, y: 90),
                score: 90
            ),
            AUScaleLSDLineSegment(
                start: AUPoint(x: 90, y: 10),
                end: AUPoint(x: 90, y: 90),
                score: 60
            ),
        ]
        let guides = AnyUprightUprightV2GuideSelector.representativeCandidates(
            supporterIndexes: [0, 1, 2],
            orientation: .vertical,
            lines: lines,
            imageSize: AUSize(width: 100, height: 100)
        )

        try require(guides.count == 2, "a supported family should produce at most two guides")
        try require(guides.allSatisfy { $0.orientation == .vertical }, "guide orientation should be preserved")
        try require(abs(guides[0].start.x - 0.1) < 1e-12, "highest-quality line should be selected first")
        try require(abs(guides[1].start.x - 0.9) < 1e-12, "second guide should favor spatial coverage")
        try require(abs(guides[0].start.y - 0.9) < 1e-12, "image Y should convert once to object-space Y")
        try require(abs(guides[0].end.y - 0.1) < 1e-12, "converted endpoint should preserve line direction")
        try require(guides[0].score > guides[1].score, "guide ordering score should remain deterministic")
    }

    private static func testSemiAutomaticRepresentativeLimit() throws {
        var lines: [AUScaleLSDLineSegment] = []
        for index in 0..<12 {
            let x = Double(index * 8 + 4)
            let score = Double(100 - index)
            lines.append(AUScaleLSDLineSegment(
                start: AUPoint(x: x, y: 10),
                end: AUPoint(x: x, y: 90),
                score: score
            ))
        }
        let guides = AnyUprightUprightV2GuideSelector.representativeCandidates(
            supporterIndexes: Array(lines.indices),
            orientation: .vertical,
            lines: lines,
            imageSize: AUSize(width: 100, height: 100),
            maximumCount: AnyUprightUprightCandidates.semiAutomaticLimitPerOrientation
        )

        try require(guides.count == 10, "Semi Auto should expose at most ten supporters per orientation")
        try require(Set(guides.map { $0.start.x }).count == 10, "Semi Auto representatives should not duplicate lines")
        try require(
            zip(guides, guides.dropFirst()).allSatisfy { pair in
                pair.0.score > pair.1.score
            },
            "Semi Auto representative scores should preserve deterministic selection order"
        )
    }

    private static func testInvalidAndDuplicateSupportersAreIgnored() throws {
        let lines = [
            AUScaleLSDLineSegment(
                start: AUPoint(x: 10, y: 40),
                end: AUPoint(x: 90, y: 40),
                score: 10
            ),
        ]
        let guides = AnyUprightUprightV2GuideSelector.representativeCandidates(
            supporterIndexes: [0, 0, -1, 4],
            orientation: .horizontal,
            lines: lines,
            imageSize: AUSize(width: 100, height: 100)
        )

        try require(guides.count == 1, "duplicates and out-of-range supporters should not create extra guides")
        try require(guides[0].orientation == .horizontal, "single valid supporter should retain its orientation")
        try require(abs(guides[0].start.y - 0.6) < 1e-12, "single guide should use object-space coordinates")
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else {
            throw UprightV2GuideSelectorTestFailure.failed(message)
        }
    }
}
