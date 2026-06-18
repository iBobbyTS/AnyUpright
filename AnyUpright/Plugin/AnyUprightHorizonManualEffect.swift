//
//  AnyUprightHorizonManualEffect.swift
//  AnyUpright
//

import Foundation
import AppKit
import CoreImage
import IOSurface
import Vision

enum HorizonParam: UInt32 {
    case rotation = 100
    case fillFrame = 101
    case analyze = 102
}


@objc(AnyUprightHorizonManualPlugIn)
class AnyUprightHorizonManualPlugIn: AnyUprightWarpEffect, FxAnalyzer {
    private let analysisLock = NSLock()
    private let analysisContext = CIContext(options: nil)
    private var analysisState = HorizonAnalysisScratchState()

    override func addEffectParameters(_ paramAPI: FxParameterCreationAPI_v5) throws {
        paramAPI.addPushButton(
            withName: "Analyze Horizon",
            parameterID: HorizonParam.analyze.rawValue,
            selector: #selector(analyzeHorizon),
            parameterFlags: defaultFlags()
        )
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
        var result = AnyUprightParameterState(effectKind: AnyUprightEffectKind.horizon.rawValue)
        guard let paramAPI = parameterRetrievalAPI() else {
            return result
        }

        var rotation = 0.0
        var fillFrame = ObjCBool(false)

        paramAPI.getFloatValue(&rotation, fromParameter: HorizonParam.rotation.rawValue, at: renderTime)
        paramAPI.getBoolValue(&fillFrame, fromParameter: HorizonParam.fillFrame.rawValue, at: renderTime)

        result.rotationRadians = Float(rotation)
        result.fillFrame = fillFrame.boolValue ? 1 : 0
        return result
    }

    @objc private func analyzeHorizon() {
        analysisLock.lock()
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
        analysisState.detectedRotationRadians = nil
        analysisState.detectedRotationTime = analysisRange.start
        analysisLock.unlock()
    }

    func analyzeFrame(_ frame: FxImageTile, at frameTime: CMTime) throws {
        analysisLock.lock()
        let alreadyDetected = analysisState.detectedRotationRadians != nil
        analysisLock.unlock()

        if alreadyDetected {
            return
        }

        guard let image = AnyUprightAnalysisImage.ciImage(from: frame) else {
            return
        }

        let request = VNDetectHorizonRequest()
        let handler = VNImageRequestHandler(ciImage: image, options: [:])
        var rotationRadians: Double?

        do {
            try handler.perform([request])

            if let observation = request.results?.first as? VNHorizonObservation {
                let bounds = frame.imagePixelBounds
                let width = max(1, Int(bounds.right - bounds.left))
                let height = max(1, Int(bounds.top - bounds.bottom))
                let transform = observation.transform(forImageWidth: width, height: height)
                rotationRadians = atan2(Double(transform.b), Double(transform.a))
            }
        } catch {
            rotationRadians = nil
        }

        if rotationRadians == nil,
           let grayscaleImage = AnyUprightAnalysisImage.grayscaleImage(from: frame, maxDimension: 360, context: analysisContext) {
            let lines = AnyUprightLineDetection.detectLineSegments(
                in: grayscaleImage,
                options: AULineDetectionOptions(
                    orientation: .horizontal,
                    edgeThreshold: 40.0,
                    voteThreshold: max(20, grayscaleImage.width / 5),
                    maxLines: 40
                )
            )
            rotationRadians = AnyUprightGeometry.dominantHorizonCorrectionRadians(from: lines)
        }

        guard let rotationRadians else {
            return
        }

        analysisLock.lock()
        analysisState.detectedRotationRadians = rotationRadians
        analysisState.detectedRotationTime = frameTime
        analysisLock.unlock()
    }

    func cleanupAnalysis() throws {
        analysisLock.lock()
        let rotationRadians = analysisState.detectedRotationRadians
        let rotationTime = analysisState.detectedRotationTime
        let requestedTime = analysisState.requestedAnalysisTime
        analysisLock.unlock()

        let writeTime = parameterWriteTime(preferred: requestedTime, fallback: rotationTime)
        guard let settingAPI = _apiManager.api(for: FxParameterSettingAPI_v5.self) as? FxParameterSettingAPI_v5 else {
            return
        }

        guard let rotationRadians else {
            return
        }

        _ = settingAPI.setFloatValue(rotationRadians, toParameter: HorizonParam.rotation.rawValue, at: writeTime)
    }
}
