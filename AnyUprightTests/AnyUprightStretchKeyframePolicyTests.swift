//
//  AnyUprightStretchKeyframePolicyTests.swift
//  AnyUprightTests
//

import CoreMedia

private enum StretchKeyframePolicyTestFailure: Error {
    case failed(String)
    case simulatedQueryFailure
}

@main
private enum AnyUprightStretchKeyframePolicyTests {
    static func main() throws {
        try testReturnsAllTargetsWhenNoKeyframesExist()
        try testKeepsOrderAndSkipsExistingKeyframes()
        try testRejectsInvalidTimeBeforeQueryingChannels()
        try testPropagatesQueryFailureBeforeAnyWritePhase()
        print("AnyUprightStretchKeyframePolicyTests passed")
    }

    private static let targets = [202, 203, 206, 207, 210, 211, 214, 215].map {
        AUStretchKeyframeTarget(parameterID: UInt32($0), channelIndex: 0)
    }

    private static func testReturnsAllTargetsWhenNoKeyframesExist() throws {
        var queried: [AUStretchKeyframeTarget] = []
        let time = CMTime(value: 125, timescale: 25)
        let missing = try AUStretchKeyframePolicy.missingTargets(from: targets, at: time) { target, queriedTime in
            queried.append(target)
            try require(queriedTime == time, "policy must query the requested timeline time")
            return false
        }

        try require(missing == targets, "all eight channels must be returned when none has a keyframe")
        try require(queried == targets, "all channels must be queried in deterministic order")
    }

    private static func testKeepsOrderAndSkipsExistingKeyframes() throws {
        let existing = Set([targets[0].parameterID, targets[3].parameterID, targets[7].parameterID])
        let missing = try AUStretchKeyframePolicy.missingTargets(
            from: targets,
            at: CMTime(value: 1001, timescale: 30000)
        ) { target, _ in
            existing.contains(target.parameterID)
        }

        try require(
            missing == [targets[1], targets[2], targets[4], targets[5], targets[6]],
            "existing keyframes must remain untouched while missing channels preserve their order"
        )
    }

    private static func testRejectsInvalidTimeBeforeQueryingChannels() throws {
        var queryCount = 0
        do {
            _ = try AUStretchKeyframePolicy.missingTargets(from: targets, at: .invalid) { _, _ in
                queryCount += 1
                return false
            }
            throw StretchKeyframePolicyTestFailure.failed("invalid time must throw")
        } catch AUStretchKeyframePolicyError.invalidTime {
            try require(queryCount == 0, "invalid time must fail before querying parameter channels")
        }
    }

    private static func testPropagatesQueryFailureBeforeAnyWritePhase() throws {
        var queryCount = 0
        do {
            _ = try AUStretchKeyframePolicy.missingTargets(from: targets, at: .zero) { _, _ in
                queryCount += 1
                if queryCount == 4 {
                    throw StretchKeyframePolicyTestFailure.simulatedQueryFailure
                }
                return false
            }
            throw StretchKeyframePolicyTestFailure.failed("query failure must propagate")
        } catch StretchKeyframePolicyTestFailure.simulatedQueryFailure {
            try require(queryCount == 4, "querying must stop at the first host API failure")
        }
    }

    private static func require(_ condition: Bool, _ message: String) throws {
        guard condition else {
            throw StretchKeyframePolicyTestFailure.failed(message)
        }
    }
}
