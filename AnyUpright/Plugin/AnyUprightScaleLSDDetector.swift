//
//  AnyUprightScaleLSDDetector.swift
//  AnyUpright
//

import CoreML
import Dispatch
import Foundation

enum AUScaleLSDDetectorError: Error, CustomStringConvertible {
    case missingFrameImage
    case missingModel([URL])
    case invalidInput

    var description: String {
        switch self {
        case .missingFrameImage:
            return "Missing frame image for ScaleLSD detection"
        case .missingModel(let urls):
            return "Missing ScaleLSD Core ML model at \(urls.map(\.path).joined(separator: ", "))"
        case .invalidInput:
            return "Could not build the fixed-512 ScaleLSD input"
        }
    }
}

private final class AUScaleLSDResourceAnchor: NSObject {}

enum AnyUprightScaleLSDDetector {
    private static let inputSize = 512
    static func prepareCoreMLCacheForPluginAdd() {
        do {
            let cache = try configuredCache()
            try cache.prewarmAfterPluginAdded(logger: debugLog)
        } catch {
            debugLog("scalelsd_prewarm_unavailable error=\(String(describing: error))")
        }
    }

    static func detectCandidates(
        in frame: FxImageTile,
        request: UprightAnalysisRequest
    ) throws -> [UprightDetectedCandidate] {
        let totalStart = AUMonotonicClock.nowNanos()
        let sourceBounds = frame.imagePixelBounds
        let referenceImageSize = AUSize(
            width: max(1.0, Double(sourceBounds.right - sourceBounds.left)),
            height: max(1.0, Double(sourceBounds.top - sourceBounds.bottom))
        )
        let preprocessStart = AUMonotonicClock.nowNanos()
        let input = try resampledGrayscaleInput(from: frame)
        let preprocessMS = AUMonotonicClock.elapsedMilliseconds(since: preprocessStart)

        let coreMLRun = try configuredCache().run(inputNCHW: input, logger: debugLog)
        let dense = coreMLRun.output

        let decodeStart = AUMonotonicClock.nowNanos()
        let lines = try AnyUprightScaleLSDPostprocessor.decode(
            denseLogits: dense.values,
            shape: dense.shape,
            imageWidth: inputSize,
            imageHeight: inputSize
        )
        let decodeMS = AUMonotonicClock.elapsedMilliseconds(since: decodeStart)

        let candidatesStart = AUMonotonicClock.nowNanos()
        if request.controlMode == .automatic, request.correctionMode == .full {
            do {
                let ranked = try v2FullAutoCandidates(
                    lines: lines,
                    frame: frame,
                    imageSize: AUSize(width: Double(inputSize), height: Double(inputSize))
                )
                let candidatesMS = AUMonotonicClock.elapsedMilliseconds(since: candidatesStart)
                debugLog(
                    String(
                        format: "scalelsd_stages selector=v2 preprocess_ms=%.3f coreml_cache_hit=%@ coreml_load_ms=%.3f coreml_predict_ms=%.3f coreml_total_ms=%.3f decode_ms=%.3f candidates_ms=%.3f lines=%d candidates=%d total_ms=%.3f",
                        preprocessMS,
                        coreMLRun.cacheHit ? "true" : "false",
                        coreMLRun.loadMilliseconds,
                        coreMLRun.predictionMilliseconds,
                        coreMLRun.totalMilliseconds,
                        decodeMS,
                        candidatesMS,
                        lines.count,
                        ranked.count,
                        AUMonotonicClock.elapsedMilliseconds(since: totalStart)
                    )
                )
                return ranked
            } catch {
                debugLog("upright_v2_fallback error=\(String(describing: error))")
            }
        }
        let candidates = AnyUprightScaleLSDPreprocessor.detectedCandidates(
            from: lines,
            imageSize: AUSize(width: Double(inputSize), height: Double(inputSize)),
            referenceImageSize: referenceImageSize
        )
        let ranked = AnyUprightUprightCandidates.analysisCandidates(from: candidates, request: request)
        let candidatesMS = AUMonotonicClock.elapsedMilliseconds(since: candidatesStart)
        debugLog(
            String(
                format: "scalelsd_stages preprocess_ms=%.3f coreml_cache_hit=%@ coreml_load_ms=%.3f coreml_predict_ms=%.3f coreml_total_ms=%.3f decode_ms=%.3f candidates_ms=%.3f lines=%d candidates=%d total_ms=%.3f",
                preprocessMS,
                coreMLRun.cacheHit ? "true" : "false",
                coreMLRun.loadMilliseconds,
                coreMLRun.predictionMilliseconds,
                coreMLRun.totalMilliseconds,
                decodeMS,
                candidatesMS,
                lines.count,
                ranked.count,
                AUMonotonicClock.elapsedMilliseconds(since: totalStart)
            )
        )
        return ranked
    }

    private static func v2FullAutoCandidates(
        lines: [AUScaleLSDLineSegment],
        frame: FxImageTile,
        imageSize: AUSize
    ) throws -> [UprightDetectedCandidate] {
        let priorStart = AUMonotonicClock.nowNanos()
        let prior: AUUprightV2CameraPrior?
        do {
            prior = try AnyUprightGeoCalibCameraPriorProvider.cameraPrior(
                for: frame,
                logger: debugLog
            )
        } catch {
            prior = nil
            debugLog("upright_v2_geocalib unavailable error=\(String(describing: error)); using_no_prior")
        }
        let selectorStart = AUMonotonicClock.nowNanos()
        let selection = try AnyUprightUprightV2GuideSelector.select(
            lines: lines,
            imageSize: imageSize,
            cameraPrior: prior
        )
        let selectorMS = AUMonotonicClock.elapsedMilliseconds(since: selectorStart)
        guard selection.selected else {
            debugLog(String(
                format: "upright_v2_identity prior=%@ prior_ms=%.3f selector_ms=%.3f prepared=%d clusters=%d candidates=%d",
                prior == nil ? "false" : "true",
                AUMonotonicClock.elapsedMilliseconds(since: priorStart, nowNanos: selectorStart),
                selectorMS,
                selection.preparedLineCount,
                selection.vpClusterCount,
                selection.candidateCount
            ))
            return []
        }
        let verticalGuideCount = selection.guides.filter { $0.orientation == .vertical }.count
        let horizontalGuideCount = selection.guides.filter { $0.orientation == .horizontal }.count
        debugLog(String(
            format: "upright_v2_selected prior=%@ prior_ms=%.3f selector_ms=%.3f prepared=%d clusters=%d candidates=%d pairs=%d pair_score=%.6f risk=%.6f vertical_support=%d horizontal_support=%d vertical_guides=%d horizontal_guides=%d",
            prior == nil ? "false" : "true",
            AUMonotonicClock.elapsedMilliseconds(since: priorStart, nowNanos: selectorStart),
            selectorMS,
            selection.preparedLineCount,
            selection.vpClusterCount,
            selection.candidateCount,
            selection.pairCount,
            selection.rankScore ?? .nan,
            selection.riskProbability ?? .nan,
            selection.verticalSupporterCount,
            selection.horizontalSupporterCount,
            verticalGuideCount,
            horizontalGuideCount
        ))
        return selection.guides
    }

    private static func configuredCache() throws -> AUScaleLSDCoreMLSharedCache {
        let modelURL = try resolvedModelURL()
        let cache = AUScaleLSDCoreMLSharedCache.shared
        cache.configure(modelURL: modelURL, computeUnits: .all)
        return cache
    }

    private static func resolvedModelURL() throws -> URL {
        let roots = [
            Bundle(for: AUScaleLSDResourceAnchor.self).resourceURL,
            Bundle.main.resourceURL,
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
        ].compactMap { $0 }
        let candidates = roots.flatMap { root in
            [
                root.appendingPathComponent("scalelsd_neural_forward.mlmodelc", isDirectory: true),
                root.appendingPathComponent("ScaleLSDCoreML/scalelsd_neural_forward.mlmodelc", isDirectory: true),
                root.appendingPathComponent("Plugin/ScaleLSDCoreML/scalelsd_neural_forward.mlmodelc", isDirectory: true),
                root.appendingPathComponent("AnyUpright/Plugin/ScaleLSDCoreML/scalelsd_neural_forward.mlmodelc", isDirectory: true),
            ]
        }
        for candidate in candidates where FileManager.default.fileExists(atPath: candidate.path) {
            return candidate
        }
        throw AUScaleLSDDetectorError.missingModel(candidates)
    }

    private static func resampledGrayscaleInput(from frame: FxImageTile) throws -> [Float] {
        guard frame.ioSurface != nil else {
            throw AUScaleLSDDetectorError.missingFrameImage
        }
        let bounds = frame.imagePixelBounds
        let sourceWidth = max(1, Int(bounds.right - bounds.left))
        let sourceHeight = max(1, Int(bounds.top - bounds.bottom))
        guard let device = MetalDeviceCache.deviceCache.analysisDevice(preferredRegistryID: frame.deviceRegistryID),
              let sourceTexture = frame.metalTexture(for: device) else {
            throw AUScaleLSDDetectorError.missingFrameImage
        }
        debugLog(
            "scalelsd_metal_source requested_registry_id=\(frame.deviceRegistryID) resolved_registry_id=\(device.registryID) "
                + "surface=\(frame.ioSurface.width)x\(frame.ioSurface.height) texture=\(sourceTexture.width)x\(sourceTexture.height) "
                + "image_bounds=\(frame.imagePixelBounds) tile_bounds=\(frame.tilePixelBounds)"
        )
        let pixelFormat = MetalDeviceCache.FxMTLPixelFormat(for: frame)
        let lease = MetalDeviceCache.deviceCache.commandQueueLease(
            with: device.registryID,
            pixelFormat: pixelFormat
        )
        defer { lease?.returnToCache() }
        guard let commandQueue = lease?.commandQueue ?? device.makeCommandQueue() else {
            throw AUScaleLSDDetectorError.invalidInput
        }

        do {
            let tensor = try AUAppleSiliconImageResampler.resample(
                sourceTexture: sourceTexture,
                sourceWidth: sourceWidth,
                sourceHeight: sourceHeight,
                targetWidth: inputSize,
                targetHeight: inputSize,
                layout: .stretch,
                channels: .grayscale,
                commandQueue: commandQueue
            )
            guard tensor.shape == [1, 1, inputSize, inputSize] else {
                throw AUScaleLSDDetectorError.invalidInput
            }
            return tensor.values
        } catch let error as AUScaleLSDDetectorError {
            throw error
        } catch {
            throw AUScaleLSDDetectorError.invalidInput
        }
    }

    private static func debugLog(_ message: String) {
        AUAnalysisDiagnostics.upright.log(message)
    }
}
