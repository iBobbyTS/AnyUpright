//
//  AnyUprightGeoCalibCameraPriorProvider.swift
//  AnyUpright
//

import Foundation

private final class AUGeoCalibCameraPriorResourceAnchor: NSObject {}

enum AnyUprightGeoCalibCameraPriorProvider {
    typealias Logger = (String) -> Void

    private static let configurationLock = NSLock()
    private static var configuredResourcePath: String?

    static func cameraPrior(
        for frame: FxImageTile,
        logger: @escaping Logger
    ) throws -> AUUprightV2CameraPrior {
        let bounds = frame.imagePixelBounds
        let width = max(1, Int(bounds.right - bounds.left))
        let height = max(1, Int(bounds.top - bounds.bottom))
        let shape = try AUGeoCalibInputShapeSpec.closest(toWidth: width, height: height)
        try configureCache(logger: logger)

        let preprocessStart = AUMonotonicClock.nowNanos()
        let preprocessed = try AUGeoCalibDirectImagePreprocessor.preprocessFrame(
            frame,
            targetInputShape: shape.inputShape
        )
        let preprocessMilliseconds = AUMonotonicClock.elapsedMilliseconds(since: preprocessStart)
        let run = try AUGeoCalibCoreMLSharedCache.shared.run(
            inputRGB: preprocessed.inputRGBNCHW,
            inputShape: preprocessed.inputShape,
            logger: logger
        )
        let optimizerStart = AUMonotonicClock.nowNanos()
        let detection = try AUGeoCalibHorizonDetector.detect(
            preprocessedImage: preprocessed,
            neuralOutput: run.output
        )
        let optimizerMilliseconds = AUMonotonicClock.elapsedMilliseconds(since: optimizerStart)
        let optimizer = detection.optimizerResult
        guard optimizer.gravityData.count >= 3 else {
            throw AUGeoCalibHorizonDetectorError.invalidNeuralOutput(
                "optimizer returned an incomplete gravity vector"
            )
        }
        logger(String(
            format: "upright_v2_geocalib shape=%@ preprocess_ms=%.3f cache_hit=%@ load_ms=%.3f predict_ms=%.3f optimizer_ms=%.3f",
            String(describing: shape.inputShape),
            preprocessMilliseconds,
            run.cacheHit ? "true" : "false",
            run.loadMilliseconds,
            run.predictionMilliseconds,
            optimizerMilliseconds
        ))
        return AUUprightV2CameraPrior(
            gravity: SIMD3(
                Double(optimizer.gravityData[0]),
                Double(optimizer.gravityData[1]),
                Double(optimizer.gravityData[2])
            ),
            gravityUncertainty: optimizer.gravityUncertainty,
            verticalFOVRadians: optimizer.verticalFOVRadians,
            verticalFOVUncertaintyRadians: optimizer.verticalFOVUncertaintyRadians
        )
    }

    private static func configureCache(logger: Logger) throws {
        guard let resourceURL = Bundle(for: AUGeoCalibCameraPriorResourceAnchor.self).resourceURL else {
            throw AUGeoCalibHorizonDetectorError.invalidImage(
                "GeoCalib resource bundle is unavailable"
            )
        }
        configurationLock.lock()
        defer { configurationLock.unlock() }
        if configuredResourcePath == resourceURL.path {
            return
        }
        let specs = AUGeoCalibInputShapeSpec.production.map {
            AUGeoCalibCoreMLModelSpec(
                inputShape: $0.inputShape,
                modelURL: resourceURL.appendingPathComponent($0.modelResourceName, isDirectory: true)
            )
        }
        for spec in specs where !FileManager.default.fileExists(atPath: spec.modelURL.path) {
            throw AUGeoCalibHorizonDetectorError.invalidImage(
                "missing GeoCalib model \(spec.modelURL.lastPathComponent)"
            )
        }
        try AUGeoCalibCoreMLSharedCache.shared.configure(modelSpecs: specs)
        configuredResourcePath = resourceURL.path
        logger("upright_v2_geocalib configured resource=\(resourceURL.path)")
    }
}
