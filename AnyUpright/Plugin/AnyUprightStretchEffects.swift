//
//  AnyUprightStretchEffects.swift
//  AnyUpright
//

import Foundation

class AnyUprightStretchModePlugIn: AnyUprightWarpEffect {
    var fixedStretchMode: AUStretchTransformMode {
        fatalError("Subclasses must choose a fixed Stretch mode.")
    }

    override var needsFullBuffer: Bool {
        true
    }

    var showsSourceEditMode: Bool {
        fixedStretchMode == .innerStretch
    }

    var showsCornerParameters: Bool {
        fixedStretchMode == .outputCorners
    }

    override func addEffectParameters(_ paramAPI: FxParameterCreationAPI_v5) throws {
        addFixedModeParameter(paramAPI)

        paramAPI.addPopupMenu(
            withName: "Ratio",
            parameterID: StretchParam.ratio.rawValue,
            defaultValue: UInt32(AUStretchRatioMode.none.rawValue),
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

        let cornerGroupFlags = showsCornerParameters ? collapsedFlags() : hiddenCollapsedFlags()
        addCornerParameters(paramAPI, title: "Top Left", groupID: StretchGroup.topLeft.rawValue, percentX: .topLeftPercentX, percentY: .topLeftPercentY, pixelX: .topLeftPixelX, pixelY: .topLeftPixelY, groupFlags: cornerGroupFlags)
        addCornerParameters(paramAPI, title: "Top Right", groupID: StretchGroup.topRight.rawValue, percentX: .topRightPercentX, percentY: .topRightPercentY, pixelX: .topRightPixelX, pixelY: .topRightPixelY, groupFlags: cornerGroupFlags)
        addCornerParameters(paramAPI, title: "Bottom Right", groupID: StretchGroup.bottomRight.rawValue, percentX: .bottomRightPercentX, percentY: .bottomRightPercentY, pixelX: .bottomRightPixelX, pixelY: .bottomRightPixelY, groupFlags: cornerGroupFlags)
        addCornerParameters(paramAPI, title: "Bottom Left", groupID: StretchGroup.bottomLeft.rawValue, percentX: .bottomLeftPercentX, percentY: .bottomLeftPercentY, pixelX: .bottomLeftPixelX, pixelY: .bottomLeftPixelY, groupFlags: cornerGroupFlags)

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

    private func addCornerParameters(_ paramAPI: FxParameterCreationAPI_v5, title: String, groupID: UInt32, percentX: StretchParam, percentY: StretchParam, pixelX: StretchParam, pixelY: StretchParam, groupFlags: FxParameterFlags) {
        paramAPI.startParameterSubGroup(title, parameterID: groupID, parameterFlags: groupFlags)
        addPercentSlider(paramAPI, name: "\(title) X %", id: percentX.rawValue)
        addPercentSlider(paramAPI, name: "\(title) Y %", id: percentY.rawValue)
        addPixelSlider(paramAPI, name: "\(title) X px", id: pixelX.rawValue)
        addPixelSlider(paramAPI, name: "\(title) Y px", id: pixelY.rawValue)
        paramAPI.endParameterSubGroup()
    }

    private func addPercentSlider(_ paramAPI: FxParameterCreationAPI_v5, name: String, id: UInt32) {
        paramAPI.addPercentSlider(
            withName: name,
            parameterID: id,
            defaultValue: 0.0,
            parameterMin: -1.0,
            parameterMax: 1.0,
            sliderMin: -0.5,
            sliderMax: 0.5,
            delta: 0.01,
            parameterFlags: defaultFlags()
        )
    }

    private func addPixelSlider(_ paramAPI: FxParameterCreationAPI_v5, name: String, id: UInt32) {
        paramAPI.addFloatSlider(
            withName: name,
            parameterID: id,
            defaultValue: 0.0,
            parameterMin: -10000.0,
            parameterMax: 10000.0,
            sliderMin: -500.0,
            sliderMax: 500.0,
            delta: 1.0,
            parameterFlags: defaultFlags()
        )
    }

    private func hiddenFlags() -> FxParameterFlags {
        FxParameterFlags(kFxParameterFlag_HIDDEN)
    }

    private func hiddenCollapsedFlags() -> FxParameterFlags {
        FxParameterFlags(kFxParameterFlag_HIDDEN | kFxParameterFlag_COLLAPSED)
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
