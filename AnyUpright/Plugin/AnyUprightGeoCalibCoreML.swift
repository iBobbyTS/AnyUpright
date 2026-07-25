//
//  AnyUprightGeoCalibCoreML.swift
//  AnyUpright
//

import CoreML
import Dispatch
import Foundation

enum AUGeoCalibCoreMLNeuralError: Error, CustomStringConvertible {
    case invalidModel(String)
    case invalidInput(String)
    case missingOutput(String)

    var description: String {
        switch self {
        case .invalidModel(let message):
            return "Invalid GeoCalib Core ML model: \(message)"
        case .invalidInput(let message):
            return "Invalid GeoCalib Core ML input: \(message)"
        case .missingOutput(let name):
            return "Missing GeoCalib Core ML output: \(name)"
        }
    }
}

struct AUGeoCalibCoreMLModelSpec: Equatable {
    var inputShape: [Int]
    var modelURL: URL
}

typealias AUGeoCalibCoreMLRunResult = AUCoreMLSessionLifecycleRunResult<AUGeoCalibNeuralOutput>

final class AUGeoCalibCoreMLSharedCache {
    static let shared = AUGeoCalibCoreMLSharedCache()

    typealias Logger = (String) -> Void
    private typealias LifecycleCache = AUCoreMLSessionLifecycleCache<[Int], AUGeoCalibCoreMLNeuralInferenceSession>

    private let configurationLock = NSLock()
    private var modelSpecsByShape: [[Int]: AUGeoCalibCoreMLModelSpec] = [:]
    private var computeUnits: MLComputeUnits = .all
    private var lifecycleCache: LifecycleCache?

    private init() {}

    func configure(modelSpecs: [AUGeoCalibCoreMLModelSpec], computeUnits: MLComputeUnits = .all) throws {
        guard !modelSpecs.isEmpty else {
            throw AUGeoCalibCoreMLNeuralError.invalidModel("at least one Core ML model spec is required")
        }

        var byShape: [[Int]: AUGeoCalibCoreMLModelSpec] = [:]
        for spec in modelSpecs {
            if byShape[spec.inputShape] != nil {
                throw AUGeoCalibCoreMLNeuralError.invalidModel(
                    "duplicate Core ML model spec for input shape \(geoCalibShapeDescription(spec.inputShape)): \(spec.modelURL.path)"
                )
            }
            byShape[spec.inputShape] = spec
        }

        configurationLock.lock()
        defer { configurationLock.unlock() }
        if modelSpecsByShape == byShape,
           self.computeUnits == computeUnits,
           lifecycleCache != nil {
            return
        }

        lifecycleCache = LifecycleCache(
            label: "geocalib coreml cache",
            keyDescription: geoCalibShapeDescription,
            loadSession: { shape in
                guard let spec = byShape[shape] else {
                    let supported = byShape.keys
                        .map(geoCalibShapeDescription)
                        .sorted()
                        .joined(separator: ", ")
                    throw AUGeoCalibCoreMLNeuralError.invalidInput(
                        "no Core ML model spec for input shape \(geoCalibShapeDescription(shape)); supported shapes: \(supported)"
                    )
                }
                let session = try AUGeoCalibCoreMLNeuralInferenceSession(
                    modelURL: spec.modelURL,
                    computeUnits: computeUnits
                )
                guard session.supportedInputShape == shape else {
                    throw AUGeoCalibCoreMLNeuralError.invalidModel(
                        "\(spec.modelURL.path) supports \(geoCalibShapeDescription(session.supportedInputShape)), expected \(geoCalibShapeDescription(shape))"
                    )
                }
                return session
            },
            warmSession: { try $0.warmUp() },
            logger: { _ in }
        )
        modelSpecsByShape = byShape
        self.computeUnits = computeUnits
    }

    func markPluginAdded(prewarmShape: [Int]?, logger: @escaping Logger) {
        guard let prewarmShape else {
            logger("geocalib coreml cache plugin_added no_prewarm_shape")
            return
        }
        do {
            let cache = try configuredCache(for: prewarmShape)
            cache.updateLogger(logger)
            cache.prewarmAfterPluginAdded(key: prewarmShape)
        } catch {
            logger("geocalib coreml cache plugin_added unavailable shape=\(geoCalibShapeDescription(prewarmShape)) error=\(String(describing: error))")
        }
    }

    func run(
        inputRGB: [Float],
        inputShape: [Int],
        logger: @escaping Logger
    ) throws -> AUGeoCalibCoreMLRunResult {
        let cache = try configuredCache(for: inputShape)
        cache.updateLogger(logger)
        return try cache.withSessionForAnalysis(key: inputShape) { session in
            try session.run(inputRGB: inputRGB, inputShape: inputShape)
        }
    }

    private func configuredCache(for shape: [Int]) throws -> LifecycleCache {
        configurationLock.lock()
        let cache = lifecycleCache
        let supportedShapes = modelSpecsByShape.keys
        let supportsShape = modelSpecsByShape[shape] != nil
        configurationLock.unlock()

        guard let cache else {
            throw AUGeoCalibCoreMLNeuralError.invalidModel("Core ML shared cache is not configured")
        }
        guard supportsShape else {
            let supported = supportedShapes
                .map(geoCalibShapeDescription)
                .sorted()
                .joined(separator: ", ")
            throw AUGeoCalibCoreMLNeuralError.invalidInput(
                "no Core ML model spec for input shape \(geoCalibShapeDescription(shape)); supported shapes: \(supported)"
            )
        }
        return cache
    }
}

struct AUGeoCalibCoreMLNeuralInferenceRouter {
    private var sessionsByShape: [[Int]: AUGeoCalibCoreMLNeuralInferenceSession] = [:]

    var supportedInputShapes: [[Int]] {
        sessionsByShape.keys.sorted { geoCalibShapeDescription($0) < geoCalibShapeDescription($1) }
    }

    init(modelURLs: [URL], computeUnits: MLComputeUnits = .all) throws {
        guard !modelURLs.isEmpty else {
            throw AUGeoCalibCoreMLNeuralError.invalidModel("at least one Core ML model is required")
        }
        for modelURL in modelURLs {
            let session = try AUGeoCalibCoreMLNeuralInferenceSession(
                modelURL: modelURL,
                computeUnits: computeUnits
            )
            let shape = session.supportedInputShape
            if sessionsByShape[shape] != nil {
                throw AUGeoCalibCoreMLNeuralError.invalidModel(
                    "duplicate Core ML model for input shape \(geoCalibShapeDescription(shape)): \(modelURL.path)"
                )
            }
            sessionsByShape[shape] = session
        }
    }

    func run(inputRGB: [Float], inputShape: [Int]) throws -> AUGeoCalibNeuralOutput {
        guard let session = sessionsByShape[inputShape] else {
            let supported = sessionsByShape.keys
                .map(geoCalibShapeDescription)
                .sorted()
                .joined(separator: ", ")
            throw AUGeoCalibCoreMLNeuralError.invalidInput(
                "no Core ML model for input shape \(geoCalibShapeDescription(inputShape)); supported shapes: \(supported)"
            )
        }
        return try session.run(inputRGB: inputRGB, inputShape: inputShape)
    }

    func warmUp() throws {
        for shape in sessionsByShape.keys.sorted(by: { geoCalibShapeDescription($0) < geoCalibShapeDescription($1) }) {
            try sessionsByShape[shape]?.warmUp()
        }
    }
}

final class AUGeoCalibCoreMLNeuralInferenceSession {
    private let model: MLModel
    private let inputShape: [Int]
    private let inputElementCount: Int
    private let inputArray: MLMultiArray
    private let inputProvider: MLDictionaryFeatureProvider
    private let outputShapes: [String: [Int]]
    private let predictionLock = NSLock()

    var supportedInputShape: [Int] {
        inputShape
    }

    init(modelURL: URL, computeUnits: MLComputeUnits = .all) throws {
        let configuration = MLModelConfiguration()
        configuration.computeUnits = computeUnits

        let loadURL: URL
        if modelURL.pathExtension == "mlmodelc" {
            loadURL = modelURL
        } else {
            loadURL = try MLModel.compileModel(at: modelURL)
        }

        model = try MLModel(contentsOf: loadURL, configuration: configuration)

        guard let input = model.modelDescription.inputDescriptionsByName.first(where: { $0.key == "image" }) ??
            model.modelDescription.inputDescriptionsByName.first else {
            throw AUGeoCalibCoreMLNeuralError.invalidModel("model has no inputs")
        }
        let resolvedInputName = input.key
        let resolvedInputShape = try Self.modelIO {
            try AUCoreMLMultiArrayIO.fixedFloat32Shape(input.value, name: input.key)
        }
        let resolvedInputElementCount = try Self.modelIO {
            try AUCoreMLMultiArrayIO.elementCount(shape: resolvedInputShape)
        }
        let resolvedInputArray = try Self.modelIO {
            try AUCoreMLMultiArrayIO.makeContiguousFloat32Array(shape: resolvedInputShape)
        }
        let resolvedInputProvider = try MLDictionaryFeatureProvider(
            dictionary: [resolvedInputName: MLFeatureValue(multiArray: resolvedInputArray)]
        )

        var shapes: [String: [Int]] = [:]
        for name in ["up_field", "up_confidence", "latitude_field", "latitude_confidence"] {
            guard let description = model.modelDescription.outputDescriptionsByName[name] else {
                throw AUGeoCalibCoreMLNeuralError.invalidModel("missing output description \(name)")
            }
            shapes[name] = try Self.modelIO {
                try AUCoreMLMultiArrayIO.fixedFloat32Shape(description, name: name)
            }
        }
        inputShape = resolvedInputShape
        inputElementCount = resolvedInputElementCount
        inputArray = resolvedInputArray
        inputProvider = resolvedInputProvider
        outputShapes = shapes
    }

    func run(inputRGB: [Float], inputShape requestedShape: [Int]) throws -> AUGeoCalibNeuralOutput {
        guard requestedShape == inputShape else {
            throw AUGeoCalibCoreMLNeuralError.invalidInput(
                "expected input shape \(inputShape), got \(requestedShape)"
            )
        }
        guard inputRGB.count == inputElementCount else {
            throw AUGeoCalibCoreMLNeuralError.invalidInput(
                "expected \(inputElementCount) floats, got \(inputRGB.count)"
            )
        }

        predictionLock.lock()
        defer { predictionLock.unlock() }

        do {
            try AUCoreMLMultiArrayIO.copyFloat32(inputRGB, to: inputArray)
        } catch {
            throw AUGeoCalibCoreMLNeuralError.invalidInput(String(describing: error))
        }
        let output = try model.prediction(from: inputProvider)

        let upField = try Self.outputTensor(from: output, name: "up_field").values
        let upConfidence = try Self.outputTensor(from: output, name: "up_confidence").values
        let latitudeField = try Self.outputTensor(from: output, name: "latitude_field").values
        let latitudeConfidence = try Self.outputTensor(from: output, name: "latitude_confidence").values

        guard let upFieldShape = outputShapes["up_field"],
              let upConfidenceShape = outputShapes["up_confidence"],
              let latitudeFieldShape = outputShapes["latitude_field"],
              let latitudeConfidenceShape = outputShapes["latitude_confidence"] else {
            throw AUGeoCalibCoreMLNeuralError.invalidModel("missing cached output shapes")
        }
        guard latitudeFieldShape == upConfidenceShape,
              latitudeConfidenceShape == upConfidenceShape else {
            throw AUGeoCalibCoreMLNeuralError.invalidModel(
                "latitude/confidence output shapes do not match confidence shape"
            )
        }

        return AUGeoCalibNeuralOutput(
            upField: upField,
            upConfidence: upConfidence,
            latitudeField: latitudeField,
            latitudeConfidence: latitudeConfidence,
            fieldShape: upFieldShape,
            confidenceShape: upConfidenceShape
        )
    }

    func warmUp() throws {
        let zeros = Array(repeating: Float(0), count: inputElementCount)
        _ = try run(inputRGB: zeros, inputShape: inputShape)
    }

    private static func modelIO<T>(_ body: () throws -> T) throws -> T {
        do {
            return try body()
        } catch {
            throw AUGeoCalibCoreMLNeuralError.invalidModel(String(describing: error))
        }
    }

    private static func outputTensor(from provider: MLFeatureProvider, name: String) throws -> AUCoreMLFloat32Tensor {
        do {
            return try AUCoreMLMultiArrayIO.readFloat32(from: provider, name: name)
        } catch AUCoreMLMultiArrayIOError.missingOutput {
            throw AUGeoCalibCoreMLNeuralError.missingOutput(name)
        } catch {
            throw AUGeoCalibCoreMLNeuralError.invalidModel(String(describing: error))
        }
    }
}

private func geoCalibShapeDescription(_ shape: [Int]) -> String {
    shape.map(String.init).joined(separator: "x")
}
