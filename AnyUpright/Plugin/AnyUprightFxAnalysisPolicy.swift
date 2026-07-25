//
//  AnyUprightFxAnalysisPolicy.swift
//  AnyUpright
//

import Foundation
import CoreMedia

struct AUFxAnalysisProbePolicy {
    static let minimumDuration = CMTime(value: 1, timescale: 20)
    static let requestedSampleCount: Int32 = 2

    static func range(
        near inputTime: CMTime,
        within inputRange: CMTimeRange,
        sampleDuration: CMTime
    ) -> CMTimeRange {
        guard inputRange.isValid,
              inputRange.start.isValid,
              inputRange.start.isNumeric,
              inputRange.duration.isValid,
              inputRange.duration.isNumeric,
              CMTimeCompare(inputRange.duration, .zero) > 0 else {
            return CMTimeRange(start: inputRange.start, duration: .zero)
        }

        let rangeStart = inputRange.start
        let rangeEnd = CMTimeRangeGetEnd(inputRange)
        let hasValidSampleDuration = sampleDuration.isValid
            && sampleDuration.isNumeric
            && CMTimeCompare(sampleDuration, .zero) > 0
        let probeDuration: CMTime
        if hasValidSampleDuration {
            let sampledDuration = CMTimeMultiply(sampleDuration, multiplier: requestedSampleCount)
            probeDuration = CMTimeCompare(sampledDuration, minimumDuration) > 0
                ? sampledDuration
                : minimumDuration
        } else {
            probeDuration = minimumDuration
        }

        var target = inputTime
        if !target.isValid || !target.isNumeric || CMTimeCompare(target, rangeStart) < 0 {
            target = rangeStart
        } else if CMTimeCompare(target, rangeEnd) >= 0 {
            let tailStep = hasValidSampleDuration ? sampleDuration : minimumDuration
            let availableStep = CMTimeCompare(tailStep, inputRange.duration) < 0
                ? tailStep
                : inputRange.duration
            target = CMTimeSubtract(rangeEnd, availableStep)
        }

        var alignedStart = target
        if hasValidSampleDuration {
            let delta = CMTimeSubtract(target, rangeStart)
            let deltaAtSampleScale = CMTimeConvertScale(
                delta,
                timescale: sampleDuration.timescale,
                method: .roundTowardZero
            )
            let sampleIndex = deltaAtSampleScale.value / sampleDuration.value
            let (offsetValue, overflow) = sampleIndex.multipliedReportingOverflow(by: sampleDuration.value)
            if !overflow {
                alignedStart = CMTimeAdd(
                    rangeStart,
                    CMTime(value: offsetValue, timescale: sampleDuration.timescale)
                )
            }
        }

        if CMTimeCompare(alignedStart, rangeStart) < 0 {
            alignedStart = rangeStart
        }
        if CMTimeCompare(alignedStart, rangeEnd) >= 0 {
            alignedStart = target
        }

        let remaining = CMTimeSubtract(rangeEnd, alignedStart)
        let duration = CMTimeCompare(probeDuration, remaining) < 0 ? probeDuration : remaining
        return CMTimeRange(start: alignedStart, duration: duration)
    }
}

struct AUFirstUsableAnalysisFrameGate {
    private(set) var receivedFrameCount = 0
    private(set) var hasClaimedFrame = false

    mutating func reset() {
        receivedFrameCount = 0
        hasClaimedFrame = false
    }

    mutating func claimIfUsable(_ isUsable: Bool) -> Bool {
        receivedFrameCount += 1
        guard isUsable, !hasClaimedFrame else {
            return false
        }
        hasClaimedFrame = true
        return true
    }

    mutating func relinquishClaimForUnusablePreparation() {
        hasClaimedFrame = false
    }
}
