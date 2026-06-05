//
//  AnyUprightManualEffects.swift
//  AnyUpright
//

import Foundation

private enum HorizonParam: UInt32 {
    case rotation = 100
    case fillFrame = 101
}

private enum QuadParam: UInt32 {
    case topLeftPercentX = 200
    case topLeftPercentY = 201
    case topLeftPixelX = 202
    case topLeftPixelY = 203
    case topRightPercentX = 204
    case topRightPercentY = 205
    case topRightPixelX = 206
    case topRightPixelY = 207
    case bottomRightPercentX = 208
    case bottomRightPercentY = 209
    case bottomRightPixelX = 210
    case bottomRightPixelY = 211
    case bottomLeftPercentX = 212
    case bottomLeftPercentY = 213
    case bottomLeftPixelX = 214
    case bottomLeftPixelY = 215
}

private enum UprightParam: UInt32 {
    case verticalPerspective = 300
    case horizontalPerspective = 301
    case rotation = 302
}

@objc(AnyUprightHorizonManualPlugIn)
class AnyUprightHorizonManualPlugIn: AnyUprightWarpEffect {
    override func addEffectParameters(_ paramAPI: FxParameterCreationAPI_v5) throws {
        paramAPI.addAngleSlider(
            withName: "Rotation",
            parameterID: HorizonParam.rotation.rawValue,
            defaultDegrees: 0.0,
            parameterMinDegrees: -45.0,
            parameterMaxDegrees: 45.0,
            parameterFlags: defaultFlags()
        )
        paramAPI.addToggleButton(
            withName: "Fill Frame",
            parameterID: HorizonParam.fillFrame.rawValue,
            defaultValue: false,
            parameterFlags: defaultFlags()
        )
    }

    override func state(at renderTime: CMTime) -> AnyUprightParameterState {
        let paramAPI = parameterRetrievalAPI()
        var result = AnyUprightParameterState(effectKind: AnyUprightEffectKind.horizon.rawValue)
        var rotation = 0.0
        var fillFrame = ObjCBool(false)

        paramAPI.getFloatValue(&rotation, fromParameter: HorizonParam.rotation.rawValue, at: renderTime)
        paramAPI.getBoolValue(&fillFrame, fromParameter: HorizonParam.fillFrame.rawValue, at: renderTime)

        result.rotationRadians = Float(rotation)
        result.fillFrame = fillFrame.boolValue ? 1 : 0
        return result
    }
}

@objc(AnyUprightQuadManualPlugIn)
class AnyUprightQuadManualPlugIn: AnyUprightWarpEffect {
    override func addEffectParameters(_ paramAPI: FxParameterCreationAPI_v5) throws {
        addCornerParameters(paramAPI, title: "Top Left", groupID: 220, percentX: .topLeftPercentX, percentY: .topLeftPercentY, pixelX: .topLeftPixelX, pixelY: .topLeftPixelY)
        addCornerParameters(paramAPI, title: "Top Right", groupID: 221, percentX: .topRightPercentX, percentY: .topRightPercentY, pixelX: .topRightPixelX, pixelY: .topRightPixelY)
        addCornerParameters(paramAPI, title: "Bottom Right", groupID: 222, percentX: .bottomRightPercentX, percentY: .bottomRightPercentY, pixelX: .bottomRightPixelX, pixelY: .bottomRightPixelY)
        addCornerParameters(paramAPI, title: "Bottom Left", groupID: 223, percentX: .bottomLeftPercentX, percentY: .bottomLeftPercentY, pixelX: .bottomLeftPixelX, pixelY: .bottomLeftPixelY)
    }

    override func state(at renderTime: CMTime) -> AnyUprightParameterState {
        let paramAPI = parameterRetrievalAPI()
        var result = AnyUprightParameterState(effectKind: AnyUprightEffectKind.quad.rawValue)

        result.topLeftPercentX = floatParam(paramAPI, .topLeftPercentX, renderTime)
        result.topLeftPercentY = floatParam(paramAPI, .topLeftPercentY, renderTime)
        result.topLeftPixelX = floatParam(paramAPI, .topLeftPixelX, renderTime)
        result.topLeftPixelY = floatParam(paramAPI, .topLeftPixelY, renderTime)

        result.topRightPercentX = floatParam(paramAPI, .topRightPercentX, renderTime)
        result.topRightPercentY = floatParam(paramAPI, .topRightPercentY, renderTime)
        result.topRightPixelX = floatParam(paramAPI, .topRightPixelX, renderTime)
        result.topRightPixelY = floatParam(paramAPI, .topRightPixelY, renderTime)

        result.bottomRightPercentX = floatParam(paramAPI, .bottomRightPercentX, renderTime)
        result.bottomRightPercentY = floatParam(paramAPI, .bottomRightPercentY, renderTime)
        result.bottomRightPixelX = floatParam(paramAPI, .bottomRightPixelX, renderTime)
        result.bottomRightPixelY = floatParam(paramAPI, .bottomRightPixelY, renderTime)

        result.bottomLeftPercentX = floatParam(paramAPI, .bottomLeftPercentX, renderTime)
        result.bottomLeftPercentY = floatParam(paramAPI, .bottomLeftPercentY, renderTime)
        result.bottomLeftPixelX = floatParam(paramAPI, .bottomLeftPixelX, renderTime)
        result.bottomLeftPixelY = floatParam(paramAPI, .bottomLeftPixelY, renderTime)

        return result
    }

    private func addCornerParameters(_ paramAPI: FxParameterCreationAPI_v5, title: String, groupID: UInt32, percentX: QuadParam, percentY: QuadParam, pixelX: QuadParam, pixelY: QuadParam) {
        paramAPI.startParameterSubGroup(title, parameterID: groupID, parameterFlags: collapsedFlags())
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

    private func floatParam(_ paramAPI: FxParameterRetrievalAPI_v6, _ param: QuadParam, _ time: CMTime) -> Float {
        var value = 0.0
        paramAPI.getFloatValue(&value, fromParameter: param.rawValue, at: time)
        return Float(value)
    }
}

@objc(AnyUprightUprightManualPlugIn)
class AnyUprightUprightManualPlugIn: AnyUprightWarpEffect {
    override func addEffectParameters(_ paramAPI: FxParameterCreationAPI_v5) throws {
        paramAPI.addPercentSlider(
            withName: "Vertical Perspective",
            parameterID: UprightParam.verticalPerspective.rawValue,
            defaultValue: 0.0,
            parameterMin: -1.0,
            parameterMax: 1.0,
            sliderMin: -0.5,
            sliderMax: 0.5,
            delta: 0.01,
            parameterFlags: defaultFlags()
        )
        paramAPI.addPercentSlider(
            withName: "Horizontal Perspective",
            parameterID: UprightParam.horizontalPerspective.rawValue,
            defaultValue: 0.0,
            parameterMin: -1.0,
            parameterMax: 1.0,
            sliderMin: -0.5,
            sliderMax: 0.5,
            delta: 0.01,
            parameterFlags: defaultFlags()
        )
        paramAPI.addAngleSlider(
            withName: "Rotation",
            parameterID: UprightParam.rotation.rawValue,
            defaultDegrees: 0.0,
            parameterMinDegrees: -45.0,
            parameterMaxDegrees: 45.0,
            parameterFlags: defaultFlags()
        )
    }

    override func state(at renderTime: CMTime) -> AnyUprightParameterState {
        let paramAPI = parameterRetrievalAPI()
        var result = AnyUprightParameterState(effectKind: AnyUprightEffectKind.upright.rawValue)
        var vertical = 0.0
        var horizontal = 0.0
        var rotation = 0.0

        paramAPI.getFloatValue(&vertical, fromParameter: UprightParam.verticalPerspective.rawValue, at: renderTime)
        paramAPI.getFloatValue(&horizontal, fromParameter: UprightParam.horizontalPerspective.rawValue, at: renderTime)
        paramAPI.getFloatValue(&rotation, fromParameter: UprightParam.rotation.rawValue, at: renderTime)

        result.verticalPerspective = Float(vertical)
        result.horizontalPerspective = Float(horizontal)
        result.rotationRadians = Float(rotation)
        return result
    }
}
