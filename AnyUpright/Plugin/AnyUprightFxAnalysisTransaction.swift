//
//  AnyUprightFxAnalysisTransaction.swift
//  AnyUpright
//

import Foundation
import CoreMedia

enum AUFxAnalysisOutcome<Result> {
    case notProduced
    case completedWithoutResult
    case produced(Result)
}

struct AUFxAnalysisTransactionToken: Hashable {
    fileprivate let generation: UInt64
}

enum AUFxAnalysisStartDisposition {
    case started(AUFxAnalysisTransactionToken)
    case localBusy
    case hostBusy
    case invalidTimelineTime
}

struct AUFxAnalysisDesiredRange {
    let token: AUFxAnalysisTransactionToken
    let requestedTimelineTime: CMTime
    let inputTime: CMTime
    let sampleDuration: CMTime
    let usedFallbackSampleDuration: Bool
    let range: CMTimeRange
}

struct AUFxAnalysisFrameClaim<Request> {
    let token: AUFxAnalysisTransactionToken
    let request: Request
    let requestedTimelineTime: CMTime
    let callbackCount: Int
    let analysisStartNanos: UInt64
}

struct AUFxAnalysisCleanupSnapshot<Request, Result> {
    let token: AUFxAnalysisTransactionToken
    let request: Request
    let requestedTimelineTime: CMTime
    let inputFrameTime: CMTime
    let callbackCount: Int
    let analysisStartNanos: UInt64
    let outcome: AUFxAnalysisOutcome<Result>
}

enum AUFxAnalysisTransactionError: Error, CustomStringConvertible {
    case missingPendingRequest
    case invalidTimelineTime
    case invalidInputTime
    case emptyInputRange

    var description: String {
        switch self {
        case .missingPendingRequest:
            return "Missing a pending analysis request"
        case .invalidTimelineTime:
            return "Missing a valid pending timeline time"
        case .invalidInputTime:
            return "Could not convert the requested timeline time to input time"
        case .emptyInputRange:
            return "The converted input time has no analyzable range"
        }
    }
}

final class AUFxAnalysisTransaction<Request, Result> {
    private struct ActiveRequest {
        let token: AUFxAnalysisTransactionToken
        let request: Request
        let requestedTimelineTime: CMTime
        let analysisStartNanos: UInt64
        var frameGate = AUFirstUsableAnalysisFrameGate()
        var inputFrameTime = CMTime.invalid
        var outcome = AUFxAnalysisOutcome<Result>.notProduced
    }

    private let lock = NSLock()
    private var nextGeneration: UInt64 = 0
    private var active: ActiveRequest?

    var hasPendingRequest: Bool {
        lock.withLock { active != nil }
    }

    func start(
        request: Request,
        requestedTimelineTime: CMTime,
        analysisStartNanos: UInt64 = AUMonotonicClock.nowNanos(),
        hostIsBusy: () -> Bool,
        startForwardAnalysis: () throws -> Void
    ) rethrows -> AUFxAnalysisStartDisposition {
        let token: AUFxAnalysisTransactionToken
        lock.lock()
        if active != nil {
            lock.unlock()
            return .localBusy
        }
        if hostIsBusy() {
            lock.unlock()
            return .hostBusy
        }
        guard requestedTimelineTime.isValid, requestedTimelineTime.isNumeric else {
            lock.unlock()
            return .invalidTimelineTime
        }

        nextGeneration &+= 1
        token = AUFxAnalysisTransactionToken(generation: nextGeneration)
        active = ActiveRequest(
            token: token,
            request: request,
            requestedTimelineTime: requestedTimelineTime,
            analysisStartNanos: analysisStartNanos
        )
        lock.unlock()

        do {
            try startForwardAnalysis()
            return .started(token)
        } catch {
            cancel(token: token)
            throw error
        }
    }

    func desiredRange(
        within inputTimeRange: CMTimeRange,
        inputTimeFromTimeline: (CMTime) -> CMTime,
        sampleDuration: () -> CMTime
    ) throws -> AUFxAnalysisDesiredRange {
        guard let snapshot = lock.withLock({ active }) else {
            throw AUFxAnalysisTransactionError.missingPendingRequest
        }
        guard snapshot.requestedTimelineTime.isValid,
              snapshot.requestedTimelineTime.isNumeric else {
            cancel(token: snapshot.token)
            throw AUFxAnalysisTransactionError.invalidTimelineTime
        }

        let inputTime = inputTimeFromTimeline(snapshot.requestedTimelineTime)
        guard inputTime.isValid, inputTime.isNumeric else {
            cancel(token: snapshot.token)
            throw AUFxAnalysisTransactionError.invalidInputTime
        }
        let duration = sampleDuration()
        let usesFallback = !duration.isValid
            || !duration.isNumeric
            || CMTimeCompare(duration, .zero) <= 0
        let range = AUFxAnalysisProbePolicy.range(
            near: inputTime,
            within: inputTimeRange,
            sampleDuration: duration
        )
        guard range.isValid, CMTimeCompare(range.duration, .zero) > 0 else {
            cancel(token: snapshot.token)
            throw AUFxAnalysisTransactionError.emptyInputRange
        }
        return AUFxAnalysisDesiredRange(
            token: snapshot.token,
            requestedTimelineTime: snapshot.requestedTimelineTime,
            inputTime: inputTime,
            sampleDuration: duration,
            usedFallbackSampleDuration: usesFallback,
            range: range
        )
    }

    @discardableResult
    func setupAnalysis(range: CMTimeRange) -> AUFxAnalysisTransactionToken? {
        lock.withLock {
            guard var active else {
                return nil
            }
            active.frameGate.reset()
            active.inputFrameTime = range.start
            active.outcome = .notProduced
            self.active = active
            return active.token
        }
    }

    func claimFrame(hasIOSurface: Bool, hasNonEmptyPixelBounds: Bool) -> AUFxAnalysisFrameClaim<Request>? {
        lock.withLock {
            guard var active else {
                return nil
            }
            let claimed = active.frameGate.claimIfUsable(hasIOSurface && hasNonEmptyPixelBounds)
            self.active = active
            guard claimed else {
                return nil
            }
            return AUFxAnalysisFrameClaim(
                token: active.token,
                request: active.request,
                requestedTimelineTime: active.requestedTimelineTime,
                callbackCount: active.frameGate.receivedFrameCount,
                analysisStartNanos: active.analysisStartNanos
            )
        }
    }

    var receivedFrameCount: Int {
        lock.withLock { active?.frameGate.receivedFrameCount ?? 0 }
    }

    var analysisStartNanos: UInt64? {
        lock.withLock { active?.analysisStartNanos }
    }

    func relinquishFrame(token: AUFxAnalysisTransactionToken) {
        lock.withLock {
            guard var active, active.token == token else {
                return
            }
            active.frameGate.relinquishClaimForUnusablePreparation()
            self.active = active
        }
    }

    func complete(
        token: AUFxAnalysisTransactionToken,
        outcome: AUFxAnalysisOutcome<Result>,
        inputFrameTime: CMTime
    ) {
        lock.withLock {
            guard var active, active.token == token else {
                return
            }
            active.outcome = outcome
            active.inputFrameTime = inputFrameTime
            self.active = active
        }
    }

    func cleanup() -> AUFxAnalysisCleanupSnapshot<Request, Result>? {
        lock.withLock {
            guard let active else {
                return nil
            }
            self.active = nil
            return AUFxAnalysisCleanupSnapshot(
                token: active.token,
                request: active.request,
                requestedTimelineTime: active.requestedTimelineTime,
                inputFrameTime: active.inputFrameTime,
                callbackCount: active.frameGate.receivedFrameCount,
                analysisStartNanos: active.analysisStartNanos,
                outcome: active.outcome
            )
        }
    }

    func cancelCurrentRequest() {
        lock.withLock { active = nil }
    }

    func cancel(token: AUFxAnalysisTransactionToken) {
        lock.withLock {
            guard active?.token == token else {
                return
            }
            active = nil
        }
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
