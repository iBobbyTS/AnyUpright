import Foundation

private enum AnalysisDiagnosticsTestFailure: Error, CustomStringConvertible {
    case failed(String)
    var description: String {
        switch self {
        case .failed(let message): return message
        }
    }
}

@main
struct AnyUprightAnalysisDiagnosticsTests {
    static func main() throws {
        try testMarkerAndAppend()
        try testConcurrentLines()
        try testClock()
        print("AnyUprightAnalysisDiagnosticsTests passed")
    }

    private static func testMarkerAndAppend() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let marker = directory.appendingPathComponent("enabled")
        let log = directory.appendingPathComponent("analysis.log")
        let logger = AUAnalysisLogger(markerPath: marker.path, logPath: log.path, prefix: "analysis ")
        logger.log("disabled")
        try require(!FileManager.default.fileExists(atPath: log.path), "disabled marker must not write")
        try Data().write(to: marker)
        logger.log("first")
        logger.log("second")
        let contents = try String(contentsOf: log, encoding: .utf8)
        try require(contents.contains("analysis first") && contents.contains("analysis second"), "logger must create and append")
    }

    private static func testConcurrentLines() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let marker = directory.appendingPathComponent("enabled")
        let log = directory.appendingPathComponent("analysis.log")
        try Data().write(to: marker)
        let logger = AUAnalysisLogger(markerPath: marker.path, logPath: log.path)
        DispatchQueue.concurrentPerform(iterations: 40) { logger.log("line_\($0)") }
        let lines = try String(contentsOf: log, encoding: .utf8).split(separator: "\n")
        try require(lines.count == 40, "concurrent writes must preserve complete lines")
    }

    private static func testClock() throws {
        let start = AUMonotonicClock.nowNanos()
        let end = AUMonotonicClock.nowNanos()
        try require(end >= start, "clock must be monotonic")
        try require(AUMonotonicClock.elapsedMilliseconds(since: start, nowNanos: end) >= 0, "elapsed time must be nonnegative")
        try require(AUMonotonicClock.elapsedMilliseconds(since: 10, nowNanos: 5) == 0, "clock rollback must clamp")
        try require(AUAnalysisDiagnostics.upright === AUAnalysisDiagnostics.upright, "upright diagnostics must be process shared")
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw AnalysisDiagnosticsTestFailure.failed(message) }
    }
}
