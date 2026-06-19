//
//  AnyUprightQuadParameters.swift
//  AnyUpright
//

import Foundation
import AppKit
import CoreImage
import IOSurface
import Vision

enum QuadParam: UInt32 {
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
    case detectSourceQuad = 216
}

enum QuadGroup: UInt32, CaseIterable {
    case topLeft = 220
    case topRight = 221
    case bottomRight = 222
    case bottomLeft = 223
}

func quadFloatParam(_ paramAPI: FxParameterRetrievalAPI_v6, _ param: QuadParam, _ time: CMTime) -> Float {
    var value = 0.0
    paramAPI.getFloatValue(&value, fromParameter: param.rawValue, at: time)
    return Float(value)
}

func quadParameterState(
    at time: CMTime,
    paramAPI: FxParameterRetrievalAPI_v6?,
    fixedMode: AUQuadTransformMode? = nil
) -> AnyUprightParameterState {
    var result = AnyUprightParameterState(effectKind: AnyUprightEffectKind.quad.rawValue)
    guard let paramAPI else {
        if let fixedMode {
            result.quadMode = fixedMode.rawValue
        }
        return result
    }

    var mode = Int32(fixedMode?.rawValue ?? AUQuadTransformMode.sourceQuad.rawValue)
    var showCornerAdjuster = ObjCBool(true)

    if fixedMode == nil {
        paramAPI.getIntValue(&mode, fromParameter: QuadParam.mode.rawValue, at: time)
    }
    paramAPI.getBoolValue(&showCornerAdjuster, fromParameter: QuadParam.showCornerAdjuster.rawValue, at: time)
    result.quadMode = mode
    result.showCornerAdjuster = showCornerAdjuster.boolValue ? 1 : 0

    result.topLeftPercentX = quadFloatParam(paramAPI, .topLeftPercentX, time)
    result.topLeftPercentY = quadFloatParam(paramAPI, .topLeftPercentY, time)
    result.topLeftPixelX = quadFloatParam(paramAPI, .topLeftPixelX, time)
    result.topLeftPixelY = quadFloatParam(paramAPI, .topLeftPixelY, time)

    result.topRightPercentX = quadFloatParam(paramAPI, .topRightPercentX, time)
    result.topRightPercentY = quadFloatParam(paramAPI, .topRightPercentY, time)
    result.topRightPixelX = quadFloatParam(paramAPI, .topRightPixelX, time)
    result.topRightPixelY = quadFloatParam(paramAPI, .topRightPixelY, time)

    result.bottomRightPercentX = quadFloatParam(paramAPI, .bottomRightPercentX, time)
    result.bottomRightPercentY = quadFloatParam(paramAPI, .bottomRightPercentY, time)
    result.bottomRightPixelX = quadFloatParam(paramAPI, .bottomRightPixelX, time)
    result.bottomRightPixelY = quadFloatParam(paramAPI, .bottomRightPixelY, time)

    result.bottomLeftPercentX = quadFloatParam(paramAPI, .bottomLeftPercentX, time)
    result.bottomLeftPercentY = quadFloatParam(paramAPI, .bottomLeftPercentY, time)
    result.bottomLeftPixelX = quadFloatParam(paramAPI, .bottomLeftPixelX, time)
    result.bottomLeftPixelY = quadFloatParam(paramAPI, .bottomLeftPixelY, time)

    return result
}

func quadMode(from state: AnyUprightParameterState) -> AUQuadTransformMode {
    AUQuadTransformMode(rawValue: state.quadMode) ?? .sourceQuad
}

func shouldShowQuadCornerAdjuster(from state: AnyUprightParameterState, mode: AUQuadTransformMode) -> Bool {
    mode == .sourceQuad && state.showCornerAdjuster != 0
}

func shouldEnableQuadOSCControls(from state: AnyUprightParameterState, mode: AUQuadTransformMode) -> Bool {
    switch mode {
    case .outputCorners:
        return true
    case .sourceQuad:
        return shouldShowQuadCornerAdjuster(from: state, mode: mode)
    }
}

func quadCornerOffsets(from state: AnyUprightParameterState) -> AUCornerOffsets {
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

func quadObjectPoints(from state: AnyUprightParameterState, size: AUSize, mode: AUQuadTransformMode) -> AUQuad {
    switch mode {
    case .outputCorners:
        return AnyUprightGeometry.quadObjectPoints(from: quadCornerOffsets(from: state), size: size)
    case .sourceQuad:
        return AnyUprightGeometry.sourceQuadObjectPoints(from: quadCornerOffsets(from: state), size: size)
    }
}
