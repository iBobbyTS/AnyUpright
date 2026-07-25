//
//  AnyUprightCoreMLMultiArrayIO.swift
//  AnyUpright
//

import CoreML
import Foundation

struct AUCoreMLFloat32Tensor {
    let values: [Float]
    let shape: [Int]
}

enum AUCoreMLMultiArrayIOError: Error, CustomStringConvertible {
    case notMultiArray(String)
    case wrongDataType(name: String, actual: MLMultiArrayDataType)
    case invalidShape([Int])
    case elementCountOverflow([Int])
    case elementCountMismatch(expected: Int, actual: Int)
    case nonContiguousInput([Int])
    case missingOutput(String)
    case invalidStrides(shape: [Int], strides: [Int])

    var description: String {
        switch self {
        case .notMultiArray(let name):
            return "\(name) is not a MultiArray"
        case .wrongDataType(let name, let actual):
            return "\(name) is \(actual), expected Float32"
        case .invalidShape(let shape):
            return "invalid MultiArray shape \(shape)"
        case .elementCountOverflow(let shape):
            return "MultiArray shape overflows Int: \(shape)"
        case .elementCountMismatch(let expected, let actual):
            return "expected \(expected) floats, got \(actual)"
        case .nonContiguousInput(let shape):
            return "Core ML allocated non-contiguous input array for shape \(shape)"
        case .missingOutput(let name):
            return "missing output \(name)"
        case .invalidStrides(let shape, let strides):
            return "invalid MultiArray strides \(strides) for shape \(shape)"
        }
    }
}

enum AUCoreMLMultiArrayIO {
    static func fixedFloat32Shape(_ description: MLFeatureDescription, name: String) throws -> [Int] {
        guard description.type == .multiArray,
              let constraint = description.multiArrayConstraint else {
            throw AUCoreMLMultiArrayIOError.notMultiArray(name)
        }
        guard constraint.dataType == .float32 else {
            throw AUCoreMLMultiArrayIOError.wrongDataType(name: name, actual: constraint.dataType)
        }
        let shape = constraint.shape.map(\.intValue)
        _ = try elementCount(shape: shape)
        return shape
    }

    static func elementCount(shape: [Int]) throws -> Int {
        guard !shape.isEmpty, shape.allSatisfy({ $0 > 0 }) else {
            throw AUCoreMLMultiArrayIOError.invalidShape(shape)
        }
        var count = 1
        for dimension in shape {
            let (product, overflow) = count.multipliedReportingOverflow(by: dimension)
            guard !overflow else {
                throw AUCoreMLMultiArrayIOError.elementCountOverflow(shape)
            }
            count = product
        }
        return count
    }

    static func makeContiguousFloat32Array(shape: [Int]) throws -> MLMultiArray {
        _ = try elementCount(shape: shape)
        let array = try MLMultiArray(shape: shape.map(NSNumber.init(value:)), dataType: .float32)
        guard array.strides.map(\.intValue) == contiguousStrides(shape: shape) else {
            throw AUCoreMLMultiArrayIOError.nonContiguousInput(shape)
        }
        return array
    }

    static func copyFloat32(_ values: [Float], to array: MLMultiArray) throws {
        guard array.dataType == .float32 else {
            throw AUCoreMLMultiArrayIOError.wrongDataType(name: "input", actual: array.dataType)
        }
        let shape = array.shape.map(\.intValue)
        let expected = try elementCount(shape: shape)
        guard values.count == expected else {
            throw AUCoreMLMultiArrayIOError.elementCountMismatch(expected: expected, actual: values.count)
        }
        guard array.strides.map(\.intValue) == contiguousStrides(shape: shape) else {
            throw AUCoreMLMultiArrayIOError.nonContiguousInput(shape)
        }
        let destination = array.dataPointer.bindMemory(to: Float.self, capacity: expected)
        values.withUnsafeBufferPointer { source in
            guard let baseAddress = source.baseAddress else { return }
            destination.update(from: baseAddress, count: expected)
        }
    }

    static func readFloat32(from provider: MLFeatureProvider, name: String) throws -> AUCoreMLFloat32Tensor {
        guard let array = provider.featureValue(for: name)?.multiArrayValue else {
            throw AUCoreMLMultiArrayIOError.missingOutput(name)
        }
        return try readFloat32(from: array, name: name)
    }

    static func readFloat32(from array: MLMultiArray, name: String = "output") throws -> AUCoreMLFloat32Tensor {
        guard array.dataType == .float32 else {
            throw AUCoreMLMultiArrayIOError.wrongDataType(name: name, actual: array.dataType)
        }
        let shape = array.shape.map(\.intValue)
        let count = try elementCount(shape: shape)
        let strides = array.strides.map(\.intValue)
        guard strides.count == shape.count, strides.allSatisfy({ $0 >= 0 }) else {
            throw AUCoreMLMultiArrayIOError.invalidStrides(shape: shape, strides: strides)
        }
        if strides == contiguousStrides(shape: shape) {
            let pointer = array.dataPointer.bindMemory(to: Float.self, capacity: count)
            return AUCoreMLFloat32Tensor(
                values: Array(UnsafeBufferPointer(start: pointer, count: count)),
                shape: shape
            )
        }

        let maximumOffset = try maximumLogicalOffset(shape: shape, strides: strides)
        let (backingCapacity, capacityOverflow) = maximumOffset.addingReportingOverflow(1)
        guard !capacityOverflow else {
            throw AUCoreMLMultiArrayIOError.invalidStrides(shape: shape, strides: strides)
        }
        let pointer = array.dataPointer.bindMemory(to: Float.self, capacity: backingCapacity)
        var values: [Float] = []
        values.reserveCapacity(count)

        func append(axis: Int, offset: Int) {
            if axis == shape.count {
                values.append(pointer[offset])
                return
            }
            for index in 0..<shape[axis] {
                append(axis: axis + 1, offset: offset + index * strides[axis])
            }
        }
        append(axis: 0, offset: 0)
        return AUCoreMLFloat32Tensor(values: values, shape: shape)
    }

    private static func contiguousStrides(shape: [Int]) -> [Int] {
        var result = Array(repeating: 0, count: shape.count)
        var stride = 1
        for axis in shape.indices.reversed() {
            result[axis] = stride
            stride *= shape[axis]
        }
        return result
    }

    private static func maximumLogicalOffset(shape: [Int], strides: [Int]) throws -> Int {
        var maximum = 0
        for axis in shape.indices {
            let (axisOffset, axisOverflow) = (shape[axis] - 1).multipliedReportingOverflow(by: strides[axis])
            let (sum, sumOverflow) = maximum.addingReportingOverflow(axisOffset)
            guard !axisOverflow, !sumOverflow else {
                throw AUCoreMLMultiArrayIOError.invalidStrides(shape: shape, strides: strides)
            }
            maximum = sum
        }
        return maximum
    }
}
