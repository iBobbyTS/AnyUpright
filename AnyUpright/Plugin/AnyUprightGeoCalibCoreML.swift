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

struct AUGeoCalibCoreMLRunResult {
    var output: AUGeoCalibNeuralOutput
    var cacheHit: Bool
    var loadMilliseconds: Double
    var predictionMilliseconds: Double
    var totalMilliseconds: Double
}

struct AUGeoCalibCoreMLCacheExpiryEvent {
    var deadlineNanos: UInt64
    var analysisCountInWindow: Int
    var windowNanos: UInt64
}

struct AUGeoCalibCoreMLCacheExpiryPolicy {
    static let pluginIdleNanoseconds: UInt64 = 15_000_000_000
    static let singleAnalysisNanoseconds: UInt64 = 30_000_000_000
    static let repeatedAnalysisNanoseconds: UInt64 = 60_000_000_000

    private(set) var unloadDeadlineNanos: UInt64?
    private(set) var analysisWindowDeadlineNanos: UInt64?
    private(set) var analysisCountInWindow = 0

    mutating func markPluginAdded(at nowNanos: UInt64) -> UInt64 {
        let deadline = nowNanos + Self.pluginIdleNanoseconds
        extendUnloadDeadline(to: deadline)
        return unloadDeadlineNanos ?? deadline
    }

    mutating func markAnalysisStarted(at nowNanos: UInt64) -> AUGeoCalibCoreMLCacheExpiryEvent {
        if let windowDeadline = analysisWindowDeadlineNanos, nowNanos <= windowDeadline {
            analysisCountInWindow += 1
        } else {
            analysisCountInWindow = 1
            analysisWindowDeadlineNanos = nowNanos + Self.singleAnalysisNanoseconds
        }

        let retentionNanos = analysisCountInWindow >= 2 ? Self.repeatedAnalysisNanoseconds : Self.singleAnalysisNanoseconds
        let deadline = nowNanos + retentionNanos
        extendUnloadDeadline(to: deadline)
        return AUGeoCalibCoreMLCacheExpiryEvent(
            deadlineNanos: unloadDeadlineNanos ?? deadline,
            analysisCountInWindow: analysisCountInWindow,
            windowNanos: retentionNanos
        )
    }

    mutating func didUnload() {
        unloadDeadlineNanos = nil
        analysisWindowDeadlineNanos = nil
        analysisCountInWindow = 0
    }

    private mutating func extendUnloadDeadline(to deadline: UInt64) {
        if let current = unloadDeadlineNanos, current > deadline {
            return
        }
        unloadDeadlineNanos = deadline
    }
}

final class AUGeoCalibCoreMLSharedCache {
    static let shared = AUGeoCalibCoreMLSharedCache()

    typealias Logger = (String) -> Void

    private final class ShapeExpiryState {
        var policy = AUGeoCalibCoreMLCacheExpiryPolicy()
        var timer: DispatchSourceTimer?
        var generation: UInt64 = 0
    }

    private let queue = DispatchQueue(label: "com.anyupright.geocalib.coreml.shared-cache")
    private var modelSpecsByShape: [[Int]: AUGeoCalibCoreMLModelSpec] = [:]
    private var sessionsByShape: [[Int]: AUGeoCalibCoreMLNeuralInferenceSession] = [:]
    private var computeUnits: MLComputeUnits = .all
    private var expiryStatesByShape: [[Int]: ShapeExpiryState] = [:]

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

        queue.sync {
            if modelSpecsByShape == byShape, self.computeUnits == computeUnits {
                return
            }
            for state in expiryStatesByShape.values {
                state.timer?.cancel()
            }
            sessionsByShape.removeAll()
            expiryStatesByShape.removeAll()
            modelSpecsByShape = byShape
            self.computeUnits = computeUnits
        }
    }

    func markPluginAdded(prewarmShape: [Int]?, logger: @escaping Logger) {
        queue.async { [weak self] in
            guard let self else {
                return
            }
            let now = geoCalibNowNanos()
            guard let prewarmShape else {
                logger("geocalib coreml cache plugin_added no_prewarm_shape cached_shapes=\(self.cachedShapeSummaryLocked())")
                return
            }
            guard self.modelSpecsByShape[prewarmShape] != nil else {
                logger("geocalib coreml cache plugin_added unsupported_prewarm_shape=\(geoCalibShapeDescription(prewarmShape)) cached_shapes=\(self.cachedShapeSummaryLocked())")
                return
            }

            let state = self.expiryStateLocked(for: prewarmShape)
            let deadline = state.policy.markPluginAdded(at: now)
            self.scheduleExpirationLocked(
                shape: prewarmShape,
                state: state,
                deadlineNanos: deadline,
                reason: "plugin_added",
                logger: logger
            )
            logger(String(
                format: "geocalib coreml cache plugin_added shape=%@ expiry_s=%.3f cached_shapes=%@",
                geoCalibShapeDescription(prewarmShape),
                Double(deadline - now) / 1_000_000_000.0,
                self.cachedShapeSummaryLocked()
            ))
            self.prewarmLocked(shape: prewarmShape, logger: logger)
        }
    }

    func markAnalysisStarted(inputShape: [Int], logger: @escaping Logger) {
        queue.async { [weak self] in
            guard let self else {
                return
            }
            guard self.modelSpecsByShape[inputShape] != nil else {
                logger("geocalib coreml cache analysis_started unsupported_shape=\(geoCalibShapeDescription(inputShape)) cached_shapes=\(self.cachedShapeSummaryLocked())")
                return
            }
            let now = geoCalibNowNanos()
            let state = self.expiryStateLocked(for: inputShape)
            let event = state.policy.markAnalysisStarted(at: now)
            self.scheduleExpirationLocked(
                shape: inputShape,
                state: state,
                deadlineNanos: event.deadlineNanos,
                reason: "analysis_started",
                logger: logger
            )
            logger(String(
                format: "geocalib coreml cache analysis_started shape=%@ count_in_window=%d window_s=%.0f expiry_s=%.3f cached_shapes=%@",
                geoCalibShapeDescription(inputShape),
                event.analysisCountInWindow,
                Double(event.windowNanos) / 1_000_000_000.0,
                Double(event.deadlineNanos - now) / 1_000_000_000.0,
                self.cachedShapeSummaryLocked()
            ))
        }
    }

    func run(
        inputRGB: [Float],
        inputShape: [Int],
        logger: @escaping Logger
    ) throws -> AUGeoCalibCoreMLRunResult {
        let totalStart = geoCalibNowNanos()
        var cacheHit = false
        var loadMilliseconds = 0.0

        let session = try queue.sync { () throws -> AUGeoCalibCoreMLNeuralInferenceSession in
            if let session = sessionsByShape[inputShape] {
                cacheHit = true
                return session
            }
            let loadStart = geoCalibNowNanos()
            let session = try loadSessionLocked(shape: inputShape)
            loadMilliseconds = geoCalibElapsedMilliseconds(since: loadStart)
            logger(String(
                format: "geocalib coreml cache loaded shape=%@ load_ms=%.3f model=%@",
                geoCalibShapeDescription(inputShape),
                loadMilliseconds,
                modelSpecsByShape[inputShape]?.modelURL.lastPathComponent ?? "<unknown>"
            ))
            return session
        }

        let predictionStart = geoCalibNowNanos()
        let output = try session.run(inputRGB: inputRGB, inputShape: inputShape)
        let predictionMilliseconds = geoCalibElapsedMilliseconds(since: predictionStart)
        let totalMilliseconds = geoCalibElapsedMilliseconds(since: totalStart)
        logger(String(
            format: "geocalib coreml cache run shape=%@ cache_hit=%@ load_ms=%.3f predict_ms=%.3f total_ms=%.3f",
            geoCalibShapeDescription(inputShape),
            cacheHit ? "true" : "false",
            loadMilliseconds,
            predictionMilliseconds,
            totalMilliseconds
        ))
        return AUGeoCalibCoreMLRunResult(
            output: output,
            cacheHit: cacheHit,
            loadMilliseconds: loadMilliseconds,
            predictionMilliseconds: predictionMilliseconds,
            totalMilliseconds: totalMilliseconds
        )
    }

    private func prewarmLocked(shape: [Int], logger: Logger) {
        let totalStart = geoCalibNowNanos()
        do {
            let session: AUGeoCalibCoreMLNeuralInferenceSession
            var loadMilliseconds = 0.0
            if let cached = sessionsByShape[shape] {
                session = cached
            } else {
                let loadStart = geoCalibNowNanos()
                session = try loadSessionLocked(shape: shape)
                loadMilliseconds = geoCalibElapsedMilliseconds(since: loadStart)
            }

            let warmStart = geoCalibNowNanos()
            try session.warmUp()
            let warmMilliseconds = geoCalibElapsedMilliseconds(since: warmStart)
            logger(String(
                format: "geocalib coreml cache prewarm ok shape=%@ load_ms=%.3f warm_ms=%.3f total_ms=%.3f",
                geoCalibShapeDescription(shape),
                loadMilliseconds,
                warmMilliseconds,
                geoCalibElapsedMilliseconds(since: totalStart)
            ))
        } catch {
            logger("geocalib coreml cache prewarm failed shape=\(geoCalibShapeDescription(shape)) error=\(String(describing: error))")
        }
    }

    private func loadSessionLocked(shape: [Int]) throws -> AUGeoCalibCoreMLNeuralInferenceSession {
        guard let spec = modelSpecsByShape[shape] else {
            let supported = modelSpecsByShape.keys
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
        sessionsByShape[shape] = session
        return session
    }

    private func expiryStateLocked(for shape: [Int]) -> ShapeExpiryState {
        if let state = expiryStatesByShape[shape] {
            return state
        }
        let state = ShapeExpiryState()
        expiryStatesByShape[shape] = state
        return state
    }

    private func scheduleExpirationLocked(
        shape: [Int],
        state: ShapeExpiryState,
        deadlineNanos: UInt64,
        reason: String,
        logger: @escaping Logger
    ) {
        state.generation &+= 1
        let generation = state.generation
        state.timer?.cancel()

        let timer = DispatchSource.makeTimerSource(queue: queue)
        state.timer = timer
        let now = geoCalibNowNanos()
        let delayNanos = deadlineNanos > now ? deadlineNanos - now : 0
        timer.schedule(deadline: .now() + .nanoseconds(Int(delayNanos)))
        timer.setEventHandler { [weak self] in
            self?.expireIfDueLocked(shape: shape, generation: generation, logger: logger)
        }
        timer.resume()
        logger(String(
            format: "geocalib coreml cache expiry_scheduled shape=%@ reason=%@ delay_s=%.3f generation=%llu",
            geoCalibShapeDescription(shape),
            reason,
            Double(delayNanos) / 1_000_000_000.0,
            generation
        ))
    }

    private func expireIfDueLocked(shape: [Int], generation: UInt64, logger: @escaping Logger) {
        guard let state = expiryStatesByShape[shape],
              generation == state.generation,
              let deadline = state.policy.unloadDeadlineNanos else {
            return
        }

        let now = geoCalibNowNanos()
        guard now >= deadline else {
            scheduleExpirationLocked(
                shape: shape,
                state: state,
                deadlineNanos: deadline,
                reason: "deadline_adjusted",
                logger: logger
            )
            return
        }

        let hadSession = sessionsByShape.removeValue(forKey: shape) != nil
        state.timer?.cancel()
        state.timer = nil
        state.policy.didUnload()
        expiryStatesByShape.removeValue(forKey: shape)
        logger("geocalib coreml cache unloaded shape=\(geoCalibShapeDescription(shape)) count=\(hadSession ? 1 : 0) cached_shapes=\(cachedShapeSummaryLocked())")
    }

    private func cachedShapeSummaryLocked() -> String {
        let shapes = sessionsByShape.keys.map(geoCalibShapeDescription).sorted()
        return shapes.isEmpty ? "[]" : "[\(shapes.joined(separator: ","))]"
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
        let resolvedInputShape = try Self.multiArrayShape(input.value, name: input.key)
        let resolvedInputElementCount = coreMLProduct(resolvedInputShape)
        let resolvedInputArray = try Self.makeEmptyContiguousFloat32Array(shape: resolvedInputShape)
        let resolvedInputProvider = try MLDictionaryFeatureProvider(
            dictionary: [resolvedInputName: MLFeatureValue(multiArray: resolvedInputArray)]
        )

        var shapes: [String: [Int]] = [:]
        for name in ["up_field", "up_confidence", "latitude_field", "latitude_confidence"] {
            guard let description = model.modelDescription.outputDescriptionsByName[name] else {
                throw AUGeoCalibCoreMLNeuralError.invalidModel("missing output description \(name)")
            }
            shapes[name] = try Self.multiArrayShape(description, name: name)
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

        let inputPointer = inputArray.dataPointer.bindMemory(to: Float.self, capacity: inputElementCount)
        inputRGB.withUnsafeBufferPointer { source in
            inputPointer.update(from: source.baseAddress!, count: inputElementCount)
        }
        let output = try model.prediction(from: inputProvider)

        let upField = try Self.floatArray(from: output, name: "up_field")
        let upConfidence = try Self.floatArray(from: output, name: "up_confidence")
        let latitudeField = try Self.floatArray(from: output, name: "latitude_field")
        let latitudeConfidence = try Self.floatArray(from: output, name: "latitude_confidence")

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
        let zeros = Array(repeating: Float(0), count: coreMLProduct(inputShape))
        _ = try run(inputRGB: zeros, inputShape: inputShape)
    }

    private static func multiArrayShape(_ description: MLFeatureDescription, name: String) throws -> [Int] {
        guard description.type == .multiArray,
              let constraint = description.multiArrayConstraint else {
            throw AUGeoCalibCoreMLNeuralError.invalidModel("\(name) is not a MultiArray")
        }
        guard constraint.dataType == .float32 else {
            throw AUGeoCalibCoreMLNeuralError.invalidModel("\(name) is \(constraint.dataType), expected Float32")
        }
        return constraint.shape.map { $0.intValue }
    }

    private static func makeEmptyContiguousFloat32Array(shape: [Int]) throws -> MLMultiArray {
        let array = try MLMultiArray(shape: shape.map { NSNumber(value: $0) }, dataType: .float32)
        guard contiguousShape(array) == shape else {
            throw AUGeoCalibCoreMLNeuralError.invalidInput("Core ML allocated non-contiguous input array")
        }
        return array
    }

    private static func floatArray(from provider: MLFeatureProvider, name: String) throws -> [Float] {
        guard let multiArray = provider.featureValue(for: name)?.multiArrayValue else {
            throw AUGeoCalibCoreMLNeuralError.missingOutput(name)
        }
        guard multiArray.dataType == .float32 else {
            throw AUGeoCalibCoreMLNeuralError.invalidModel("\(name) is \(multiArray.dataType), expected Float32")
        }
        let shape = multiArray.shape.map { $0.intValue }
        let count = coreMLProduct(shape)
        guard contiguousShape(multiArray) == shape else {
            return stridedFloatArray(from: multiArray, shape: shape)
        }
        let pointer = multiArray.dataPointer.bindMemory(to: Float.self, capacity: count)
        return Array(UnsafeBufferPointer(start: pointer, count: count))
    }

    private static func contiguousShape(_ array: MLMultiArray) -> [Int]? {
        let shape = array.shape.map { $0.intValue }
        let strides = array.strides.map { $0.intValue }
        var expectedStride = 1
        var expected = Array(repeating: 0, count: shape.count)
        for index in stride(from: shape.count - 1, through: 0, by: -1) {
            expected[index] = expectedStride
            expectedStride *= shape[index]
        }
        return strides == expected ? shape : nil
    }

    private static func stridedFloatArray(from array: MLMultiArray, shape: [Int]) -> [Float] {
        let strides = array.strides.map { $0.intValue }
        let pointer = array.dataPointer.bindMemory(to: Float.self, capacity: array.count)
        var output: [Float] = []
        output.reserveCapacity(coreMLProduct(shape))

        func append(axis: Int, offset: Int) {
            if axis == shape.count {
                output.append(pointer[offset])
                return
            }
            for index in 0..<shape[axis] {
                append(axis: axis + 1, offset: offset + index * strides[axis])
            }
        }

        append(axis: 0, offset: 0)
        return output
    }
}

private func geoCalibShapeDescription(_ shape: [Int]) -> String {
    shape.map(String.init).joined(separator: "x")
}

private func coreMLProduct(_ shape: [Int]) -> Int {
    shape.reduce(1, *)
}

private func geoCalibNowNanos() -> UInt64 {
    DispatchTime.now().uptimeNanoseconds
}

private func geoCalibElapsedMilliseconds(since startNanos: UInt64) -> Double {
    Double(geoCalibNowNanos() - startNanos) / 1_000_000.0
}
