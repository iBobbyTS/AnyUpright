import Foundation
import CoreMedia

private enum FxAnalysisPolicyTestFailure: Error, CustomStringConvertible {
    case failed(String)

    var description: String {
        switch self {
        case .failed(let message):
            return message
        }
    }
}

@main
struct AnyUprightFxAnalysisPolicyTests {
    static func main() throws {
        try testProbeDurations()
        try testRationalSampleAlignment()
        try testRangeClamping()
        try testInvalidSampleDurationFallback()
        try testFirstUsableFrameGate()
        print("AnyUprightFxAnalysisPolicyTests passed")
    }

    private static func testProbeDurations() throws {
        let inputRange = CMTimeRange(start: .zero, duration: CMTime(seconds: 10, preferredTimescale: 600))
        let cases: [(Int32, CMTime)] = [
            (60, CMTime(value: 1, timescale: 20)),
            (24, CMTime(value: 1, timescale: 12)),
            (5, CMTime(value: 2, timescale: 5)),
            (1, CMTime(value: 2, timescale: 1)),
        ]
        for (fps, expected) in cases {
            let range = AUFxAnalysisProbePolicy.range(
                near: CMTime(seconds: 1, preferredTimescale: 600),
                within: inputRange,
                sampleDuration: CMTime(value: 1, timescale: fps)
            )
            try require(CMTimeCompare(range.duration, expected) == 0, "\(fps)fps duration: \(range.duration)")
        }
    }

    private static func testRationalSampleAlignment() throws {
        let sample = CMTime(value: 1001, timescale: 30_000)
        let expectedStart = CMTime(value: 1001 * 100, timescale: 30_000)
        let range = AUFxAnalysisProbePolicy.range(
            near: CMTimeAdd(expectedStart, CMTime(value: 500, timescale: 30_000)),
            within: CMTimeRange(start: .zero, duration: CMTime(value: 300_000, timescale: 30_000)),
            sampleDuration: sample
        )
        try require(CMTimeCompare(range.start, expectedStart) == 0, "30000/1001 alignment: \(range.start)")
        try require(
            CMTimeCompare(range.duration, CMTime(value: 2002, timescale: 30_000)) == 0,
            "30000/1001 duration: \(range.duration)"
        )
    }

    private static func testRangeClamping() throws {
        let sample = CMTime(value: 1, timescale: 24)
        let inputRange = CMTimeRange(start: CMTime(seconds: 5, preferredTimescale: 600), duration: CMTime(value: 10, timescale: 24))

        let head = AUFxAnalysisProbePolicy.range(near: .zero, within: inputRange, sampleDuration: sample)
        try require(CMTimeCompare(head.start, inputRange.start) == 0, "head start")

        let tail = AUFxAnalysisProbePolicy.range(near: CMTime(seconds: 99, preferredTimescale: 600), within: inputRange, sampleDuration: sample)
        try require(CMTimeCompare(CMTimeRangeGetEnd(tail), CMTimeRangeGetEnd(inputRange)) == 0, "tail end")
        try require(CMTimeCompare(tail.duration, sample) == 0, "tail should request remaining sample")

        let shortRange = CMTimeRange(start: inputRange.start, duration: CMTime(value: 1, timescale: 48))
        let short = AUFxAnalysisProbePolicy.range(near: inputRange.start, within: shortRange, sampleDuration: sample)
        try require(CMTimeCompare(short.duration, shortRange.duration) == 0, "short input range")
    }

    private static func testInvalidSampleDurationFallback() throws {
        let inputRange = CMTimeRange(start: .zero, duration: CMTime(seconds: 1, preferredTimescale: 600))
        let range = AUFxAnalysisProbePolicy.range(
            near: CMTime(seconds: 0.25, preferredTimescale: 600),
            within: inputRange,
            sampleDuration: .invalid
        )
        try require(CMTimeCompare(range.start, CMTime(seconds: 0.25, preferredTimescale: 600)) == 0, "fallback start")
        try require(CMTimeCompare(range.duration, AUFxAnalysisProbePolicy.minimumDuration) == 0, "fallback duration")
    }

    private static func testFirstUsableFrameGate() throws {
        var gate = AUFirstUsableAnalysisFrameGate()
        try require(!gate.claimIfUsable(false), "unusable first frame must not claim")
        try require(gate.claimIfUsable(true), "usable second frame should claim")
        try require(!gate.claimIfUsable(true), "later frame must not claim")
        try require(gate.receivedFrameCount == 3, "received callback count")

        gate.relinquishClaimForUnusablePreparation()
        try require(gate.claimIfUsable(true), "preparation failure should permit a later callback")
        gate.reset()
        try require(gate.receivedFrameCount == 0 && !gate.hasClaimedFrame, "reset state")
        try require(gate.claimIfUsable(true), "reset should allow a new request")
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else {
            throw FxAnalysisPolicyTestFailure.failed(message)
        }
    }
}
