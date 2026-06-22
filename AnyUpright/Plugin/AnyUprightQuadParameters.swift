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
    case detectInnerStretch = 216
    case detectionScoreThreshold = 217
    case chooseFromDetections = 218
}

enum QuadGroup: UInt32, CaseIterable {
    case topLeft = 220
    case topRight = 221
    case bottomRight = 222
    case bottomLeft = 223
    case sourceDetectionEdges = 384
    case sourceDetectionCorners = 385
}

struct QuadInnerStretchDetectionEdgeSpec {
    var visible: UInt32
    var startX: UInt32
    var startY: UInt32
    var endX: UInt32
    var endY: UInt32
    var score: UInt32
}

struct QuadInnerStretchDetectionCornerSpec {
    var visible: UInt32
    var x: UInt32
    var y: UInt32
    var score: UInt32
}

struct QuadInnerStretchDetectionEdge {
    var index: Int
    var spec: QuadInnerStretchDetectionEdgeSpec
    var line: AULineSegment
    var score: Double
}

struct QuadInnerStretchDetectionCorner {
    var index: Int
    var spec: QuadInnerStretchDetectionCornerSpec
    var point: AUPoint
    var score: Double
}

struct QuadDetectedSourceEdge {
    var line: AULineSegment
    var score: Double
}

struct QuadDetectedSourceCorner {
    var point: AUPoint
    var score: Double
}

struct QuadDetectedSourcePrimitives {
    var edges: [QuadDetectedSourceEdge] = []
    var corners: [QuadDetectedSourceCorner] = []
}

enum AnyUprightQuadInnerStretchDetectionEdges {
    static let slotCount = 24
    static let specs: [QuadInnerStretchDetectionEdgeSpec] = (0..<slotCount).map { index in
        let base = UInt32(400 + index * 6)
        return QuadInnerStretchDetectionEdgeSpec(
            visible: base,
            startX: base + 1,
            startY: base + 2,
            endX: base + 3,
            endY: base + 4,
            score: base + 5
        )
    }
}

enum AnyUprightQuadInnerStretchDetectionCorners {
    static let slotCount = 48
    static let specs: [QuadInnerStretchDetectionCornerSpec] = (0..<slotCount).map { index in
        let base = UInt32(600 + index * 4)
        return QuadInnerStretchDetectionCornerSpec(
            visible: base,
            x: base + 1,
            y: base + 2,
            score: base + 3
        )
    }
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

    var mode = Int32(fixedMode?.rawValue ?? AUQuadTransformMode.innerStretch.rawValue)
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
    AUQuadTransformMode(rawValue: state.quadMode) ?? .innerStretch
}

func shouldShowQuadCornerAdjuster(from state: AnyUprightParameterState, mode: AUQuadTransformMode) -> Bool {
    mode == .innerStretch && state.showCornerAdjuster != 0
}

func shouldEnableQuadOSCControls(from state: AnyUprightParameterState, mode: AUQuadTransformMode) -> Bool {
    switch mode {
    case .outputCorners:
        return true
    case .innerStretch:
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

func quadDetectionScoreThreshold(at time: CMTime, paramAPI: FxParameterRetrievalAPI_v6?) -> Double {
    guard let paramAPI else {
        return 1.0
    }

    let value = quadFloatParam(paramAPI, .detectionScoreThreshold, time)
    return min(1.0, max(0.0, Double(value)))
}

func quadChooseFromDetections(at time: CMTime, paramAPI: FxParameterRetrievalAPI_v6?) -> Bool {
    guard let paramAPI else {
        return false
    }

    var value = ObjCBool(false)
    paramAPI.getBoolValue(&value, fromParameter: QuadParam.chooseFromDetections.rawValue, at: time)
    return value.boolValue
}

func quadInnerStretchDetectionEdges(at time: CMTime, paramAPI: FxParameterRetrievalAPI_v6?) -> [QuadInnerStretchDetectionEdge] {
    guard let paramAPI else {
        return []
    }

    return AnyUprightQuadInnerStretchDetectionEdges.specs.enumerated().compactMap { index, spec in
        var visible = ObjCBool(false)
        paramAPI.getBoolValue(&visible, fromParameter: spec.visible, at: time)
        guard visible.boolValue else {
            return nil
        }

        return QuadInnerStretchDetectionEdge(
            index: index,
            spec: spec,
            line: AULineSegment(
                start: AUPoint(
                    x: quadFloatParam(paramAPI, spec.startX, time),
                    y: quadFloatParam(paramAPI, spec.startY, time)
                ),
                end: AUPoint(
                    x: quadFloatParam(paramAPI, spec.endX, time),
                    y: quadFloatParam(paramAPI, spec.endY, time)
                )
            ),
            score: quadFloatParam(paramAPI, spec.score, time)
        )
    }
}

func quadInnerStretchDetectionCorners(at time: CMTime, paramAPI: FxParameterRetrievalAPI_v6?) -> [QuadInnerStretchDetectionCorner] {
    guard let paramAPI else {
        return []
    }

    return AnyUprightQuadInnerStretchDetectionCorners.specs.enumerated().compactMap { index, spec in
        var visible = ObjCBool(false)
        paramAPI.getBoolValue(&visible, fromParameter: spec.visible, at: time)
        guard visible.boolValue else {
            return nil
        }

        return QuadInnerStretchDetectionCorner(
            index: index,
            spec: spec,
            point: AUPoint(
                x: quadFloatParam(paramAPI, spec.x, time),
                y: quadFloatParam(paramAPI, spec.y, time)
            ),
            score: quadFloatParam(paramAPI, spec.score, time)
        )
    }
}

func quadFloatParam(_ paramAPI: FxParameterRetrievalAPI_v6, _ parameterID: UInt32, _ time: CMTime) -> Double {
    var value = 0.0
    paramAPI.getFloatValue(&value, fromParameter: parameterID, at: time)
    return value
}

func addQuadInnerStretchDetectionScoreThreshold(_ paramAPI: FxParameterCreationAPI_v5, parameterFlags: FxParameterFlags) {
    paramAPI.addFloatSlider(
        withName: "Score Threshold",
        parameterID: QuadParam.detectionScoreThreshold.rawValue,
        defaultValue: 1.0,
        parameterMin: 0.0,
        parameterMax: 1.0,
        sliderMin: 0.0,
        sliderMax: 1.0,
        delta: 0.01,
        parameterFlags: parameterFlags
    )
}

func addQuadChooseFromDetections(_ paramAPI: FxParameterCreationAPI_v5, parameterFlags: FxParameterFlags) {
    paramAPI.addToggleButton(
        withName: "Choose from detections",
        parameterID: QuadParam.chooseFromDetections.rawValue,
        defaultValue: false,
        parameterFlags: parameterFlags
    )
}

func addQuadInnerStretchDetectionPrimitiveParameters(_ paramAPI: FxParameterCreationAPI_v5, collapsedFlags: FxParameterFlags, hiddenFlags: FxParameterFlags) {
    paramAPI.startParameterSubGroup("Detected Edges", parameterID: QuadGroup.sourceDetectionEdges.rawValue, parameterFlags: collapsedFlags)
    for (index, spec) in AnyUprightQuadInnerStretchDetectionEdges.specs.enumerated() {
        let title = "Detected Edge \(index + 1)"
        paramAPI.addToggleButton(withName: "\(title) Visible", parameterID: spec.visible, defaultValue: false, parameterFlags: hiddenFlags)
        addQuadHiddenUnitSlider(paramAPI, name: "\(title) Start X", id: spec.startX, flags: hiddenFlags)
        addQuadHiddenUnitSlider(paramAPI, name: "\(title) Start Y", id: spec.startY, flags: hiddenFlags)
        addQuadHiddenUnitSlider(paramAPI, name: "\(title) End X", id: spec.endX, flags: hiddenFlags)
        addQuadHiddenUnitSlider(paramAPI, name: "\(title) End Y", id: spec.endY, flags: hiddenFlags)
        addQuadHiddenScoreSlider(paramAPI, name: "\(title) Score", id: spec.score, flags: hiddenFlags)
    }
    paramAPI.endParameterSubGroup()

    paramAPI.startParameterSubGroup("Detected Corners", parameterID: QuadGroup.sourceDetectionCorners.rawValue, parameterFlags: collapsedFlags)
    for (index, spec) in AnyUprightQuadInnerStretchDetectionCorners.specs.enumerated() {
        let title = "Detected Corner \(index + 1)"
        paramAPI.addToggleButton(withName: "\(title) Visible", parameterID: spec.visible, defaultValue: false, parameterFlags: hiddenFlags)
        addQuadHiddenUnitSlider(paramAPI, name: "\(title) X", id: spec.x, flags: hiddenFlags)
        addQuadHiddenUnitSlider(paramAPI, name: "\(title) Y", id: spec.y, flags: hiddenFlags)
        addQuadHiddenScoreSlider(paramAPI, name: "\(title) Score", id: spec.score, flags: hiddenFlags)
    }
    paramAPI.endParameterSubGroup()
}

private func addQuadHiddenUnitSlider(_ paramAPI: FxParameterCreationAPI_v5, name: String, id: UInt32, flags: FxParameterFlags) {
    paramAPI.addFloatSlider(
        withName: name,
        parameterID: id,
        defaultValue: 0.0,
        parameterMin: 0.0,
        parameterMax: 1.0,
        sliderMin: 0.0,
        sliderMax: 1.0,
        delta: 0.001,
        parameterFlags: flags
    )
}

private func addQuadHiddenScoreSlider(_ paramAPI: FxParameterCreationAPI_v5, name: String, id: UInt32, flags: FxParameterFlags) {
    paramAPI.addFloatSlider(
        withName: name,
        parameterID: id,
        defaultValue: 0.0,
        parameterMin: 0.0,
        parameterMax: 1.0,
        sliderMin: 0.0,
        sliderMax: 1.0,
        delta: 0.01,
        parameterFlags: flags
    )
}

func writeQuadInnerStretchDetectionPrimitives(_ primitives: QuadDetectedSourcePrimitives, size: AUSize, settingAPI: FxParameterSettingAPI_v5, time: CMTime) {
    for (index, spec) in AnyUprightQuadInnerStretchDetectionEdges.specs.enumerated() {
        guard index < primitives.edges.count else {
            clearQuadInnerStretchDetectionEdge(spec, settingAPI: settingAPI, time: time)
            continue
        }

        let objectLine = AnyUprightGeometry.normalizedObjectLine(fromImageLine: primitives.edges[index].line, size: size)
        settingAPI.setBoolValue(true, toParameter: spec.visible, at: time)
        settingAPI.setFloatValue(objectLine.start.x, toParameter: spec.startX, at: time)
        settingAPI.setFloatValue(objectLine.start.y, toParameter: spec.startY, at: time)
        settingAPI.setFloatValue(objectLine.end.x, toParameter: spec.endX, at: time)
        settingAPI.setFloatValue(objectLine.end.y, toParameter: spec.endY, at: time)
        settingAPI.setFloatValue(primitives.edges[index].score, toParameter: spec.score, at: time)
    }

    for (index, spec) in AnyUprightQuadInnerStretchDetectionCorners.specs.enumerated() {
        guard index < primitives.corners.count else {
            clearQuadInnerStretchDetectionCorner(spec, settingAPI: settingAPI, time: time)
            continue
        }

        let objectPoint = AnyUprightGeometry.normalizedObjectPoint(fromImagePoint: primitives.corners[index].point, size: size)
        settingAPI.setBoolValue(true, toParameter: spec.visible, at: time)
        settingAPI.setFloatValue(objectPoint.x, toParameter: spec.x, at: time)
        settingAPI.setFloatValue(objectPoint.y, toParameter: spec.y, at: time)
        settingAPI.setFloatValue(primitives.corners[index].score, toParameter: spec.score, at: time)
    }
}

private func clearQuadInnerStretchDetectionEdge(_ spec: QuadInnerStretchDetectionEdgeSpec, settingAPI: FxParameterSettingAPI_v5, time: CMTime) {
    settingAPI.setBoolValue(false, toParameter: spec.visible, at: time)
    settingAPI.setFloatValue(0.0, toParameter: spec.startX, at: time)
    settingAPI.setFloatValue(0.0, toParameter: spec.startY, at: time)
    settingAPI.setFloatValue(0.0, toParameter: spec.endX, at: time)
    settingAPI.setFloatValue(0.0, toParameter: spec.endY, at: time)
    settingAPI.setFloatValue(0.0, toParameter: spec.score, at: time)
}

private func clearQuadInnerStretchDetectionCorner(_ spec: QuadInnerStretchDetectionCornerSpec, settingAPI: FxParameterSettingAPI_v5, time: CMTime) {
    settingAPI.setBoolValue(false, toParameter: spec.visible, at: time)
    settingAPI.setFloatValue(0.0, toParameter: spec.x, at: time)
    settingAPI.setFloatValue(0.0, toParameter: spec.y, at: time)
    settingAPI.setFloatValue(0.0, toParameter: spec.score, at: time)
}

func quadObjectPoints(from state: AnyUprightParameterState, size: AUSize, mode: AUQuadTransformMode) -> AUQuad {
    switch mode {
    case .outputCorners:
        return AnyUprightGeometry.quadObjectPoints(from: quadCornerOffsets(from: state), size: size)
    case .innerStretch:
        return AnyUprightGeometry.innerStretchObjectPoints(from: quadCornerOffsets(from: state), size: size)
    }
}
