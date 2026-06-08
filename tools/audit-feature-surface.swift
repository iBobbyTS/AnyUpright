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
    var supportedPlugins: Set<String> = []
}

struct AuditFeatureSurface {
    static func run() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? FileManager.default.currentDirectoryPath)
        let infoPlist = root.appendingPathComponent("AnyUpright/Plugin/Info.plist")
        let effects = try String(contentsOf: root.appendingPathComponent("AnyUpright/Plugin/AnyUprightManualEffects.swift"), encoding: .utf8)
        let geometry = try String(contentsOf: root.appendingPathComponent("AnyUpright/Plugin/AnyUprightGeometry.swift"), encoding: .utf8)
        let overlay = try String(contentsOf: root.appendingPathComponent("AnyUpright/Plugin/AnyUprightOSCOverlayRenderer.swift"), encoding: .utf8)
        let warp = try String(contentsOf: root.appendingPathComponent("AnyUpright/Plugin/AnyUprightWarpEffect.swift"), encoding: .utf8)
        let metal = try String(contentsOf: root.appendingPathComponent("AnyUpright/Plugin/AnyUprightWarp.metal"), encoding: .utf8)
        let candidates = try String(contentsOf: root.appendingPathComponent("AnyUpright/Plugin/AnyUprightUprightCandidates.swift"), encoding: .utf8)

        try auditRegisteredPlugins(infoPlist)
        try auditHorizon(effects)
        try auditQuad(effects, geometry: geometry, overlay: overlay, metal: metal)
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
            FeaturePluginExpectation(className: "AnyUprightQuadManualPlugIn", protocols: ["FxFilter"]),
            FeaturePluginExpectation(className: "AnyUprightQuadManualOSCPlugIn", protocols: ["FxOnScreenControl"], supportedPlugins: ["9BB4C7D9-9384-4C8F-927D-4F716DA78B14"]),
            FeaturePluginExpectation(className: "AnyUprightUprightManualPlugIn", protocols: ["FxFilter", "FxAnalyzer"]),
            FeaturePluginExpectation(className: "AnyUprightUprightManualOSCPlugIn", protocols: ["FxOnScreenControl"], supportedPlugins: ["A8F7169F-B5C7-44EB-B0AD-5F9178DCE9AB"])
        ]

        for item in expected {
            guard let plugin = plugins.first(where: { $0["className"] as? String == item.className }) else {
                throw FeatureSurfaceAuditFailure.failed("Missing registered plugin \(item.className)")
            }
            let protocols = Set(plugin["protocolNames"] as? [String] ?? [])
            try assertEqual(protocols, item.protocols, "\(item.className) protocols")
            let supportedPlugins = Set(plugin["supportedPlugins"] as? [String] ?? [])
            try assertEqual(supportedPlugins, item.supportedPlugins, "\(item.className) supported plugins")
        }
    }

    private static func auditHorizon(_ effects: String) throws {
        try require(effects, "VNDetectHorizonRequest()", "Horizon uses Vision horizon detection")
        try require(effects, "dominantHorizonCorrectionRadians", "Horizon has a traditional line fallback")
        try require(effects, "Analyze Horizon", "Horizon exposes explicit analysis button")
        try require(effects, "Fill Frame", "Horizon exposes fill toggle")
        try require(effects, "singleFrameAnalysisRange", "Horizon analysis targets a representative frame")
    }

    private static func auditQuad(_ effects: String, geometry: String, overlay: String, metal: String) throws {
        try require(effects, "Output Corners", "Quad exposes realtime output-corner mode")
        try require(effects, "Source Quad", "Quad exposes Lens-style source-quad mode")
        try require(effects, "Edit Mode", "Quad exposes edit mode for source-quad handles without applying the warp")
        try require(effects, "Stretch Mode", "Quad exposes Reverse Corner Pin-style source stretch mode")
        try require(effects, "Mirror Horizontal", "Quad can mirror the pinned source area horizontally")
        try require(effects, "Mirror Vertical", "Quad can mirror the pinned source area vertically")
        try require(effects, "class AnyUprightQuadManualPlugIn: AnyUprightWarpEffect", "Quad filter owns render parameters")
        try require(effects, "class AnyUprightQuadManualOSCPlugIn: AnyUprightOSCPlugIn, FxOnScreenControl_v4", "Quad exposes onscreen controls as a separate FxPlug class")
        try require(effects, "hiddenCollapsedFlags", "Source Quad hides the offset controls while keeping them as persistent state")
        try require(effects, "sourceCornerPercentOffset", "Source Quad OSC writes hidden source-corner percent offsets")
        try require(effects, "overlayRenderer.clear", "Quad OSC clears its host overlay surface while the effect render output owns the visible Source Quad adjuster")
        try require(geometry, "quadOutputToSourceMatrix", "Quad render matrix is centralized in geometry")
        try require(geometry, "AUSourceQuadStretchMode", "Source Quad stretch modes are testable geometry state")
        try require(geometry, "quadSelectionToOutputRectMatrix", "Source Quad mirror modes identify the selected output area")
        try require(geometry, "sourceQuadDefault", "Source Quad has a central default quadrilateral")
        try require(geometry, "sourceQuadObjectPoints", "Source Quad converts persistent offsets into object-space handles")
        try require(geometry, "guard !showCornerAdjuster else", "Source Quad mode can preview handles without warping")
        try require(geometry, "sourceCornerPercentOffset", "Source Quad OSC writes resolution-independent corner offsets")
        try require(geometry, "cornerPixelOffset", "Output Corners OSC writes stable corner pixel offsets")
        try require(overlay, "IOSurfaceGetWidth", "OSC renderer uses the destination IOSurface width for canvas overlays")
        try require(overlay, "IOSurfaceGetHeight", "OSC renderer uses the destination IOSurface height for canvas overlays")
        try require(overlay, "width = surfaceWidth", "OSC renderer treats the destination surface as the overlay viewport")
        try require(overlay, "height = surfaceHeight", "OSC renderer treats the destination surface as the overlay viewport")
        try require(overlay, "outputTexture.pixelFormat", "OSC renderer uses the actual Metal texture pixel format")
        try require(overlay, "MTLCreateSystemDefaultDevice", "OSC renderer can fall back when the destination registry ID is unavailable")
        try require(metal, "AURM_SourceQuadAdjusterPreview", "Source Quad edit overlay is rendered into the effect output")
        try require(metal, "color.rgb *= 0.70", "Source Quad edit preview dims pixels outside the selected quad")
        try require(metal, "? warpState->fallbackOutputToSource", "Selection mirror fallback only applies outside the selected quad")
        try require(metal, ": warpState->outputToSource", "Full-frame Quad warps use the primary output-to-source matrix")
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
        try require(effects, "class AnyUprightUprightManualPlugIn: AnyUprightWarpEffect, FxAnalyzer", "Upright filter is separated from its onscreen control")
        try require(effects, "class AnyUprightUprightManualOSCPlugIn: AnyUprightOSCPlugIn, FxOnScreenControl_v4", "Upright exposes onscreen controls as a separate FxPlug class")
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
