//
//  AnyUprightStretchKeyframePolicy.swift
//  AnyUpright
//

import CoreMedia

struct AUStretchKeyframeTarget: Equatable {
    let parameterID: UInt32
    let channelIndex: UInt
}

enum AUStretchKeyframePolicyError: Error, Equatable {
    case invalidTime
}

enum AUStretchKeyframePolicy {
    static func missingTargets(
        from targets: [AUStretchKeyframeTarget],
        at time: CMTime,
        hasKeyframe: (AUStretchKeyframeTarget, CMTime) throws -> Bool
    ) throws -> [AUStretchKeyframeTarget] {
        guard time.isValid, time.isNumeric, !time.isIndefinite else {
            throw AUStretchKeyframePolicyError.invalidTime
        }

        var missing: [AUStretchKeyframeTarget] = []
        missing.reserveCapacity(targets.count)
        for target in targets where try !hasKeyframe(target, time) {
            missing.append(target)
        }
        return missing
    }
}
