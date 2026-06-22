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
        let pluginDirectory = root.appendingPathComponent("AnyUpright/Plugin")
        let horizonEffect = try pluginSwiftSources(
            at: pluginDirectory,
            relativePaths: [
                "AnyUprightHorizonEffect.swift"
            ]
        )
        let quadEffects = try pluginSwiftSources(
            at: pluginDirectory,
            relativePaths: [
                "AnyUprightStretchEffects.swift",
                "AnyUprightQuadOSCControls.swift",
                "AnyUprightQuadOSCParameterWriter.swift",
                "AnyUprightQuadParameters.swift"
            ]
        )
        let uprightEffects = try pluginSwiftSources(
            at: pluginDirectory,
            relativePaths: [
                "AnyUprightUprightEffect.swift",
                "AnyUprightUprightOSCControls.swift",
                "AnyUprightUprightParameters.swift"
            ]
        )
        let geometry = try String(contentsOf: root.appendingPathComponent("AnyUpright/Plugin/AnyUprightGeometry.swift"), encoding: .utf8)
        let overlay = try String(contentsOf: root.appendingPathComponent("AnyUpright/Plugin/AnyUprightOSCOverlayRenderer.swift"), encoding: .utf8)
        let warp = try String(contentsOf: root.appendingPathComponent("AnyUpright/Plugin/AnyUprightWarpEffect.swift"), encoding: .utf8)
        let metal = try String(contentsOf: root.appendingPathComponent("AnyUpright/Plugin/AnyUprightWarp.metal"), encoding: .utf8)
        let candidates = try String(contentsOf: root.appendingPathComponent("AnyUpright/Plugin/AnyUprightUprightCandidates.swift"), encoding: .utf8)

        try auditRegisteredPlugins(infoPlist)
        try auditHorizon(horizonEffect)
        try auditQuad(quadEffects, geometry: geometry, overlay: overlay, metal: metal)
        try auditUpright(uprightEffects, geometry: geometry, warp: warp, candidates: candidates)

        print("AnyUpright feature surface audit passed")
    }

    private static func pluginSwiftSources(at pluginDirectory: URL, relativePaths: [String]) throws -> String {
        return try relativePaths
            .map { try String(contentsOf: pluginDirectory.appendingPathComponent($0), encoding: .utf8) }
            .joined(separator: "\n")
    }

    private static func auditRegisteredPlugins(_ infoPlist: URL) throws {
        let data = try Data(contentsOf: infoPlist)
        guard let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              let plugins = plist["ProPlugPlugInList"] as? [[String: Any]] else {
            throw FeatureSurfaceAuditFailure.failed("Unable to read ProPlugPlugInList")
        }

        let expected = [
            FeaturePluginExpectation(className: "AnyUprightHorizonPlugIn", protocols: ["FxFilter", "FxAnalyzer"]),
            FeaturePluginExpectation(className: "AnyUprightInnerStretchPlugIn", protocols: ["FxFilter", "FxAnalyzer"]),
            FeaturePluginExpectation(className: "AnyUprightOuterStretchPlugIn", protocols: ["FxFilter"]),
            FeaturePluginExpectation(className: "AnyUprightInnerStretchOSCPlugIn", protocols: ["FxOnScreenControl"], supportedPlugins: ["9BB4C7D9-9384-4C8F-927D-4F716DA78B14"]),
            FeaturePluginExpectation(className: "AnyUprightOuterStretchOSCPlugIn", protocols: ["FxOnScreenControl"], supportedPlugins: ["81C621CF-4119-46E9-BC04-47A1539A8B54"]),
            FeaturePluginExpectation(className: "AnyUprightUprightPlugIn", protocols: ["FxFilter", "FxAnalyzer"]),
            FeaturePluginExpectation(className: "AnyUprightUprightOSCPlugIn", protocols: ["FxOnScreenControl"], supportedPlugins: ["A8F7169F-B5C7-44EB-B0AD-5F9178DCE9AB"])
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
        try require(effects, "class AnyUprightInnerStretchPlugIn: AnyUprightQuadModePlugIn", "Inner Stretch is registered as its own filter")
        try require(effects, "class AnyUprightOuterStretchPlugIn: AnyUprightQuadModePlugIn", "Outer Stretch is registered as its own filter")
        try require(effects, "FxAnalyzer", "Inner Stretch supports explicit frame analysis")
        try require(effects, "Detect Edge and Corner", "Inner Stretch exposes explicit source-quadrilateral detection")
        try require(effects, "addPushButton", "Inner Stretch detection uses a native FxPlug push button")
        try require(effects, "selector: #selector(detectSourceQuad)", "Inner Stretch push button dispatches to detection")
        try reject(effects, "addCustomParameter", "Inner Stretch detection should not use a custom parameter for button UI")
        try reject(effects, "kFxParameterFlag_CUSTOM_UI", "Inner Stretch detection should not replace the standard parameter UI")
        try reject(effects, "FxCustomParameterViewHost_v2", "Inner Stretch should not provide a custom inspector view for its detection button")
        try reject(effects, "defaultValue: NSData()", "Inner Stretch native button should not use data-backed custom value storage")
        try reject(effects, "retainedDetectSourceQuadButtonViews", "Inner Stretch native button should not retain custom parameter views")
        try reject(effects, "createView(forParameterID", "Inner Stretch native button should not create a custom detection button view")
        try reject(effects, "NSButton(title: \"Detect Edge and Corner\"", "Inner Stretch detection should not expose its own AppKit button")
        try require(effects, "detectSupportedLineSegments", "Inner Stretch detects independent edge primitives instead of rectangle candidates")
        try require(effects, "Score Threshold", "Inner Stretch exposes a normalized detection-score threshold")
        try require(effects, "Choose from detections", "Inner Stretch can switch OSC hit testing from manual handles to detected primitives")
        try require(effects, "chooseFromDetections", "Inner Stretch exposes detection-choice mode as a persistent FxPlug parameter")
        try require(effects, "writeQuadSourceDetectionPrimitives", "Inner Stretch detection writes primitive slots instead of moving the current quad")
        try require(effects, "quadSourceDetectionEdges", "Inner Stretch OSC reads detected edge primitives")
        try require(effects, "quadSourceDetectionCorners", "Inner Stretch OSC reads detected corner primitives")
        try require(effects, "sourceDetectionOverlaySegments", "Inner Stretch OSC draws detected edge/corner overlays")
        try require(effects, "toggleDetectionSelection", "Inner Stretch OSC can select detected edges/corners for writeback")
        try reject(effects, "VNDetectRectanglesRequest()", "Inner Stretch detection overlay should not be limited to closed rectangle observations")
        try reject(effects, "writeDetectedSourceQuadOffsets", "Inner Stretch detection should not directly move the existing quad")
        try require(effects, "override var fixedQuadMode: AUQuadTransformMode", "Quad filters choose fixed modes")
        try require(effects, "class AnyUprightOuterStretchOSCPlugIn: AnyUprightInnerStretchOSCPlugIn", "Outer Stretch exposes its own onscreen control")
        try require(effects, "parameterFlags: hiddenFlags()", "Quad fixed mode parameter is hidden from the inspector")
        try require(effects, "Edit Mode", "Quad exposes edit mode for source-quad handles without applying the warp")
        try require(effects, "class AnyUprightInnerStretchOSCPlugIn: AnyUprightOSCPlugIn, FxOnScreenControl_v4", "Inner Stretch exposes onscreen controls as a separate FxPlug class")
        try require(effects, "renderOutputCornersOSC", "Outer Stretch draws host onscreen output-corner controls")
        try require(effects, "hiddenCollapsedFlags", "Inner Stretch hides the offset controls while keeping them as persistent state")
        try require(effects, "sourceCornerPercentOffset", "Inner Stretch OSC writes hidden source-corner percent offsets")
        try require(effects, "overlayRenderer.clear", "Quad OSC clears its host overlay surface while the effect render output owns the visible Inner Stretch adjuster")
        try require(geometry, "quadOutputToSourceMatrix", "Quad render matrix is centralized in geometry")
        try require(geometry, "quadSelectionToOutputRectMatrix", "Inner Stretch edit preview identifies the selected source area")
        try require(geometry, "sourceQuadDefault", "Inner Stretch defines its default source quadrilateral")
        try require(geometry, "sourceQuadInset = 0.10", "Inner Stretch defaults to the central 80 percent of the source frame")
        try require(geometry, "sourceQuadObjectPoints", "Inner Stretch converts persistent offsets into object-space handles")
        try require(geometry, "imageQuad(fromNormalizedObjectPoints", "Detected corner selections can be ordered into a source quad")
        try require(geometry, "imageQuad(fromNormalizedObjectLines", "Detected edge selections can be intersected into a source quad")
        try require(geometry, "guard !showCornerAdjuster else", "Inner Stretch mode can preview handles without warping")
        try require(geometry, "sourceCornerPercentOffset", "Inner Stretch OSC writes resolution-independent corner offsets")
        try require(geometry, "cornerPixelOffset", "Outer Stretch OSC writes stable corner pixel offsets")
        try require(overlay, "IOSurfaceGetWidth", "OSC renderer uses the destination IOSurface width for canvas overlays")
        try require(overlay, "IOSurfaceGetHeight", "OSC renderer uses the destination IOSurface height for canvas overlays")
        try require(overlay, "width = surfaceWidth", "OSC renderer treats the destination surface as the overlay viewport")
        try require(overlay, "height = surfaceHeight", "OSC renderer treats the destination surface as the overlay viewport")
        try require(overlay, "outputTexture.pixelFormat", "OSC renderer uses the actual Metal texture pixel format")
        try require(overlay, "MTLCreateSystemDefaultDevice", "OSC renderer can fall back when the destination registry ID is unavailable")
        try require(metal, "AURM_SourceQuadAdjusterPreview", "Inner Stretch edit overlay is rendered into the effect output")
        try require(metal, "color.rgb *= 0.70", "Inner Stretch edit preview dims pixels outside the selected quad")
        try require(metal, "warpState->outputToSource * float3(outputCoordinate, 1.0)", "Quad warps use the primary output-to-source matrix")
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
        try require(effects, "class AnyUprightUprightPlugIn: AnyUprightWarpEffect, FxAnalyzer", "Upright filter is separated from its onscreen control")
        try require(effects, "class AnyUprightUprightOSCPlugIn: AnyUprightOSCPlugIn, FxOnScreenControl_v4", "Upright exposes onscreen controls as a separate FxPlug class")
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

    private static func reject(_ haystack: String, _ needle: String, _ label: String) throws {
        guard !haystack.contains(needle) else {
            throw FeatureSurfaceAuditFailure.failed("\(label): found \(needle)")
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
