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
    private static let geoCalibVerifierMaxDimension = 640
    private static let geoCalibCoreMLModelShapes = AUGeoCalibInputShapeSpec.production
    private let analysisContext = CIContext(options: nil)
    private let analysisTransaction = AUFxAnalysisTransaction<Void, Double>()
    private var geoCalibCoreMLConfigurationAttempted = false
    private var geoCalibCoreMLConfigurationAvailable = false

    override func addEffectParameters(_ paramAPI: FxParameterCreationAPI_v5) throws {
        addAnalysisDisplayStatusParameter(paramAPI)
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
        let startNanos = AUMonotonicClock.nowNanos()
        guard let analysisAPI = _apiManager.api(for: FxAnalysisAPI.self) as? FxAnalysisAPI else {
            horizonAnalysisDebugLog("start missing FxAnalysisAPI")
            return
        }
        let requestedTimelineTime = currentParameterTime()
        do {
            let disposition = try analysisTransaction.start(
                request: (),
                requestedTimelineTime: requestedTimelineTime,
                analysisStartNanos: startNanos,
                hostIsBusy: {
                    let state = analysisAPI.analysisStateForEffect()
                    return state == kFxAnalysisState_AnalysisRequested || state == kFxAnalysisState_AnalysisStarted
                },
                willStart: {
                    self.setAnalysisDisplayStatus(.modelLoading, at: requestedTimelineTime)
                },
                startForwardAnalysis: {
                    horizonAnalysisDebugLog("start requested_timeline=\(requestedTimelineTime)")
                    try analysisAPI.startForwardAnalysis(kFxAnalysisLocation_CPU)
                }
            )
            switch disposition {
            case .started:
                horizonAnalysisDebugLog(String(format: "startForwardAnalysis returned elapsed_ms=%.3f", AUMonotonicClock.elapsedMilliseconds(since: startNanos)))
            case .localBusy:
                horizonAnalysisDebugLog("start ignored busy local=true")
            case .hostBusy:
                horizonAnalysisDebugLog("start ignored busy host=true")
            case .invalidTimelineTime:
                horizonAnalysisDebugLog("start invalid timeline time=\(requestedTimelineTime)")
            }
        } catch {
            setAnalysisDisplayStatus(.none, at: requestedTimelineTime)
            horizonAnalysisDebugLog("startForwardAnalysis error=\(String(describing: error))")
        }
    }

    func desiredAnalysisTimeRange(_ desiredRange: UnsafeMutablePointer<CMTimeRange>, forInputWith inputTimeRange: CMTimeRange) throws {
        let requestedTimelineTime = analysisTransaction.requestedTimelineTime ?? currentParameterTime()
        guard let timingAPI = _apiManager.api(for: FxTimingAPI_v4.self) as? FxTimingAPI_v4 else {
            analysisTransaction.cancelCurrentRequest()
            setAnalysisDisplayStatus(.none, at: requestedTimelineTime)
            throw horizonAnalysisError("FxTimingAPI_v4 is unavailable")
        }
        do {
            let details = try analysisTransaction.desiredRange(
                within: inputTimeRange,
                inputTimeFromTimeline: { timelineTime in
                    var inputTime = CMTime.invalid
                    timingAPI.inputTime(&inputTime, fromTimelineTime: timelineTime)
                    return inputTime
                },
                sampleDuration: {
                    var duration = CMTime.invalid
                    timingAPI.sampleDuration(&duration)
                    return duration
                }
            )
            if details.usedFallbackSampleDuration {
                horizonAnalysisDebugLog("desired range invalid sample_duration=\(details.sampleDuration); using 0.05s fallback")
            }
            desiredRange.pointee = details.range
            horizonAnalysisDebugLog("desired range timeline=\(details.requestedTimelineTime) input=\(details.inputTime) sample_duration=\(details.sampleDuration) start=\(details.range.start) duration=\(details.range.duration)")
        } catch {
            setAnalysisDisplayStatus(.none, at: requestedTimelineTime)
            throw horizonAnalysisError(String(describing: error))
        }
    }

    func setupAnalysis(for analysisRange: CMTimeRange, frameDuration: CMTime) throws {
        _ = analysisTransaction.setupAnalysis(range: analysisRange)
        let elapsed = analysisTransaction.analysisStartNanos
            .map { AUMonotonicClock.elapsedMilliseconds(since: $0) } ?? 0.0
        horizonAnalysisDebugLog(String(format: "setup rangeStart=%@ duration=%@ frameDuration=%@ since_start_ms=%.3f", String(describing: analysisRange.start), String(describing: analysisRange.duration), String(describing: frameDuration), elapsed))
    }

    func analyzeFrame(_ frame: FxImageTile, at frameTime: CMTime) throws {
        let frameStartNanos = AUMonotonicClock.nowNanos()
        let bounds = frame.imagePixelBounds
        guard let claim = analysisTransaction.claimFrame(
            hasIOSurface: frame.ioSurface != nil,
            hasNonEmptyPixelBounds: bounds.right > bounds.left && bounds.top > bounds.bottom
        ) else {
            let structurallyUsable = frame.ioSurface != nil && bounds.right > bounds.left && bounds.top > bounds.bottom
            let receivedFrameCount = analysisTransaction.receivedFrameCount
            horizonAnalysisDebugLog("analyze skipped frameTime=\(frameTime) usable=\(structurallyUsable) callback=\(receivedFrameCount)")
            return
        }

        var rotationRadians: Double?
        let sinceStart = AUMonotonicClock.elapsedMilliseconds(since: claim.analysisStartNanos)
        horizonAnalysisDebugLog(String(format: "analyze begin frameTime=%@ bounds=%@ since_start_ms=%.3f", String(describing: frameTime), String(describing: bounds), sinceStart))

        switch analyzeGeoCalibHorizon(frame, requestedTimelineTime: claim.requestedTimelineTime) {
        case .accepted(let correctionRadians):
            rotationRadians = correctionRadians
            horizonAnalysisDebugLog(String(format: "analyze geocalib accepted correctionDeg=%.6f", correctionRadians * 180 / Double.pi))
        case .rejected:
            analysisTransaction.complete(
                token: claim.token,
                outcome: .completedWithoutResult,
                inputFrameTime: frameTime,
                onCompleted: {
                    self.setAnalysisDisplayStatus(.none, at: claim.requestedTimelineTime)
                }
            )
            horizonAnalysisDebugLog("analyze geocalib rejected")
            return
        case .unavailable:
            setAnalysisDisplayStatus(.analyzingFrame, at: claim.requestedTimelineTime)
            horizonAnalysisDebugLog("analyze geocalib unavailable; trying fallback detectors")
            guard let image = AnyUprightAnalysisImage.ciImage(from: frame) else {
                analysisTransaction.relinquishFrame(token: claim.token)
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
            analysisTransaction.complete(
                token: claim.token,
                outcome: .completedWithoutResult,
                inputFrameTime: frameTime,
                onCompleted: {
                    self.setAnalysisDisplayStatus(.none, at: claim.requestedTimelineTime)
                }
            )
            horizonAnalysisDebugLog("analyze no rotation detected")
            return
        }

        analysisTransaction.complete(
            token: claim.token,
            outcome: .produced(rotationRadians),
            inputFrameTime: frameTime,
            onCompleted: {
                self.setAnalysisDisplayStatus(.none, at: claim.requestedTimelineTime)
            }
        )
        horizonAnalysisDebugLog(String(
            format: "analyze stored correctionDeg=%.6f frameTime=%@ frame_ms=%.3f since_start_ms=%.3f",
            rotationRadians * 180 / Double.pi,
            String(describing: frameTime),
            AUMonotonicClock.elapsedMilliseconds(since: frameStartNanos),
            AUMonotonicClock.elapsedMilliseconds(since: claim.analysisStartNanos)
        ))
    }

    func cleanupAnalysis() throws {
        let snapshot = analysisTransaction.cleanup()
        guard let snapshot else {
            horizonAnalysisDebugLog("cleanup ignored without pending request")
            return
        }
        guard let settingAPI = _apiManager.api(for: FxParameterSettingAPI_v5.self) as? FxParameterSettingAPI_v5 else {
            horizonAnalysisDebugLog("cleanup missing FxParameterSettingAPI")
            return
        }

        guard case .produced(let rotationRadians) = snapshot.outcome else {
            horizonAnalysisDebugLog("cleanup no rotation requestedTimelineTime=\(snapshot.requestedTimelineTime) inputFrameTime=\(snapshot.inputFrameTime)")
            return
        }
        guard snapshot.requestedTimelineTime.isValid, snapshot.requestedTimelineTime.isNumeric else {
            horizonAnalysisDebugLog("cleanup invalid requested timeline time=\(snapshot.requestedTimelineTime)")
            return
        }

        let result = settingAPI.setFloatValue(rotationRadians, toParameter: HorizonParam.rotation.rawValue, at: snapshot.requestedTimelineTime)
        horizonAnalysisDebugLog(String(
            format: "cleanup wrote correctionDeg=%.6f writeTime=%@ result=%@ since_start_ms=%.3f",
            rotationRadians * 180 / Double.pi,
            String(describing: snapshot.requestedTimelineTime),
            String(describing: result),
            AUMonotonicClock.elapsedMilliseconds(since: snapshot.analysisStartNanos)
        ))
    }

    private func horizonAnalysisError(_ message: String) -> NSError {
        NSError(
            domain: "AnyUpright.FxAnalysis",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Horizon analysis: \(message)"]
        )
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
        let totalStart = AUMonotonicClock.nowNanos()
        let grayscaleStart = AUMonotonicClock.nowNanos()
        guard let grayscaleImage = AnyUprightAnalysisImage.grayscaleImage(
            from: frame,
            maxDimension: Self.geoCalibVerifierMaxDimension,
            context: analysisContext
        ) else {
            return nil
        }
        let grayscaleMilliseconds = AUMonotonicClock.elapsedMilliseconds(since: grayscaleStart)

        var workerResults: [GeoCalibVerifierWorkerResult] = []
        let resultLock = NSLock()
        DispatchQueue.concurrentPerform(iterations: 2) { index in
            let start = AUMonotonicClock.nowNanos()
            let estimate: AUGeoCalibHorizonVerifierEstimate
            if index == 0 {
                estimate = AUGeoCalibHorizonVerifiers.axisHough(in: grayscaleImage)
            } else {
                estimate = AUGeoCalibHorizonVerifiers.gradientAxis(in: grayscaleImage)
            }
            let milliseconds = AUMonotonicClock.elapsedMilliseconds(since: start)
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
            totalMilliseconds: AUMonotonicClock.elapsedMilliseconds(since: totalStart)
        )
    }

    private func analyzeGeoCalibHorizon(
        _ frame: FxImageTile,
        requestedTimelineTime: CMTime
    ) -> GeoCalibHorizonAnalysisOutcome {
        let totalStart = AUMonotonicClock.nowNanos()

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
            horizonAnalysisDebugLog("geocalib coreml shape=\(preprocessed.inputShape)")
            let run = try AUGeoCalibCoreMLSharedCache.shared.run(
                inputRGB: preprocessed.inputRGBNCHW,
                inputShape: preprocessed.inputShape,
                logger: Self.horizonAnalysisDebugLog,
                sessionReady: { [weak self] _ in
                    self?.setAnalysisDisplayStatus(.analyzingFrame, at: requestedTimelineTime)
                }
            )
            coreMLRun = run
            let optimizerStart = AUMonotonicClock.nowNanos()
            var result = try AUGeoCalibHorizonDetector.detect(
                preprocessedImage: preprocessed,
                neuralOutput: run.output,
                verifierEstimates: []
            )
            optimizerGateMilliseconds = AUMonotonicClock.elapsedMilliseconds(since: optimizerStart)

            var verifierRun: GeoCalibVerifierRun?
            var verifierGateMilliseconds: Double?
            if result.accepted {
                verifierRun = runGeoCalibVerifiers(frame)
                if let verifierRun {
                    let gateStart = AUMonotonicClock.nowNanos()
                    result = AUGeoCalibHorizonDetector.applyVerifierGate(
                        to: result,
                        verifierEstimates: verifierRun.estimates
                    )
                    verifierGateMilliseconds = AUMonotonicClock.elapsedMilliseconds(since: gateStart)
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
                String(format: "total_ms=%.3f", AUMonotonicClock.elapsedMilliseconds(since: totalStart)),
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

        let preprocessStart = AUMonotonicClock.nowNanos()
        let preprocessed = try AUGeoCalibDirectImagePreprocessor.preprocessFrame(
            frame,
            targetInputShape: shapeSpec.inputShape
        )
        return GeoCalibPreprocessRun(
            preprocessed: preprocessed,
            source: "metal_mps_lanczos",
            shapeLabel: shapeSpec.label,
            inputWidth: sourceWidth,
            inputHeight: sourceHeight,
            renderMilliseconds: nil,
            preprocessMilliseconds: AUMonotonicClock.elapsedMilliseconds(since: preprocessStart)
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
        AUAnalysisDiagnostics.horizon.log(message)
    }
}
