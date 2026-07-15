import Foundation
import simd

private enum UprightProposalTestFailure: Error, CustomStringConvertible {
    case failed(String)

    var description: String {
        switch self {
        case .failed(let message): return message
        }
    }
}

@main
struct AnyUprightUprightProposalTests {
    private static let size = AUSize(width: 1000.0, height: 1000.0)

    static func main() throws {
        try testVerticalSelectsSupportedPair()
        try testHorizontalSelectsSupportedPair()
        try testFullRequiresAndSelectsBothFamilies()
        try testCameraPriorAnchorsVerticalSelection()
        try testCameraPriorHorizontalRequiresOrthogonalVerifier()
        try testCameraPriorFullUsesOrthogonalVerifier()
        try testMissingFamilyIsRejected()
        try testInvalidImageSizeIsRejected()
        try testCropLimitRejectsUnsafeTransform()
        print("AnyUprightUprightProposalTests passed")
    }

    private static func testVerticalSelectsSupportedPair() throws {
        let proposal = AnyUprightUprightProposalRanker.makeProposal(
            lines: verticalCluster() + distractors(),
            correctionMode: .vertical,
            imageSize: size
        )
        try require(proposal.accepted, "vertical proposal should be accepted: \(String(describing: proposal.rejectionReason)) crop=\(String(describing: proposal.autoCropScale))")
        try require(proposal.verticalPair?.supportCount == 3, "vertical cluster should have three supporters")
        try require(proposal.horizontalPair == nil, "vertical mode should not select a horizontal pair")
        try require((proposal.verticalResidualDegrees ?? 1.0) < 1e-3, "vertical residual should be near zero")
    }

    private static func testHorizontalSelectsSupportedPair() throws {
        let proposal = AnyUprightUprightProposalRanker.makeProposal(
            lines: horizontalCluster() + distractors(),
            correctionMode: .horizontal,
            imageSize: size
        )
        try require(proposal.accepted, "horizontal proposal should be accepted: \(String(describing: proposal.rejectionReason))")
        try require(proposal.horizontalPair?.supportCount == 3, "horizontal cluster should have three supporters")
        try require(proposal.verticalPair == nil, "horizontal mode should not select a vertical pair")
        try require((proposal.horizontalResidualDegrees ?? 1.0) < 1e-3, "horizontal residual should be near zero")
    }

    private static func testFullRequiresAndSelectsBothFamilies() throws {
        let inputs = verticalCluster() + horizontalCluster() + horizontalVerifierCluster() + distractors()
        let first = AnyUprightUprightProposalRanker.makeProposal(
            lines: inputs,
            correctionMode: .full,
            imageSize: size
        )
        let second = AnyUprightUprightProposalRanker.makeProposal(
            lines: inputs,
            correctionMode: .full,
            imageSize: size
        )
        try require(first.accepted, "full proposal should be accepted: \(String(describing: first.rejectionReason))")
        try require(first.verticalPair != nil && first.horizontalPair != nil, "full mode should select 2V + 2H")
        try require(first.verticalPair == second.verticalPair, "vertical ranking should be deterministic")
        try require(first.horizontalPair == second.horizontalPair, "horizontal ranking should be deterministic")
        try require((first.verticalResidualDegrees ?? 1.0) < 1e-3, "full vertical residual should be near zero")
        try require((first.horizontalResidualDegrees ?? 1.0) < 0.1, "full horizontal residual should be near zero: \(String(describing: first.horizontalResidualDegrees)) pair=\(String(describing: first.horizontalPair))")
    }

    private static func testMissingFamilyIsRejected() throws {
        let proposal = AnyUprightUprightProposalRanker.makeProposal(
            lines: verticalCluster(),
            correctionMode: .full,
            imageSize: size
        )
        try require(proposal.rejectionReason == .missingHorizontalPair, "full mode should reject a missing horizontal pair")
    }

    private static func testCameraPriorAnchorsVerticalSelection() throws {
        let gravity = simd_normalize(SIMD3<Double>(0.6, -9.0, 1.0))
        let prior = AUUprightCameraPrior(
            gravity: gravity,
            verticalFOVRadians: .pi / 2.0,
            gravityUncertainty: radians(1.0),
            verticalFOVUncertaintyRadians: radians(2.0)
        )
        let proposal = AnyUprightUprightProposalRanker.makeProposal(
            lines: verticalCluster() + distractors(),
            correctionMode: .vertical,
            imageSize: size,
            cameraPrior: prior
        )
        try require(proposal.accepted, "camera prior should anchor a vertical proposal")
        try require(proposal.verticalPair?.supportCount ?? 0 >= 2, "camera-prior proposal should retain support")
    }

    private static func testCameraPriorHorizontalRequiresOrthogonalVerifier() throws {
        let withoutVerifier = AnyUprightUprightProposalRanker.makeProposal(
            lines: priorHorizontalPrimaryCluster(),
            correctionMode: .horizontal,
            imageSize: size,
            cameraPrior: syntheticCameraPrior()
        )
        try require(
            withoutVerifier.rejectionReason == .incompatibleVanishingPoints,
            "camera-prior horizontal mode should require an orthogonal verifier"
        )

        let withVerifier = AnyUprightUprightProposalRanker.makeProposal(
            lines: priorHorizontalPrimaryCluster() + priorHorizontalVerifierCluster(),
            correctionMode: .horizontal,
            imageSize: size,
            cameraPrior: syntheticCameraPrior()
        )
        try require(
            withVerifier.rejectionReason != .incompatibleVanishingPoints,
            "an orthogonal verifier should satisfy horizontal compatibility"
        )
        try require(withVerifier.horizontalPair != nil, "horizontal mode should select a primary pair")
    }

    private static func testCameraPriorFullUsesOrthogonalVerifier() throws {
        var configuration = AUUprightProposalConfiguration()
        configuration.maximumAutoCropScale = 10.0
        let proposal = AnyUprightUprightProposalRanker.makeProposal(
            lines: priorVerticalCluster()
                + priorHorizontalPrimaryCluster()
                + priorHorizontalVerifierCluster(),
            correctionMode: .full,
            imageSize: size,
            cameraPrior: syntheticCameraPrior(),
            configuration: configuration
        )
        try require(
            proposal.rejectionReason != .incompatibleVanishingPoints,
            "camera-prior full mode should find the orthogonal horizontal pair: \(String(describing: proposal.rejectionReason))"
        )
        try require(
            proposal.verticalPair != nil && proposal.horizontalPair != nil,
            "camera-prior full mode should select 2V + 2H"
        )
    }

    private static func testInvalidImageSizeIsRejected() throws {
        let proposal = AnyUprightUprightProposalRanker.makeProposal(
            lines: verticalCluster(),
            correctionMode: .vertical,
            imageSize: AUSize(width: 0.0, height: 1000.0)
        )
        try require(proposal.rejectionReason == .invalidImageSize, "invalid image size should be rejected")
    }

    private static func testCropLimitRejectsUnsafeTransform() throws {
        var configuration = AUUprightProposalConfiguration()
        configuration.maximumAutoCropScale = 1.01
        let proposal = AnyUprightUprightProposalRanker.makeProposal(
            lines: verticalCluster(),
            correctionMode: .vertical,
            imageSize: size,
            configuration: configuration
        )
        try require(proposal.rejectionReason == .excessiveCrop, "tight crop limit should reject the perspective transform")
    }

    private static func verticalCluster() -> [AUUprightProposalInputLine] {
        [
            input(320, 0, 200, 1000, 80),
            input(560, 0, 500, 1000, 70),
            input(800, 0, 800, 1000, 60),
        ]
    }

    private static func horizontalCluster() -> [AUUprightProposalInputLine] {
        [
            input(0, 425, 1000, 200, 85),
            input(0, 500, 1000, 500, 75),
            input(0, 575, 1000, 800, 65),
        ]
    }

    private static func distractors() -> [AUUprightProposalInputLine] {
        [
            input(100, 0, 180, 1000, 120),
            input(0, 900, 1000, 850, 115),
            input(100, 100, 900, 900, 200),
        ]
    }

    private static func horizontalVerifierCluster() -> [AUUprightProposalInputLine] {
        [
            input(0, 300, 1000, 644, 72),
            input(0, 500, 1000, 594, 68),
            input(0, 700, 1000, 543, 62),
        ]
    }

    private static func syntheticCameraPrior() -> AUUprightCameraPrior {
        AUUprightCameraPrior(
            gravity: simd_normalize(SIMD3<Double>(0.0, -5.0, 1.0)),
            verticalFOVRadians: .pi / 2.0,
            gravityUncertainty: radians(1.0),
            verticalFOVUncertaintyRadians: radians(2.0)
        )
    }

    private static func priorVerticalCluster() -> [AUUprightProposalInputLine] {
        [
            input(300, 0, 200, 1000, 90),
            input(500, 0, 500, 1000, 80),
            input(700, 0, 800, 1000, 70),
        ]
    }

    private static func priorHorizontalPrimaryCluster() -> [AUUprightProposalInputLine] {
        [
            input(0, 200, 1000, 561.9, 90),
            input(0, 450, 1000, 585.7, 80),
            input(0, 800, 1000, 619.0, 70),
        ]
    }

    private static func priorHorizontalVerifierCluster() -> [AUUprightProposalInputLine] {
        [
            input(0, 634.3, 1000, 200, 85),
            input(0, 612.9, 1000, 450, 75),
            input(0, 582.9, 1000, 800, 65),
        ]
    }

    private static func input(
        _ x1: Double,
        _ y1: Double,
        _ x2: Double,
        _ y2: Double,
        _ score: Double
    ) -> AUUprightProposalInputLine {
        AUUprightProposalInputLine(
            line: AULineSegment(start: AUPoint(x: x1, y: y1), end: AUPoint(x: x2, y: y2)),
            score: score
        )
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else {
            throw UprightProposalTestFailure.failed(message)
        }
    }

    private static func radians(_ degrees: Double) -> Double {
        degrees * .pi / 180.0
    }
}
