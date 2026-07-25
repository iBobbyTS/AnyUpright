//
//  AnyUprightCoreMLSessionLifecycle.swift
//  AnyUpright
//

import Dispatch
import Foundation

struct AUCoreMLSessionRetentionPolicy: Equatable {
    var pluginIdleNanoseconds: UInt64
    var firstAnalysisNanoseconds: UInt64
    var repeatedAnalysisNanoseconds: UInt64

    static let analysisDefault = AUCoreMLSessionRetentionPolicy(
        pluginIdleNanoseconds: 15_000_000_000,
        firstAnalysisNanoseconds: 30_000_000_000,
        repeatedAnalysisNanoseconds: 60_000_000_000
    )
}

struct AUCoreMLSessionLifecycleRunResult<Output> {
    var output: Output
    var cacheHit: Bool
    var loadMilliseconds: Double
    var predictionMilliseconds: Double
    var totalMilliseconds: Double
}

struct AUCoreMLSessionRetentionEvent {
    var deadlineNanos: UInt64
    var analysisCountInWindow: Int
    var retentionNanoseconds: UInt64
}

struct AUCoreMLSessionRetentionState {
    private(set) var unloadDeadlineNanos: UInt64?
    private(set) var analysisWindowDeadlineNanos: UInt64?
    private(set) var analysisCountInWindow = 0

    mutating func markPluginAdded(
        at nowNanos: UInt64,
        policy: AUCoreMLSessionRetentionPolicy
    ) -> UInt64 {
        let deadline = nowNanos + policy.pluginIdleNanoseconds
        extendUnloadDeadline(to: deadline)
        return unloadDeadlineNanos ?? deadline
    }

    mutating func markAnalysisStarted(
        at nowNanos: UInt64,
        policy: AUCoreMLSessionRetentionPolicy
    ) -> AUCoreMLSessionRetentionEvent {
        if let windowDeadline = analysisWindowDeadlineNanos, nowNanos <= windowDeadline {
            analysisCountInWindow += 1
        } else {
            analysisCountInWindow = 1
            analysisWindowDeadlineNanos = nowNanos + policy.firstAnalysisNanoseconds
        }

        let retention = analysisCountInWindow >= 2
            ? policy.repeatedAnalysisNanoseconds
            : policy.firstAnalysisNanoseconds
        let deadline = nowNanos + retention
        extendUnloadDeadline(to: deadline)
        return AUCoreMLSessionRetentionEvent(
            deadlineNanos: unloadDeadlineNanos ?? deadline,
            analysisCountInWindow: analysisCountInWindow,
            retentionNanoseconds: retention
        )
    }

    mutating func didUnload() {
        unloadDeadlineNanos = nil
        analysisWindowDeadlineNanos = nil
        analysisCountInWindow = 0
    }

    private mutating func extendUnloadDeadline(to deadline: UInt64) {
        if let current = unloadDeadlineNanos, current > deadline {
            return
        }
        unloadDeadlineNanos = deadline
    }
}

final class AUCoreMLSessionLifecycleCache<Key: Hashable, Session> {
    typealias Logger = (String) -> Void

    private final class Entry {
        var session: Session?
        var retentionState = AUCoreMLSessionRetentionState()
        var timer: DispatchSourceTimer?
        var generation: UInt64 = 0
    }

    private struct Acquisition {
        var session: Session
        var cacheHit: Bool
        var loadMilliseconds: Double
    }

    private let label: String
    private let retentionPolicy: AUCoreMLSessionRetentionPolicy
    private let keyDescription: (Key) -> String
    private let loadSession: (Key) throws -> Session
    private let warmSession: (Session) throws -> Void
    private let loggerLock = NSLock()
    private var logger: Logger
    private let stateQueue: DispatchQueue
    private let prewarmQueue: DispatchQueue
    private let loggerQueue: DispatchQueue
    private let stateQueueKey = DispatchSpecificKey<Void>()
    private var entries: [Key: Entry] = [:]

    init(
        label: String,
        retentionPolicy: AUCoreMLSessionRetentionPolicy = .analysisDefault,
        keyDescription: @escaping (Key) -> String,
        loadSession: @escaping (Key) throws -> Session,
        warmSession: @escaping (Session) throws -> Void,
        logger: @escaping Logger
    ) {
        self.label = label
        self.retentionPolicy = retentionPolicy
        self.keyDescription = keyDescription
        self.loadSession = loadSession
        self.warmSession = warmSession
        self.logger = logger
        stateQueue = DispatchQueue(label: "\(label).state")
        prewarmQueue = DispatchQueue(label: "\(label).prewarm")
        loggerQueue = DispatchQueue(label: "\(label).logger")
        stateQueue.setSpecific(key: stateQueueKey, value: ())
    }

    deinit {
        let cancelTimers = {
            for entry in self.entries.values {
                entry.timer?.cancel()
                entry.timer = nil
            }
            self.entries.removeAll()
        }
        if DispatchQueue.getSpecific(key: stateQueueKey) != nil {
            cancelTimers()
        } else {
            stateQueue.sync(execute: cancelTimers)
        }
    }

    func prewarmAfterPluginAdded(key: Key) {
        let now = Self.nowNanos()
        let keyLabel = keyDescription(key)
        let deadline = stateQueue.sync { () -> UInt64 in
            let entry = entryLocked(for: key)
            let deadline = entry.retentionState.markPluginAdded(at: now, policy: retentionPolicy)
            scheduleExpirationLocked(
                key: key,
                entry: entry,
                deadlineNanos: deadline,
                reason: "plugin_added"
            )
            return deadline
        }
        emit(String(
            format: "%@ plugin_added key=%@ expiry_s=%.3f",
            label,
            keyLabel,
            Double(deadline - now) / 1_000_000_000.0
        ))

        prewarmQueue.async { [weak self] in
            self?.performPrewarm(key: key)
        }
    }

    func updateLogger(_ logger: @escaping Logger) {
        loggerLock.lock()
        self.logger = logger
        loggerLock.unlock()
    }

    func withSessionForAnalysis<Output>(
        key: Key,
        run: (Session) throws -> Output
    ) throws -> AUCoreMLSessionLifecycleRunResult<Output> {
        let totalStart = Self.nowNanos()
        let keyLabel = keyDescription(key)
        var pendingLogs: [String] = []
        let acquisition: Acquisition

        do {
            acquisition = try stateQueue.sync {
                let now = Self.nowNanos()
                let entry = entryLocked(for: key)
                let event = entry.retentionState.markAnalysisStarted(at: now, policy: retentionPolicy)
                scheduleExpirationLocked(
                    key: key,
                    entry: entry,
                    deadlineNanos: event.deadlineNanos,
                    reason: "analysis_started"
                )
                pendingLogs.append(String(
                    format: "%@ analysis_started key=%@ count_in_window=%d retention_s=%.0f expiry_s=%.3f",
                    label,
                    keyLabel,
                    event.analysisCountInWindow,
                    Double(event.retentionNanoseconds) / 1_000_000_000.0,
                    Double(event.deadlineNanos - now) / 1_000_000_000.0
                ))
                return try acquireSessionLocked(key: key, entry: entry, logs: &pendingLogs)
            }
        } catch {
            pendingLogs.forEach(emit)
            emit("\(label) load_failed key=\(keyLabel) error=\(String(describing: error))")
            throw error
        }
        pendingLogs.forEach(emit)

        let predictionStart = Self.nowNanos()
        do {
            let output = try run(acquisition.session)
            let predictionMilliseconds = Self.elapsedMilliseconds(since: predictionStart)
            let totalMilliseconds = Self.elapsedMilliseconds(since: totalStart)
            emit(String(
                format: "%@ run key=%@ cache_hit=%@ load_ms=%.3f predict_ms=%.3f total_ms=%.3f",
                label,
                keyLabel,
                acquisition.cacheHit ? "true" : "false",
                acquisition.loadMilliseconds,
                predictionMilliseconds,
                totalMilliseconds
            ))
            return AUCoreMLSessionLifecycleRunResult(
                output: output,
                cacheHit: acquisition.cacheHit,
                loadMilliseconds: acquisition.loadMilliseconds,
                predictionMilliseconds: predictionMilliseconds,
                totalMilliseconds: totalMilliseconds
            )
        } catch {
            emit(String(
                format: "%@ run_failed key=%@ cache_hit=%@ load_ms=%.3f predict_ms=%.3f error=%@",
                label,
                keyLabel,
                acquisition.cacheHit ? "true" : "false",
                acquisition.loadMilliseconds,
                Self.elapsedMilliseconds(since: predictionStart),
                String(describing: error)
            ))
            throw error
        }
    }

    private func performPrewarm(key: Key) {
        let totalStart = Self.nowNanos()
        let keyLabel = keyDescription(key)
        var pendingLogs: [String] = []
        let acquisition: Acquisition
        do {
            acquisition = try stateQueue.sync {
                let entry = entryLocked(for: key)
                return try acquireSessionLocked(key: key, entry: entry, logs: &pendingLogs)
            }
        } catch {
            pendingLogs.forEach(emit)
            emit("\(label) prewarm_failed key=\(keyLabel) error=\(String(describing: error))")
            return
        }
        pendingLogs.forEach(emit)

        guard !acquisition.cacheHit else {
            emit(String(
                format: "%@ prewarm_cache_hit key=%@ total_ms=%.3f",
                label,
                keyLabel,
                Self.elapsedMilliseconds(since: totalStart)
            ))
            return
        }

        let warmStart = Self.nowNanos()
        do {
            try warmSession(acquisition.session)
            emit(String(
                format: "%@ prewarm_ok key=%@ load_ms=%.3f warm_ms=%.3f total_ms=%.3f",
                label,
                keyLabel,
                acquisition.loadMilliseconds,
                Self.elapsedMilliseconds(since: warmStart),
                Self.elapsedMilliseconds(since: totalStart)
            ))
        } catch {
            emit(String(
                format: "%@ prewarm_failed key=%@ load_ms=%.3f warm_ms=%.3f error=%@",
                label,
                keyLabel,
                acquisition.loadMilliseconds,
                Self.elapsedMilliseconds(since: warmStart),
                String(describing: error)
            ))
        }
    }

    private func entryLocked(for key: Key) -> Entry {
        if let entry = entries[key] {
            return entry
        }
        let entry = Entry()
        entries[key] = entry
        return entry
    }

    private func acquireSessionLocked(
        key: Key,
        entry: Entry,
        logs: inout [String]
    ) throws -> Acquisition {
        if let session = entry.session {
            return Acquisition(session: session, cacheHit: true, loadMilliseconds: 0)
        }

        let loadStart = Self.nowNanos()
        let session = try loadSession(key)
        let loadMilliseconds = Self.elapsedMilliseconds(since: loadStart)
        entry.session = session
        logs.append(String(
            format: "%@ loaded key=%@ load_ms=%.3f",
            label,
            keyDescription(key),
            loadMilliseconds
        ))
        return Acquisition(session: session, cacheHit: false, loadMilliseconds: loadMilliseconds)
    }

    private func scheduleExpirationLocked(
        key: Key,
        entry: Entry,
        deadlineNanos: UInt64,
        reason: String
    ) {
        entry.generation &+= 1
        let generation = entry.generation
        entry.timer?.cancel()

        let timer = DispatchSource.makeTimerSource(queue: stateQueue)
        entry.timer = timer
        let now = Self.nowNanos()
        let delayNanos = deadlineNanos > now ? deadlineNanos - now : 0
        let boundedDelay = min(delayNanos, UInt64(Int.max))
        timer.schedule(deadline: .now() + .nanoseconds(Int(boundedDelay)))
        timer.setEventHandler { [weak self] in
            self?.expireIfDueLocked(key: key, generation: generation)
        }
        timer.resume()
        emit(String(
            format: "%@ expiry_scheduled key=%@ reason=%@ delay_s=%.3f generation=%llu",
            label,
            keyDescription(key),
            reason,
            Double(delayNanos) / 1_000_000_000.0,
            generation
        ))
    }

    private func expireIfDueLocked(key: Key, generation: UInt64) {
        guard let entry = entries[key],
              generation == entry.generation,
              let deadline = entry.retentionState.unloadDeadlineNanos else {
            return
        }

        let now = Self.nowNanos()
        guard now >= deadline else {
            scheduleExpirationLocked(
                key: key,
                entry: entry,
                deadlineNanos: deadline,
                reason: "deadline_adjusted"
            )
            return
        }

        let hadSession = entry.session != nil
        entry.session = nil
        entry.timer?.cancel()
        entry.timer = nil
        entry.retentionState.didUnload()
        entries.removeValue(forKey: key)
        emit("\(label) unloaded key=\(keyDescription(key)) count=\(hadSession ? 1 : 0)")
    }

    private func emit(_ message: String) {
        loggerLock.lock()
        let logger = self.logger
        loggerLock.unlock()
        loggerQueue.async {
            logger(message)
        }
    }

    private static func nowNanos() -> UInt64 {
        DispatchTime.now().uptimeNanoseconds
    }

    private static func elapsedMilliseconds(since startNanos: UInt64) -> Double {
        Double(nowNanos() - startNanos) / 1_000_000.0
    }
}
