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
        try testSetsAllTargetsWhenNoKeyframesExist()
        try testUnsetsExistingTargetsWhenAnyKeyframeExists()
        try testUnsetsAllTargetsWhenAllKeyframesExist()
        try testRejectsInvalidTimeBeforeQueryingChannels()
        try testPropagatesQueryFailureBeforeAnyWritePhase()
        try testSnapshotsCurrentNonzeroValuesBeforeSettingKeyframes()
        try testRejectsInvalidAssignmentTimeBeforeReadingValues()
        print("AnyUprightStretchKeyframePolicyTests passed")
    }

    private static let targets = [202, 203, 206, 207, 210, 211, 214, 215].map {
        AUStretchKeyframeTarget(parameterID: UInt32($0), channelIndex: 0)
    }

    private static func testSetsAllTargetsWhenNoKeyframesExist() throws {
        var queried: [AUStretchKeyframeTarget] = []
        let time = CMTime(value: 125, timescale: 25)
        let action = try AUStretchKeyframePolicy.action(from: targets, at: time) { target, queriedTime in
            queried.append(target)
            try require(queriedTime == time, "policy must query the requested timeline time")
            return false
        }

        try require(action == .set(targets), "all eight channels must be set when none has a keyframe")
        try require(queried == targets, "all channels must be queried in deterministic order")
    }

    private static func testUnsetsExistingTargetsWhenAnyKeyframeExists() throws {
        let existing = Set([targets[0].parameterID, targets[3].parameterID, targets[7].parameterID])
        var queried: [AUStretchKeyframeTarget] = []
        let action = try AUStretchKeyframePolicy.action(
            from: targets,
            at: CMTime(value: 1001, timescale: 30000)
        ) { target, _ in
            queried.append(target)
            return existing.contains(target.parameterID)
        }

        try require(
            action == .unset([targets[0], targets[3], targets[7]]),
            "when any channel is keyed, only channels keyed at the current time must be unset"
        )
        try require(queried == targets, "partial keyframe state must still query all eight channels")
    }

    private static func testUnsetsAllTargetsWhenAllKeyframesExist() throws {
        let action = try AUStretchKeyframePolicy.action(from: targets, at: .zero) { _, _ in true }
        try require(action == .unset(targets), "all eight channels must be unset when all are keyed")
    }

    private static func testRejectsInvalidTimeBeforeQueryingChannels() throws {
        var queryCount = 0
        do {
            _ = try AUStretchKeyframePolicy.action(from: targets, at: .invalid) { _, _ in
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
            _ = try AUStretchKeyframePolicy.action(from: targets, at: .zero) { _, _ in
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

    private static func testSnapshotsCurrentNonzeroValuesBeforeSettingKeyframes() throws {
        let time = CMTime(value: 59, timescale: 30)
        let values = [1242.0, -879.0, 16.0, -24.0, 31.0, 48.0, -7.0, 93.0]
        var queried: [AUStretchKeyframeTarget] = []
        let assignments = try AUStretchKeyframePolicy.assignments(
            for: targets,
            at: time
        ) { target, queriedTime in
            queried.append(target)
            try require(queriedTime == time, "current values must be read at the keyframe time")
            guard let index = targets.firstIndex(of: target) else {
                throw StretchKeyframePolicyTestFailure.failed("queried an unknown target")
            }
            return values[index]
        }

        try require(queried == targets, "all eight values must be snapshotted in deterministic order")
        try require(
            assignments == zip(targets, values).map(AUStretchKeyframeAssignment.init),
            "the keyframe snapshot must preserve nonzero and negative current values"
        )
    }

    private static func testRejectsInvalidAssignmentTimeBeforeReadingValues() throws {
        var readCount = 0
        do {
            _ = try AUStretchKeyframePolicy.assignments(for: targets, at: .invalid) { _, _ in
                readCount += 1
                return 0
            }
            throw StretchKeyframePolicyTestFailure.failed("invalid assignment time must throw")
        } catch AUStretchKeyframePolicyError.invalidTime {
            try require(readCount == 0, "invalid time must fail before reading parameter values")
        }
    }

    private static func require(_ condition: Bool, _ message: String) throws {
        guard condition else {
            throw StretchKeyframePolicyTestFailure.failed(message)
        }
    }
}
