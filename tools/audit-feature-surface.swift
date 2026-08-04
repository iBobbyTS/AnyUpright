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
        let stretchEffects = try pluginSwiftSources(
            at: pluginDirectory,
            relativePaths: [
                "AnyUprightStretchEffects.swift",
                "AnyUprightStretchOSCControls.swift",
                "AnyUprightStretchOSCParameterWriter.swift",
                "AnyUprightStretchParameters.swift"
            ]
        )
        let uprightEffects = try pluginSwiftSources(
            at: pluginDirectory,
            relativePaths: [
                "AnyUprightUprightEffect.swift",
                "AnyUprightUprightCandidateParameters.swift",
                "AnyUprightUprightOSCControls.swift",
                "AnyUprightUprightParameters.swift"
            ]
        )
        let geometry = try String(contentsOf: root.appendingPathComponent("AnyUpright/Plugin/AnyUprightGeometry.swift"), encoding: .utf8)
        let overlay = try String(contentsOf: root.appendingPathComponent("AnyUpright/Plugin/AnyUprightOSCOverlayRenderer.swift"), encoding: .utf8)
        let warp = try String(contentsOf: root.appendingPathComponent("AnyUpright/Plugin/AnyUprightWarpEffect.swift"), encoding: .utf8)
        let metal = try String(contentsOf: root.appendingPathComponent("AnyUpright/Plugin/AnyUprightWarp.metal"), encoding: .utf8)
        let candidates = try String(contentsOf: root.appendingPathComponent("AnyUpright/Plugin/AnyUprightUprightCandidates.swift"), encoding: .utf8)
        let analysisTransaction = try String(contentsOf: root.appendingPathComponent("AnyUpright/Plugin/AnyUprightFxAnalysisTransaction.swift"), encoding: .utf8)
        let pluginDefaults = try String(contentsOf: root.appendingPathComponent("AnyUpright/Plugin/AnyUprightPluginDefaults.swift"), encoding: .utf8)
        let pluginDefaultsUI = try String(contentsOf: root.appendingPathComponent("AnyUpright/Plugin/AnyUprightPluginDefaultsUI.swift"), encoding: .utf8)

        try auditRegisteredPlugins(infoPlist)
        try reject(warp, "AUAnalysisStatusTextRenderer.shared.encode", "Analysis status remains outside the final Warp output")
        try reject(warp, "var analysisDisplayStatus:", "Warp parameter state does not carry OSC-only analysis status")
        try reject(warp, "populateAnalysisDisplayStatus", "Warp render state does not read OSC-only analysis status")
        try require(overlay, "analysisStatus: AUAnalysisDisplayStatus", "OSC overlay owns analysis status composition")
        try auditPluginDefaults(pluginDefaults, ui: pluginDefaultsUI, warp: warp)
        try auditHorizon(horizonEffect, transaction: analysisTransaction)
        try auditStretch(stretchEffects, geometry: geometry, overlay: overlay, metal: metal)
        try auditUpright(uprightEffects, geometry: geometry, warp: warp, metal: metal, candidates: candidates, transaction: analysisTransaction)

        print("AnyUpright feature surface audit passed")
    }

    private static func auditPluginDefaults(_ defaults: String, ui: String, warp: String) throws {
        try require(defaults, "AUPluginDefaultsStore<AUHorizonDefaultSettings>", "Horizon owns a strongly typed defaults store")
        try require(defaults, "AUPluginDefaultsStore<AUInnerStretchDefaultSettings>", "Inner Stretch owns a strongly typed defaults store")
        try require(defaults, "AUPluginDefaultsStore<AUOuterStretchDefaultSettings>", "Outer Stretch owns a strongly typed defaults store")
        try require(defaults, "AUPluginDefaultsStore<AUUprightDefaultSettings>", "Upright owns a strongly typed defaults store")
        try require(defaults, "fileName = \"Horizon.plist\"", "Horizon defaults use an independent plist")
        try require(defaults, "fileName = \"InnerStretch.plist\"", "Inner Stretch defaults use an independent plist")
        try require(defaults, "fileName = \"OuterStretch.plist\"", "Outer Stretch defaults use an independent plist")
        try require(defaults, "fileName = \"Upright.plist\"", "Upright defaults use an independent plist")
        try require(defaults, ".appendingPathComponent(\"Defaults\", isDirectory: true)", "Plugin defaults share the suite defaults directory")
        try require(defaults, "struct AUPluginDefaultsEditingState<Settings: Equatable>", "Defaults editors compare typed factory, saved, and current settings")
        try require(ui, "final class AUPluginDefaultsWindowPresenter", "Defaults editors share one remote-window presenter")
        try require(ui, "remoteWindowAPI: FxRemoteWindowAPI", "Defaults window uses the host-provided base remote-window API")
        try require(ui, "remoteWindowAPI.remoteWindow(of: Self.contentSize)", "Defaults window requests its desired content size")
        try require(ui, "let hostView = callbackParentView.superview ?? callbackParentView", "Defaults window mounts into the actual ViewBridge host when available")
        try require(ui, "rootView.translatesAutoresizingMaskIntoConstraints = false", "Defaults root view uses host-owned Auto Layout")
        try require(ui, "rootView.leadingAnchor.constraint(equalTo: hostView.leadingAnchor)", "Defaults root view is pinned to the host leading edge")
        try require(ui, "rootView.trailingAnchor.constraint(equalTo: hostView.trailingAnchor)", "Defaults root view is pinned to the host trailing edge")
        try require(ui, "rootView.topAnchor.constraint(equalTo: hostView.topAnchor)", "Defaults root view is pinned to the host top edge")
        try require(ui, "rootView.bottomAnchor.constraint(equalTo: hostView.bottomAnchor)", "Defaults root view is pinned to the host bottom edge")
        try reject(ui, "rootView.autoresizingMask = [.width, .height]", "Defaults root does not mix autoresizing with host-edge constraints")
        try require(ui, "let layoutStack = NSStackView(views: [contentStack, flexibleSpacer, footerStack])", "Defaults content uses one constrained vertical stack")
        try require(ui, "layoutStack.bottomAnchor.constraint(equalTo: rootView.bottomAnchor", "Defaults layout is constrained to the remote root bottom edge")
        try require(ui, "let footerStack = NSStackView(views: [statusLabel, resetButton])", "Defaults footer contains status and Restore only")
        try require(ui, "footerStack.widthAnchor.constraint(equalTo: layoutStack.widthAnchor)", "Defaults footer remains within the remote root width")
        try require(ui, "statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)", "Defaults status yields horizontal space before Restore")
        try reject(ui, "override func viewDidLayout()", "Defaults layout does not mix manual frames with Auto Layout")
        try require(ui, "final class AUPluginDefaultsEditorSession<Settings: AUPluginDefaultSettings>", "Defaults editors share one typed in-memory edit session")
        try require(ui, "func updateAndSave(_ settings: Settings)", "Defaults controls persist through one shared auto-save path")
        try require(ui, "try store.save(state.current)", "Defaults auto-save writes the current typed settings")
        try require(ui, "resetButton.isEnabled = editor.canRestoreFactoryDefaults", "Restore is enabled only when current differs from factory defaults")
        try reject(ui, "saveButton", "Defaults window has no manual Save button")
        try reject(ui, "func save() throws", "Defaults editors do not expose manual save actions")
        try require(ui, "final class AUHorizonDefaultsEditor", "Horizon has an independent defaults editor")
        try require(ui, "final class AUInnerStretchDefaultsEditor", "Inner Stretch has an independent defaults editor")
        try require(ui, "final class AUOuterStretchDefaultsEditor", "Outer Stretch has an independent defaults editor")
        try require(ui, "final class AUUprightDefaultsEditor", "Upright has an independent defaults editor")
        try require(warp, "private let pluginDefaultsWindowPresenter = AUPluginDefaultsWindowPresenter()", "Each filter instance owns the shared defaults-window wrapper")
        try require(warp, "func presentPluginDefaults(makeEditor: @escaping () -> AUPluginDefaultsEditor)", "Filters open defaults through the shared wrapper")
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
            FeaturePluginExpectation(className: "AnyUprightInnerStretchPlugIn", protocols: ["FxFilter"]),
            FeaturePluginExpectation(className: "AnyUprightOuterStretchPlugIn", protocols: ["FxFilter"]),
            FeaturePluginExpectation(className: "AnyUprightInnerStretchOSCPlugIn", protocols: ["FxOnScreenControl"], supportedPlugins: ["9BB4C7D9-9384-4C8F-927D-4F716DA78B14"]),
            FeaturePluginExpectation(className: "AnyUprightOuterStretchOSCPlugIn", protocols: ["FxOnScreenControl"], supportedPlugins: ["81C621CF-4119-46E9-BC04-47A1539A8B54"]),
            FeaturePluginExpectation(className: "AnyUprightUprightPlugIn", protocols: ["FxFilter", "FxAnalyzer"]),
            FeaturePluginExpectation(className: "AnyUprightUprightOSCPlugIn", protocols: ["FxOnScreenControl"], supportedPlugins: ["A8F7169F-B5C7-44EB-B0AD-5F9178DCE9AB", "2E32E3C2-91C7-44D4-A0AC-0E87832A86A1"])
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

    private static func auditHorizon(_ effects: String, transaction: String) throws {
        try require(effects, "override var needsFullBuffer: Bool", "Horizon requests a full frame for its global rotation warp")
        try require(effects, "VNDetectHorizonRequest()", "Horizon uses Vision horizon detection")
        try require(effects, "dominantHorizonCorrectionRadians", "Horizon has a traditional line fallback")
        try require(effects, "Analyze Horizon", "Horizon exposes explicit analysis button")
        try require(effects, "Fill Frame", "Horizon exposes fill toggle")
        try require(effects, "AUPluginDefaults.horizon.load()", "Horizon reads only its defaults store during parameter registration")
        try require(effects, "defaultValue: defaults.fillFrame", "Horizon Fill Frame uses the persisted default")
        try require(effects, "AUHorizonDefaultsEditor()", "Horizon opens its independent defaults editor")
        try require(effects, "AUFxAnalysisTransaction<Void, Double>", "Horizon owns a typed shared analysis transaction")
        try require(transaction, "AUFxAnalysisProbePolicy.range", "Shared transaction requests a bounded representative-frame probe")
        try require(effects, "inputTime(&inputTime, fromTimelineTime:", "Horizon converts timeline time to input time")
        try require(effects, "timingAPI.sampleDuration(&duration)", "Horizon uses the input sample duration")
        try require(effects, "analysisStateForEffect()", "Horizon rejects duplicate host analysis requests")
    }

    private static func auditStretch(_ effects: String, geometry: String, overlay: String, metal: String) throws {
        try require(effects, "class AnyUprightInnerStretchPlugIn: AnyUprightStretchModePlugIn", "Inner Stretch is registered as its own filter")
        try require(effects, "class AnyUprightOuterStretchPlugIn: AnyUprightStretchModePlugIn", "Outer Stretch is registered as its own filter")
        try reject(effects, "FxAnalyzer", "Inner Stretch remains a manual-only filter")
        try reject(effects, "Detect Edge and Corner", "Inner Stretch does not expose analysis controls")
        try reject(effects, "Score Threshold", "Inner Stretch does not expose detection thresholds")
        try reject(effects, "Choose from detections", "Inner Stretch does not expose candidate-selection mode")
        try require(effects, "withName: \"Ratio\"", "Inner Stretch exposes a manual ratio policy")
        try require(effects, "menuEntries: [\"None\", \"Fit\", \"Fill\"]", "Inner Stretch ratio policy exposes None, Fit, and Fill")
        try require(effects, "AUPluginDefaults.innerStretch.load().ratio", "Inner Stretch reads its Ratio default during parameter registration")
        try require(effects, "AUPluginDefaults.innerStretch.load().suppressKeyframeNotifications", "Inner Stretch reloads notification suppression for each keyframe action")
        try require(effects, "showKeyframeNotification", "Stretch keyframe notifications share one suppression boundary")
        try require(effects, "? AUPluginDefaults.innerStretch.load().ratio\n            : AUStretchRatioMode.none", "Outer Stretch keeps a fixed None ratio default")
        try require(effects, "AUInnerStretchDefaultsEditor()", "Inner Stretch opens its independent defaults editor")
        try require(effects, "AUOuterStretchDefaultsEditor()", "Outer Stretch opens its independent defaults editor")
        try require(effects, "AUPluginDefaults.outerStretch.load().suppressKeyframeNotifications", "Outer Stretch reloads its independent notification suppression for each keyframe action")
        try require(geometry, "innerStretchAverageAspectRatio", "Inner Stretch ratio averages opposing edge lengths in shared geometry")
        try reject(metal, "outsideTarget", "Inner Stretch Fit does not switch to an unwarped background outside the fitted target")
        try reject(effects, "detectInnerStretch", "Inner Stretch has no detector callback")
        try reject(effects, "InnerStretchDetection", "Inner Stretch has no detection parameter slots")
        try reject(effects, "sourceDetection", "Inner Stretch OSC has no detection overlay path")
        try require(effects, "override var fixedStretchMode: AUStretchTransformMode", "Stretch filters choose fixed modes")
        try require(effects, "class AnyUprightOuterStretchOSCPlugIn: AnyUprightInnerStretchOSCPlugIn", "Outer Stretch exposes its own onscreen control")
        try require(effects, "parameterFlags: hiddenFlags()", "Stretch fixed mode parameter is hidden from the inspector")
        try require(effects, "Edit Mode", "Stretch exposes edit mode for inner-stretch handles without applying the warp")
        try require(effects, "Set Corner Keyframe", "Both Stretch filters expose one-click keyframing for all eight corner channels")
        try require(effects, "FxKeyframeAPI_v3", "Stretch uses the host keyframe API for its existing corner channels")
        try require(effects, "class AnyUprightInnerStretchOSCPlugIn: AnyUprightOSCPlugIn, FxOnScreenControl_v4", "Inner Stretch exposes onscreen controls as a separate FxPlug class")
        try require(effects, "renderOutputCornersOSC", "Outer Stretch draws host onscreen output-corner controls")
        try require(
            effects,
            "hostActivePart: activePart,\n                outputSize: outputSize",
            "Outer Stretch forwards the host active part into the shared Stretch highlight renderer"
        )
        try require(
            effects,
            "renderStretchOSC(\n            points: points,\n            displayPart: displayPart",
            "Outer Stretch uses the shared Inner Stretch segment and handle renderer"
        )
        try require(
            effects,
            "canvasFrame: canvasFrame,\n            coordinateSpace: .canvasFramePixels",
            "Outer Stretch renders converted host-canvas corners without renormalizing them against the viewer frame"
        )
        try require(
            effects,
            "handleStyle: innerStretchOverlayStyle()",
            "Outer Stretch uses the same circular handles and active colors as Inner Stretch"
        )
        try require(effects, "let cornerGroupFlags = collapsedFlags()", "Both Stretch filters expose the four corner coordinate groups")
        try reject(effects, "hiddenCollapsedFlags", "Stretch corner coordinate groups are not hidden")
        try require(effects, "addPixelSlider(paramAPI, name: \"\\(title) X px\"", "Stretch exposes horizontal pixel offsets")
        try require(effects, "addPixelSlider(paramAPI, name: \"\\(title) Y px\"", "Stretch exposes vertical pixel offsets")
        try reject(effects, "addPercentSlider", "Stretch does not register percentage corner offsets")
        try require(effects, "overlayRenderer.clear", "Stretch OSC clears its host overlay surface while the effect render output owns the visible Inner Stretch adjuster")
        try require(geometry, "stretchOutputToSourceMatrix", "Stretch render matrix is centralized in geometry")
        try require(geometry, "stretchSelectionToOutputRectMatrix", "Inner Stretch edit preview identifies the selected source area")
        try require(geometry, "innerStretchDefault", "Inner Stretch defines its default input selection")
        try require(geometry, "AUStretchCorners.fullFrame(size)", "Inner Stretch defaults to the four source-frame corners")
        try reject(geometry, "innerStretchInset", "Inner Stretch no longer keeps a central-inset default")
        try require(geometry, "innerStretchObjectPoints", "Inner Stretch converts persistent offsets into object-space handles")
        try require(geometry, "guard !showCornerAdjuster else", "Inner Stretch mode can preview handles without warping")
        try require(geometry, "sourceCornerPixelOffset", "Inner Stretch OSC writes source-corner pixel offsets")
        try require(geometry, "cornerPixelOffset", "Outer Stretch OSC writes stable corner pixel offsets")
        try require(overlay, "IOSurfaceGetWidth", "OSC renderer uses the destination IOSurface width for canvas overlays")
        try require(overlay, "IOSurfaceGetHeight", "OSC renderer uses the destination IOSurface height for canvas overlays")
        try require(overlay, "width = surfaceWidth", "OSC renderer treats the destination surface as the overlay viewport")
        try require(overlay, "height = surfaceHeight", "OSC renderer treats the destination surface as the overlay viewport")
        try require(overlay, "outputTexture.pixelFormat", "OSC renderer uses the actual Metal texture pixel format")
        try require(overlay, "MTLCreateSystemDefaultDevice", "OSC renderer can fall back when the destination registry ID is unavailable")
        try require(metal, "AURM_InnerStretchAdjusterPreview", "Inner Stretch edit overlay is rendered into the effect output")
        try require(metal, "color.rgb *= 0.70", "Inner Stretch edit preview dims pixels outside the selected stretch")
        try require(metal, "warpState->renderMode == AURM_OuterStretch", "Outer Stretch has a dedicated render path")
        try require(metal, "outerStretchCoverage(outputCoordinate, warpState)", "Outer Stretch masks fragments to its destination quadrilateral")
        try require(metal, "if (outputCoverage <= 0.0)", "Outer Stretch rejects invalid output pixels before projective sampling")
        try require(metal, "warpState->outputToSource * float3(outputCoordinate, 1.0)", "Stretch warps use the primary output-to-source matrix")
    }

    private static func auditUpright(_ effects: String, geometry: String, warp: String, metal: String, candidates: String, transaction: String) throws {
        try require(effects, "withName: \"Direction\"", "Upright exposes direction-based correction selection")
        try require(effects, "menuEntries: [\"Vertical\", \"Horizontal\", \"Full\"]", "Upright exposes vertical, horizontal, and full correction directions")
        try require(effects, "withName: \"Mode\"", "Upright exposes workflow mode selection")
        try require(effects, "menuEntries: [\"Manual\", \"Semi Auto\", \"Auto\"]", "Upright exposes manual, semi-auto, and auto modes")
        try require(effects, "defaults: AUPluginDefaults.upright.load()", "Upright reads only its defaults store during parameter registration")
        try require(effects, "defaultValue: UInt32(defaults.direction.rawValue)", "Upright Direction uses the persisted default")
        try require(effects, "defaultValue: UInt32(defaults.mode.rawValue)", "Upright Mode uses the persisted default")
        try require(effects, "defaultValue: defaults.autoCrop", "Upright Auto Crop uses the persisted default")
        try require(effects, "AUUprightDefaultsEditor()", "Upright opens its independent defaults editor")
        try require(effects, "withName: \"Analyze\"", "Upright exposes one analysis/apply action for the selected mode")
        try require(effects, "guard controlMode != .manual else", "Upright Analyze applies manual guides without running detection")
        try require(effects, "UprightAnalysisRequest(correctionMode: correctionMode, controlMode: controlMode)", "Upright Analyze starts semi-auto and full-auto candidate detection")
        try require(effects, "AUFxAnalysisTransaction<UprightAnalysisRequest, [UprightDetectedCandidate]>", "Upright owns a typed shared analysis transaction")
        try require(transaction, "AUFxAnalysisProbePolicy.range", "Upright uses the shared bounded representative-frame probe")
        try require(effects, "inputTime(&inputTime, fromTimelineTime:", "Upright converts timeline time to input time")
        try require(effects, "timingAPI.sampleDuration(&duration)", "Upright uses the input sample duration")
        try require(effects, "case .produced(let candidates)", "Upright distinguishes an empty result from a missing analysis frame")
        try require(effects, "controlMode == .automatic", "Upright full-auto selects candidates during parameter writeback")
        try require(effects, "selectionValueAfterToggling", "Upright semi-auto can select candidates from onscreen controls")
        try require(effects, "writeUprightManualGuides", "Upright can transfer selected automatic lines into manual guides")
        try require(effects, "class AnyUprightUprightPlugIn: AnyUprightWarpEffect, FxAnalyzer", "Upright filter is separated from its onscreen control")
        try require(effects, "class AnyUprightUprightOSCPlugIn: AnyUprightOSCPlugIn, FxOnScreenControl_v4", "Upright and Horizon share the stable status/OSC control class")
        try require(effects, "guide4Enabled", "Upright exposes four guide lines")
        try require(effects, "guide4Start", "Upright exposes the fourth guide start handle")
        try require(effects, "guide4End", "Upright exposes the fourth guide end handle")
        try require(effects, "AnyUprightUprightCandidates.displayCandidates", "Upright OSC filters displayed candidates by mode and direction")
        try require(effects, "AnyUprightUprightCandidates.automaticSelectedIndexes", "Upright full-auto chooses detected candidates through shared candidate ranking")
        try require(effects, "lineCandidates.prefix(candidateLimit(for: request))", "Upright candidate detection limits references per direction")
        try require(geometry, "uprightOutputToSourceMatrix", "Upright perspective matrix is centralized in geometry")
        try require(geometry, "isStrictlyWithinDeviationLimit", "Upright candidate filtering uses strict deviation limits")
        try require(warp, "case .upright:", "Shared warp renderer has an Upright branch")
        try require(effects, "guidedUprightOutputToSourceMatrix", "All Upright control modes use the shared guided matrix solver")
        try require(warp, "appliedOutputToCurrentSourceMatrix", "Upright reference correction is routed through shared warp state")
        try require(metal, "warpState->outputToSource * float3(outputCoordinate, 1.0)", "Metal renderer consumes the shared output-to-source matrix")
        try require(candidates, "case vertical = 0", "Upright correction mode stores vertical direction")
        try require(candidates, "case horizontal = 1", "Upright correction mode stores horizontal direction")
        try require(candidates, "case full = 2", "Upright correction mode stores full direction")
        try require(candidates, "case semiAutomatic = 1", "Upright stores semi-auto workflow mode")
        try require(candidates, "case automatic = 2", "Upright stores full-auto workflow mode")
        try require(candidates, "static func automaticSelectedIndexes", "Upright full-auto ranking is centralized")
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
