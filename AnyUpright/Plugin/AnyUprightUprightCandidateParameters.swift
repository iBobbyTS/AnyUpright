//
//  AnyUprightUprightCandidateParameters.swift
//  AnyUpright
//

import Foundation
import AppKit
import CoreImage
import IOSurface
import Vision

func uprightCandidateLines(at time: CMTime, paramAPI: FxParameterRetrievalAPI_v6?) -> [UprightCandidateLine] {
    guard let paramAPI else {
        return []
    }

    return AnyUprightUprightCandidates.specs.compactMap { spec in
        var visible = ObjCBool(false)
        var selected = ObjCBool(false)
        var orientationRaw = Int32(UprightGuideOrientation.vertical.rawValue)
        var score = 0.0
        paramAPI.getBoolValue(&visible, fromParameter: spec.visible, at: time)
        paramAPI.getBoolValue(&selected, fromParameter: spec.selected, at: time)
        paramAPI.getIntValue(&orientationRaw, fromParameter: spec.orientation, at: time)
        paramAPI.getFloatValue(&score, fromParameter: spec.score, at: time)

        guard visible.boolValue else {
            return nil
        }

        return UprightCandidateLine(
            spec: spec,
            selected: selected.boolValue,
            orientation: UprightGuideOrientation(rawValue: orientationRaw) ?? .vertical,
            start: uprightPointParam(paramAPI, spec.start, defaultValue: AUPoint(x: 0.0, y: 0.0), time: time),
            end: uprightPointParam(paramAPI, spec.end, defaultValue: AUPoint(x: 0.0, y: 0.0), time: time),
            score: min(1.0, max(0.0, score))
        )
    }
}

func addUprightCandidateParameters(_ paramAPI: FxParameterCreationAPI_v5, collapsedFlags: FxParameterFlags, defaultFlags: FxParameterFlags) {
    paramAPI.startParameterSubGroup("Detected Candidates", parameterID: 420, parameterFlags: collapsedFlags)
    for (index, spec) in AnyUprightUprightCandidates.specs.enumerated() {
        let title = "Candidate \(index + 1)"
        paramAPI.startParameterSubGroup(title, parameterID: spec.group, parameterFlags: collapsedFlags)
        paramAPI.addToggleButton(
            withName: "\(title) Visible",
            parameterID: spec.visible,
            defaultValue: false,
            parameterFlags: defaultFlags
        )
        paramAPI.addToggleButton(
            withName: "\(title) Selected",
            parameterID: spec.selected,
            defaultValue: false,
            parameterFlags: defaultFlags
        )
        paramAPI.addPopupMenu(
            withName: "\(title) Orientation",
            parameterID: spec.orientation,
            defaultValue: UInt32(UprightGuideOrientation.vertical.rawValue),
            menuEntries: ["Vertical", "Horizontal"],
            parameterFlags: defaultFlags
        )
        paramAPI.addPointParameter(
            withName: "\(title) Start",
            parameterID: spec.start,
            defaultX: 0.0,
            defaultY: 0.0,
            parameterFlags: defaultFlags
        )
        paramAPI.addPointParameter(
            withName: "\(title) End",
            parameterID: spec.end,
            defaultX: 0.0,
            defaultY: 0.0,
            parameterFlags: defaultFlags
        )
        paramAPI.addPercentSlider(
            withName: "\(title) Score",
            parameterID: spec.score,
            defaultValue: 0.0,
            parameterMin: 0.0,
            parameterMax: 1.0,
            sliderMin: 0.0,
            sliderMax: 1.0,
            delta: 0.01,
            parameterFlags: defaultFlags
        )
        paramAPI.endParameterSubGroup()
    }
    paramAPI.endParameterSubGroup()
}

func writeUprightCandidateSlots(_ candidates: [UprightDetectedCandidate], settingAPI: FxParameterSettingAPI_v5, time: CMTime) {
    var selectedCountByOrientation: [UprightGuideOrientation: Int] = [
        .vertical: 0,
        .horizontal: 0
    ]

    for (index, spec) in AnyUprightUprightCandidates.specs.enumerated() {
        guard index < candidates.count else {
            settingAPI.setBoolValue(false, toParameter: spec.visible, at: time)
            settingAPI.setBoolValue(false, toParameter: spec.selected, at: time)
            settingAPI.setFloatValue(0.0, toParameter: spec.score, at: time)
            continue
        }

        let candidate = candidates[index]
        let selectedCount = selectedCountByOrientation[candidate.orientation, default: 0]
        let shouldPreselect = selectedCount < 2
        selectedCountByOrientation[candidate.orientation] = selectedCount + 1

        settingAPI.setBoolValue(true, toParameter: spec.visible, at: time)
        settingAPI.setBoolValue(shouldPreselect, toParameter: spec.selected, at: time)
        settingAPI.setIntValue(Int32(candidate.orientation.rawValue), toParameter: spec.orientation, at: time)
        settingAPI.setXValue(candidate.start.x, yValue: candidate.start.y, toParameter: spec.start, at: time)
        settingAPI.setXValue(candidate.end.x, yValue: candidate.end.y, toParameter: spec.end, at: time)
        settingAPI.setFloatValue(candidate.score, toParameter: spec.score, at: time)
    }
}
