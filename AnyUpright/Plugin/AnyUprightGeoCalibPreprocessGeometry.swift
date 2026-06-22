//
//  AnyUprightGeoCalibPreprocessGeometry.swift
//  AnyUpright
//

import Foundation

enum AUGeoCalibPreprocessError: Error, CustomStringConvertible {
    case invalidImage(String)

    var description: String {
        switch self {
        case .invalidImage(let message):
            return "Invalid GeoCalib preprocessing input: \(message)"
        }
    }
}

struct AUGeoCalibInputShapeSpec: Equatable {
    var label: String
    var inputShape: [Int]

    var cropHeight: Int { inputShape[2] }
    var cropWidth: Int { inputShape[3] }
    var aspectRatio: Double { Double(cropWidth) / Double(cropHeight) }
    var modelResourceName: String { "neural_forward_\(cropHeight)x\(cropWidth).mlmodelc" }

    static let production: [AUGeoCalibInputShapeSpec] = [
        AUGeoCalibInputShapeSpec(label: "4:3", inputShape: [1, 3, 320, 416]),
        AUGeoCalibInputShapeSpec(label: "3:4", inputShape: [1, 3, 416, 320]),
        AUGeoCalibInputShapeSpec(label: "16:9", inputShape: [1, 3, 320, 544]),
        AUGeoCalibInputShapeSpec(label: "9:16", inputShape: [1, 3, 544, 320]),
        AUGeoCalibInputShapeSpec(label: "1:1", inputShape: [1, 3, 320, 320]),
        AUGeoCalibInputShapeSpec(label: "3:2", inputShape: [1, 3, 320, 480]),
        AUGeoCalibInputShapeSpec(label: "2:3", inputShape: [1, 3, 480, 320]),
        AUGeoCalibInputShapeSpec(label: "2.35:1", inputShape: [1, 3, 320, 736]),
    ]

    static func closest(toWidth width: Int, height: Int, in candidates: [AUGeoCalibInputShapeSpec] = production) throws -> AUGeoCalibInputShapeSpec {
        guard width > 0, height > 0 else {
            throw AUGeoCalibPreprocessError.invalidImage("source dimensions must be positive")
        }
        guard let best = candidates.min(by: { lhs, rhs in
            let sourceRatio = Double(width) / Double(height)
            let lhsDistance = abs(log(sourceRatio / lhs.aspectRatio))
            let rhsDistance = abs(log(sourceRatio / rhs.aspectRatio))
            return lhsDistance < rhsDistance
        }) else {
            throw AUGeoCalibPreprocessError.invalidImage("no GeoCalib input shapes are configured")
        }
        return best
    }

    static func validateInputShape(_ inputShape: [Int]) throws -> (cropWidth: Int, cropHeight: Int) {
        guard inputShape.count == 4,
              inputShape[0] == 1,
              inputShape[1] == 3,
              inputShape[2] > 0,
              inputShape[3] > 0 else {
            throw AUGeoCalibPreprocessError.invalidImage("invalid target input shape \(inputShape)")
        }
        return (cropWidth: inputShape[3], cropHeight: inputShape[2])
    }
}

struct AUGeoCalibPreprocessGeometry {
    var sourceWidth: Int
    var sourceHeight: Int
    var targetShortSide: Int
    var edgeDivisibleBy: Int
    var resizedWidth: Int
    var resizedHeight: Int
    var cropWidth: Int
    var cropHeight: Int
    var cropLeft: Int
    var cropTop: Int
    var factorX: Double
    var factorY: Double
    var sigmaX: Double
    var sigmaY: Double
    var kernelX: [Float]
    var kernelY: [Float]

    var inputShape: [Int] {
        [1, 3, cropHeight, cropWidth]
    }

    var scales: SIMD2<Float> {
        SIMD2<Float>(
            Float(resizedWidth) / Float(sourceWidth),
            Float(resizedHeight) / Float(sourceHeight)
        )
    }

    var needsAntialias: Bool {
        max(factorX, factorY) > 1.0
    }

    init(
        sourceWidth: Int,
        sourceHeight: Int,
        targetShortSide: Int = 320,
        edgeDivisibleBy: Int = 32,
        targetInputShape: [Int]? = nil
    ) throws {
        guard sourceWidth > 0, sourceHeight > 0 else {
            throw AUGeoCalibPreprocessError.invalidImage("source dimensions must be positive")
        }
        guard targetShortSide > 0, edgeDivisibleBy > 0 else {
            throw AUGeoCalibPreprocessError.invalidImage("preprocessing dimensions must be positive")
        }

        let resized: (width: Int, height: Int)
        let cropWidth: Int
        let cropHeight: Int
        if let targetInputShape {
            let target = try AUGeoCalibInputShapeSpec.validateInputShape(targetInputShape)
            cropWidth = target.cropWidth
            cropHeight = target.cropHeight
            let scale = max(
                Double(cropWidth) / Double(sourceWidth),
                Double(cropHeight) / Double(sourceHeight)
            )
            resized = (
                max(cropWidth, Int(Double(sourceWidth) * scale)),
                max(cropHeight, Int(Double(sourceHeight) * scale))
            )
        } else {
            let aspectRatio = Double(sourceWidth) / Double(sourceHeight)
            if aspectRatio >= 1.0 {
                resized = (Int(Double(targetShortSide) * aspectRatio), targetShortSide)
            } else {
                resized = (targetShortSide, Int(Double(targetShortSide) / aspectRatio))
            }
            cropWidth = max(edgeDivisibleBy, (resized.width / edgeDivisibleBy) * edgeDivisibleBy)
            cropHeight = max(edgeDivisibleBy, (resized.height / edgeDivisibleBy) * edgeDivisibleBy)
        }

        guard cropWidth <= resized.width, cropHeight <= resized.height else {
            throw AUGeoCalibPreprocessError.invalidImage(
                "resized image \(resized.width)x\(resized.height) is too small for \(edgeDivisibleBy)-multiple crop"
            )
        }

        let factorX = Double(sourceWidth) / Double(resized.width)
        let factorY = Double(sourceHeight) / Double(resized.height)
        let sigmaX = max((factorX - 1.0) / 2.0, 0.001)
        let sigmaY = max((factorY - 1.0) / 2.0, 0.001)

        self.sourceWidth = sourceWidth
        self.sourceHeight = sourceHeight
        self.targetShortSide = targetShortSide
        self.edgeDivisibleBy = edgeDivisibleBy
        self.resizedWidth = resized.width
        self.resizedHeight = resized.height
        self.cropWidth = cropWidth
        self.cropHeight = cropHeight
        self.cropLeft = (resized.width - cropWidth + 1) / 2
        self.cropTop = (resized.height - cropHeight + 1) / 2
        self.factorX = factorX
        self.factorY = factorY
        self.sigmaX = sigmaX
        self.sigmaY = sigmaY
        self.kernelX = Self.gaussianKernel(size: Self.antialiasKernelSize(sigmaX), sigma: sigmaX)
        self.kernelY = Self.gaussianKernel(size: Self.antialiasKernelSize(sigmaY), sigma: sigmaY)
    }

    static func antialiasKernelSize(_ sigma: Double) -> Int {
        var size = Int(max(4.0 * sigma, 3.0))
        if size % 2 == 0 {
            size += 1
        }
        return size
    }

    static func gaussianKernel(size: Int, sigma: Double) -> [Float] {
        let mean = Double(size / 2)
        var values: [Double] = []
        values.reserveCapacity(size)
        for index in 0..<size {
            let x = Double(index) - mean
            values.append(exp(-(x * x) / (2.0 * sigma * sigma)))
        }
        let sum = values.reduce(0.0, +)
        return values.map { Float($0 / sum) }
    }
}
