//
//  AnyUprightStretchParameters.swift
//  AnyUpright
//

import Foundation

enum StretchParam: UInt32 {
    case mode = 198
    case showCornerAdjuster = 199
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
    // Parameter IDs 216...218 are retired and must not be reused.
}

enum StretchGroup: UInt32, CaseIterable {
    case topLeft = 220
    case topRight = 221
    case bottomRight = 222
    case bottomLeft = 223
}

func stretchFloatParam(_ paramAPI: FxParameterRetrievalAPI_v6, _ param: StretchParam, _ time: CMTime) -> Float {
    var value = 0.0
    paramAPI.getFloatValue(&value, fromParameter: param.rawValue, at: time)
    return Float(value)
}

func stretchParameterState(
    at time: CMTime,
    paramAPI: FxParameterRetrievalAPI_v6?,
    fixedMode: AUStretchTransformMode? = nil
) -> AnyUprightParameterState {
    var result = AnyUprightParameterState(effectKind: AnyUprightEffectKind.stretch.rawValue)
    guard let paramAPI else {
        if let fixedMode {
            result.stretchMode = fixedMode.rawValue
        }
        return result
    }

    var mode = Int32(fixedMode?.rawValue ?? AUStretchTransformMode.innerStretch.rawValue)
    var showCornerAdjuster = ObjCBool(true)

    if fixedMode == nil {
        paramAPI.getIntValue(&mode, fromParameter: StretchParam.mode.rawValue, at: time)
    }
    paramAPI.getBoolValue(&showCornerAdjuster, fromParameter: StretchParam.showCornerAdjuster.rawValue, at: time)
    result.stretchMode = mode
    result.showCornerAdjuster = showCornerAdjuster.boolValue ? 1 : 0

    result.topLeftPercentX = stretchFloatParam(paramAPI, .topLeftPercentX, time)
    result.topLeftPercentY = stretchFloatParam(paramAPI, .topLeftPercentY, time)
    result.topLeftPixelX = stretchFloatParam(paramAPI, .topLeftPixelX, time)
    result.topLeftPixelY = stretchFloatParam(paramAPI, .topLeftPixelY, time)

    result.topRightPercentX = stretchFloatParam(paramAPI, .topRightPercentX, time)
    result.topRightPercentY = stretchFloatParam(paramAPI, .topRightPercentY, time)
    result.topRightPixelX = stretchFloatParam(paramAPI, .topRightPixelX, time)
    result.topRightPixelY = stretchFloatParam(paramAPI, .topRightPixelY, time)

    result.bottomRightPercentX = stretchFloatParam(paramAPI, .bottomRightPercentX, time)
    result.bottomRightPercentY = stretchFloatParam(paramAPI, .bottomRightPercentY, time)
    result.bottomRightPixelX = stretchFloatParam(paramAPI, .bottomRightPixelX, time)
    result.bottomRightPixelY = stretchFloatParam(paramAPI, .bottomRightPixelY, time)

    result.bottomLeftPercentX = stretchFloatParam(paramAPI, .bottomLeftPercentX, time)
    result.bottomLeftPercentY = stretchFloatParam(paramAPI, .bottomLeftPercentY, time)
    result.bottomLeftPixelX = stretchFloatParam(paramAPI, .bottomLeftPixelX, time)
    result.bottomLeftPixelY = stretchFloatParam(paramAPI, .bottomLeftPixelY, time)

    return result
}

func stretchMode(from state: AnyUprightParameterState) -> AUStretchTransformMode {
    AUStretchTransformMode(rawValue: state.stretchMode) ?? .innerStretch
}

func shouldShowStretchCornerAdjuster(from state: AnyUprightParameterState, mode: AUStretchTransformMode) -> Bool {
    mode == .innerStretch && state.showCornerAdjuster != 0
}

func shouldEnableStretchOSCControls(from state: AnyUprightParameterState, mode: AUStretchTransformMode) -> Bool {
    switch mode {
    case .outputCorners:
        return true
    case .innerStretch:
        return shouldShowStretchCornerAdjuster(from: state, mode: mode)
    }
}

func stretchCornerOffsets(from state: AnyUprightParameterState) -> AUCornerOffsets {
    AUCornerOffsets(
        topLeftPercent: AUPoint(x: Double(state.topLeftPercentX), y: Double(state.topLeftPercentY)),
        topRightPercent: AUPoint(x: Double(state.topRightPercentX), y: Double(state.topRightPercentY)),
        bottomRightPercent: AUPoint(x: Double(state.bottomRightPercentX), y: Double(state.bottomRightPercentY)),
        bottomLeftPercent: AUPoint(x: Double(state.bottomLeftPercentX), y: Double(state.bottomLeftPercentY)),
        topLeftPixels: AUPoint(x: Double(state.topLeftPixelX), y: Double(state.topLeftPixelY)),
        topRightPixels: AUPoint(x: Double(state.topRightPixelX), y: Double(state.topRightPixelY)),
        bottomRightPixels: AUPoint(x: Double(state.bottomRightPixelX), y: Double(state.bottomRightPixelY)),
        bottomLeftPixels: AUPoint(x: Double(state.bottomLeftPixelX), y: Double(state.bottomLeftPixelY))
    )
}

func stretchObjectPoints(from state: AnyUprightParameterState, size: AUSize, mode: AUStretchTransformMode) -> AUStretchCorners {
    switch mode {
    case .outputCorners:
        return AnyUprightGeometry.stretchObjectPoints(from: stretchCornerOffsets(from: state), size: size)
    case .innerStretch:
        return AnyUprightGeometry.innerStretchObjectPoints(from: stretchCornerOffsets(from: state), size: size)
    }
}
