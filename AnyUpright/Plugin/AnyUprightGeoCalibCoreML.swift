//
//  AnyUprightGeoCalibCoreML.swift
//  AnyUpright
//

import CoreML
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

struct AUGeoCalibCoreMLNeuralInferenceRouter {
    private var sessionsByShape: [[Int]: AUGeoCalibCoreMLNeuralInferenceSession] = [:]

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
        let resolvedInputElementCount = product(resolvedInputShape)
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
        let zeros = Array(repeating: Float(0), count: product(inputShape))
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
        let count = product(shape)
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
        output.reserveCapacity(product(shape))

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
