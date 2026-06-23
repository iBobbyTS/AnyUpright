//
//  AnyUprightUprightEffect.swift
//  AnyUpright
//

import Foundation
import AppKit
import CoreImage
import IOSurface
import Vision

@objc(AnyUprightUprightPlugIn)
class AnyUprightUprightPlugIn: AnyUprightWarpEffect, FxAnalyzer {
    private let analysisLock = NSLock()
    private let analysisContext = CIContext(options: nil)
    private var analysisState = UprightAnalysisScratchState()

    override func addEffectParameters(_ paramAPI: FxParameterCreationAPI_v5) throws {
        addUprightWorkflowParameters(paramAPI, defaultFlags: defaultFlags())
        addHiddenCorrectionResultParameters(paramAPI)
        addUprightGuideParameters(paramAPI, collapsedFlags: hiddenCollapsedFlags(), defaultFlags: hiddenFlags())
        addUprightCandidateParameters(paramAPI, collapsedFlags: hiddenCollapsedFlags(), defaultFlags: hiddenFlags())
    }

    private func addHiddenCorrectionResultParameters(_ paramAPI: FxParameterCreationAPI_v5) {
        paramAPI.addPercentSlider(
            withName: "Vertical Perspective",
            parameterID: UprightParam.verticalPerspective.rawValue,
            defaultValue: 0.0,
            parameterMin: -1.0,
            parameterMax: 1.0,
            sliderMin: -0.5,
            sliderMax: 0.5,
            delta: 0.01,
            parameterFlags: hiddenFlags()
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
            parameterFlags: hiddenFlags()
        )
        paramAPI.addAngleSlider(
            withName: "Rotation",
            parameterID: UprightParam.rotation.rawValue,
            defaultDegrees: 0.0,
            parameterMinDegrees: -45.0,
            parameterMaxDegrees: 45.0,
            parameterFlags: hiddenFlags()
        )
    }

    private func hiddenFlags() -> FxParameterFlags {
        FxParameterFlags(kFxParameterFlag_HIDDEN)
    }

    private func hiddenCollapsedFlags() -> FxParameterFlags {
        FxParameterFlags(kFxParameterFlag_HIDDEN | kFxParameterFlag_COLLAPSED)
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

        let correctionMode = uprightCorrectionMode(at: renderTime, paramAPI: paramAPI)
        let editMode = uprightEditMode(at: renderTime, paramAPI: paramAPI)
        result.fillFrame = uprightAutoCrop(at: renderTime, paramAPI: paramAPI) ? 1 : 0
        result.showCornerAdjuster = editMode ? 1 : 0
        result.verticalPerspective = correctionMode.includesVertical ? Float(vertical) : 0.0
        result.horizontalPerspective = correctionMode.includesHorizontal ? Float(horizontal) : 0.0
        result.rotationRadians = correctionMode == .full ? Float(rotation) : 0.0
        return result
    }

    @objc func analyze() {
        let time = currentParameterTime()
        let paramAPI = parameterRetrievalAPI()
        let correctionMode = uprightCorrectionMode(at: time, paramAPI: paramAPI)
        let controlMode = uprightControlMode(at: time, paramAPI: paramAPI)
        guard controlMode != .manual else {
            applyGuided(correctionMode, time: time)
            return
        }

        startAnalysis(UprightAnalysisRequest(correctionMode: correctionMode, controlMode: controlMode))
    }

    private func startAnalysis(_ request: UprightAnalysisRequest) {
        analysisLock.lock()
        analysisState.pendingAnalysisRequest = request
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
        let request = analysisState.pendingAnalysisRequest
        analysisLock.unlock()

        guard let request else {
            return
        }

        if request.shouldUseCandidateDetection {
            do {
                let mlsdCandidates = try AnyUprightMLSDCoreMLDetector.detectCandidates(
                    in: frame,
                    request: request,
                    context: analysisContext
                )
                analysisLock.lock()
                analysisState.detectedCandidates = mlsdCandidates
                analysisState.detectedPerspectiveTime = frameTime
                analysisLock.unlock()
                return
            } catch {
                // Keep local development usable before the ignored M-LSD model bundle is installed.
            }
        }

        guard let grayscaleImage = AnyUprightAnalysisImage.grayscaleImage(from: frame, maxDimension: 360, context: analysisContext) else {
            return
        }

        let size = AUSize(width: Double(grayscaleImage.width), height: Double(grayscaleImage.height))
        var candidates: [UprightDetectedCandidate] = []

        if request.includesVertical {
            let lines = AnyUprightLineDetection.detectLineSegments(
                in: grayscaleImage,
                options: AULineDetectionOptions(
                    orientation: .vertical,
                    edgeThreshold: 40.0,
                    voteThreshold: max(20, grayscaleImage.height / 5),
                    maxLines: candidateLimit(for: request)
                )
            )
            let lineCandidates = AnyUprightGeometry.lineCandidates(
                from: lines,
                orientation: .vertical,
                minimumLength: Double(grayscaleImage.height) * 0.25
            )

            candidates.append(contentsOf: AnyUprightUprightCandidates.detectedCandidates(
                from: Array(lineCandidates.prefix(candidateLimit(for: request))),
                orientation: .vertical,
                size: size
            ))
        }

        if request.includesHorizontal {
            let lines = AnyUprightLineDetection.detectLineSegments(
                in: grayscaleImage,
                options: AULineDetectionOptions(
                    orientation: .horizontal,
                    edgeThreshold: 40.0,
                    voteThreshold: max(20, grayscaleImage.width / 5),
                    maxLines: candidateLimit(for: request)
                )
            )
            let lineCandidates = AnyUprightGeometry.lineCandidates(
                from: lines,
                orientation: .horizontal,
                minimumLength: Double(grayscaleImage.width) * 0.25
            )

            candidates.append(contentsOf: AnyUprightUprightCandidates.detectedCandidates(
                from: Array(lineCandidates.prefix(candidateLimit(for: request))),
                orientation: .horizontal,
                size: size
            ))
        }

        analysisLock.lock()
        analysisState.detectedCandidates = Array(candidates.prefix(AnyUprightUprightCandidates.slotCount))
        analysisState.detectedPerspectiveTime = frameTime
        analysisLock.unlock()
    }

    func cleanupAnalysis() throws {
        analysisLock.lock()
        let request = analysisState.pendingAnalysisRequest
        let candidates = analysisState.detectedCandidates
        let time = parameterWriteTime(preferred: analysisState.requestedAnalysisTime, fallback: analysisState.detectedPerspectiveTime)
        analysisState.pendingAnalysisRequest = nil
        analysisLock.unlock()

        guard let request,
              let settingAPI = _apiManager.api(for: FxParameterSettingAPI_v5.self) as? FxParameterSettingAPI_v5 else {
            return
        }

        writeUprightCandidateSlots(
            candidates,
            correctionMode: request.correctionMode,
            controlMode: request.controlMode,
            settingAPI: settingAPI,
            time: time
        )

        if request.controlMode == .automatic {
            let selectedIndexes = AnyUprightUprightCandidates.automaticSelectedIndexes(
                from: candidates,
                correctionMode: request.correctionMode
            )
            let selectedCandidates = candidates.enumerated()
                .filter { selectedIndexes.contains($0.offset) }
                .map(\.element)
            let verticalLines = selectedDetectedImageLines(from: selectedCandidates, orientation: .vertical, correctionMode: request.correctionMode)
            let horizontalLines = selectedDetectedImageLines(from: selectedCandidates, orientation: .horizontal, correctionMode: request.correctionMode)
            writeUprightCorrection(
                verticalLines: verticalLines,
                horizontalLines: horizontalLines,
                correctionMode: request.correctionMode,
                settingAPI: settingAPI,
                time: time
            )
        }
    }

    private func applyGuided(_ correctionMode: UprightCorrectionMode, time: CMTime) {
        let guides = uprightGuideLines(at: time, paramAPI: parameterRetrievalAPI())
        let verticalLines = guides
            .filter { $0.orientation == .vertical && correctionMode.includesVertical }
            .map { imageLine(from: $0, size: AUSize(width: 1.0, height: 1.0)) }
        let horizontalLines = guides
            .filter { $0.orientation == .horizontal && correctionMode.includesHorizontal }
            .map { imageLine(from: $0, size: AUSize(width: 1.0, height: 1.0)) }

        applyReferences(verticalLines: verticalLines, horizontalLines: horizontalLines, correctionMode: correctionMode, time: time)
    }

    private func applySelected(_ correctionMode: UprightCorrectionMode, time: CMTime) {
        let candidates = uprightCandidateLines(at: time, paramAPI: parameterRetrievalAPI())
        let verticalLines = AnyUprightUprightCandidates.selectedImageLines(from: candidates, orientation: .vertical)
        let horizontalLines = AnyUprightUprightCandidates.selectedImageLines(from: candidates, orientation: .horizontal)

        applyReferences(verticalLines: verticalLines, horizontalLines: horizontalLines, correctionMode: correctionMode, time: time)
    }

    private func applyReferences(verticalLines: [AULineSegment], horizontalLines: [AULineSegment], correctionMode: UprightCorrectionMode, time: CMTime) {
        guard let settingAPI = _apiManager.api(for: FxParameterSettingAPI_v5.self) as? FxParameterSettingAPI_v5 else {
            return
        }

        writeUprightCorrection(
            verticalLines: verticalLines,
            horizontalLines: horizontalLines,
            correctionMode: correctionMode,
            settingAPI: settingAPI,
            time: time
        )
    }

    private func selectedDetectedImageLines(from candidates: [UprightDetectedCandidate], orientation: UprightGuideOrientation, correctionMode: UprightCorrectionMode) -> [AULineSegment] {
        let selected = candidates
            .filter { $0.orientation == orientation }
            .sorted {
                if $0.score == $1.score {
                    return $0.start.x < $1.start.x
                }
                return $0.score > $1.score
            }
            .prefix(2)

        guard (orientation == .vertical && correctionMode.includesVertical)
            || (orientation == .horizontal && correctionMode.includesHorizontal) else {
            return []
        }

        return selected.map {
            AULineSegment(
                start: AUPoint(x: $0.start.x, y: 1.0 - $0.start.y),
                end: AUPoint(x: $0.end.x, y: 1.0 - $0.end.y)
            )
        }
    }

    private func candidateLimit(for request: UprightAnalysisRequest) -> Int {
        AnyUprightUprightCandidates.slotLimit(isFullMode: request.correctionMode == .full)
    }

}
