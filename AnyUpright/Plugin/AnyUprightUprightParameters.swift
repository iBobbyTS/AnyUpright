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
    case analyzeVertical = 303
    case analyzeHorizontal = 304
    case analyzeFull = 305
    case applyGuidedVertical = 306
    case applyGuidedHorizontal = 307
    case applyGuidedFull = 308
    case detectVerticalCandidates = 309
    case detectHorizontalCandidates = 310
    case detectFullCandidates = 311
    case applySelectedVertical = 312
    case applySelectedHorizontal = 313
    case applySelectedFull = 314
    case chooseFromDetections = 315
    case candidateScoreThreshold = 316

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

enum UprightAnalysisMode {
    case vertical
    case horizontal
    case full
    case detectVerticalCandidates
    case detectHorizontalCandidates
    case detectFullCandidates

    var includesVertical: Bool {
        switch self {
        case .vertical, .full, .detectVerticalCandidates, .detectFullCandidates:
            return true
        case .horizontal, .detectHorizontalCandidates:
            return false
        }
    }

    var includesHorizontal: Bool {
        switch self {
        case .horizontal, .full, .detectHorizontalCandidates, .detectFullCandidates:
            return true
        case .vertical, .detectVerticalCandidates:
            return false
        }
    }

    var isCandidateDetection: Bool {
        switch self {
        case .detectVerticalCandidates, .detectHorizontalCandidates, .detectFullCandidates:
            return true
        case .vertical, .horizontal, .full:
            return false
        }
    }
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
}

struct UprightGuideSpec {
    var enabled: UprightParam
    var orientation: UprightParam
    var start: UprightParam
    var end: UprightParam
    var startPart: UprightOSCPart
    var endPart: UprightOSCPart
    var defaultOrientation: UprightGuideOrientation
    var defaultStart: AUPoint
    var defaultEnd: AUPoint
}

struct UprightGuideLine {
    var spec: UprightGuideSpec
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
        defaultOrientation: .horizontal,
        defaultStart: AUPoint(x: 0.2, y: 0.65),
        defaultEnd: AUPoint(x: 0.8, y: 0.65)
    )
]

func uprightGuideLines(at time: CMTime, paramAPI: FxParameterRetrievalAPI_v6?) -> [UprightGuideLine] {
    guard let paramAPI else {
        return []
    }

    return uprightGuideSpecs.compactMap { spec in
        var enabled = ObjCBool(false)
        var orientationRaw = Int32(spec.defaultOrientation.rawValue)
        paramAPI.getBoolValue(&enabled, fromParameter: spec.enabled.rawValue, at: time)
        paramAPI.getIntValue(&orientationRaw, fromParameter: spec.orientation.rawValue, at: time)
        guard enabled.boolValue else {
            return nil
        }

        return UprightGuideLine(
            spec: spec,
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

func imageLine(from guide: UprightGuideLine, size: AUSize) -> AULineSegment {
    AULineSegment(
        start: AUPoint(x: guide.start.x * size.width, y: (1.0 - guide.start.y) * size.height),
        end: AUPoint(x: guide.end.x * size.width, y: (1.0 - guide.end.y) * size.height)
    )
}

func uprightChooseFromDetections(at time: CMTime, paramAPI: FxParameterRetrievalAPI_v6?) -> Bool {
    guard let paramAPI else {
        return false
    }

    var choose = ObjCBool(false)
    paramAPI.getBoolValue(&choose, fromParameter: UprightParam.chooseFromDetections.rawValue, at: time)
    return choose.boolValue
}

func uprightCandidateScoreThreshold(at time: CMTime, paramAPI: FxParameterRetrievalAPI_v6?) -> Double {
    guard let paramAPI else {
        return 0.0
    }

    var threshold = 0.2
    paramAPI.getFloatValue(&threshold, fromParameter: UprightParam.candidateScoreThreshold.rawValue, at: time)
    return min(1.0, max(0.0, threshold))
}

func addUprightSemiAutomaticParameters(_ paramAPI: FxParameterCreationAPI_v5, defaultFlags: FxParameterFlags) {
    paramAPI.addToggleButton(
        withName: "Choose from detections",
        parameterID: UprightParam.chooseFromDetections.rawValue,
        defaultValue: false,
        parameterFlags: defaultFlags
    )
    paramAPI.addPercentSlider(
        withName: "Score Threshold",
        parameterID: UprightParam.candidateScoreThreshold.rawValue,
        defaultValue: 0.2,
        parameterMin: 0.0,
        parameterMax: 1.0,
        sliderMin: 0.0,
        sliderMax: 1.0,
        delta: 0.01,
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
