//
//  AnyUprightScaleLSDCoreML.swift
//  AnyUpright
//

import CoreML
import Foundation

enum AUScaleLSDCoreMLError: Error, CustomStringConvertible {
    case invalidModel(String)
    case invalidInput(expected: Int, actual: Int)
    case missingOutput(String)

    var description: String {
        switch self {
        case .invalidModel(let message):
            return "Invalid ScaleLSD Core ML model: \(message)"
        case .invalidInput(let expected, let actual):
            return "Invalid ScaleLSD Core ML input: expected \(expected) values, got \(actual)"
        case .missingOutput(let name):
            return "Missing ScaleLSD Core ML output: \(name)"
        }
    }
}

struct AUScaleLSDCoreMLOutput {
    var values: [Float]
    var shape: [Int]
}

final class AUScaleLSDCoreMLSession {
    private let model: MLModel
    private let inputName: String
    private let inputShape: [Int]
    private let inputElementCount: Int
    private let inputArray: MLMultiArray
    private let inputProvider: MLDictionaryFeatureProvider
    private let outputName: String
    private let predictionLock = NSLock()

    init(modelURL: URL, computeUnits: MLComputeUnits = .all) throws {
        let configuration = MLModelConfiguration()
        configuration.computeUnits = computeUnits
        let loadURL = modelURL.pathExtension == "mlmodelc" ? modelURL : try MLModel.compileModel(at: modelURL)
        model = try MLModel(contentsOf: loadURL, configuration: configuration)

        guard let input = model.modelDescription.inputDescriptionsByName.first(where: { $0.value.type == .multiArray }) else {
            throw AUScaleLSDCoreMLError.invalidModel("model has no MultiArray input")
        }
        let resolvedInputName = input.key
        let resolvedInputShape = try Self.modelIO {
            try AUCoreMLMultiArrayIO.fixedFloat32Shape(input.value, name: input.key)
        }
        let resolvedInputElementCount = try Self.modelIO {
            try AUCoreMLMultiArrayIO.elementCount(shape: resolvedInputShape)
        }
        guard resolvedInputShape == [1, 1, 512, 512] else {
            throw AUScaleLSDCoreMLError.invalidModel("expected [1, 1, 512, 512] input, got \(resolvedInputShape)")
        }
        let resolvedInputArray = try Self.modelIO {
            try AUCoreMLMultiArrayIO.makeContiguousFloat32Array(shape: resolvedInputShape)
        }
        let resolvedInputProvider = try MLDictionaryFeatureProvider(dictionary: [resolvedInputName: MLFeatureValue(multiArray: resolvedInputArray)])

        guard let output = model.modelDescription.outputDescriptionsByName.first(where: { description in
            guard description.value.type == .multiArray,
                  let shape = try? AUCoreMLMultiArrayIO.fixedFloat32Shape(description.value, name: description.key) else {
                return false
            }
            return shape == [1, 9, 256, 256]
        }) else {
            throw AUScaleLSDCoreMLError.invalidModel("expected [1, 9, 256, 256] MultiArray output")
        }
        inputName = resolvedInputName
        inputShape = resolvedInputShape
        inputElementCount = resolvedInputElementCount
        inputArray = resolvedInputArray
        inputProvider = resolvedInputProvider
        outputName = output.key
    }

    func run(inputNCHW: [Float]) throws -> AUScaleLSDCoreMLOutput {
        guard inputNCHW.count == inputElementCount else {
            throw AUScaleLSDCoreMLError.invalidInput(expected: inputElementCount, actual: inputNCHW.count)
        }
        predictionLock.lock()
        defer { predictionLock.unlock() }

        do {
            try AUCoreMLMultiArrayIO.copyFloat32(inputNCHW, to: inputArray)
        } catch AUCoreMLMultiArrayIOError.elementCountMismatch(let expected, let actual) {
            throw AUScaleLSDCoreMLError.invalidInput(expected: expected, actual: actual)
        } catch {
            throw AUScaleLSDCoreMLError.invalidModel(String(describing: error))
        }
        let prediction = try model.prediction(from: inputProvider)
        let tensor: AUCoreMLFloat32Tensor
        do {
            tensor = try AUCoreMLMultiArrayIO.readFloat32(from: prediction, name: outputName)
        } catch AUCoreMLMultiArrayIOError.missingOutput {
            throw AUScaleLSDCoreMLError.missingOutput(outputName)
        } catch {
            throw AUScaleLSDCoreMLError.invalidModel(String(describing: error))
        }
        return AUScaleLSDCoreMLOutput(
            values: tensor.values,
            shape: tensor.shape
        )
    }

    func warmUp() throws {
        _ = try run(inputNCHW: Array(repeating: 0, count: inputElementCount))
    }

    private static func modelIO<T>(_ body: () throws -> T) throws -> T {
        do {
            return try body()
        } catch {
            throw AUScaleLSDCoreMLError.invalidModel(String(describing: error))
        }
    }
}

private enum AUScaleLSDCoreMLModelKey: Hashable {
    case fixed512
}

typealias AUScaleLSDCoreMLRunResult = AUCoreMLSessionLifecycleRunResult<AUScaleLSDCoreMLOutput>

final class AUScaleLSDCoreMLSharedCache {
    static let shared = AUScaleLSDCoreMLSharedCache()

    typealias Logger = (String) -> Void
    private typealias LifecycleCache = AUCoreMLSessionLifecycleCache<AUScaleLSDCoreMLModelKey, AUScaleLSDCoreMLSession>

    private let configurationLock = NSLock()
    private var modelURL: URL?
    private var computeUnits: MLComputeUnits = .all
    private var lifecycleCache: LifecycleCache?

    private init() {}

    func configure(modelURL: URL, computeUnits: MLComputeUnits = .all) {
        configurationLock.lock()
        defer { configurationLock.unlock() }
        if self.modelURL == modelURL,
           self.computeUnits == computeUnits,
           lifecycleCache != nil {
            return
        }

        lifecycleCache = LifecycleCache(
            label: "scalelsd coreml cache",
            keyDescription: { _ in "fixed512" },
            loadSession: { _ in
                try AUScaleLSDCoreMLSession(modelURL: modelURL, computeUnits: computeUnits)
            },
            warmSession: { try $0.warmUp() },
            logger: { _ in }
        )
        self.modelURL = modelURL
        self.computeUnits = computeUnits
    }

    func prewarmAfterPluginAdded(logger: @escaping Logger) throws {
        let cache = try configuredCache()
        cache.updateLogger(logger)
        cache.prewarmAfterPluginAdded(key: .fixed512)
    }

    func run(
        inputNCHW: [Float],
        logger: @escaping Logger,
        sessionReady: ((Bool) -> Void)? = nil
    ) throws -> AUScaleLSDCoreMLRunResult {
        let cache = try configuredCache()
        cache.updateLogger(logger)
        return try cache.withSessionForAnalysis(key: .fixed512, sessionReady: sessionReady) { session in
            try session.run(inputNCHW: inputNCHW)
        }
    }

    private func configuredCache() throws -> LifecycleCache {
        configurationLock.lock()
        let cache = lifecycleCache
        configurationLock.unlock()
        guard let cache else {
            throw AUScaleLSDCoreMLError.invalidModel("Core ML shared cache is not configured")
        }
        return cache
    }
}
