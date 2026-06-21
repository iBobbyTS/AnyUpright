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

struct AUGeoCalibCoreMLNeuralInferenceSession {
    private let model: MLModel
    private let inputName: String
    private let inputShape: [Int]
    private let outputShapes: [String: [Int]]

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
        inputName = input.key
        inputShape = try Self.multiArrayShape(input.value, name: input.key)

        var shapes: [String: [Int]] = [:]
        for name in ["up_field", "up_confidence", "latitude_field", "latitude_confidence"] {
            guard let description = model.modelDescription.outputDescriptionsByName[name] else {
                throw AUGeoCalibCoreMLNeuralError.invalidModel("missing output description \(name)")
            }
            shapes[name] = try Self.multiArrayShape(description, name: name)
        }
        outputShapes = shapes
    }

    func run(inputRGB: [Float], inputShape requestedShape: [Int]) throws -> AUGeoCalibNeuralOutput {
        guard requestedShape == inputShape else {
            throw AUGeoCalibCoreMLNeuralError.invalidInput(
                "expected input shape \(inputShape), got \(requestedShape)"
            )
        }
        guard inputRGB.count == product(inputShape) else {
            throw AUGeoCalibCoreMLNeuralError.invalidInput(
                "expected \(product(inputShape)) floats, got \(inputRGB.count)"
            )
        }

        let inputArray = try Self.makeContiguousFloat32Array(values: inputRGB, shape: inputShape)
        let provider = try MLDictionaryFeatureProvider(
            dictionary: [inputName: MLFeatureValue(multiArray: inputArray)]
        )
        let output = try model.prediction(from: provider)

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

    private static func makeContiguousFloat32Array(values: [Float], shape: [Int]) throws -> MLMultiArray {
        let array = try MLMultiArray(shape: shape.map { NSNumber(value: $0) }, dataType: .float32)
        guard contiguousShape(array) == shape else {
            throw AUGeoCalibCoreMLNeuralError.invalidInput("Core ML allocated non-contiguous input array")
        }
        let pointer = array.dataPointer.bindMemory(to: Float.self, capacity: values.count)
        values.withUnsafeBufferPointer { source in
            pointer.update(from: source.baseAddress!, count: values.count)
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
