import CoreML
import Foundation

private enum CoreMLMultiArrayIOTestFailure: Error, CustomStringConvertible {
    case failed(String)
    var description: String {
        switch self { case .failed(let message): return message }
    }
}

@main
struct AnyUprightCoreMLMultiArrayIOTests {
    static func main() throws {
        try testContiguousAllocationCopyAndRead()
        try testElementCountFailures()
        try testWrongTypeAndMissingOutput()
        try testPaddedStrides()
        print("AnyUprightCoreMLMultiArrayIOTests passed")
    }

    private static func testContiguousAllocationCopyAndRead() throws {
        let array = try AUCoreMLMultiArrayIO.makeContiguousFloat32Array(shape: [1, 2, 2])
        try AUCoreMLMultiArrayIO.copyFloat32([1, 2, 3, 4], to: array)
        let tensor = try AUCoreMLMultiArrayIO.readFloat32(from: array)
        try require(tensor.shape == [1, 2, 2], "shape")
        try require(tensor.values == [1, 2, 3, 4], "contiguous values")
        do {
            try AUCoreMLMultiArrayIO.copyFloat32([1], to: array)
            throw CoreMLMultiArrayIOTestFailure.failed("count mismatch must throw")
        } catch AUCoreMLMultiArrayIOError.elementCountMismatch {}
    }

    private static func testElementCountFailures() throws {
        do {
            _ = try AUCoreMLMultiArrayIO.elementCount(shape: [Int.max, 2])
            throw CoreMLMultiArrayIOTestFailure.failed("overflow must throw")
        } catch AUCoreMLMultiArrayIOError.elementCountOverflow {}
        do {
            _ = try AUCoreMLMultiArrayIO.elementCount(shape: [2, 0])
            throw CoreMLMultiArrayIOTestFailure.failed("zero dimension must throw")
        } catch AUCoreMLMultiArrayIOError.invalidShape {}
    }

    private static func testWrongTypeAndMissingOutput() throws {
        let doubleArray = try MLMultiArray(shape: [1], dataType: .double)
        do {
            _ = try AUCoreMLMultiArrayIO.readFloat32(from: doubleArray)
            throw CoreMLMultiArrayIOTestFailure.failed("wrong data type must throw")
        } catch AUCoreMLMultiArrayIOError.wrongDataType {}
        let provider = try MLDictionaryFeatureProvider(dictionary: [:])
        do {
            _ = try AUCoreMLMultiArrayIO.readFloat32(from: provider, name: "missing")
            throw CoreMLMultiArrayIOTestFailure.failed("missing output must throw")
        } catch AUCoreMLMultiArrayIOError.missingOutput {}
    }

    private static func testPaddedStrides() throws {
        let pointer = UnsafeMutablePointer<Float>.allocate(capacity: 5)
        pointer.initialize(repeating: -1, count: 5)
        pointer[0] = 1
        pointer[1] = 2
        pointer[3] = 3
        pointer[4] = 4
        let array = try MLMultiArray(
            dataPointer: UnsafeMutableRawPointer(pointer),
            shape: [2, 2],
            dataType: .float32,
            strides: [3, 1],
            deallocator: { _ in pointer.deallocate() }
        )
        let tensor = try AUCoreMLMultiArrayIO.readFloat32(from: array)
        try require(tensor.values == [1, 2, 3, 4], "padded strides must preserve logical order")
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw CoreMLMultiArrayIOTestFailure.failed(message) }
    }
}
