//
//  AnyUprightStretchEffects.swift
//  AnyUpright
//

import Foundation

private enum AUStretchKeyframeOperationError: Error {
    case keyframeIndexNotFound(AUStretchKeyframeTarget, CMTime)
    case parameterValueUnavailable(AUStretchKeyframeTarget, CMTime)
}

class AnyUprightStretchModePlugIn: AnyUprightWarpEffect {
    private static let cornerKeyframeTargets = [
        AUStretchKeyframeTarget(parameterID: StretchParam.topLeftPixelX.rawValue, channelIndex: 0),
        AUStretchKeyframeTarget(parameterID: StretchParam.topLeftPixelY.rawValue, channelIndex: 0),
        AUStretchKeyframeTarget(parameterID: StretchParam.topRightPixelX.rawValue, channelIndex: 0),
        AUStretchKeyframeTarget(parameterID: StretchParam.topRightPixelY.rawValue, channelIndex: 0),
        AUStretchKeyframeTarget(parameterID: StretchParam.bottomRightPixelX.rawValue, channelIndex: 0),
        AUStretchKeyframeTarget(parameterID: StretchParam.bottomRightPixelY.rawValue, channelIndex: 0),
        AUStretchKeyframeTarget(parameterID: StretchParam.bottomLeftPixelX.rawValue, channelIndex: 0),
        AUStretchKeyframeTarget(parameterID: StretchParam.bottomLeftPixelY.rawValue, channelIndex: 0)
    ]

    var fixedStretchMode: AUStretchTransformMode {
        fatalError("Subclasses must choose a fixed Stretch mode.")
    }

    override var needsFullBuffer: Bool {
        true
    }

    var showsSourceEditMode: Bool {
        fixedStretchMode == .innerStretch
    }

    override func addEffectParameters(_ paramAPI: FxParameterCreationAPI_v5) throws {
        addAnalysisDisplayStatusParameter(paramAPI)
        addFixedModeParameter(paramAPI)
        let ratioDefault = showsSourceEditMode
            ? AUPluginDefaults.innerStretch.load().ratio
            : AUStretchRatioMode.none

        paramAPI.addPopupMenu(
            withName: "Ratio",
            parameterID: StretchParam.ratio.rawValue,
            defaultValue: UInt32(ratioDefault.rawValue),
            menuEntries: ["None", "Fit", "Fill"],
            parameterFlags: showsSourceEditMode ? defaultFlags() : hiddenFlags()
        )

        if showsSourceEditMode {
            paramAPI.addToggleButton(
                withName: "Edit Mode",
                parameterID: StretchParam.showCornerAdjuster.rawValue,
                defaultValue: true,
                parameterFlags: defaultFlags()
            )
        } else {
            paramAPI.addToggleButton(
                withName: "Edit Mode",
                parameterID: StretchParam.showCornerAdjuster.rawValue,
                defaultValue: false,
                parameterFlags: hiddenFlags()
            )
        }

        paramAPI.addPushButton(
            withName: "Set/Unset Key Frame",
            parameterID: StretchParam.setCornerKeyframe.rawValue,
            selector: #selector(toggleCornerKeyframe),
            parameterFlags: defaultFlags()
        )

        let cornerGroupFlags = collapsedFlags()
        addCornerParameters(paramAPI, title: "Top Left", groupID: StretchGroup.topLeft.rawValue, pixelX: .topLeftPixelX, pixelY: .topLeftPixelY, groupFlags: cornerGroupFlags)
        addCornerParameters(paramAPI, title: "Top Right", groupID: StretchGroup.topRight.rawValue, pixelX: .topRightPixelX, pixelY: .topRightPixelY, groupFlags: cornerGroupFlags)
        addCornerParameters(paramAPI, title: "Bottom Right", groupID: StretchGroup.bottomRight.rawValue, pixelX: .bottomRightPixelX, pixelY: .bottomRightPixelY, groupFlags: cornerGroupFlags)
        addCornerParameters(paramAPI, title: "Bottom Left", groupID: StretchGroup.bottomLeft.rawValue, pixelX: .bottomLeftPixelX, pixelY: .bottomLeftPixelY, groupFlags: cornerGroupFlags)

        if showsSourceEditMode {
            paramAPI.addPushButton(
                withName: "Defaults...",
                parameterID: StretchParam.defaults.rawValue,
                selector: #selector(showInnerStretchDefaults),
                parameterFlags: defaultFlags()
            )
        }
    }

    @objc private func showInnerStretchDefaults() {
        AUPluginDefaultsDiagnostics.log(
            "selector enter selector=showInnerStretchDefaults instance=\(ObjectIdentifier(self))"
        )
        presentPluginDefaults { AUInnerStretchDefaultsEditor() }
    }

    @objc private func toggleCornerKeyframe() {
        guard let actionAPI = _apiManager.api(for: FxCustomParameterActionAPI_v4.self) as? FxCustomParameterActionAPI_v4,
              let keyframeAPI = _apiManager.api(for: FxKeyframeAPI_v3.self) as? FxKeyframeAPI_v3 else {
            NSLog("AnyUpright Stretch: keyframe APIs unavailable")
            return
        }

        let time = actionAPI.currentTime()
        do {
            let action = try AUStretchKeyframePolicy.action(
                from: Self.cornerKeyframeTargets,
                at: time
            ) { target, targetTime in
                var hasKeyframe = ObjCBool(false)
                if let error = keyframeAPI.parameter(
                    UInt(target.parameterID),
                    channel: target.channelIndex,
                    hasKeyframe: &hasKeyframe,
                    at: targetTime
                ) {
                    throw error
                }
                return hasKeyframe.boolValue
            }

            switch action {
            case .set(let targets):
                guard let retrievalAPI = parameterRetrievalAPI(),
                      let settingAPI = parameterSettingAPI() else {
                    NSLog("AnyUpright Stretch: parameter APIs unavailable")
                    return
                }
                let assignments = try AUStretchKeyframePolicy.assignments(
                    for: targets,
                    at: time
                ) { target, targetTime in
                    var value = 0.0
                    guard retrievalAPI.getFloatValue(
                        &value,
                        fromParameter: target.parameterID,
                        at: targetTime
                    ) else {
                        throw AUStretchKeyframeOperationError.parameterValueUnavailable(target, targetTime)
                    }
                    return value
                }
                try setKeyframes(
                    assignments,
                    at: time,
                    keyframeAPI: keyframeAPI,
                    settingAPI: settingAPI
                )
                showTransientDisplayStatus(
                    .keyframesSet,
                    at: time,
                    duration: AUAnalysisDisplayStatus.keyframesSet.preferredTransientDuration
                )
            case .unset(let targets):
                let removalIndices = try targets.map { target in
                    (target, try keyframeIndex(for: target, at: time, keyframeAPI: keyframeAPI))
                }
                try unsetKeyframes(removalIndices, keyframeAPI: keyframeAPI)
                showTransientDisplayStatus(
                    .keyframesRemoved,
                    at: time,
                    duration: AUAnalysisDisplayStatus.keyframesRemoved.preferredTransientDuration
                )
            }
        } catch {
            NSLog("AnyUpright Stretch: unable to toggle corner keyframes: %@", String(describing: error))
        }
    }

    private func unsetKeyframes(
        _ removals: [(target: AUStretchKeyframeTarget, index: UInt)],
        keyframeAPI: FxKeyframeAPI_v3
    ) throws {
        let undoAPI = _apiManager.api(for: FxUndoAPI.self) as? FxUndoAPI
        let startedUndoGroup = undoAPI?.startUndoGroup("Unset Corner Keyframe") ?? false
        defer {
            if startedUndoGroup {
                _ = undoAPI?.endUndoGroup()
            }
        }

        for removal in removals {
            if let error = keyframeAPI.removeKeyframe(
                at: removal.index,
                fromParameter: UInt(removal.target.parameterID),
                andChannel: removal.target.channelIndex
            ) {
                throw error
            }
        }
    }

    private func setKeyframes(
        _ assignments: [AUStretchKeyframeAssignment],
        at time: CMTime,
        keyframeAPI: FxKeyframeAPI_v3,
        settingAPI: FxParameterSettingAPI_v5
    ) throws {
        let undoAPI = _apiManager.api(for: FxUndoAPI.self) as? FxUndoAPI
        let startedUndoGroup = undoAPI?.startUndoGroup("Set Corner Keyframe") ?? false
        defer {
            if startedUndoGroup {
                _ = undoAPI?.endUndoGroup()
            }
        }

        for assignment in assignments {
            var keyframe = FxKeyframe()
            keyframe.version = 3
            keyframe.time = time
            keyframe.segmentStyle = .linear
            if let error = keyframeAPI.add(
                &keyframe,
                toParameter: UInt(assignment.target.parameterID),
                andChannel: assignment.target.channelIndex
            ) {
                throw error
            }
        }

        for assignment in assignments {
            let didSet = settingAPI.setFloatValue(
                assignment.value,
                toParameter: assignment.target.parameterID,
                at: time
            )
            guard didSet else {
                throw AUStretchKeyframeOperationError.parameterValueUnavailable(assignment.target, time)
            }
        }
    }

    private func keyframeIndex(
        for target: AUStretchKeyframeTarget,
        at time: CMTime,
        keyframeAPI: FxKeyframeAPI_v3
    ) throws -> UInt {
        var count: UInt = 0
        if let error = keyframeAPI.keyframeCount(
            &count,
            forParameter: UInt(target.parameterID),
            andChannel: target.channelIndex
        ) {
            throw error
        }

        for index in 0..<count {
            var keyframe = FxKeyframe()
            keyframe.version = 3
            if let error = keyframeAPI.keyframe(
                &keyframe,
                forParameter: UInt(target.parameterID),
                channel: target.channelIndex,
                andIndex: index
            ) {
                throw error
            }
            if CMTimeCompare(keyframe.time, time) == 0 {
                return index
            }
        }

        throw AUStretchKeyframeOperationError.keyframeIndexNotFound(target, time)
    }

    override func state(at renderTime: CMTime) -> AnyUprightParameterState {
        var result = stretchParameterState(at: renderTime, paramAPI: parameterRetrievalAPI(), fixedMode: fixedStretchMode)
        populateStableRenderSizes(&result, at: renderTime)
        return result
    }

    private func addFixedModeParameter(_ paramAPI: FxParameterCreationAPI_v5) {
        paramAPI.addPopupMenu(
            withName: "Mode",
            parameterID: StretchParam.mode.rawValue,
            defaultValue: UInt32(fixedStretchMode.rawValue),
            menuEntries: ["Outer Stretch", "Inner Stretch"],
            parameterFlags: hiddenFlags()
        )
    }

    private func addCornerParameters(_ paramAPI: FxParameterCreationAPI_v5, title: String, groupID: UInt32, pixelX: StretchParam, pixelY: StretchParam, groupFlags: FxParameterFlags) {
        paramAPI.startParameterSubGroup(title, parameterID: groupID, parameterFlags: groupFlags)
        addPixelSlider(paramAPI, name: "\(title) X px", id: pixelX.rawValue)
        addPixelSlider(paramAPI, name: "\(title) Y px", id: pixelY.rawValue)
        paramAPI.endParameterSubGroup()
    }

    private func addPixelSlider(_ paramAPI: FxParameterCreationAPI_v5, name: String, id: UInt32) {
        paramAPI.addFloatSlider(
            withName: name,
            parameterID: id,
            defaultValue: 0.0,
            parameterMin: -10000.0,
            parameterMax: 10000.0,
            sliderMin: -2000.0,
            sliderMax: 2000.0,
            delta: 1.0,
            parameterFlags: defaultFlags()
        )
    }

    private func hiddenFlags() -> FxParameterFlags {
        FxParameterFlags(kFxParameterFlag_HIDDEN)
    }

}

@objc(AnyUprightInnerStretchPlugIn)
class AnyUprightInnerStretchPlugIn: AnyUprightStretchModePlugIn {
    override var fixedStretchMode: AUStretchTransformMode {
        .innerStretch
    }
}

@objc(AnyUprightOuterStretchPlugIn)
class AnyUprightOuterStretchPlugIn: AnyUprightStretchModePlugIn {
    override var fixedStretchMode: AUStretchTransformMode {
        .outputCorners
    }
}
