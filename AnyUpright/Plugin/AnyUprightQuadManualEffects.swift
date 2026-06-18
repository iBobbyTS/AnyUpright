//
//  AnyUprightQuadManualEffects.swift
//  AnyUpright
//

import Foundation
import AppKit
import CoreImage
import IOSurface
import Vision

class AnyUprightQuadModePlugIn: AnyUprightWarpEffect {
    var fixedQuadMode: AUQuadTransformMode {
        fatalError("Subclasses must choose a fixed Quad mode.")
    }

    var showsSourceEditMode: Bool {
        fixedQuadMode == .sourceQuad
    }

    var showsCornerParameters: Bool {
        fixedQuadMode == .outputCorners
    }

    override func addEffectParameters(_ paramAPI: FxParameterCreationAPI_v5) throws {
        addFixedModeParameter(paramAPI)

        if showsSourceEditMode {
            paramAPI.addToggleButton(
                withName: "Edit Mode",
                parameterID: QuadParam.showCornerAdjuster.rawValue,
                defaultValue: true,
                parameterFlags: defaultFlags()
            )
        } else {
            paramAPI.addToggleButton(
                withName: "Edit Mode",
                parameterID: QuadParam.showCornerAdjuster.rawValue,
                defaultValue: false,
                parameterFlags: hiddenFlags()
            )
        }

        let cornerGroupFlags = showsCornerParameters ? collapsedFlags() : hiddenCollapsedFlags()
        addCornerParameters(paramAPI, title: "Top Left", groupID: QuadGroup.topLeft.rawValue, percentX: .topLeftPercentX, percentY: .topLeftPercentY, pixelX: .topLeftPixelX, pixelY: .topLeftPixelY, groupFlags: cornerGroupFlags)
        addCornerParameters(paramAPI, title: "Top Right", groupID: QuadGroup.topRight.rawValue, percentX: .topRightPercentX, percentY: .topRightPercentY, pixelX: .topRightPixelX, pixelY: .topRightPixelY, groupFlags: cornerGroupFlags)
        addCornerParameters(paramAPI, title: "Bottom Right", groupID: QuadGroup.bottomRight.rawValue, percentX: .bottomRightPercentX, percentY: .bottomRightPercentY, pixelX: .bottomRightPixelX, pixelY: .bottomRightPixelY, groupFlags: cornerGroupFlags)
        addCornerParameters(paramAPI, title: "Bottom Left", groupID: QuadGroup.bottomLeft.rawValue, percentX: .bottomLeftPercentX, percentY: .bottomLeftPercentY, pixelX: .bottomLeftPixelX, pixelY: .bottomLeftPixelY, groupFlags: cornerGroupFlags)
    }

    override func state(at renderTime: CMTime) -> AnyUprightParameterState {
        quadParameterState(at: renderTime, paramAPI: parameterRetrievalAPI(), fixedMode: fixedQuadMode)
    }

    private func addFixedModeParameter(_ paramAPI: FxParameterCreationAPI_v5) {
        paramAPI.addPopupMenu(
            withName: "Mode",
            parameterID: QuadParam.mode.rawValue,
            defaultValue: UInt32(fixedQuadMode.rawValue),
            menuEntries: ["Output Corners", "Source Quad"],
            parameterFlags: hiddenFlags()
        )
    }

    private func addCornerParameters(_ paramAPI: FxParameterCreationAPI_v5, title: String, groupID: UInt32, percentX: QuadParam, percentY: QuadParam, pixelX: QuadParam, pixelY: QuadParam, groupFlags: FxParameterFlags) {
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

@objc(AnyUprightQuadManualPlugIn)
class AnyUprightQuadManualPlugIn: AnyUprightQuadModePlugIn {
    override var fixedQuadMode: AUQuadTransformMode {
        .sourceQuad
    }
}

@objc(AnyUprightQuadOutputCornersPlugIn)
class AnyUprightQuadOutputCornersPlugIn: AnyUprightQuadModePlugIn {
    override var fixedQuadMode: AUQuadTransformMode {
        .outputCorners
    }
}
