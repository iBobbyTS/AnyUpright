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
    private static let geoCalibAnalysisMaxDimension = 1920

    private let analysisLock = NSLock()
    private let analysisContext = CIContext(options: nil)
    private var analysisState = HorizonAnalysisScratchState()
    private var geoCalibCoreMLRouter: AUGeoCalibCoreMLNeuralInferenceRouter?
    private var geoCalibCoreMLLoadAttempted = false
    private var geoCalibRuntimeBundle: AUGeoCalibRuntimeBundle?
    private var geoCalibRuntimeLoadAttempted = false
    private var geoCalibMetalLibraryURL: URL?

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
        let requestedTime = analysisState.requestedAnalysisTime
        analysisLock.unlock()
        horizonAnalysisDebugLog("start requested=\(requestedTime)")

        guard let analysisAPI = _apiManager.api(for: FxAnalysisAPI.self) as? FxAnalysisAPI else {
            horizonAnalysisDebugLog("start missing FxAnalysisAPI")
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
        horizonAnalysisDebugLog("setup rangeStart=\(analysisRange.start) duration=\(analysisRange.duration) frameDuration=\(frameDuration)")
    }

    func analyzeFrame(_ frame: FxImageTile, at frameTime: CMTime) throws {
        analysisLock.lock()
        let alreadyDetected = analysisState.detectedRotationRadians != nil
        analysisLock.unlock()

        if alreadyDetected {
            horizonAnalysisDebugLog("analyze skipped alreadyDetected frameTime=\(frameTime)")
            return
        }

        var rotationRadians: Double?
        let bounds = frame.imagePixelBounds
        horizonAnalysisDebugLog("analyze begin frameTime=\(frameTime) bounds=\(bounds)")

        switch analyzeGeoCalibHorizon(frame) {
        case .accepted(let correctionRadians):
            rotationRadians = correctionRadians
            horizonAnalysisDebugLog(String(format: "analyze geocalib accepted correctionDeg=%.6f", correctionRadians * 180 / Double.pi))
        case .rejected:
            horizonAnalysisDebugLog("analyze geocalib rejected")
            return
        case .unavailable:
            horizonAnalysisDebugLog("analyze geocalib unavailable; trying fallback detectors")
            guard let image = AnyUprightAnalysisImage.ciImage(from: frame) else {
                horizonAnalysisDebugLog("analyze fallback no CIImage")
                return
            }

            let request = VNDetectHorizonRequest()
            let handler = VNImageRequestHandler(ciImage: image, options: [:])

            do {
                try handler.perform([request])

                if let observation = request.results?.first as? VNHorizonObservation {
                    let bounds = frame.imagePixelBounds
                    let width = max(1, Int(bounds.right - bounds.left))
                    let height = max(1, Int(bounds.top - bounds.bottom))
                    let transform = observation.transform(forImageWidth: width, height: height)
                    rotationRadians = atan2(Double(transform.b), Double(transform.a))
                    horizonAnalysisDebugLog(String(format: "analyze vision fallback correctionDeg=%.6f", (rotationRadians ?? 0.0) * 180 / Double.pi))
                }
            } catch {
                horizonAnalysisDebugLog("analyze vision fallback error=\(String(describing: error))")
                rotationRadians = nil
            }
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
            horizonAnalysisDebugLog(String(format: "analyze hough fallback lines=%d correctionDeg=%.6f", lines.count, (rotationRadians ?? 0.0) * 180 / Double.pi))
        }

        guard let rotationRadians else {
            horizonAnalysisDebugLog("analyze no rotation detected")
            return
        }

        analysisLock.lock()
        analysisState.detectedRotationRadians = rotationRadians
        analysisState.detectedRotationTime = frameTime
        analysisLock.unlock()
        horizonAnalysisDebugLog(String(format: "analyze stored correctionDeg=%.6f frameTime=%@", rotationRadians * 180 / Double.pi, String(describing: frameTime)))
    }

    func cleanupAnalysis() throws {
        analysisLock.lock()
        let rotationRadians = analysisState.detectedRotationRadians
        let rotationTime = analysisState.detectedRotationTime
        let requestedTime = analysisState.requestedAnalysisTime
        analysisLock.unlock()

        let writeTime = parameterWriteTime(preferred: requestedTime, fallback: rotationTime)
        guard let settingAPI = _apiManager.api(for: FxParameterSettingAPI_v5.self) as? FxParameterSettingAPI_v5 else {
            horizonAnalysisDebugLog("cleanup missing FxParameterSettingAPI")
            return
        }

        guard let rotationRadians else {
            horizonAnalysisDebugLog("cleanup no rotation requestedTime=\(requestedTime) rotationTime=\(rotationTime)")
            return
        }

        let result = settingAPI.setFloatValue(rotationRadians, toParameter: HorizonParam.rotation.rawValue, at: writeTime)
        horizonAnalysisDebugLog(String(format: "cleanup wrote correctionDeg=%.6f writeTime=%@ result=%@", rotationRadians * 180 / Double.pi, String(describing: writeTime), String(describing: result)))
    }

    private enum GeoCalibHorizonAnalysisOutcome {
        case accepted(Double)
        case rejected
        case unavailable
    }

    private func analyzeGeoCalibHorizon(_ frame: FxImageTile) -> GeoCalibHorizonAnalysisOutcome {
        guard let rgbImage = AnyUprightAnalysisImage.rgbFloatImage(
            from: frame,
            maxDimension: Self.geoCalibAnalysisMaxDimension,
            context: analysisContext
        ) else {
            horizonAnalysisDebugLog("geocalib unavailable: unable to render RGB frame")
            return .unavailable
        }
        horizonAnalysisDebugLog("geocalib input rgb=\(rgbImage.width)x\(rgbImage.height)")

        do {
            let preprocessed = try AUGeoCalibImagePreprocessor.preprocessRGB(
                rgbImage.pixelsNCHW,
                width: rgbImage.width,
                height: rgbImage.height
            )
            var verifiers: [AUGeoCalibHorizonVerifierEstimate] = []
            if let grayscaleImage = AnyUprightAnalysisImage.grayscaleImage(from: frame, maxDimension: 640, context: analysisContext) {
                verifiers.append(AUGeoCalibHorizonVerifiers.axisHough(in: grayscaleImage))
                verifiers.append(AUGeoCalibHorizonVerifiers.gradientAxis(in: grayscaleImage))
            }

            let result: AUGeoCalibHorizonDetectionResult
            if let coreMLRouter = loadGeoCalibCoreMLRouter() {
                do {
                    horizonAnalysisDebugLog("geocalib coreml shape=\(preprocessed.inputShape)")
                    let neuralOutput = try coreMLRouter.run(
                        inputRGB: preprocessed.inputRGBNCHW,
                        inputShape: preprocessed.inputShape
                    )
                    result = try AUGeoCalibHorizonDetector.detect(
                        preprocessedImage: preprocessed,
                        neuralOutput: neuralOutput,
                        verifierEstimates: verifiers
                    )
                } catch {
                    horizonAnalysisDebugLog("geocalib coreml failed; trying metal fallback error=\(String(describing: error))")
                    result = try analyzeGeoCalibHorizonWithMetalFallback(
                        preprocessed: preprocessed,
                        verifiers: verifiers
                    )
                }
            } else {
                result = try analyzeGeoCalibHorizonWithMetalFallback(
                    preprocessed: preprocessed,
                    verifiers: verifiers
                )
            }

            let verifierSummary = result.verifierDiffs.map { diff -> String in
                if let radians = diff.differenceRadians {
                    return "\(diff.name)=\(radians * 180 / Double.pi)deg"
                }
                return "\(diff.name)=nil"
            }.joined(separator: ", ")
            horizonAnalysisDebugLog(String(
                format: "geocalib result accepted=%@ rollDeg=%.6f correctionDeg=%.6f uncDeg=%.6f reasons=%@ verifiers=%@",
                result.accepted ? "true" : "false",
                result.rollRadians * 180 / Double.pi,
                result.correctionRadians * 180 / Double.pi,
                result.rollUncertaintyRadians * 180 / Double.pi,
                result.rejectionReasons.joined(separator: ","),
                verifierSummary
            ))
            return result.accepted ? .accepted(result.correctionRadians) : .rejected
        } catch {
            horizonAnalysisDebugLog("geocalib unavailable: error=\(String(describing: error))")
            return .unavailable
        }
    }

    private func analyzeGeoCalibHorizonWithMetalFallback(
        preprocessed: AUGeoCalibPreprocessedImage,
        verifiers: [AUGeoCalibHorizonVerifierEstimate]
    ) throws -> AUGeoCalibHorizonDetectionResult {
        guard let runtimeBundle = loadGeoCalibRuntimeBundle() else {
            throw AUGeoCalibCoreMLNeuralError.invalidModel("runtime bundle failed to load")
        }
        guard let metalLibraryURL = geoCalibMetalLibraryURL else {
            throw AUGeoCalibCoreMLNeuralError.invalidModel("missing metallib URL")
        }
        horizonAnalysisDebugLog("geocalib metal fallback shape=\(preprocessed.inputShape) metal=\(metalLibraryURL.path)")
        return try AUGeoCalibHorizonDetector.detect(
            preprocessedImage: preprocessed,
            runtimeBundle: runtimeBundle,
            metalLibraryURL: metalLibraryURL,
            verifierEstimates: verifiers
        )
    }

    private func loadGeoCalibCoreMLRouter() -> AUGeoCalibCoreMLNeuralInferenceRouter? {
        if geoCalibCoreMLLoadAttempted {
            return geoCalibCoreMLRouter
        }
        geoCalibCoreMLLoadAttempted = true

        let bundle = Bundle(for: AnyUprightHorizonManualPlugIn.self)
        guard let resourceURL = bundle.resourceURL else {
            horizonAnalysisDebugLog("geocalib coreml load missing resourceURL bundle=\(bundle.bundlePath)")
            return nil
        }
        let modelURLs = [
            resourceURL.appendingPathComponent("neural_forward_416x320.mlmodelc", isDirectory: true),
            resourceURL.appendingPathComponent("neural_forward_320x416.mlmodelc", isDirectory: true),
        ]
        for modelURL in modelURLs where !FileManager.default.fileExists(atPath: modelURL.path) {
            horizonAnalysisDebugLog("geocalib coreml load missing model path=\(modelURL.path)")
            return nil
        }

        do {
            let router = try AUGeoCalibCoreMLNeuralInferenceRouter(modelURLs: modelURLs)
            try router.warmUp()
            geoCalibCoreMLRouter = router
            horizonAnalysisDebugLog("geocalib coreml load ok resourceURL=\(resourceURL.path)")
        } catch {
            horizonAnalysisDebugLog("geocalib coreml load failed resourceURL=\(resourceURL.path) error=\(String(describing: error))")
            geoCalibCoreMLRouter = nil
        }
        return geoCalibCoreMLRouter
    }

    private func loadGeoCalibRuntimeBundle() -> AUGeoCalibRuntimeBundle? {
        if geoCalibRuntimeLoadAttempted {
            return geoCalibRuntimeBundle
        }
        geoCalibRuntimeLoadAttempted = true

        let bundle = Bundle(for: AnyUprightHorizonManualPlugIn.self)
        guard let resourceURL = bundle.resourceURL else {
            horizonAnalysisDebugLog("geocalib load missing resourceURL bundle=\(bundle.bundlePath)")
            return nil
        }
        let metalURL = resourceURL.appendingPathComponent("default.metallib")
        guard FileManager.default.fileExists(atPath: metalURL.path) else {
            horizonAnalysisDebugLog("geocalib load missing metallib path=\(metalURL.path)")
            return nil
        }

        geoCalibMetalLibraryURL = metalURL
        do {
            geoCalibRuntimeBundle = try AUGeoCalibRuntimeBundle(rootURL: resourceURL)
            horizonAnalysisDebugLog("geocalib load ok resourceURL=\(resourceURL.path)")
        } catch {
            horizonAnalysisDebugLog("geocalib load failed resourceURL=\(resourceURL.path) error=\(String(describing: error))")
            geoCalibRuntimeBundle = nil
        }
        return geoCalibRuntimeBundle
    }

    private func horizonAnalysisDebugLog(_ message: String) {
        #if DEBUG
        guard FileManager.default.fileExists(atPath: "/tmp/AnyUprightGeoCalib.debug") else {
            return
        }
        let logPath = "/tmp/anyupright-geocalib-debug.log"
        let timestamp = String(format: "%.3f", Date().timeIntervalSince1970)
        guard let data = "[\(timestamp)] \(message)\n".data(using: .utf8) else {
            return
        }

        if FileManager.default.fileExists(atPath: logPath),
           let handle = try? FileHandle(forWritingTo: URL(fileURLWithPath: logPath)) {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
            try? handle.close()
        } else {
            try? data.write(to: URL(fileURLWithPath: logPath))
        }
        #else
        _ = message
        #endif
    }
}
