import Foundation
import CoreMedia

private enum FxAnalysisTransactionTestFailure: Error, CustomStringConvertible {
    case failed(String)

    var description: String {
        switch self {
        case .failed(let message): return message
        }
    }
}

@main
struct AnyUprightFxAnalysisTransactionTests {
    private struct Request: Equatable { let value: Int }
    private enum StartError: Error { case failed }

    static func main() throws {
        try testStartBusyAndRollback()
        try testConcurrentStart()
        try testDesiredRangeAndClaim()
        try testGenerationIsolationAndCleanupOutcomes()
        try testCompletedWithoutResultAndNoCallback()
        print("AnyUprightFxAnalysisTransactionTests passed")
    }

    private static func testStartBusyAndRollback() throws {
        let transaction = AUFxAnalysisTransaction<Request, [Int]>()
        let time = CMTime(value: 10, timescale: 24)
        let hostBusy = transaction.start(
            request: Request(value: 1),
            requestedTimelineTime: time,
            hostIsBusy: { true },
            startForwardAnalysis: {}
        )
        try require(isHostBusy(hostBusy), "host busy must reject")
        try require(!transaction.hasPendingRequest, "host busy must not create state")

        do {
            _ = try transaction.start(
                request: Request(value: 1),
                requestedTimelineTime: time,
                hostIsBusy: { false },
                startForwardAnalysis: { throw StartError.failed }
            )
            throw FxAnalysisTransactionTestFailure.failed("start failure must throw")
        } catch StartError.failed {}
        try require(!transaction.hasPendingRequest, "start failure must roll back")
    }

    private static func testConcurrentStart() throws {
        let transaction = AUFxAnalysisTransaction<Request, Int>()
        let queue = DispatchQueue(label: "transaction-test", attributes: .concurrent)
        let group = DispatchGroup()
        let resultLock = NSLock()
        var starts = 0
        var accepted = 0
        for index in 0..<12 {
            group.enter()
            queue.async {
                let result = transaction.start(
                    request: Request(value: index),
                    requestedTimelineTime: .zero,
                    hostIsBusy: { false },
                    startForwardAnalysis: {
                        resultLock.lock(); starts += 1; resultLock.unlock()
                    }
                )
                if case .started = result {
                    resultLock.lock(); accepted += 1; resultLock.unlock()
                }
                group.leave()
            }
        }
        group.wait()
        try require(starts == 1 && accepted == 1, "concurrent cold start must start once")
    }

    private static func testDesiredRangeAndClaim() throws {
        let transaction = AUFxAnalysisTransaction<Request, [Int]>()
        _ = transaction.start(
            request: Request(value: 7),
            requestedTimelineTime: CMTime(value: 24, timescale: 24),
            analysisStartNanos: 123,
            hostIsBusy: { false },
            startForwardAnalysis: {}
        )
        let details = try transaction.desiredRange(
            within: CMTimeRange(start: .zero, duration: CMTime(seconds: 10, preferredTimescale: 600)),
            inputTimeFromTimeline: { $0 },
            sampleDuration: { CMTime(value: 1, timescale: 24) }
        )
        try require(CMTimeCompare(details.range.duration, CMTime(value: 1, timescale: 12)) == 0, "range must cover two samples")
        _ = transaction.setupAnalysis(range: details.range)
        try require(transaction.claimFrame(hasIOSurface: false, hasNonEmptyPixelBounds: true) == nil, "missing surface must not claim")
        let claim = transaction.claimFrame(hasIOSurface: true, hasNonEmptyPixelBounds: true)
        try require(claim?.request == Request(value: 7), "second usable callback must claim request")
        try require(claim?.callbackCount == 2, "callback count")
        transaction.relinquishFrame(token: claim!.token)
        try require(transaction.claimFrame(hasIOSurface: true, hasNonEmptyPixelBounds: true) != nil, "relinquish must allow next callback")
    }

    private static func testGenerationIsolationAndCleanupOutcomes() throws {
        let transaction = AUFxAnalysisTransaction<Request, [Int]>()
        let first = try startedToken(transaction.start(
            request: Request(value: 1),
            requestedTimelineTime: .zero,
            hostIsBusy: { false },
            startForwardAnalysis: {}
        ))
        transaction.cancel(token: first)
        let second = try startedToken(transaction.start(
            request: Request(value: 2),
            requestedTimelineTime: .zero,
            hostIsBusy: { false },
            startForwardAnalysis: {}
        ))
        transaction.complete(token: first, outcome: .produced([1]), inputFrameTime: .zero)
        transaction.complete(token: second, outcome: .produced([]), inputFrameTime: CMTime(value: 1, timescale: 24))
        let snapshot = transaction.cleanup()
        try require(snapshot?.request == Request(value: 2), "old generation must not mutate new request")
        guard case .produced(let result)? = snapshot?.outcome else {
            throw FxAnalysisTransactionTestFailure.failed("empty produced result must remain distinct")
        }
        try require(result.isEmpty, "empty result must be preserved")
        try require(!transaction.hasPendingRequest, "cleanup must reset state")
    }

    private static func testCompletedWithoutResultAndNoCallback() throws {
        let completed = AUFxAnalysisTransaction<Request, Int>()
        let completedToken = try startedToken(completed.start(
            request: Request(value: 3),
            requestedTimelineTime: .zero,
            hostIsBusy: { false },
            startForwardAnalysis: {}
        ))
        completed.complete(token: completedToken, outcome: .completedWithoutResult, inputFrameTime: .zero)
        guard case .completedWithoutResult? = completed.cleanup()?.outcome else {
            throw FxAnalysisTransactionTestFailure.failed("completed without value must remain distinct")
        }

        let noCallback = AUFxAnalysisTransaction<Request, Int>()
        _ = noCallback.start(
            request: Request(value: 4),
            requestedTimelineTime: .zero,
            hostIsBusy: { false },
            startForwardAnalysis: {}
        )
        guard case .notProduced? = noCallback.cleanup()?.outcome else {
            throw FxAnalysisTransactionTestFailure.failed("zero callback must remain not produced")
        }
    }

    private static func startedToken(_ disposition: AUFxAnalysisStartDisposition) throws -> AUFxAnalysisTransactionToken {
        guard case .started(let token) = disposition else {
            throw FxAnalysisTransactionTestFailure.failed("expected started disposition")
        }
        return token
    }

    private static func isHostBusy(_ disposition: AUFxAnalysisStartDisposition) -> Bool {
        if case .hostBusy = disposition { return true }
        return false
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw FxAnalysisTransactionTestFailure.failed(message) }
    }
}
