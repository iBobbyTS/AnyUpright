//
//  AnyUprightHorizonEffect.swift
//  AnyUpright
//

import Foundation
import AppKit
import CoreImage
import Dispatch
import IOSurface
import Vision

enum HorizonParam: UInt32 {
    case rotation = 100
    case fillFrame = 101
    case analyze = 102
}


@objc(AnyUprightHorizonPlugIn)
class AnyUprightHorizonPlugIn: AnyUprightWarpEffect, FxAnalyzer {
    private static let geoCalibAnalysisMaxDimension = 1920
    private static let geoCalibVerifierMaxDimension = 640
    private static let geoCalibCoreMLModelShapes = AUGeoCalibInputShapeSpec.production
    private static let geoCalibLogLock = NSLock()

    private let analysisLock = NSLock()
    private let analysisContext = CIContext(options: nil)
    private var analysisState = HorizonAnalysisScratchState()
    private var geoCalibCoreMLConfigurationAttempted = false
    private var geoCalibCoreMLConfigurationAvailable = false

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
        prepareGeoCalibCoreMLCacheForPluginAdd()
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
        let startNanos = Self.nowNanos()
        analysisLock.lock()
        analysisState.requestedAnalysisTime = currentParameterTime()
        analysisState.analysisStartNanos = startNanos
        let requestedTime = analysisState.requestedAnalysisTime
        analysisLock.unlock()
        horizonAnalysisDebugLog("start requested=\(requestedTime)")

        guard let analysisAPI = _apiManager.api(for: FxAnalysisAPI.self) as? FxAnalysisAPI else {
            horizonAnalysisDebugLog("start missing FxAnalysisAPI")
            return
        }

        try? analysisAPI.startForwardAnalysis(kFxAnalysisLocation_CPU)
        horizonAnalysisDebugLog(String(format: "startForwardAnalysis returned elapsed_ms=%.3f", Self.elapsedMilliseconds(since: startNanos)))
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
        let startNanos = analysisState.analysisStartNanos
        analysisLock.unlock()
        let elapsed = startNanos.map(Self.elapsedMilliseconds) ?? 0.0
        horizonAnalysisDebugLog(String(format: "setup rangeStart=%@ duration=%@ frameDuration=%@ since_start_ms=%.3f", String(describing: analysisRange.start), String(describing: analysisRange.duration), String(describing: frameDuration), elapsed))
    }

    func analyzeFrame(_ frame: FxImageTile, at frameTime: CMTime) throws {
        let frameStartNanos = Self.nowNanos()
        analysisLock.lock()
        let alreadyDetected = analysisState.detectedRotationRadians != nil
        let analysisStartNanos = analysisState.analysisStartNanos
        analysisLock.unlock()

        if alreadyDetected {
            horizonAnalysisDebugLog("analyze skipped alreadyDetected frameTime=\(frameTime)")
            return
        }

        var rotationRadians: Double?
        let bounds = frame.imagePixelBounds
        let sinceStart = analysisStartNanos.map(Self.elapsedMilliseconds) ?? 0.0
        horizonAnalysisDebugLog(String(format: "analyze begin frameTime=%@ bounds=%@ since_start_ms=%.3f", String(describing: frameTime), String(describing: bounds), sinceStart))

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
        horizonAnalysisDebugLog(String(
            format: "analyze stored correctionDeg=%.6f frameTime=%@ frame_ms=%.3f since_start_ms=%.3f",
            rotationRadians * 180 / Double.pi,
            String(describing: frameTime),
            Self.elapsedMilliseconds(since: frameStartNanos),
            analysisStartNanos.map(Self.elapsedMilliseconds) ?? 0.0
        ))
    }

    func cleanupAnalysis() throws {
        analysisLock.lock()
        let rotationRadians = analysisState.detectedRotationRadians
        let rotationTime = analysisState.detectedRotationTime
        let requestedTime = analysisState.requestedAnalysisTime
        let analysisStartNanos = analysisState.analysisStartNanos
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
        horizonAnalysisDebugLog(String(
            format: "cleanup wrote correctionDeg=%.6f writeTime=%@ result=%@ since_start_ms=%.3f",
            rotationRadians * 180 / Double.pi,
            String(describing: writeTime),
            String(describing: result),
            analysisStartNanos.map(Self.elapsedMilliseconds) ?? 0.0
        ))
    }

    private enum GeoCalibHorizonAnalysisOutcome {
        case accepted(Double)
        case rejected
        case unavailable
    }

    private struct GeoCalibVerifierRun {
        var estimates: [AUGeoCalibHorizonVerifierEstimate]
        var grayscaleMilliseconds: Double
        var axisHoughMilliseconds: Double?
        var gradientAxisMilliseconds: Double?
        var totalMilliseconds: Double
    }

    private struct GeoCalibPreprocessRun {
        var preprocessed: AUGeoCalibPreprocessedImage
        var source: String
        var shapeLabel: String
        var inputWidth: Int
        var inputHeight: Int
        var renderMilliseconds: Double?
        var preprocessMilliseconds: Double
    }

    private struct GeoCalibVerifierWorkerResult {
        var index: Int
        var estimate: AUGeoCalibHorizonVerifierEstimate
        var milliseconds: Double
    }

    private func runGeoCalibVerifiers(_ frame: FxImageTile) -> GeoCalibVerifierRun? {
        let totalStart = Self.nowNanos()
        let grayscaleStart = Self.nowNanos()
        guard let grayscaleImage = AnyUprightAnalysisImage.grayscaleImage(
            from: frame,
            maxDimension: Self.geoCalibVerifierMaxDimension,
            context: analysisContext
        ) else {
            return nil
        }
        let grayscaleMilliseconds = Self.elapsedMilliseconds(since: grayscaleStart)

        var workerResults: [GeoCalibVerifierWorkerResult] = []
        let resultLock = NSLock()
        DispatchQueue.concurrentPerform(iterations: 2) { index in
            let start = Self.nowNanos()
            let estimate: AUGeoCalibHorizonVerifierEstimate
            if index == 0 {
                estimate = AUGeoCalibHorizonVerifiers.axisHough(in: grayscaleImage)
            } else {
                estimate = AUGeoCalibHorizonVerifiers.gradientAxis(in: grayscaleImage)
            }
            let milliseconds = Self.elapsedMilliseconds(since: start)
            resultLock.lock()
            workerResults.append(GeoCalibVerifierWorkerResult(index: index, estimate: estimate, milliseconds: milliseconds))
            resultLock.unlock()
        }

        workerResults.sort { $0.index < $1.index }
        let estimates = workerResults.map(\.estimate)
        return GeoCalibVerifierRun(
            estimates: estimates,
            grayscaleMilliseconds: grayscaleMilliseconds,
            axisHoughMilliseconds: workerResults.first(where: { $0.index == 0 })?.milliseconds,
            gradientAxisMilliseconds: workerResults.first(where: { $0.index == 1 })?.milliseconds,
            totalMilliseconds: Self.elapsedMilliseconds(since: totalStart)
        )
    }

    private func analyzeGeoCalibHorizon(_ frame: FxImageTile) -> GeoCalibHorizonAnalysisOutcome {
        let totalStart = Self.nowNanos()

        do {
            let preprocessRun = try preprocessGeoCalibInput(frame)
            let preprocessed = preprocessRun.preprocessed
            horizonAnalysisDebugLog(String(
                format: "geocalib input source=%@ input=%dx%d selected_ratio=%@ shape=%@ render_ms=%@ preprocess_ms=%.3f",
                preprocessRun.source,
                preprocessRun.inputWidth,
                preprocessRun.inputHeight,
                preprocessRun.shapeLabel,
                String(describing: preprocessed.inputShape),
                Self.formatMilliseconds(preprocessRun.renderMilliseconds),
                preprocessRun.preprocessMilliseconds
            ))

            let source = "coreml"
            var coreMLRun: AUGeoCalibCoreMLRunResult?
            var optimizerGateMilliseconds: Double?
            guard configureGeoCalibCoreMLCacheIfAvailable() else {
                horizonAnalysisDebugLog("geocalib coreml unavailable: no configured model resources")
                return .unavailable
            }
            markGeoCalibCoreMLAnalysisStarted(inputShape: preprocessed.inputShape)
            horizonAnalysisDebugLog("geocalib coreml shape=\(preprocessed.inputShape)")
            let run = try AUGeoCalibCoreMLSharedCache.shared.run(
                inputRGB: preprocessed.inputRGBNCHW,
                inputShape: preprocessed.inputShape,
                logger: Self.horizonAnalysisDebugLog
            )
            coreMLRun = run
            let optimizerStart = Self.nowNanos()
            var result = try AUGeoCalibHorizonDetector.detect(
                preprocessedImage: preprocessed,
                neuralOutput: run.output,
                verifierEstimates: []
            )
            optimizerGateMilliseconds = Self.elapsedMilliseconds(since: optimizerStart)

            var verifierRun: GeoCalibVerifierRun?
            var verifierGateMilliseconds: Double?
            if result.accepted {
                verifierRun = runGeoCalibVerifiers(frame)
                if let verifierRun {
                    let gateStart = Self.nowNanos()
                    result = AUGeoCalibHorizonDetector.applyVerifierGate(
                        to: result,
                        verifierEstimates: verifierRun.estimates
                    )
                    verifierGateMilliseconds = Self.elapsedMilliseconds(since: gateStart)
                } else {
                    horizonAnalysisDebugLog("geocalib verifier skipped: unable to render grayscale frame")
                }
            } else {
                horizonAnalysisDebugLog("geocalib verifier skipped: base gate rejected reasons=\(result.rejectionReasons.joined(separator: ","))")
            }

            let verifierSummary = result.verifierDiffs.map { diff -> String in
                if let radians = diff.differenceRadians {
                    return "\(diff.name)=\(radians * 180 / Double.pi)deg"
                }
                return "\(diff.name)=nil"
            }.joined(separator: ", ")
            let timingParts = [
                "source=\(source)",
                "input_source=\(preprocessRun.source)",
                "input_size=\(preprocessRun.inputWidth)x\(preprocessRun.inputHeight)",
                "render_ms=\(Self.formatMilliseconds(preprocessRun.renderMilliseconds))",
                String(format: "preprocess_ms=%.3f", preprocessRun.preprocessMilliseconds),
                "coreml_cache_hit=\(coreMLRun?.cacheHit == true ? "true" : (coreMLRun == nil ? "nil" : "false"))",
                "coreml_load_ms=\(Self.formatMilliseconds(coreMLRun?.loadMilliseconds))",
                "coreml_predict_ms=\(Self.formatMilliseconds(coreMLRun?.predictionMilliseconds))",
                "coreml_total_ms=\(Self.formatMilliseconds(coreMLRun?.totalMilliseconds))",
                "optimizer_gate_ms=\(Self.formatMilliseconds(optimizerGateMilliseconds))",
                "verifier_total_ms=\(Self.formatMilliseconds(verifierRun?.totalMilliseconds))",
                "verifier_grayscale_ms=\(Self.formatMilliseconds(verifierRun?.grayscaleMilliseconds))",
                "axis_hough_ms=\(Self.formatMilliseconds(verifierRun?.axisHoughMilliseconds))",
                "gradient_axis_ms=\(Self.formatMilliseconds(verifierRun?.gradientAxisMilliseconds))",
                "verifier_gate_ms=\(Self.formatMilliseconds(verifierGateMilliseconds))",
                String(format: "total_ms=%.3f", Self.elapsedMilliseconds(since: totalStart)),
            ]
            horizonAnalysisDebugLog("geocalib timing \(timingParts.joined(separator: " "))")
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

    private func preprocessGeoCalibInput(_ frame: FxImageTile) throws -> GeoCalibPreprocessRun {
        let bounds = frame.imagePixelBounds
        let sourceWidth = max(1, Int(bounds.right - bounds.left))
        let sourceHeight = max(1, Int(bounds.top - bounds.bottom))
        let shapeSpec = try Self.geoCalibCoreMLModelShape(forWidth: sourceWidth, height: sourceHeight)

        let directStart = Self.nowNanos()
        do {
            let preprocessed = try AUGeoCalibDirectImagePreprocessor.preprocessFrame(
                frame,
                targetInputShape: shapeSpec.inputShape
            )
            return GeoCalibPreprocessRun(
                preprocessed: preprocessed,
                source: "metal_direct",
                shapeLabel: shapeSpec.label,
                inputWidth: sourceWidth,
                inputHeight: sourceHeight,
                renderMilliseconds: nil,
                preprocessMilliseconds: Self.elapsedMilliseconds(since: directStart)
            )
        } catch {
            horizonAnalysisDebugLog("geocalib direct preprocess failed; falling back to CI/CPU error=\(String(describing: error))")
        }

        let renderStart = Self.nowNanos()
        guard let rgbImage = AnyUprightAnalysisImage.rgbFloatImage(
            from: frame,
            maxDimension: Self.geoCalibAnalysisMaxDimension,
            context: analysisContext
        ) else {
            throw AUGeoCalibHorizonDetectorError.invalidImage("unable to render RGB frame")
        }
        let renderMilliseconds = Self.elapsedMilliseconds(since: renderStart)

        let preprocessStart = Self.nowNanos()
        let preprocessed = try AUGeoCalibImagePreprocessor.preprocessRGB(
            rgbImage.pixelsNCHW,
            width: rgbImage.width,
            height: rgbImage.height,
            targetInputShape: shapeSpec.inputShape
        )
        return GeoCalibPreprocessRun(
            preprocessed: preprocessed,
            source: "ci_cpu_fallback",
            shapeLabel: shapeSpec.label,
            inputWidth: rgbImage.width,
            inputHeight: rgbImage.height,
            renderMilliseconds: renderMilliseconds,
            preprocessMilliseconds: Self.elapsedMilliseconds(since: preprocessStart)
        )
    }

    private func prepareGeoCalibCoreMLCacheForPluginAdd() {
        guard configureGeoCalibCoreMLCacheIfAvailable() else {
            return
        }
        let prewarmShape = currentInputShapeForGeoCalibPrewarm()
        AUGeoCalibCoreMLSharedCache.shared.markPluginAdded(
            prewarmShape: prewarmShape?.spec.inputShape,
            logger: Self.horizonAnalysisDebugLog
        )
        if let prewarmShape {
            horizonAnalysisDebugLog("geocalib coreml prewarm selected input_size=\(prewarmShape.width)x\(prewarmShape.height) ratio=\(prewarmShape.spec.label) shape=\(prewarmShape.spec.inputShape)")
        } else {
            horizonAnalysisDebugLog("geocalib coreml prewarm skipped: input size unavailable at plugin add")
        }
    }

    private func markGeoCalibCoreMLAnalysisStarted(inputShape: [Int]) {
        guard configureGeoCalibCoreMLCacheIfAvailable() else {
            return
        }
        AUGeoCalibCoreMLSharedCache.shared.markAnalysisStarted(inputShape: inputShape, logger: Self.horizonAnalysisDebugLog)
    }

    private func configureGeoCalibCoreMLCacheIfAvailable() -> Bool {
        if geoCalibCoreMLConfigurationAttempted {
            return geoCalibCoreMLConfigurationAvailable
        }
        geoCalibCoreMLConfigurationAttempted = true

        let bundle = Bundle(for: AnyUprightHorizonPlugIn.self)
        guard let resourceURL = bundle.resourceURL else {
            horizonAnalysisDebugLog("geocalib coreml configure missing resourceURL bundle=\(bundle.bundlePath)")
            return false
        }
        let modelSpecs = Self.geoCalibCoreMLModelShapes.map { shape in
            AUGeoCalibCoreMLModelSpec(
                inputShape: shape.inputShape,
                modelURL: resourceURL.appendingPathComponent(shape.modelResourceName, isDirectory: true)
            )
        }
        for spec in modelSpecs where !FileManager.default.fileExists(atPath: spec.modelURL.path) {
            horizonAnalysisDebugLog("geocalib coreml configure missing model path=\(spec.modelURL.path)")
            return false
        }

        do {
            try AUGeoCalibCoreMLSharedCache.shared.configure(modelSpecs: modelSpecs)
            geoCalibCoreMLConfigurationAvailable = true
            horizonAnalysisDebugLog("geocalib coreml configure ok resourceURL=\(resourceURL.path)")
        } catch {
            horizonAnalysisDebugLog("geocalib coreml configure failed resourceURL=\(resourceURL.path) error=\(String(describing: error))")
            geoCalibCoreMLConfigurationAvailable = false
        }
        return geoCalibCoreMLConfigurationAvailable
    }

    private struct GeoCalibPrewarmSelection {
        var width: Int
        var height: Int
        var spec: AUGeoCalibInputShapeSpec
    }

    private func currentInputShapeForGeoCalibPrewarm() -> GeoCalibPrewarmSelection? {
        guard let oscAPI = _apiManager.api(for: FxOnScreenControlAPI_v4.self) as? FxOnScreenControlAPI_v4 else {
            return nil
        }

        var width: UInt = 0
        var height: UInt = 0
        var pixelAspectRatio = 1.0
        oscAPI.inputWidth(&width, height: &height, pixelAspectRatio: &pixelAspectRatio)
        if width == 0 || height == 0 {
            oscAPI.objectWidth(&width, height: &height, pixelAspectRatio: &pixelAspectRatio)
        }
        guard width > 0, height > 0,
              let spec = try? Self.geoCalibCoreMLModelShape(forWidth: Int(width), height: Int(height)) else {
            return nil
        }
        return GeoCalibPrewarmSelection(width: Int(width), height: Int(height), spec: spec)
    }

    private static func geoCalibCoreMLModelShape(forWidth width: Int, height: Int) throws -> AUGeoCalibInputShapeSpec {
        try AUGeoCalibInputShapeSpec.closest(toWidth: width, height: height, in: geoCalibCoreMLModelShapes)
    }

    private static func nowNanos() -> UInt64 {
        DispatchTime.now().uptimeNanoseconds
    }

    private static func elapsedMilliseconds(since startNanos: UInt64) -> Double {
        Double(nowNanos() - startNanos) / 1_000_000.0
    }

    private static func formatMilliseconds(_ value: Double?) -> String {
        guard let value else {
            return "nil"
        }
        return String(format: "%.3f", value)
    }

    private func horizonAnalysisDebugLog(_ message: String) {
        Self.horizonAnalysisDebugLog(message)
    }

    private static func horizonAnalysisDebugLog(_ message: String) {
        guard FileManager.default.fileExists(atPath: "/tmp/AnyUprightGeoCalib.debug") else {
            return
        }
        let logPath = "/tmp/anyupright-geocalib-debug.log"
        let timestamp = String(format: "%.3f", Date().timeIntervalSince1970)
        guard let data = "[\(timestamp)] \(message)\n".data(using: .utf8) else {
            return
        }

        geoCalibLogLock.lock()
        defer { geoCalibLogLock.unlock() }

        if FileManager.default.fileExists(atPath: logPath),
           let handle = try? FileHandle(forWritingTo: URL(fileURLWithPath: logPath)) {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
            try? handle.close()
        } else {
            try? data.write(to: URL(fileURLWithPath: logPath))
        }
    }
}
