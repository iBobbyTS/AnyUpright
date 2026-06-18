//
//  AnyUprightUprightManualEffect.swift
//  AnyUpright
//

import Foundation
import AppKit
import CoreImage
import IOSurface
import Vision

@objc(AnyUprightUprightManualPlugIn)
class AnyUprightUprightManualPlugIn: AnyUprightWarpEffect, FxAnalyzer {
    private let analysisLock = NSLock()
    private let analysisContext = CIContext(options: nil)
    private var analysisState = UprightAnalysisScratchState()

    override func addEffectParameters(_ paramAPI: FxParameterCreationAPI_v5) throws {
        paramAPI.addPushButton(
            withName: "Auto Vertical",
            parameterID: UprightParam.analyzeVertical.rawValue,
            selector: #selector(analyzeVertical),
            parameterFlags: defaultFlags()
        )
        paramAPI.addPushButton(
            withName: "Auto Horizontal",
            parameterID: UprightParam.analyzeHorizontal.rawValue,
            selector: #selector(analyzeHorizontal),
            parameterFlags: defaultFlags()
        )
        paramAPI.addPushButton(
            withName: "Auto Full",
            parameterID: UprightParam.analyzeFull.rawValue,
            selector: #selector(analyzeFull),
            parameterFlags: defaultFlags()
        )
        paramAPI.addPushButton(
            withName: "Detect Vertical Candidates",
            parameterID: UprightParam.detectVerticalCandidates.rawValue,
            selector: #selector(detectVerticalCandidates),
            parameterFlags: defaultFlags()
        )
        paramAPI.addPushButton(
            withName: "Detect Horizontal Candidates",
            parameterID: UprightParam.detectHorizontalCandidates.rawValue,
            selector: #selector(detectHorizontalCandidates),
            parameterFlags: defaultFlags()
        )
        paramAPI.addPushButton(
            withName: "Detect Full Candidates",
            parameterID: UprightParam.detectFullCandidates.rawValue,
            selector: #selector(detectFullCandidates),
            parameterFlags: defaultFlags()
        )
        paramAPI.addPushButton(
            withName: "Apply Selected Vertical",
            parameterID: UprightParam.applySelectedVertical.rawValue,
            selector: #selector(applySelectedVertical),
            parameterFlags: defaultFlags()
        )
        paramAPI.addPushButton(
            withName: "Apply Selected Horizontal",
            parameterID: UprightParam.applySelectedHorizontal.rawValue,
            selector: #selector(applySelectedHorizontal),
            parameterFlags: defaultFlags()
        )
        paramAPI.addPushButton(
            withName: "Apply Selected Full",
            parameterID: UprightParam.applySelectedFull.rawValue,
            selector: #selector(applySelectedFull),
            parameterFlags: defaultFlags()
        )
        paramAPI.addPushButton(
            withName: "Apply Guided Vertical",
            parameterID: UprightParam.applyGuidedVertical.rawValue,
            selector: #selector(applyGuidedVertical),
            parameterFlags: defaultFlags()
        )
        paramAPI.addPushButton(
            withName: "Apply Guided Horizontal",
            parameterID: UprightParam.applyGuidedHorizontal.rawValue,
            selector: #selector(applyGuidedHorizontal),
            parameterFlags: defaultFlags()
        )
        paramAPI.addPushButton(
            withName: "Apply Guided Full",
            parameterID: UprightParam.applyGuidedFull.rawValue,
            selector: #selector(applyGuidedFull),
            parameterFlags: defaultFlags()
        )
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
        addUprightGuideParameters(paramAPI, collapsedFlags: collapsedFlags(), defaultFlags: defaultFlags())
        addUprightCandidateParameters(paramAPI, collapsedFlags: collapsedFlags(), defaultFlags: defaultFlags())
    }

    override func state(at renderTime: CMTime) -> AnyUprightParameterState {
        var result = AnyUprightParameterState(effectKind: AnyUprightEffectKind.upright.rawValue)
        guard let paramAPI = parameterRetrievalAPI() else {
            return result
        }

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

    @objc private func analyzeVertical() {
        startAnalysis(.vertical)
    }

    @objc private func analyzeHorizontal() {
        startAnalysis(.horizontal)
    }

    @objc private func analyzeFull() {
        startAnalysis(.full)
    }

    @objc private func detectVerticalCandidates() {
        startAnalysis(.detectVerticalCandidates)
    }

    @objc private func detectHorizontalCandidates() {
        startAnalysis(.detectHorizontalCandidates)
    }

    @objc private func detectFullCandidates() {
        startAnalysis(.detectFullCandidates)
    }

    @objc private func applySelectedVertical() {
        applySelected(.vertical)
    }

    @objc private func applySelectedHorizontal() {
        applySelected(.horizontal)
    }

    @objc private func applySelectedFull() {
        applySelected(.full)
    }

    @objc private func applyGuidedVertical() {
        applyGuided(.vertical)
    }

    @objc private func applyGuidedHorizontal() {
        applyGuided(.horizontal)
    }

    @objc private func applyGuidedFull() {
        applyGuided(.full)
    }

    private func startAnalysis(_ mode: UprightAnalysisMode) {
        analysisLock.lock()
        analysisState.pendingAnalysisMode = mode
        analysisState.requestedAnalysisTime = currentParameterTime()
        analysisLock.unlock()

        guard let analysisAPI = _apiManager.api(for: FxAnalysisAPI.self) as? FxAnalysisAPI else {
            return
        }

        try? analysisAPI.startForwardAnalysis(kFxAnalysisLocation_CPU)
    }

    func desiredAnalysisTimeRange(_ desiredRange: UnsafeMutablePointer<CMTimeRange>, forInputWith inputTimeRange: CMTimeRange) throws {
        analysisLock.lock()
        let requestedTime = analysisState.requestedAnalysisTime
        analysisLock.unlock()
        desiredRange.pointee = singleFrameAnalysisRange(near: requestedTime, within: inputTimeRange)
    }

    func setupAnalysis(for analysisRange: CMTimeRange, frameDuration: CMTime) throws {
        analysisLock.lock()
        analysisState.detectedVerticalPerspective = nil
        analysisState.detectedHorizontalPerspective = nil
        analysisState.detectedRotationRadians = nil
        analysisState.detectedCandidates = []
        analysisState.detectedPerspectiveTime = analysisRange.start
        analysisLock.unlock()
    }

    func analyzeFrame(_ frame: FxImageTile, at frameTime: CMTime) throws {
        analysisLock.lock()
        let mode = analysisState.pendingAnalysisMode
        analysisLock.unlock()

        guard let mode,
              let grayscaleImage = AnyUprightAnalysisImage.grayscaleImage(from: frame, maxDimension: 360, context: analysisContext) else {
            return
        }

        let size = AUSize(width: Double(grayscaleImage.width), height: Double(grayscaleImage.height))
        var verticalPerspective: Double?
        var horizontalPerspective: Double?
        var rotationRadians: Double?
        var verticalReferenceLines: [AULineSegment] = []
        var horizontalReferenceLines: [AULineSegment] = []
        var candidates: [UprightDetectedCandidate] = []

        if mode.includesVertical {
            let lines = AnyUprightLineDetection.detectLineSegments(
                in: grayscaleImage,
                options: AULineDetectionOptions(
                    orientation: .vertical,
                    edgeThreshold: 40.0,
                    voteThreshold: max(20, grayscaleImage.height / 5),
                    maxLines: candidateLimit(for: mode)
                )
            )
            let lineCandidates = AnyUprightGeometry.lineCandidates(
                from: lines,
                orientation: .vertical,
                minimumLength: Double(grayscaleImage.height) * 0.25
            )

            if mode.isCandidateDetection {
                candidates.append(contentsOf: AnyUprightUprightCandidates.detectedCandidates(
                    from: Array(lineCandidates.prefix(candidateLimit(for: mode))),
                    orientation: .vertical,
                    size: size
                ))
            } else {
                let references = Array(lineCandidates.prefix(2).map(\.line))
                verticalReferenceLines = references
                verticalPerspective = AnyUprightGeometry.estimateVerticalPerspective(from: references, size: size)
            }
        }

        if mode.includesHorizontal {
            let lines = AnyUprightLineDetection.detectLineSegments(
                in: grayscaleImage,
                options: AULineDetectionOptions(
                    orientation: .horizontal,
                    edgeThreshold: 40.0,
                    voteThreshold: max(20, grayscaleImage.width / 5),
                    maxLines: candidateLimit(for: mode)
                )
            )
            let lineCandidates = AnyUprightGeometry.lineCandidates(
                from: lines,
                orientation: .horizontal,
                minimumLength: Double(grayscaleImage.width) * 0.25
            )

            if mode.isCandidateDetection {
                candidates.append(contentsOf: AnyUprightUprightCandidates.detectedCandidates(
                    from: Array(lineCandidates.prefix(candidateLimit(for: mode))),
                    orientation: .horizontal,
                    size: size
                ))
            } else {
                let references = Array(lineCandidates.prefix(2).map(\.line))
                horizontalReferenceLines = references
                horizontalPerspective = AnyUprightGeometry.estimateHorizontalPerspective(from: references, size: size)
            }
        }

        if mode == .full {
            let rotationLines = horizontalReferenceLines.isEmpty ? verticalReferenceLines : horizontalReferenceLines
            let rotationOrientation: AUReferenceOrientation = horizontalReferenceLines.isEmpty ? .vertical : .horizontal
            if let rotation = AnyUprightGeometry.rotationCorrectionRadians(from: rotationLines, orientation: rotationOrientation) {
                rotationRadians = rotation
            }
        }

        analysisLock.lock()
        analysisState.detectedVerticalPerspective = verticalPerspective
        analysisState.detectedHorizontalPerspective = horizontalPerspective
        analysisState.detectedRotationRadians = rotationRadians
        analysisState.detectedCandidates = Array(candidates.prefix(AnyUprightUprightCandidates.slotCount))
        analysisState.detectedPerspectiveTime = frameTime
        analysisLock.unlock()
    }

    func cleanupAnalysis() throws {
        analysisLock.lock()
        let mode = analysisState.pendingAnalysisMode
        let vertical = analysisState.detectedVerticalPerspective
        let horizontal = analysisState.detectedHorizontalPerspective
        let rotation = analysisState.detectedRotationRadians
        let candidates = analysisState.detectedCandidates
        let time = parameterWriteTime(preferred: analysisState.requestedAnalysisTime, fallback: analysisState.detectedPerspectiveTime)
        analysisState.pendingAnalysisMode = nil
        analysisLock.unlock()

        guard let settingAPI = _apiManager.api(for: FxParameterSettingAPI_v5.self) as? FxParameterSettingAPI_v5 else {
            return
        }

        if mode?.isCandidateDetection == true {
            writeUprightCandidateSlots(candidates, settingAPI: settingAPI, time: time)
            return
        }

        if let vertical {
            _ = settingAPI.setFloatValue(vertical, toParameter: UprightParam.verticalPerspective.rawValue, at: time)
        }
        if let horizontal {
            _ = settingAPI.setFloatValue(horizontal, toParameter: UprightParam.horizontalPerspective.rawValue, at: time)
        }
        if let rotation {
            _ = settingAPI.setFloatValue(rotation, toParameter: UprightParam.rotation.rawValue, at: time)
        }
    }

    private func applyGuided(_ mode: UprightAnalysisMode) {
        let time = currentParameterTime()
        let guides = uprightGuideLines(at: time, paramAPI: parameterRetrievalAPI())
        let verticalLines = guides
            .filter { $0.orientation == .vertical }
            .map { imageLine(from: $0, size: AUSize(width: 1.0, height: 1.0)) }
        let horizontalLines = guides
            .filter { $0.orientation == .horizontal }
            .map { imageLine(from: $0, size: AUSize(width: 1.0, height: 1.0)) }

        applyReferences(verticalLines: verticalLines, horizontalLines: horizontalLines, mode: mode, time: time)
    }

    private func applySelected(_ mode: UprightAnalysisMode) {
        let time = currentParameterTime()
        let candidates = uprightCandidateLines(at: time, paramAPI: parameterRetrievalAPI())
        let verticalLines = AnyUprightUprightCandidates.selectedImageLines(from: candidates, orientation: .vertical)
        let horizontalLines = AnyUprightUprightCandidates.selectedImageLines(from: candidates, orientation: .horizontal)

        applyReferences(verticalLines: verticalLines, horizontalLines: horizontalLines, mode: mode, time: time)
    }

    private func applyReferences(verticalLines: [AULineSegment], horizontalLines: [AULineSegment], mode: UprightAnalysisMode, time: CMTime) {
        guard let settingAPI = _apiManager.api(for: FxParameterSettingAPI_v5.self) as? FxParameterSettingAPI_v5 else {
            return
        }

        if mode.includesVertical,
           let vertical = AnyUprightGeometry.estimateVerticalPerspective(from: verticalLines, size: AUSize(width: 1.0, height: 1.0)) {
            settingAPI.setFloatValue(vertical, toParameter: UprightParam.verticalPerspective.rawValue, at: time)
        }

        if mode.includesHorizontal,
           let horizontal = AnyUprightGeometry.estimateHorizontalPerspective(from: horizontalLines, size: AUSize(width: 1.0, height: 1.0)) {
            settingAPI.setFloatValue(horizontal, toParameter: UprightParam.horizontalPerspective.rawValue, at: time)
        }

        guard mode == .full else {
            return
        }

        let rotationLines = horizontalLines.isEmpty ? verticalLines : horizontalLines
        let rotationOrientation: AUReferenceOrientation = horizontalLines.isEmpty ? .vertical : .horizontal
        if let rotation = AnyUprightGeometry.rotationCorrectionRadians(from: rotationLines, orientation: rotationOrientation) {
            settingAPI.setFloatValue(rotation, toParameter: UprightParam.rotation.rawValue, at: time)
        }
    }

    private func candidateLimit(for mode: UprightAnalysisMode) -> Int {
        AnyUprightUprightCandidates.slotLimit(isFullMode: mode == .detectFullCandidates)
    }

}
