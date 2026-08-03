//
//  AnyUprightStretchEffects.swift
//  AnyUpright
//

import Foundation

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
            withName: "Set Corner Keyframe",
            parameterID: StretchParam.setCornerKeyframe.rawValue,
            selector: #selector(setCornerKeyframe),
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

    @objc private func setCornerKeyframe() {
        guard let actionAPI = _apiManager.api(for: FxCustomParameterActionAPI_v4.self) as? FxCustomParameterActionAPI_v4,
              let keyframeAPI = _apiManager.api(for: FxKeyframeAPI_v3.self) as? FxKeyframeAPI_v3 else {
            NSLog("AnyUpright Stretch: keyframe APIs unavailable")
            return
        }

        let time = actionAPI.currentTime()
        do {
            let missingTargets = try AUStretchKeyframePolicy.missingTargets(
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

            guard !missingTargets.isEmpty else {
                return
            }

            let undoAPI = _apiManager.api(for: FxUndoAPI.self) as? FxUndoAPI
            let startedUndoGroup = undoAPI?.startUndoGroup("Set Corner Keyframe") ?? false
            defer {
                if startedUndoGroup {
                    _ = undoAPI?.endUndoGroup()
                }
            }

            for target in missingTargets {
                var keyframe = FxKeyframe()
                keyframe.version = 3
                keyframe.time = time
                keyframe.segmentStyle = .linear
                if let error = keyframeAPI.add(
                    &keyframe,
                    toParameter: UInt(target.parameterID),
                    andChannel: target.channelIndex
                ) {
                    throw error
                }
            }
        } catch {
            NSLog("AnyUpright Stretch: unable to set corner keyframes: %@", String(describing: error))
        }
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
