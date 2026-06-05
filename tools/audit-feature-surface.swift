//
//  audit-feature-surface.swift
//  AnyUpright
//

import Foundation

enum FeatureSurfaceAuditFailure: Error, CustomStringConvertible {
    case failed(String)

    var description: String {
        switch self {
        case .failed(let message):
            return message
        }
    }
}

struct FeaturePluginExpectation {
    var className: String
    var protocols: Set<String>
}

struct AuditFeatureSurface {
    static func run() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? FileManager.default.currentDirectoryPath)
        let infoPlist = root.appendingPathComponent("AnyUpright/Plugin/Info.plist")
        let effects = try String(contentsOf: root.appendingPathComponent("AnyUpright/Plugin/AnyUprightManualEffects.swift"), encoding: .utf8)
        let geometry = try String(contentsOf: root.appendingPathComponent("AnyUpright/Plugin/AnyUprightGeometry.swift"), encoding: .utf8)
        let warp = try String(contentsOf: root.appendingPathComponent("AnyUpright/Plugin/AnyUprightWarpEffect.swift"), encoding: .utf8)
        let candidates = try String(contentsOf: root.appendingPathComponent("AnyUpright/Plugin/AnyUprightUprightCandidates.swift"), encoding: .utf8)

        try auditRegisteredPlugins(infoPlist)
        try auditHorizon(effects)
        try auditQuad(effects, geometry: geometry)
        try auditUpright(effects, geometry: geometry, warp: warp, candidates: candidates)

        print("AnyUpright feature surface audit passed")
    }

    private static func auditRegisteredPlugins(_ infoPlist: URL) throws {
        let data = try Data(contentsOf: infoPlist)
        guard let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              let plugins = plist["ProPlugPlugInList"] as? [[String: Any]] else {
            throw FeatureSurfaceAuditFailure.failed("Unable to read ProPlugPlugInList")
        }

        let expected = [
            FeaturePluginExpectation(className: "AnyUprightHorizonManualPlugIn", protocols: ["FxFilter", "FxAnalyzer"]),
            FeaturePluginExpectation(className: "AnyUprightQuadManualPlugIn", protocols: ["FxFilter", "FxOnScreenControl"]),
            FeaturePluginExpectation(className: "AnyUprightUprightManualPlugIn", protocols: ["FxFilter", "FxAnalyzer", "FxOnScreenControl"])
        ]

        for item in expected {
            guard let plugin = plugins.first(where: { $0["className"] as? String == item.className }) else {
                throw FeatureSurfaceAuditFailure.failed("Missing registered plugin \(item.className)")
            }
            let protocols = Set(plugin["protocolNames"] as? [String] ?? [])
            try assertEqual(protocols, item.protocols, "\(item.className) protocols")
        }
    }

    private static func auditHorizon(_ effects: String) throws {
        try require(effects, "VNDetectHorizonRequest()", "Horizon uses Vision horizon detection")
        try require(effects, "dominantHorizonCorrectionRadians", "Horizon has a traditional line fallback")
        try require(effects, "Analyze Horizon", "Horizon exposes explicit analysis button")
        try require(effects, "Fill Frame", "Horizon exposes fill toggle")
        try require(effects, "singleFrameAnalysisRange", "Horizon analysis targets a representative frame")
    }

    private static func auditQuad(_ effects: String, geometry: String) throws {
        try require(effects, "Output Corners", "Quad exposes realtime output-corner mode")
        try require(effects, "Source Quad", "Quad exposes Lens-style source-quad mode")
        try require(effects, "Show Corner Adjuster", "Quad can show source-quad handles without applying the warp")
        try require(effects, "FxOnScreenControl_v4", "Quad exposes onscreen controls")
        try require(effects, "renderQuadAdjuster", "Source Quad draws a dedicated adjuster overlay")
        try require(geometry, "quadOutputToSourceMatrix", "Quad render matrix is centralized in geometry")
        try require(geometry, "sourceQuadDefault", "Source Quad has a central default quadrilateral")
        try require(geometry, "sourceQuadObjectPoints", "Source Quad handles use their own object-space base")
        try require(geometry, "guard !showCornerAdjuster else", "Source Quad mode can preview handles without warping")
        try require(geometry, "cornerPixelOffset", "Quad OSC writes stable corner pixel offsets")
    }

    private static func auditUpright(_ effects: String, geometry: String, warp: String, candidates: String) throws {
        try require(effects, "Auto Vertical", "Upright exposes automatic vertical correction")
        try require(effects, "Auto Horizontal", "Upright exposes automatic horizontal correction")
        try require(effects, "Auto Full", "Upright exposes automatic full correction")
        try require(effects, "Detect Vertical Candidates", "Upright exposes semi-auto vertical detection")
        try require(effects, "Detect Horizontal Candidates", "Upright exposes semi-auto horizontal detection")
        try require(effects, "Detect Full Candidates", "Upright exposes semi-auto full detection")
        try require(effects, "Apply Selected Full", "Upright can apply selected semi-auto candidates")
        try require(effects, "Apply Guided Full", "Upright can apply manually drawn guides")
        try require(effects, "guide4Enabled", "Upright exposes four guide lines")
        try require(effects, "guide4Start", "Upright exposes the fourth guide start handle")
        try require(effects, "guide4End", "Upright exposes the fourth guide end handle")
        try require(effects, "lineCandidates.prefix(2)", "Upright auto chooses at most two smallest-angle references")
        try require(geometry, "uprightOutputToSourceMatrix", "Upright perspective matrix is centralized in geometry")
        try require(geometry, "isStrictlyWithinDeviationLimit", "Upright candidate filtering uses strict deviation limits")
        try require(warp, "uprightOutputToSourceMatrix", "Upright Metal renderer uses centered perspective matrix")
        try require(candidates, "maximumSelectedPerOrientation: Int = 2", "Semi-auto selection limits to two references per orientation")
        try require(candidates, "slotCount = 40", "Semi-auto has fixed candidate slots for detected lines")
    }

    private static func require(_ haystack: String, _ needle: String, _ label: String) throws {
        guard haystack.contains(needle) else {
            throw FeatureSurfaceAuditFailure.failed("\(label): missing \(needle)")
        }
    }

    private static func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ label: String) throws {
        guard actual == expected else {
            throw FeatureSurfaceAuditFailure.failed("\(label): expected \(expected), got \(actual)")
        }
    }
}

do {
    try AuditFeatureSurface.run()
} catch {
    FileHandle.standardError.write(Data("\(error)\n".utf8))
    exit(1)
}
