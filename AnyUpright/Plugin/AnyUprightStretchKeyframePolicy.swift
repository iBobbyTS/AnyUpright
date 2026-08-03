//
//  AnyUprightStretchKeyframePolicy.swift
//  AnyUpright
//

import CoreMedia

struct AUStretchKeyframeTarget: Equatable {
    let parameterID: UInt32
    let channelIndex: UInt
}

struct AUStretchKeyframeAssignment: Equatable {
    let target: AUStretchKeyframeTarget
    let value: Double
}

enum AUStretchKeyframePolicyError: Error, Equatable {
    case invalidTime
}

enum AUStretchKeyframeAction: Equatable {
    case set([AUStretchKeyframeTarget])
    case unset([AUStretchKeyframeTarget])
}

enum AUStretchKeyframePolicy {
    static func action(
        from targets: [AUStretchKeyframeTarget],
        at time: CMTime,
        hasKeyframe: (AUStretchKeyframeTarget, CMTime) throws -> Bool
    ) throws -> AUStretchKeyframeAction {
        guard time.isValid, time.isNumeric, !time.isIndefinite else {
            throw AUStretchKeyframePolicyError.invalidTime
        }

        var keyframed: [AUStretchKeyframeTarget] = []
        keyframed.reserveCapacity(targets.count)
        for target in targets where try hasKeyframe(target, time) {
            keyframed.append(target)
        }
        return keyframed.isEmpty ? .set(targets) : .unset(keyframed)
    }

    static func assignments(
        for targets: [AUStretchKeyframeTarget],
        at time: CMTime,
        currentValue: (AUStretchKeyframeTarget, CMTime) throws -> Double
    ) throws -> [AUStretchKeyframeAssignment] {
        guard time.isValid, time.isNumeric, !time.isIndefinite else {
            throw AUStretchKeyframePolicyError.invalidTime
        }

        return try targets.map { target in
            AUStretchKeyframeAssignment(
                target: target,
                value: try currentValue(target, time)
            )
        }
    }
}
