//
//  AnyUprightAnalysisDiagnostics.swift
//  AnyUpright
//

import Foundation

enum AUMonotonicClock {
    static func nowNanos() -> UInt64 {
        DispatchTime.now().uptimeNanoseconds
    }

    static func elapsedMilliseconds(since startNanos: UInt64, nowNanos: UInt64 = nowNanos()) -> Double {
        guard nowNanos >= startNanos else {
            return 0
        }
        return Double(nowNanos - startNanos) / 1_000_000.0
    }
}

final class AUAnalysisLogger {
    let markerPath: String
    let logPath: String

    private let prefix: String
    private let fileManager: FileManager
    private let lock = NSLock()

    init(markerPath: String, logPath: String, prefix: String = "", fileManager: FileManager = .default) {
        self.markerPath = markerPath
        self.logPath = logPath
        self.prefix = prefix
        self.fileManager = fileManager
    }

    func log(_ message: String) {
        guard fileManager.fileExists(atPath: markerPath) else {
            return
        }
        let timestamp = String(format: "%.3f", Date().timeIntervalSince1970)
        guard let data = "[\(timestamp)] \(prefix)\(message)\n".data(using: .utf8) else {
            return
        }

        lock.lock()
        defer { lock.unlock() }
        let url = URL(fileURLWithPath: logPath)
        if fileManager.fileExists(atPath: logPath),
           let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url)
        }
    }
}

enum AUAnalysisDiagnostics {
    static let horizon = AUAnalysisLogger(
        markerPath: "/tmp/AnyUprightGeoCalib.debug",
        logPath: "/tmp/anyupright-geocalib-debug.log"
    )
    static let upright = AUAnalysisLogger(
        markerPath: "/tmp/AnyUprightUprightAnalysis.debug",
        logPath: "/tmp/AnyUprightUprightAnalysis.log"
    )
}
