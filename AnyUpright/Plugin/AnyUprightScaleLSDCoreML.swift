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
        inputName = input.key
        inputShape = try Self.multiArrayShape(input.value, name: input.key)
        inputElementCount = inputShape.reduce(1, *)
        guard inputShape == [1, 1, 512, 512] else {
            throw AUScaleLSDCoreMLError.invalidModel("expected [1, 1, 512, 512] input, got \(inputShape)")
        }
        inputArray = try MLMultiArray(shape: inputShape.map(NSNumber.init(value:)), dataType: .float32)
        inputProvider = try MLDictionaryFeatureProvider(dictionary: [inputName: MLFeatureValue(multiArray: inputArray)])

        guard let output = model.modelDescription.outputDescriptionsByName.first(where: { description in
            guard description.value.type == .multiArray,
                  let shape = try? Self.multiArrayShape(description.value, name: description.key) else {
                return false
            }
            return shape == [1, 9, 256, 256]
        }) else {
            throw AUScaleLSDCoreMLError.invalidModel("expected [1, 9, 256, 256] MultiArray output")
        }
        outputName = output.key
    }

    func run(inputNCHW: [Float]) throws -> AUScaleLSDCoreMLOutput {
        guard inputNCHW.count == inputElementCount else {
            throw AUScaleLSDCoreMLError.invalidInput(expected: inputElementCount, actual: inputNCHW.count)
        }
        predictionLock.lock()
        defer { predictionLock.unlock() }

        let inputPointer = inputArray.dataPointer.bindMemory(to: Float.self, capacity: inputElementCount)
        inputNCHW.withUnsafeBufferPointer { source in
            inputPointer.update(from: source.baseAddress!, count: inputElementCount)
        }
        let prediction = try model.prediction(from: inputProvider)
        guard let output = prediction.featureValue(for: outputName)?.multiArrayValue else {
            throw AUScaleLSDCoreMLError.missingOutput(outputName)
        }
        return AUScaleLSDCoreMLOutput(
            values: try Self.floatArray(from: output),
            shape: output.shape.map(\.intValue)
        )
    }

    private static func multiArrayShape(_ description: MLFeatureDescription, name: String) throws -> [Int] {
        guard description.type == .multiArray,
              let constraint = description.multiArrayConstraint else {
            throw AUScaleLSDCoreMLError.invalidModel("\(name) is not a MultiArray")
        }
        guard constraint.dataType == .float32 else {
            throw AUScaleLSDCoreMLError.invalidModel("\(name) is \(constraint.dataType), expected Float32")
        }
        return constraint.shape.map(\.intValue)
    }

    private static func floatArray(from array: MLMultiArray) throws -> [Float] {
        guard array.dataType == .float32 else {
            throw AUScaleLSDCoreMLError.invalidModel("output is \(array.dataType), expected Float32")
        }
        let shape = array.shape.map(\.intValue)
        let count = shape.reduce(1, *)
        let strides = array.strides.map(\.intValue)
        var expectedStride = 1
        var contiguousStrides = Array(repeating: 0, count: shape.count)
        for axis in stride(from: shape.count - 1, through: 0, by: -1) {
            contiguousStrides[axis] = expectedStride
            expectedStride *= shape[axis]
        }
        let pointer = array.dataPointer.bindMemory(to: Float.self, capacity: array.count)
        if strides == contiguousStrides {
            return Array(UnsafeBufferPointer(start: pointer, count: count))
        }

        var result: [Float] = []
        result.reserveCapacity(count)
        func append(axis: Int, offset: Int) {
            if axis == shape.count {
                result.append(pointer[offset])
                return
            }
            for index in 0..<shape[axis] {
                append(axis: axis + 1, offset: offset + index * strides[axis])
            }
        }
        append(axis: 0, offset: 0)
        return result
    }
}
