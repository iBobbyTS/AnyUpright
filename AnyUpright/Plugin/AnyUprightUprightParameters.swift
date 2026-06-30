//
//  AnyUprightUprightParameters.swift
//  AnyUpright
//

import Foundation
import AppKit
import CoreImage
import IOSurface
import Vision

enum UprightParam: UInt32 {
    case verticalPerspective = 300
    case horizontalPerspective = 301
    case rotation = 302
    case analyze = 303
    case correctionMode = 304
    case controlMode = 305
    case autoCrop = 306
    case editMode = 307

    case guide1Enabled = 320
    case guide1Orientation = 321
    case guide1Start = 322
    case guide1End = 323
    case guide2Enabled = 330
    case guide2Orientation = 331
    case guide2Start = 332
    case guide2End = 333
    case guide3Enabled = 340
    case guide3Orientation = 341
    case guide3Start = 342
    case guide3End = 343
    case guide4Enabled = 350
    case guide4Orientation = 351
    case guide4Start = 352
    case guide4End = 353
}

enum UprightOSCPart: Int {
    case none = 0
    case guide1Start = 1
    case guide1End = 2
    case guide2Start = 3
    case guide2End = 4
    case guide3Start = 5
    case guide3End = 6
    case guide4Start = 7
    case guide4End = 8
    case guide1Line = 9
    case guide2Line = 10
    case guide3Line = 11
    case guide4Line = 12
}

struct UprightGuideSpec {
    var enabled: UprightParam
    var orientation: UprightParam
    var start: UprightParam
    var end: UprightParam
    var startPart: UprightOSCPart
    var endPart: UprightOSCPart
    var linePart: UprightOSCPart
    var defaultOrientation: UprightGuideOrientation
    var defaultStart: AUPoint
    var defaultEnd: AUPoint
}

struct UprightGuideLine {
    var spec: UprightGuideSpec
    var enabled: Bool
    var orientation: UprightGuideOrientation
    var start: AUPoint
    var end: AUPoint
}

let uprightGuideSpecs = [
    UprightGuideSpec(
        enabled: .guide1Enabled,
        orientation: .guide1Orientation,
        start: .guide1Start,
        end: .guide1End,
        startPart: .guide1Start,
        endPart: .guide1End,
        linePart: .guide1Line,
        defaultOrientation: .vertical,
        defaultStart: AUPoint(x: 0.35, y: 0.2),
        defaultEnd: AUPoint(x: 0.35, y: 0.8)
    ),
    UprightGuideSpec(
        enabled: .guide2Enabled,
        orientation: .guide2Orientation,
        start: .guide2Start,
        end: .guide2End,
        startPart: .guide2Start,
        endPart: .guide2End,
        linePart: .guide2Line,
        defaultOrientation: .vertical,
        defaultStart: AUPoint(x: 0.65, y: 0.2),
        defaultEnd: AUPoint(x: 0.65, y: 0.8)
    ),
    UprightGuideSpec(
        enabled: .guide3Enabled,
        orientation: .guide3Orientation,
        start: .guide3Start,
        end: .guide3End,
        startPart: .guide3Start,
        endPart: .guide3End,
        linePart: .guide3Line,
        defaultOrientation: .horizontal,
        defaultStart: AUPoint(x: 0.2, y: 0.35),
        defaultEnd: AUPoint(x: 0.8, y: 0.35)
    ),
    UprightGuideSpec(
        enabled: .guide4Enabled,
        orientation: .guide4Orientation,
        start: .guide4Start,
        end: .guide4End,
        startPart: .guide4Start,
        endPart: .guide4End,
        linePart: .guide4Line,
        defaultOrientation: .horizontal,
        defaultStart: AUPoint(x: 0.2, y: 0.65),
        defaultEnd: AUPoint(x: 0.8, y: 0.65)
    )
]

func uprightGuideLines(at time: CMTime, paramAPI: FxParameterRetrievalAPI_v6?, includeDisabled: Bool = false) -> [UprightGuideLine] {
    guard let paramAPI else {
        return []
    }

    return uprightGuideSpecs.compactMap { spec in
        var enabled = ObjCBool(false)
        var orientationRaw = Int32(spec.defaultOrientation.rawValue)
        paramAPI.getBoolValue(&enabled, fromParameter: spec.enabled.rawValue, at: time)
        paramAPI.getIntValue(&orientationRaw, fromParameter: spec.orientation.rawValue, at: time)
        guard enabled.boolValue || includeDisabled else {
            return nil
        }

        return UprightGuideLine(
            spec: spec,
            enabled: enabled.boolValue,
            orientation: UprightGuideOrientation(rawValue: orientationRaw) ?? spec.defaultOrientation,
            start: uprightPointParam(paramAPI, spec.start, defaultValue: spec.defaultStart, time: time),
            end: uprightPointParam(paramAPI, spec.end, defaultValue: spec.defaultEnd, time: time)
        )
    }
}

func uprightPointParam(_ paramAPI: FxParameterRetrievalAPI_v6, _ param: UprightParam, defaultValue: AUPoint, time: CMTime) -> AUPoint {
    uprightPointParam(paramAPI, param.rawValue, defaultValue: defaultValue, time: time)
}

func uprightPointParam(_ paramAPI: FxParameterRetrievalAPI_v6, _ parameterID: UInt32, defaultValue: AUPoint, time: CMTime) -> AUPoint {
    var x = defaultValue.x
    var y = defaultValue.y
    paramAPI.getXValue(&x, yValue: &y, fromParameter: parameterID, at: time)
    return AUPoint(x: x, y: y)
}

func endpointParameter(for part: UprightOSCPart) -> UprightParam? {
    for spec in uprightGuideSpecs {
        if spec.startPart == part {
            return spec.start
        }
        if spec.endPart == part {
            return spec.end
        }
    }
    return nil
}

func guideSpec(forLinePart part: UprightOSCPart) -> UprightGuideSpec? {
    uprightGuideSpecs.first { $0.linePart == part }
}

func imageLine(from guide: UprightGuideLine, size: AUSize) -> AULineSegment {
    AnyUprightUprightCandidates.imageLine(
        fromManualGuide: AULineSegment(start: guide.start, end: guide.end),
        size: size
    )
}

func writeUprightCorrection(
    verticalLines: [AULineSegment],
    horizontalLines: [AULineSegment],
    correctionMode: UprightCorrectionMode,
    settingAPI: FxParameterSettingAPI_v5,
    time: CMTime
) {
    let correction = AnyUprightUprightCandidates.correctionValues(
        verticalLines: verticalLines,
        horizontalLines: horizontalLines,
        correctionMode: correctionMode
    )

    settingAPI.setFloatValue(correction.verticalPerspective, toParameter: UprightParam.verticalPerspective.rawValue, at: time)
    settingAPI.setFloatValue(correction.horizontalPerspective, toParameter: UprightParam.horizontalPerspective.rawValue, at: time)
    settingAPI.setFloatValue(correction.rotationRadians, toParameter: UprightParam.rotation.rawValue, at: time)
}

func uprightCorrectionMode(at time: CMTime, paramAPI: FxParameterRetrievalAPI_v6?) -> UprightCorrectionMode {
    guard let paramAPI else {
        return .full
    }

    var raw = Int32(UprightCorrectionMode.full.rawValue)
    paramAPI.getIntValue(&raw, fromParameter: UprightParam.correctionMode.rawValue, at: time)
    return UprightCorrectionMode(rawValue: raw) ?? .full
}

func uprightControlMode(at time: CMTime, paramAPI: FxParameterRetrievalAPI_v6?) -> UprightControlMode {
    guard let paramAPI else {
        return .manual
    }

    var raw = Int32(UprightControlMode.manual.rawValue)
    paramAPI.getIntValue(&raw, fromParameter: UprightParam.controlMode.rawValue, at: time)
    return UprightControlMode(rawValue: raw) ?? .manual
}

func uprightAutoCrop(at time: CMTime, paramAPI: FxParameterRetrievalAPI_v6?) -> Bool {
    guard let paramAPI else {
        return true
    }

    var value = ObjCBool(true)
    paramAPI.getBoolValue(&value, fromParameter: UprightParam.autoCrop.rawValue, at: time)
    return value.boolValue
}

func uprightEditMode(at time: CMTime, paramAPI: FxParameterRetrievalAPI_v6?) -> Bool {
    guard let paramAPI else {
        return true
    }

    var value = ObjCBool(true)
    paramAPI.getBoolValue(&value, fromParameter: UprightParam.editMode.rawValue, at: time)
    return value.boolValue
}

func addUprightWorkflowParameters(_ paramAPI: FxParameterCreationAPI_v5, defaultFlags: FxParameterFlags) {
    paramAPI.addPopupMenu(
        withName: "Direction",
        parameterID: UprightParam.correctionMode.rawValue,
        defaultValue: UInt32(UprightCorrectionMode.full.rawValue),
        menuEntries: ["Vertical", "Horizontal", "Full"],
        parameterFlags: defaultFlags
    )
    paramAPI.addPushButton(
        withName: "Analyze",
        parameterID: UprightParam.analyze.rawValue,
        selector: #selector(AnyUprightUprightPlugIn.analyze),
        parameterFlags: defaultFlags
    )
    paramAPI.addPopupMenu(
        withName: "Mode",
        parameterID: UprightParam.controlMode.rawValue,
        defaultValue: UInt32(UprightControlMode.manual.rawValue),
        menuEntries: ["Manual", "Semi Auto", "Full Auto"],
        parameterFlags: defaultFlags
    )
    paramAPI.addToggleButton(
        withName: "Auto Crop",
        parameterID: UprightParam.autoCrop.rawValue,
        defaultValue: true,
        parameterFlags: defaultFlags
    )
    paramAPI.addToggleButton(
        withName: "Edit Mode",
        parameterID: UprightParam.editMode.rawValue,
        defaultValue: true,
        parameterFlags: defaultFlags
    )
}

func addUprightGuideParameters(_ paramAPI: FxParameterCreationAPI_v5, collapsedFlags: FxParameterFlags, defaultFlags: FxParameterFlags) {
    paramAPI.startParameterSubGroup("Guides", parameterID: 390, parameterFlags: collapsedFlags)
    for (index, spec) in uprightGuideSpecs.enumerated() {
        let title = "Guide \(index + 1)"
        paramAPI.startParameterSubGroup(title, parameterID: UInt32(391 + index), parameterFlags: collapsedFlags)
        paramAPI.addToggleButton(
            withName: "\(title) Enabled",
            parameterID: spec.enabled.rawValue,
            defaultValue: true,
            parameterFlags: defaultFlags
        )
        paramAPI.addPopupMenu(
            withName: "\(title) Orientation",
            parameterID: spec.orientation.rawValue,
            defaultValue: UInt32(spec.defaultOrientation.rawValue),
            menuEntries: ["Vertical", "Horizontal"],
            parameterFlags: defaultFlags
        )
        paramAPI.addPointParameter(
            withName: "\(title) Start",
            parameterID: spec.start.rawValue,
            defaultX: spec.defaultStart.x,
            defaultY: spec.defaultStart.y,
            parameterFlags: defaultFlags
        )
        paramAPI.addPointParameter(
            withName: "\(title) End",
            parameterID: spec.end.rawValue,
            defaultX: spec.defaultEnd.x,
            defaultY: spec.defaultEnd.y,
            parameterFlags: defaultFlags
        )
        paramAPI.endParameterSubGroup()
    }
    paramAPI.endParameterSubGroup()
}
