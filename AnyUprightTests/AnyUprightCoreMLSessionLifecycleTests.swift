//
//  AnyUprightCoreMLSessionLifecycleTests.swift
//  AnyUprightTests
//

import Foundation

private enum CoreMLLifecycleTestFailure: Error, CustomStringConvertible {
    case failed(String)

    var description: String {
        switch self {
        case .failed(let message):
            return message
        }
    }
}

private enum CoreMLLifecycleFixtureError: Error {
    case load
    case prediction
}

private final class LockedCounter {
    private let condition = NSCondition()
    private var storedValue = 0

    var value: Int {
        condition.lock()
        defer { condition.unlock() }
        return storedValue
    }

    @discardableResult
    func increment() -> Int {
        condition.lock()
        storedValue += 1
        let value = storedValue
        condition.broadcast()
        condition.unlock()
        return value
    }

    func waitForValue(_ expected: Int, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        condition.lock()
        defer { condition.unlock() }
        while storedValue < expected {
            if !condition.wait(until: deadline) {
                return false
            }
        }
        return true
    }
}

private final class LogRecorder {
    private let condition = NSCondition()
    private var messages: [String] = []

    func append(_ message: String) {
        condition.lock()
        messages.append(message)
        condition.broadcast()
        condition.unlock()
    }

    func contains(_ fragment: String) -> Bool {
        condition.lock()
        defer { condition.unlock() }
        return messages.contains { $0.contains(fragment) }
    }

    func waitFor(_ fragment: String, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        condition.lock()
        defer { condition.unlock() }
        while !messages.contains(where: { $0.contains(fragment) }) {
            if !condition.wait(until: deadline) {
                return false
            }
        }
        return true
    }
}

private final class FakeSession {
    let id: Int

    init(id: Int) {
        self.id = id
    }
}

private final class TrackedSession {
    private let deinitCounter: LockedCounter

    init(deinitCounter: LockedCounter) {
        self.deinitCounter = deinitCounter
    }

    deinit {
        deinitCounter.increment()
    }
}

@main
struct AnyUprightCoreMLSessionLifecycleTests {
    static func main() throws {
        try testRetentionPolicyWindows()
        try testConcurrentColdLoadOccursOnce()
        try testPrewarmIsAsynchronousAndDoesNotRepeatWarmUp()
        try testIndependentExpiryAndGenerationProtection()
        try testInferenceRetainsSessionPastCacheExpiry()
        try testLoadRetryAndPredictionFailureCacheBehavior()
        try testSessionReadyCallbackOrderingAndCacheHit()
        try testConfigurationReplacementKeepsInFlightSessionAlive()
        print("AnyUprightCoreMLSessionLifecycleTests passed")
    }

    private static func testRetentionPolicyWindows() throws {
        let second: UInt64 = 1_000_000_000
        let policy = AUCoreMLSessionRetentionPolicy(
            pluginIdleNanoseconds: 15 * second,
            firstAnalysisNanoseconds: 30 * second,
            repeatedAnalysisNanoseconds: 60 * second
        )
        var state = AUCoreMLSessionRetentionState()

        try require(state.markPluginAdded(at: 100 * second, policy: policy) == 115 * second, "plugin add deadline")
        let first = state.markAnalysisStarted(at: 110 * second, policy: policy)
        try require(first.analysisCountInWindow == 1, "first analysis count")
        try require(first.deadlineNanos == 140 * second, "first analysis deadline")

        let secondAnalysis = state.markAnalysisStarted(at: 120 * second, policy: policy)
        try require(secondAnalysis.analysisCountInWindow == 2, "second analysis count")
        try require(secondAnalysis.deadlineNanos == 180 * second, "second analysis deadline")
        try require(state.markPluginAdded(at: 125 * second, policy: policy) == 180 * second, "plugin add must not shorten deadline")

        let resetWindow = state.markAnalysisStarted(at: 150 * second, policy: policy)
        try require(resetWindow.analysisCountInWindow == 1, "analysis count should reset after original window")
        try require(resetWindow.deadlineNanos == 180 * second, "reset analysis must not shorten repeated retention")

        state.didUnload()
        let afterUnload = state.markAnalysisStarted(at: 181 * second, policy: policy)
        try require(afterUnload.analysisCountInWindow == 1, "unload should reset analysis count")
        try require(afterUnload.deadlineNanos == 211 * second, "analysis deadline after unload")
    }

    private static func testConcurrentColdLoadOccursOnce() throws {
        let loadCounter = LockedCounter()
        let recorder = LogRecorder()
        let cache = AUCoreMLSessionLifecycleCache<String, FakeSession>(
            label: "test.concurrent",
            retentionPolicy: longRetentionPolicy,
            keyDescription: { $0 },
            loadSession: { _ in
                Thread.sleep(forTimeInterval: 0.03)
                return FakeSession(id: loadCounter.increment())
            },
            warmSession: { _ in },
            logger: recorder.append
        )

        let group = DispatchGroup()
        let resultLock = NSLock()
        var ids: [Int] = []
        var failures: [Error] = []
        for _ in 0..<8 {
            group.enter()
            DispatchQueue.global().async {
                defer { group.leave() }
                do {
                    let result = try cache.withSessionForAnalysis(key: "fixed") { $0.id }
                    resultLock.lock()
                    ids.append(result.output)
                    resultLock.unlock()
                } catch {
                    resultLock.lock()
                    failures.append(error)
                    resultLock.unlock()
                }
            }
        }
        try require(group.wait(timeout: .now() + 3) == .success, "concurrent analysis timed out")
        try require(failures.isEmpty, "concurrent analysis failed: \(failures)")
        try require(loadCounter.value == 1, "concurrent cold requests should load once")
        try require(ids.count == 8 && Set(ids) == [1], "concurrent requests should share one session")
    }

    private static func testPrewarmIsAsynchronousAndDoesNotRepeatWarmUp() throws {
        let loadCounter = LockedCounter()
        let warmCounter = LockedCounter()
        let recorder = LogRecorder()
        let cache = AUCoreMLSessionLifecycleCache<String, FakeSession>(
            label: "test.prewarm",
            retentionPolicy: longRetentionPolicy,
            keyDescription: { $0 },
            loadSession: { _ in
                Thread.sleep(forTimeInterval: 0.12)
                return FakeSession(id: loadCounter.increment())
            },
            warmSession: { _ in warmCounter.increment() },
            logger: recorder.append
        )

        let start = DispatchTime.now().uptimeNanoseconds
        cache.prewarmAfterPluginAdded(key: "fixed")
        let elapsedMilliseconds = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000.0
        try require(elapsedMilliseconds < 50, "prewarm call should return before the slow load completes")
        try require(warmCounter.waitForValue(1, timeout: 2), "prewarm did not finish")
        try require(loadCounter.value == 1, "prewarm should load once")

        cache.prewarmAfterPluginAdded(key: "fixed")
        try require(recorder.waitFor("prewarm_cache_hit key=fixed", timeout: 2), "second prewarm did not hit cache")
        try require(loadCounter.value == 1, "cache-hit prewarm should not reload")
        try require(warmCounter.value == 1, "cache-hit prewarm should not repeat warm-up")
    }

    private static func testIndependentExpiryAndGenerationProtection() throws {
        let loadCounter = LockedCounter()
        let recorder = LogRecorder()
        let policy = AUCoreMLSessionRetentionPolicy(
            pluginIdleNanoseconds: 100_000_000,
            firstAnalysisNanoseconds: 200_000_000,
            repeatedAnalysisNanoseconds: 400_000_000
        )
        let cache = AUCoreMLSessionLifecycleCache<String, FakeSession>(
            label: "test.expiry",
            retentionPolicy: policy,
            keyDescription: { $0 },
            loadSession: { _ in FakeSession(id: loadCounter.increment()) },
            warmSession: { _ in },
            logger: recorder.append
        )

        cache.prewarmAfterPluginAdded(key: "A")
        cache.prewarmAfterPluginAdded(key: "B")
        try require(recorder.waitFor("prewarm_ok key=A", timeout: 1), "A prewarm missing")
        try require(recorder.waitFor("prewarm_ok key=B", timeout: 1), "B prewarm missing")

        _ = try cache.withSessionForAnalysis(key: "A") { $0.id }
        _ = try cache.withSessionForAnalysis(key: "A") { $0.id }
        try require(recorder.waitFor("unloaded key=B", timeout: 1), "B should expire independently")
        Thread.sleep(forTimeInterval: 0.23)
        try require(!recorder.contains("unloaded key=A"), "old A timers must not beat repeated-analysis retention")

        let warmA = try cache.withSessionForAnalysis(key: "A") { $0.id }
        try require(warmA.cacheHit, "A should remain cached after B expires")
        try require(recorder.waitFor("unloaded key=A", timeout: 1.5), "A should eventually expire")
    }

    private static func testInferenceRetainsSessionPastCacheExpiry() throws {
        let deinitCounter = LockedCounter()
        let recorder = LogRecorder()
        weak var weakSession: TrackedSession?
        let cache = AUCoreMLSessionLifecycleCache<String, TrackedSession>(
            label: "test.hold",
            retentionPolicy: AUCoreMLSessionRetentionPolicy(
                pluginIdleNanoseconds: 20_000_000,
                firstAnalysisNanoseconds: 50_000_000,
                repeatedAnalysisNanoseconds: 80_000_000
            ),
            keyDescription: { $0 },
            loadSession: { _ in
                let session = TrackedSession(deinitCounter: deinitCounter)
                weakSession = session
                return session
            },
            warmSession: { _ in },
            logger: recorder.append
        )

        _ = try cache.withSessionForAnalysis(key: "fixed") { session in
            Thread.sleep(forTimeInterval: 0.12)
            try require(weakSession === session, "in-flight closure should retain expired session")
            try require(deinitCounter.value == 0, "session deinitialized during inference")
            return 1
        }
        try require(recorder.waitFor("unloaded key=fixed", timeout: 1), "cache did not expire during long inference")
        try require(deinitCounter.waitForValue(1, timeout: 1), "session should release after inference completes")
    }

    private static func testLoadRetryAndPredictionFailureCacheBehavior() throws {
        let attempts = LockedCounter()
        let recorder = LogRecorder()
        let cache = AUCoreMLSessionLifecycleCache<String, FakeSession>(
            label: "test.failure",
            retentionPolicy: longRetentionPolicy,
            keyDescription: { $0 },
            loadSession: { _ in
                let attempt = attempts.increment()
                if attempt == 1 {
                    throw CoreMLLifecycleFixtureError.load
                }
                return FakeSession(id: attempt)
            },
            warmSession: { _ in },
            logger: recorder.append
        )

        do {
            _ = try cache.withSessionForAnalysis(key: "fixed") { $0.id }
            throw CoreMLLifecycleTestFailure.failed("first load should fail")
        } catch CoreMLLifecycleFixtureError.load {
            // Expected.
        }

        let retry = try cache.withSessionForAnalysis(key: "fixed") { $0.id }
        try require(retry.output == 2 && !retry.cacheHit, "successful retry should load a fresh session")
        do {
            _ = try cache.withSessionForAnalysis(key: "fixed") { _ in
                throw CoreMLLifecycleFixtureError.prediction
            }
            throw CoreMLLifecycleTestFailure.failed("prediction should fail")
        } catch CoreMLLifecycleFixtureError.prediction {
            // Expected.
        }
        let afterPredictionFailure = try cache.withSessionForAnalysis(key: "fixed") { $0.id }
        try require(afterPredictionFailure.cacheHit, "prediction failure should not evict the session")
        try require(attempts.value == 2, "prediction failure should not reload the model")
    }

    private static func testConfigurationReplacementKeepsInFlightSessionAlive() throws {
        let entered = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        let completed = DispatchSemaphore(value: 0)
        let recorder = LogRecorder()
        var cache: AUCoreMLSessionLifecycleCache<String, FakeSession>? = AUCoreMLSessionLifecycleCache(
            label: "test.config.old",
            retentionPolicy: longRetentionPolicy,
            keyDescription: { $0 },
            loadSession: { _ in FakeSession(id: 1) },
            warmSession: { _ in },
            logger: recorder.append
        )
        let runningCache = cache!
        DispatchQueue.global().async {
            _ = try? runningCache.withSessionForAnalysis(key: "fixed") { session in
                entered.signal()
                _ = release.wait(timeout: .now() + 2)
                return session.id
            }
            completed.signal()
        }
        try require(entered.wait(timeout: .now() + 2) == .success, "old configuration did not start")

        cache = AUCoreMLSessionLifecycleCache(
            label: "test.config.new",
            retentionPolicy: longRetentionPolicy,
            keyDescription: { $0 },
            loadSession: { _ in FakeSession(id: 2) },
            warmSession: { _ in },
            logger: recorder.append
        )
        let newResult = try cache!.withSessionForAnalysis(key: "fixed") { $0.id }
        try require(newResult.output == 2, "new configuration should use its own cache")
        release.signal()
        try require(completed.wait(timeout: .now() + 2) == .success, "old in-flight configuration did not finish")
    }

    private static func testSessionReadyCallbackOrderingAndCacheHit() throws {
        let recorder = LogRecorder()
        let cache = AUCoreMLSessionLifecycleCache<String, FakeSession>(
            label: "test.ready",
            retentionPolicy: longRetentionPolicy,
            keyDescription: { $0 },
            loadSession: { _ in FakeSession(id: 1) },
            warmSession: { _ in },
            logger: recorder.append
        )
        var events: [String] = []
        let first = try cache.withSessionForAnalysis(
            key: "fixed",
            sessionReady: { events.append("ready-\($0)") }
        ) { session in
            events.append("run-\(session.id)")
            return session.id
        }
        try require(first.output == 1 && !first.cacheHit, "first run must load")
        try require(events == ["ready-false", "run-1"], "ready callback must precede cold prediction")

        events.removeAll()
        let second = try cache.withSessionForAnalysis(
            key: "fixed",
            sessionReady: { events.append("ready-\($0)") }
        ) { session in
            events.append("run-\(session.id)")
            return session.id
        }
        try require(second.cacheHit, "second run must hit cache")
        try require(events == ["ready-true", "run-1"], "ready callback must report cache hit before prediction")

        let failing = AUCoreMLSessionLifecycleCache<String, FakeSession>(
            label: "test.ready.failure",
            retentionPolicy: longRetentionPolicy,
            keyDescription: { $0 },
            loadSession: { _ in throw CoreMLLifecycleFixtureError.load },
            warmSession: { _ in },
            logger: recorder.append
        )
        var callbackCount = 0
        do {
            _ = try failing.withSessionForAnalysis(
                key: "fixed",
                sessionReady: { _ in callbackCount += 1 }
            ) { $0.id }
            throw CoreMLLifecycleTestFailure.failed("load failure must throw")
        } catch CoreMLLifecycleFixtureError.load {}
        try require(callbackCount == 0, "failed load must not report a ready session")
    }

    private static let longRetentionPolicy = AUCoreMLSessionRetentionPolicy(
        pluginIdleNanoseconds: 5_000_000_000,
        firstAnalysisNanoseconds: 5_000_000_000,
        repeatedAnalysisNanoseconds: 5_000_000_000
    )

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else {
            throw CoreMLLifecycleTestFailure.failed(message)
        }
    }
}
