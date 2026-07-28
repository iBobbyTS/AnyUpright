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
        try testCorrectionModeFiltersFullHypothesisGuides()
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
        try require(semi?.correctionMode == .full, "Semi Auto Full should export both Full hypothesis families")

        let automatic = AnyUprightUprightV2GuideSelector.selectionPolicy(
            for: UprightAnalysisRequest(correctionMode: .full, controlMode: .automatic)
        )
        try require(
            automatic?.maximumGuidesPerOrientation == AnyUprightUprightCandidates.automaticLimitPerOrientation,
            "Full Auto should retain its two-guide limit"
        )
        try require(automatic?.applyRiskGate == true, "Full Auto should retain the risk gate")

        let vertical = AnyUprightUprightV2GuideSelector.selectionPolicy(
            for: UprightAnalysisRequest(correctionMode: .vertical, controlMode: .semiAutomatic)
        )
        try require(
            vertical?.correctionMode == .vertical,
            "Vertical Semi Auto should rank a Full hypothesis and export only its vertical family"
        )
        let horizontal = AnyUprightUprightV2GuideSelector.selectionPolicy(
            for: UprightAnalysisRequest(correctionMode: .horizontal, controlMode: .automatic)
        )
        try require(
            horizontal?.correctionMode == .horizontal,
            "Horizontal Full Auto should rank a Full hypothesis and export only its horizontal family"
        )
        try require(
            AnyUprightUprightV2GuideSelector.selectionPolicy(
                for: UprightAnalysisRequest(correctionMode: .full, controlMode: .manual)
            ) == nil,
            "Manual should not run V2 candidate selection"
        )
    }

    private static func testCorrectionModeFiltersFullHypothesisGuides() throws {
        let lines = [
            AUScaleLSDLineSegment(
                start: AUPoint(x: 10, y: 10),
                end: AUPoint(x: 15, y: 90),
                score: 100
            ),
            AUScaleLSDLineSegment(
                start: AUPoint(x: 90, y: 10),
                end: AUPoint(x: 85, y: 90),
                score: 90
            ),
            AUScaleLSDLineSegment(
                start: AUPoint(x: 10, y: 20),
                end: AUPoint(x: 90, y: 25),
                score: 80
            ),
            AUScaleLSDLineSegment(
                start: AUPoint(x: 10, y: 80),
                end: AUPoint(x: 90, y: 75),
                score: 70
            ),
        ]
        let imageSize = AUSize(width: 100, height: 100)

        func guides(for correctionMode: UprightCorrectionMode) throws -> [UprightDetectedCandidate] {
            let policy = try unwrap(
                AnyUprightUprightV2GuideSelector.selectionPolicy(
                    for: UprightAnalysisRequest(
                        correctionMode: correctionMode,
                        controlMode: .automatic
                    )
                ),
                "automatic mode should have a V2 policy"
            )
            return AnyUprightUprightV2GuideSelector.representativeGuides(
                verticalSupporterIndexes: [0, 1],
                horizontalSupporterIndexes: [2, 3],
                lines: lines,
                imageSize: imageSize,
                policy: policy
            )
        }

        let vertical = try guides(for: .vertical)
        try require(vertical.count == 2, "Vertical should retain the two Full hypothesis vertical guides")
        try require(
            vertical.allSatisfy { $0.orientation == .vertical },
            "Vertical should not export the Full hypothesis horizontal family"
        )

        let horizontal = try guides(for: .horizontal)
        try require(horizontal.count == 2, "Horizontal should retain the two Full hypothesis horizontal guides")
        try require(
            horizontal.allSatisfy { $0.orientation == .horizontal },
            "Horizontal should not export the Full hypothesis vertical family"
        )

        let full = try guides(for: .full)
        try require(full.count == 4, "Full should continue exporting both hypothesis families")
        try require(
            full.filter { $0.orientation == .vertical }.count == 2
                && full.filter { $0.orientation == .horizontal }.count == 2,
            "Full should preserve two guides per orientation"
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

    private static func unwrap<T>(_ value: T?, _ message: String) throws -> T {
        guard let value else {
            throw UprightV2GuideSelectorTestFailure.failed(message)
        }
        return value
    }
}
