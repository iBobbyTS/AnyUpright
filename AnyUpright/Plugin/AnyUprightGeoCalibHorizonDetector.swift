//
//  AnyUprightGeoCalibHorizonDetector.swift
//  AnyUpright
//

import Foundation

struct AUGeoCalibPreprocessedImage {
    var inputRGBNCHW: [Float]
    var inputShape: [Int]
    var scales: SIMD2<Float>
}

struct AUGeoCalibHorizonVerifierEstimate {
    var name: String
    var rollRadians: Double?
    var confidence: Double
    var sampleCount: Int
}

struct AUGeoCalibHorizonVerifierDiff {
    var name: String
    var differenceRadians: Double?
    var disagrees: Bool
}

struct AUGeoCalibHorizonDetectorConfiguration {
    var maxRollUncertaintyRadians = 3.0 * .pi / 180.0
    var maxVerifierDifferenceRadians = 10.0 * .pi / 180.0
    var rejectDisagreementCount = 2
    var maxCorrectionRadians = 45.0 * .pi / 180.0
}

struct AUGeoCalibHorizonDetectionResult {
    var rollRadians: Double
    var correctionRadians: Double
    var rollUncertaintyRadians: Double
    var accepted: Bool
    var rejectionReasons: [String]
    var verifierDiffs: [AUGeoCalibHorizonVerifierDiff]
    var optimizerResult: AUGeoCalibOptimizerResult
}

enum AUGeoCalibHorizonDetectorError: Error, CustomStringConvertible {
    case invalidImage(String)
    case invalidNeuralOutput(String)

    var description: String {
        switch self {
        case .invalidImage(let message):
            return "Invalid GeoCalib preprocessing input: \(message)"
        case .invalidNeuralOutput(let message):
            return "Invalid GeoCalib neural output: \(message)"
        }
    }
}

enum AUGeoCalibImagePreprocessor {
    static func preprocessRGB(
        _ inputRGBNCHW: [Float],
        width: Int,
        height: Int,
        targetShortSide: Int = 320,
        edgeDivisibleBy: Int = 32
    ) throws -> AUGeoCalibPreprocessedImage {
        guard width > 0, height > 0 else {
            throw AUGeoCalibHorizonDetectorError.invalidImage("source dimensions must be positive")
        }
        guard targetShortSide > 0, edgeDivisibleBy > 0 else {
            throw AUGeoCalibHorizonDetectorError.invalidImage("preprocessing dimensions must be positive")
        }
        guard inputRGBNCHW.count == 3 * width * height else {
            throw AUGeoCalibHorizonDetectorError.invalidImage(
                "expected 3x\(height)x\(width) RGB tensor, got \(inputRGBNCHW.count) values"
            )
        }

        let resizedSize = resizedShortSideSize(width: width, height: height, targetShortSide: targetShortSide)
        var working = inputRGBNCHW
        let factorY = Double(height) / Double(resizedSize.height)
        let factorX = Double(width) / Double(resizedSize.width)
        if max(factorY, factorX) > 1.0 {
            working = gaussianBlurForAntialias(
                working,
                width: width,
                height: height,
                sigmaY: max((factorY - 1.0) / 2.0, 0.001),
                sigmaX: max((factorX - 1.0) / 2.0, 0.001)
            )
        }

        let cropWidth = max(edgeDivisibleBy, (resizedSize.width / edgeDivisibleBy) * edgeDivisibleBy)
        let cropHeight = max(edgeDivisibleBy, (resizedSize.height / edgeDivisibleBy) * edgeDivisibleBy)
        guard cropWidth <= resizedSize.width, cropHeight <= resizedSize.height else {
            throw AUGeoCalibHorizonDetectorError.invalidImage(
                "resized image \(resizedSize.width)x\(resizedSize.height) is too small for \(edgeDivisibleBy)-multiple crop"
            )
        }

        let cropped = bilinearResizeCenterCrop(
            working,
            sourceWidth: width,
            sourceHeight: height,
            resizedWidth: resizedSize.width,
            resizedHeight: resizedSize.height,
            cropWidth: cropWidth,
            cropHeight: cropHeight
        )
        return AUGeoCalibPreprocessedImage(
            inputRGBNCHW: cropped,
            inputShape: [1, 3, cropHeight, cropWidth],
            scales: SIMD2<Float>(
                Float(resizedSize.width) / Float(width),
                Float(resizedSize.height) / Float(height)
            )
        )
    }

    private static func resizedShortSideSize(width: Int, height: Int, targetShortSide: Int) -> (width: Int, height: Int) {
        let aspectRatio = Double(width) / Double(height)
        if aspectRatio >= 1.0 {
            return (Int(Double(targetShortSide) * aspectRatio), targetShortSide)
        }
        return (targetShortSide, Int(Double(targetShortSide) / aspectRatio))
    }

    private struct ResizeAxisSample {
        var lower: Int
        var upper: Int
        var upperWeight: Float
    }

    private static func gaussianBlurForAntialias(
        _ input: [Float],
        width: Int,
        height: Int,
        sigmaY: Double,
        sigmaX: Double
    ) -> [Float] {
        let kernelY = gaussianKernel(size: antialiasKernelSize(sigmaY), sigma: sigmaY)
        let kernelX = gaussianKernel(size: antialiasKernelSize(sigmaX), sigma: sigmaX)
        var horizontal = Array(repeating: Float(0), count: input.count)
        var output = Array(repeating: Float(0), count: input.count)
        let radiusX = kernelX.count / 2
        let radiusY = kernelY.count / 2
        var xIndices = Array(repeating: 0, count: width * kernelX.count)
        var yIndices = Array(repeating: 0, count: height * kernelY.count)

        var x = 0
        while x < width {
            var k = 0
            while k < kernelX.count {
                xIndices[x * kernelX.count + k] = reflect101(x + k - radiusX, length: width)
                k += 1
            }
            x += 1
        }

        var y = 0
        while y < height {
            var k = 0
            while k < kernelY.count {
                yIndices[y * kernelY.count + k] = reflect101(y + k - radiusY, length: height)
                k += 1
            }
            y += 1
        }

        input.withUnsafeBufferPointer { inputBuffer in
            horizontal.withUnsafeMutableBufferPointer { horizontalBuffer in
                DispatchQueue.concurrentPerform(iterations: 3) { channel in
                    let channelOffset = channel * width * height
                    var y = 0
                    while y < height {
                        let rowOffset = channelOffset + y * width
                        var x = 0
                        while x < width {
                            var sum = Float(0)
                            let indexOffset = x * kernelX.count
                            var k = 0
                            while k < kernelX.count {
                                sum += inputBuffer[rowOffset + xIndices[indexOffset + k]] * kernelX[k]
                                k += 1
                            }
                            horizontalBuffer[rowOffset + x] = sum
                            x += 1
                        }
                        y += 1
                    }
                }
            }
        }

        horizontal.withUnsafeBufferPointer { horizontalBuffer in
            output.withUnsafeMutableBufferPointer { outputBuffer in
                DispatchQueue.concurrentPerform(iterations: 3) { channel in
                    let channelOffset = channel * width * height
                    var y = 0
                    while y < height {
                        let rowOffset = channelOffset + y * width
                        let indexOffset = y * kernelY.count
                        var x = 0
                        while x < width {
                            var sum = Float(0)
                            var k = 0
                            while k < kernelY.count {
                                sum += horizontalBuffer[channelOffset + yIndices[indexOffset + k] * width + x] * kernelY[k]
                                k += 1
                            }
                            outputBuffer[rowOffset + x] = sum
                            x += 1
                        }
                        y += 1
                    }
                }
            }
        }
        return output
    }

    private static func antialiasKernelSize(_ sigma: Double) -> Int {
        var size = Int(max(4.0 * sigma, 3.0))
        if size % 2 == 0 {
            size += 1
        }
        return size
    }

    private static func gaussianKernel(size: Int, sigma: Double) -> [Float] {
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

    private static func bilinearResizeCenterCrop(
        _ input: [Float],
        sourceWidth: Int,
        sourceHeight: Int,
        resizedWidth: Int,
        resizedHeight: Int,
        cropWidth: Int,
        cropHeight: Int
    ) -> [Float] {
        let cropLeft = (resizedWidth - cropWidth + 1) / 2
        let cropTop = (resizedHeight - cropHeight + 1) / 2
        let xSamples = resizeAxisSamples(
            sourceSize: sourceWidth,
            resizedSize: resizedWidth,
            cropStart: cropLeft,
            cropSize: cropWidth
        )
        let ySamples = resizeAxisSamples(
            sourceSize: sourceHeight,
            resizedSize: resizedHeight,
            cropStart: cropTop,
            cropSize: cropHeight
        )
        var output = Array(repeating: Float(0), count: 3 * cropWidth * cropHeight)

        input.withUnsafeBufferPointer { inputBuffer in
            output.withUnsafeMutableBufferPointer { outputBuffer in
                DispatchQueue.concurrentPerform(iterations: 3) { channel in
                    let sourceChannel = channel * sourceWidth * sourceHeight
                    let outputChannel = channel * cropWidth * cropHeight
                    for y in 0..<cropHeight {
                        let ySample = ySamples[y]
                        let row0 = sourceChannel + ySample.lower * sourceWidth
                        let row1 = sourceChannel + ySample.upper * sourceWidth
                        let wy = ySample.upperWeight
                        let inverseWY = 1.0 - wy
                        for x in 0..<cropWidth {
                            let xSample = xSamples[x]
                            let wx = xSample.upperWeight
                            let inverseWX = 1.0 - wx
                            let top = inputBuffer[row0 + xSample.lower] * inverseWX +
                                inputBuffer[row0 + xSample.upper] * wx
                            let bottom = inputBuffer[row1 + xSample.lower] * inverseWX +
                                inputBuffer[row1 + xSample.upper] * wx
                            outputBuffer[outputChannel + y * cropWidth + x] = top * inverseWY + bottom * wy
                        }
                    }
                }
            }
        }
        return output
    }

    private static func resizeAxisSamples(
        sourceSize: Int,
        resizedSize: Int,
        cropStart: Int,
        cropSize: Int
    ) -> [ResizeAxisSample] {
        let scale = Double(sourceSize) / Double(resizedSize)
        var samples: [ResizeAxisSample] = []
        samples.reserveCapacity(cropSize)
        for index in 0..<cropSize {
            let resizedIndex = cropStart + index
            let source = (Double(resizedIndex) + 0.5) * scale - 0.5
            let floorIndex = Int(floor(source))
            samples.append(ResizeAxisSample(
                lower: clamp(floorIndex, lower: 0, upper: sourceSize - 1),
                upper: clamp(floorIndex + 1, lower: 0, upper: sourceSize - 1),
                upperWeight: Float(source - Double(floorIndex))
            ))
        }
        return samples
    }
}

enum AUGeoCalibHorizonDetector {
    static func detect(
        preprocessedImage: AUGeoCalibPreprocessedImage,
        runtimeBundle: AUGeoCalibRuntimeBundle,
        metalSource: URL,
        verifierEstimates: [AUGeoCalibHorizonVerifierEstimate] = [],
        configuration: AUGeoCalibHorizonDetectorConfiguration = AUGeoCalibHorizonDetectorConfiguration()
    ) throws -> AUGeoCalibHorizonDetectionResult {
        let neuralOutput = try AUGeoCalibNeuralInference.run(
            inputRGB: preprocessedImage.inputRGBNCHW,
            inputShape: preprocessedImage.inputShape,
            runtimeBundle: runtimeBundle,
            metalSource: metalSource
        )
        return try optimizeAndGate(
            neuralOutput: neuralOutput,
            scales: preprocessedImage.scales,
            verifierEstimates: verifierEstimates,
            configuration: configuration
        )
    }

    static func detect(
        preprocessedImage: AUGeoCalibPreprocessedImage,
        runtimeBundle: AUGeoCalibRuntimeBundle,
        metalLibraryURL: URL,
        verifierEstimates: [AUGeoCalibHorizonVerifierEstimate] = [],
        configuration: AUGeoCalibHorizonDetectorConfiguration = AUGeoCalibHorizonDetectorConfiguration()
    ) throws -> AUGeoCalibHorizonDetectionResult {
        let neuralOutput = try AUGeoCalibNeuralInference.run(
            inputRGB: preprocessedImage.inputRGBNCHW,
            inputShape: preprocessedImage.inputShape,
            runtimeBundle: runtimeBundle,
            metalLibraryURL: metalLibraryURL
        )
        return try optimizeAndGate(
            neuralOutput: neuralOutput,
            scales: preprocessedImage.scales,
            verifierEstimates: verifierEstimates,
            configuration: configuration
        )
    }

    static func detect(
        preprocessedImage: AUGeoCalibPreprocessedImage,
        neuralSession: AUGeoCalibNeuralInferenceSession,
        verifierEstimates: [AUGeoCalibHorizonVerifierEstimate] = [],
        configuration: AUGeoCalibHorizonDetectorConfiguration = AUGeoCalibHorizonDetectorConfiguration()
    ) throws -> AUGeoCalibHorizonDetectionResult {
        let neuralOutput = try neuralSession.run(
            inputRGB: preprocessedImage.inputRGBNCHW,
            inputShape: preprocessedImage.inputShape
        )
        return try optimizeAndGate(
            neuralOutput: neuralOutput,
            scales: preprocessedImage.scales,
            verifierEstimates: verifierEstimates,
            configuration: configuration
        )
    }

    static func detect(
        preprocessedImage: AUGeoCalibPreprocessedImage,
        neuralOutput: AUGeoCalibNeuralOutput,
        verifierEstimates: [AUGeoCalibHorizonVerifierEstimate] = [],
        configuration: AUGeoCalibHorizonDetectorConfiguration = AUGeoCalibHorizonDetectorConfiguration()
    ) throws -> AUGeoCalibHorizonDetectionResult {
        try optimizeAndGate(
            neuralOutput: neuralOutput,
            scales: preprocessedImage.scales,
            verifierEstimates: verifierEstimates,
            configuration: configuration
        )
    }

    static func gate(
        rollRadians: Double,
        rollUncertaintyRadians: Double,
        verifierEstimates: [AUGeoCalibHorizonVerifierEstimate],
        configuration: AUGeoCalibHorizonDetectorConfiguration = AUGeoCalibHorizonDetectorConfiguration()
    ) -> (accepted: Bool, reasons: [String], diffs: [AUGeoCalibHorizonVerifierDiff]) {
        let correctionRadians = -rollRadians
        var reasons: [String] = []

        if !rollRadians.isFinite || !rollUncertaintyRadians.isFinite {
            reasons.append("non_finite_geocalib_result")
        }
        if rollUncertaintyRadians > configuration.maxRollUncertaintyRadians {
            reasons.append("roll_uncertainty_gt_3deg")
        }
        if abs(correctionRadians) > configuration.maxCorrectionRadians {
            reasons.append("correction_gt_45deg")
        }

        let diffs = verifierEstimates.map { verifier -> AUGeoCalibHorizonVerifierDiff in
            guard let verifierRoll = verifier.rollRadians, verifierRoll.isFinite else {
                return AUGeoCalibHorizonVerifierDiff(name: verifier.name, differenceRadians: nil, disagrees: false)
            }
            let difference = abs(wrapRadians(rollRadians - verifierRoll))
            return AUGeoCalibHorizonVerifierDiff(
                name: verifier.name,
                differenceRadians: difference,
                disagrees: difference > configuration.maxVerifierDifferenceRadians
            )
        }
        let disagreementCount = diffs.filter(\.disagrees).count
        if disagreementCount >= configuration.rejectDisagreementCount {
            reasons.append("two_verifier_disagreements_gt_10deg")
        }

        return (reasons.isEmpty, reasons, diffs)
    }

    private static func optimizeAndGate(
        neuralOutput: AUGeoCalibNeuralOutput,
        scales: SIMD2<Float>,
        verifierEstimates: [AUGeoCalibHorizonVerifierEstimate],
        configuration: AUGeoCalibHorizonDetectorConfiguration
    ) throws -> AUGeoCalibHorizonDetectionResult {
        guard neuralOutput.fieldShape.count == 4,
              neuralOutput.fieldShape[0] == 1,
              neuralOutput.fieldShape[1] == 2,
              neuralOutput.confidenceShape == [1, 1, neuralOutput.fieldShape[2], neuralOutput.fieldShape[3]] else {
            throw AUGeoCalibHorizonDetectorError.invalidNeuralOutput("unexpected dense field shapes")
        }

        let fields = AUGeoCalibDenseFields(
            width: neuralOutput.fieldShape[3],
            height: neuralOutput.fieldShape[2],
            upFieldNCHW: neuralOutput.upField,
            upConfidenceNCHW: neuralOutput.upConfidence,
            latitudeFieldNCHW: neuralOutput.latitudeField,
            latitudeConfidenceNCHW: neuralOutput.latitudeConfidence,
            scales: scales
        )
        let optimizerResult = try AUGeoCalibOptimizer.optimize(fields: fields)
        let decision = gate(
            rollRadians: optimizerResult.rollRadians,
            rollUncertaintyRadians: optimizerResult.rollUncertaintyRadians,
            verifierEstimates: verifierEstimates,
            configuration: configuration
        )
        return AUGeoCalibHorizonDetectionResult(
            rollRadians: optimizerResult.rollRadians,
            correctionRadians: -optimizerResult.rollRadians,
            rollUncertaintyRadians: optimizerResult.rollUncertaintyRadians,
            accepted: decision.accepted,
            rejectionReasons: decision.reasons,
            verifierDiffs: decision.diffs,
            optimizerResult: optimizerResult
        )
    }
}

enum AUGeoCalibHorizonVerifiers {
    private struct EdgePixel {
        var x: Int
        var y: Int
    }

    private struct HoughPeak {
        var angleDegrees: Double
        var rho: Double
        var thetaIndex: Int
        var rhoIndex: Int
        var votes: Int
    }

    private struct ProjectedEdge {
        var projection: Double
        var x: Double
        var y: Double
    }

    static func axisHough(in image: AUGrayscaleImage) -> AUGeoCalibHorizonVerifierEstimate {
        let houghImage = boundedVerifierImage(image, maximumDimension: 640)
        let lines = probabilisticHoughLines(in: houghImage)
        let estimate = estimateAxisFromLines(lines)
        return AUGeoCalibHorizonVerifierEstimate(
            name: "axis_hough",
            rollRadians: estimate.rollRadians,
            confidence: estimate.confidence,
            sampleCount: lines.count
        )
    }

    static func gradientAxis(in image: AUGrayscaleImage) -> AUGeoCalibHorizonVerifierEstimate {
        guard image.width > 0, image.height > 0, image.pixels.count == image.width * image.height else {
            return AUGeoCalibHorizonVerifierEstimate(name: "gradient_axis", rollRadians: nil, confidence: 0, sampleCount: 0)
        }

        let blurred = blurred5x5(image)
        var magnitudes: [Double] = []
        var tangents: [Double] = []
        magnitudes.reserveCapacity(image.width * image.height)
        tangents.reserveCapacity(image.width * image.height)

        for y in 0..<image.height {
            for x in 0..<image.width {
                let p00 = grayValue(blurred, x: x - 1, y: y - 1)
                let p01 = grayValue(blurred, x: x, y: y - 1)
                let p02 = grayValue(blurred, x: x + 1, y: y - 1)
                let p10 = grayValue(blurred, x: x - 1, y: y)
                let p12 = grayValue(blurred, x: x + 1, y: y)
                let p20 = grayValue(blurred, x: x - 1, y: y + 1)
                let p21 = grayValue(blurred, x: x, y: y + 1)
                let p22 = grayValue(blurred, x: x + 1, y: y + 1)
                let gx = -p00 + p02 - 2.0 * p10 + 2.0 * p12 - p20 + p22
                let gy = -p00 - 2.0 * p01 - p02 + p20 + 2.0 * p21 + p22
                let magnitude = hypot(gx, gy)
                let normalDegrees = atan2(gy, gx) * 180.0 / .pi
                magnitudes.append(magnitude)
                tangents.append(normalizedAngleDegrees(normalDegrees))
            }
        }

        let threshold = max(25.0, percentile(magnitudes.sorted(), percent: 90.0) ?? 25.0)
        var candidates: [Double] = []
        var weights: [Double] = []
        var sampleCount = 0
        for index in magnitudes.indices where magnitudes[index] >= threshold {
            sampleCount += 1
            appendAxisCandidate(angleDegrees: tangents[index], strength: magnitudes[index], candidates: &candidates, weights: &weights)
        }
        let estimate = weightedAxisEstimate(candidates: candidates, weights: weights)
        return AUGeoCalibHorizonVerifierEstimate(
            name: "gradient_axis",
            rollRadians: estimate.rollRadians,
            confidence: estimate.confidence,
            sampleCount: sampleCount
        )
    }

    private static func estimateAxisFromLines(_ lines: [AULineSegment]) -> (rollRadians: Double?, confidence: Double) {
        var candidates: [Double] = []
        var weights: [Double] = []
        for line in lines {
            let angle = lineAngleDegrees(line)
            appendAxisCandidate(angleDegrees: angle, strength: line.length, candidates: &candidates, weights: &weights)
        }
        return weightedAxisEstimate(candidates: candidates, weights: weights)
    }

    private static func opencvLikeHoughLines(in image: AUGrayscaleImage) -> [AULineSegment] {
        guard image.width >= 3,
              image.height >= 3,
              image.pixels.count == image.width * image.height else {
            return []
        }

        let blurred = blurred5x5(image)
        let edges = cannyLikeEdges(in: blurred, lowThreshold: 50.0, highThreshold: 150.0)
        guard !edges.isEmpty else {
            return []
        }

        let minDimension = min(image.width, image.height)
        let minLineLength = max(32.0, Double(Int(Double(minDimension) * 0.075)))
        let maxLineGap = max(6.0, Double(Int(Double(minDimension) * 0.015)))
        let voteThreshold = max(35, Int(Double(minDimension) * 0.08))
        let diagonal = hypot(Double(image.width), Double(image.height))
        let rhoMin = -diagonal
        let rhoCount = Int(ceil(diagonal * 2.0)) + 1
        let lineAngles = (-90..<90).map(Double.init)
        let directions = lineAngles.map { degrees -> (dx: Double, dy: Double, nx: Double, ny: Double) in
            let radians = degrees * .pi / 180.0
            let dx = cos(radians)
            let dy = sin(radians)
            return (dx, dy, -dy, dx)
        }
        var accumulator = Array(repeating: 0, count: lineAngles.count * rhoCount)

        for edge in edges {
            let x = Double(edge.x)
            let y = Double(edge.y)
            for index in directions.indices {
                let direction = directions[index]
                let rho = x * direction.nx + y * direction.ny
                let rhoIndex = Int(round(rho - rhoMin))
                if rhoIndex >= 0 && rhoIndex < rhoCount {
                    accumulator[index * rhoCount + rhoIndex] += 1
                }
            }
        }

        var peaks: [HoughPeak] = []
        for thetaIndex in lineAngles.indices {
            for rhoIndex in 0..<rhoCount {
                let votes = accumulator[thetaIndex * rhoCount + rhoIndex]
                if votes >= voteThreshold {
                    peaks.append(HoughPeak(
                        angleDegrees: lineAngles[thetaIndex],
                        rho: rhoMin + Double(rhoIndex),
                        thetaIndex: thetaIndex,
                        rhoIndex: rhoIndex,
                        votes: votes
                    ))
                }
            }
        }
        peaks.sort { lhs, rhs in
            if lhs.votes == rhs.votes {
                return abs(lhs.angleDegrees) < abs(rhs.angleDegrees)
            }
            return lhs.votes > rhs.votes
        }

        var selected: [HoughPeak] = []
        let rhoSuppressionRadius = max(4, Int(maxLineGap.rounded()))
        for peak in peaks {
            let overlaps = selected.contains { existing in
                abs(normalizedAngleDegrees(peak.angleDegrees - existing.angleDegrees)) <= 2.0 &&
                    abs(peak.rhoIndex - existing.rhoIndex) <= rhoSuppressionRadius
            }
            if overlaps {
                continue
            }
            selected.append(peak)
            if selected.count >= 256 {
                break
            }
        }

        return selected.compactMap { peak in
            lineSegment(for: peak, edges: edges, directions: directions, minLineLength: minLineLength, maxLineGap: maxLineGap)
        }
    }

    private static func probabilisticHoughLines(in image: AUGrayscaleImage) -> [AULineSegment] {
        guard image.width >= 3,
              image.height >= 3,
              image.pixels.count == image.width * image.height else {
            return []
        }

        let blurred = blurred5x5(image)
        let edges = cannyLikeEdges(in: blurred, lowThreshold: 50.0, highThreshold: 150.0)
        guard !edges.isEmpty else {
            return []
        }

        let minDimension = min(image.width, image.height)
        let minLineLength = max(32.0, Double(Int(Double(minDimension) * 0.075)))
        let maxLineGap = max(6.0, Double(Int(Double(minDimension) * 0.015)))
        let voteThreshold = max(35, Int(Double(minDimension) * 0.08))
        let rhoMax = image.width + image.height
        let rhoCount = rhoMax * 2 + 1
        let rhoOffset = rhoMax
        let normalAngles = (0..<180).map { Double($0) * .pi / 180.0 }
        let trig = normalAngles.map { (cos($0), sin($0)) }
        var accumulator = Array(repeating: 0, count: normalAngles.count * rhoCount)
        var active = Array(repeating: false, count: image.width * image.height)
        for edge in edges {
            active[edge.y * image.width + edge.x] = true
        }

        var lines: [AULineSegment] = []
        lines.reserveCapacity(128)
        for point in shuffledEdges(edges) {
            let pointIndex = point.y * image.width + point.x
            if !active[pointIndex] {
                continue
            }

            var bestThetaIndex = 0
            var bestVotes = 0
            for thetaIndex in trig.indices {
                let value = trig[thetaIndex]
                let rhoIndex = Int(round(Double(point.x) * value.0 + Double(point.y) * value.1)) + rhoOffset
                if rhoIndex >= 0 && rhoIndex < rhoCount {
                    let accumulatorIndex = thetaIndex * rhoCount + rhoIndex
                    accumulator[accumulatorIndex] += 1
                    if accumulator[accumulatorIndex] > bestVotes {
                        bestVotes = accumulator[accumulatorIndex]
                        bestThetaIndex = thetaIndex
                    }
                }
            }
            if bestVotes < voteThreshold {
                continue
            }

            guard let segment = probabilisticSegment(
                from: point,
                thetaIndex: bestThetaIndex,
                normalAngles: normalAngles,
                active: active,
                width: image.width,
                height: image.height,
                minLineLength: minLineLength,
                maxLineGap: maxLineGap
            ) else {
                continue
            }

            lines.append(segment)
            removeSegmentSupport(
                segment,
                active: &active,
                accumulator: &accumulator,
                trig: trig,
                rhoOffset: rhoOffset,
                rhoCount: rhoCount,
                width: image.width,
                height: image.height
            )
            if lines.count >= 512 {
                break
            }
        }

        if lines.isEmpty {
            return opencvLikeHoughLines(in: image)
        }
        return lines
    }

    private static func shuffledEdges(_ edges: [EdgePixel]) -> [EdgePixel] {
        var result = edges
        var state: UInt64 = 0xffff_ffff
        if result.count > 1 {
            for index in stride(from: result.count - 1, through: 1, by: -1) {
                state = state &* 6364136223846793005 &+ 1442695040888963407
                let swapIndex = Int(state % UInt64(index + 1))
                result.swapAt(index, swapIndex)
            }
        }
        return result
    }

    private static func probabilisticSegment(
        from point: EdgePixel,
        thetaIndex: Int,
        normalAngles: [Double],
        active: [Bool],
        width: Int,
        height: Int,
        minLineLength: Double,
        maxLineGap: Double
    ) -> AULineSegment? {
        let lineAngle = normalAngles[thetaIndex] - .pi / 2.0
        let dx = cos(lineAngle)
        let dy = sin(lineAngle)
        let stepScale = max(abs(dx), abs(dy))
        guard stepScale > 0.0 else {
            return nil
        }
        let stepX = dx / stepScale
        let stepY = dy / stepScale

        func walk(sign: Double) -> EdgePixel {
            var x = Double(point.x)
            var y = Double(point.y)
            var gap = 0
            var last = point
            while true {
                x += stepX * sign
                y += stepY * sign
                let ix = Int(round(x))
                let iy = Int(round(y))
                if ix < 0 || ix >= width || iy < 0 || iy >= height {
                    break
                }
                if active[iy * width + ix] {
                    gap = 0
                    last = EdgePixel(x: ix, y: iy)
                } else {
                    gap += 1
                    if Double(gap) > maxLineGap {
                        break
                    }
                }
            }
            return last
        }

        let first = walk(sign: -1.0)
        let second = walk(sign: 1.0)
        let length = hypot(Double(second.x - first.x), Double(second.y - first.y))
        guard length >= minLineLength else {
            return nil
        }
        return AULineSegment(
            start: AUPoint(x: Double(first.x), y: Double(first.y)),
            end: AUPoint(x: Double(second.x), y: Double(second.y))
        )
    }

    private static func removeSegmentSupport(
        _ segment: AULineSegment,
        active: inout [Bool],
        accumulator: inout [Int],
        trig: [(Double, Double)],
        rhoOffset: Int,
        rhoCount: Int,
        width: Int,
        height: Int
    ) {
        let dx = segment.end.x - segment.start.x
        let dy = segment.end.y - segment.start.y
        let stepCount = max(1, Int(ceil(max(abs(dx), abs(dy)))))
        for step in 0...stepCount {
            let t = Double(step) / Double(stepCount)
            let x = Int(round(segment.start.x * (1.0 - t) + segment.end.x * t))
            let y = Int(round(segment.start.y * (1.0 - t) + segment.end.y * t))
            if x < 0 || x >= width || y < 0 || y >= height {
                continue
            }
            let index = y * width + x
            if !active[index] {
                continue
            }
            active[index] = false
            for thetaIndex in trig.indices {
                let value = trig[thetaIndex]
                let rhoIndex = Int(round(Double(x) * value.0 + Double(y) * value.1)) + rhoOffset
                if rhoIndex >= 0 && rhoIndex < rhoCount {
                    let accumulatorIndex = thetaIndex * rhoCount + rhoIndex
                    accumulator[accumulatorIndex] = max(0, accumulator[accumulatorIndex] - 1)
                }
            }
        }
    }

    private static func cannyLikeEdges(in image: AUGrayscaleImage, lowThreshold: Double, highThreshold: Double) -> [EdgePixel] {
        let count = image.width * image.height
        var magnitudes = Array(repeating: 0.0, count: count)
        var angles = Array(repeating: 0.0, count: count)
        for y in 1..<(image.height - 1) {
            for x in 1..<(image.width - 1) {
                let index = y * image.width + x
                let p00 = grayValue(image, x: x - 1, y: y - 1)
                let p01 = grayValue(image, x: x, y: y - 1)
                let p02 = grayValue(image, x: x + 1, y: y - 1)
                let p10 = grayValue(image, x: x - 1, y: y)
                let p12 = grayValue(image, x: x + 1, y: y)
                let p20 = grayValue(image, x: x - 1, y: y + 1)
                let p21 = grayValue(image, x: x, y: y + 1)
                let p22 = grayValue(image, x: x + 1, y: y + 1)
                let gx = -p00 + p02 - 2.0 * p10 + 2.0 * p12 - p20 + p22
                let gy = -p00 - 2.0 * p01 - p02 + p20 + 2.0 * p21 + p22
                magnitudes[index] = hypot(gx, gy)
                var angle = atan2(gy, gx) * 180.0 / .pi
                if angle < 0.0 {
                    angle += 180.0
                }
                angles[index] = angle
            }
        }

        var suppressed = Array(repeating: 0.0, count: count)
        for y in 1..<(image.height - 1) {
            for x in 1..<(image.width - 1) {
                let index = y * image.width + x
                let magnitude = magnitudes[index]
                if magnitude <= 0.0 {
                    continue
                }
                let angle = angles[index]
                let neighbors: (Int, Int)
                if angle < 22.5 || angle >= 157.5 {
                    neighbors = (index - 1, index + 1)
                } else if angle < 67.5 {
                    neighbors = (index - image.width + 1, index + image.width - 1)
                } else if angle < 112.5 {
                    neighbors = (index - image.width, index + image.width)
                } else {
                    neighbors = (index - image.width - 1, index + image.width + 1)
                }
                if magnitude >= magnitudes[neighbors.0] && magnitude >= magnitudes[neighbors.1] {
                    suppressed[index] = magnitude
                }
            }
        }

        var state = Array(repeating: UInt8(0), count: count)
        var queue: [Int] = []
        queue.reserveCapacity(count / 8)
        for index in 0..<count {
            let magnitude = suppressed[index]
            if magnitude >= highThreshold {
                state[index] = 2
                queue.append(index)
            } else if magnitude >= lowThreshold {
                state[index] = 1
            }
        }

        var cursor = 0
        while cursor < queue.count {
            let index = queue[cursor]
            cursor += 1
            let x = index % image.width
            let y = index / image.width
            for ny in max(1, y - 1)...min(image.height - 2, y + 1) {
                for nx in max(1, x - 1)...min(image.width - 2, x + 1) {
                    let neighbor = ny * image.width + nx
                    if state[neighbor] == 1 {
                        state[neighbor] = 2
                        queue.append(neighbor)
                    }
                }
            }
        }

        var edges: [EdgePixel] = []
        edges.reserveCapacity(queue.count)
        for index in queue {
            edges.append(EdgePixel(x: index % image.width, y: index / image.width))
        }
        return edges
    }

    private static func lineSegment(
        for peak: HoughPeak,
        edges: [EdgePixel],
        directions: [(dx: Double, dy: Double, nx: Double, ny: Double)],
        minLineLength: Double,
        maxLineGap: Double
    ) -> AULineSegment? {
        let direction = directions[peak.thetaIndex]
        var projections: [ProjectedEdge] = []
        projections.reserveCapacity(edges.count / 8)
        for edge in edges {
            let x = Double(edge.x)
            let y = Double(edge.y)
            let rho = x * direction.nx + y * direction.ny
            if abs(rho - peak.rho) <= 1.5 {
                projections.append(ProjectedEdge(
                    projection: x * direction.dx + y * direction.dy,
                    x: x,
                    y: y
                ))
            }
        }
        guard projections.count >= 2 else {
            return nil
        }
        projections.sort { $0.projection < $1.projection }

        var bestStartIndex = 0
        var bestEndIndex = 0
        var runStartIndex = 0
        var runEndIndex = 0
        for index in projections.indices.dropFirst() {
            let projection = projections[index].projection
            if projection - projections[runEndIndex].projection <= maxLineGap {
                runEndIndex = index
            } else {
                if projections[runEndIndex].projection - projections[runStartIndex].projection >
                    projections[bestEndIndex].projection - projections[bestStartIndex].projection {
                    bestStartIndex = runStartIndex
                    bestEndIndex = runEndIndex
                }
                runStartIndex = index
                runEndIndex = index
            }
        }
        if projections[runEndIndex].projection - projections[runStartIndex].projection >
            projections[bestEndIndex].projection - projections[bestStartIndex].projection {
            bestStartIndex = runStartIndex
            bestEndIndex = runEndIndex
        }

        let length = projections[bestEndIndex].projection - projections[bestStartIndex].projection
        guard length >= minLineLength else {
            return nil
        }

        let support = projections[bestStartIndex...bestEndIndex]
        let supportCount = Double(support.count)
        let meanX = support.reduce(0.0) { $0 + $1.x } / supportCount
        let meanY = support.reduce(0.0) { $0 + $1.y } / supportCount
        var covXX = 0.0
        var covXY = 0.0
        var covYY = 0.0
        for point in support {
            let dx = point.x - meanX
            let dy = point.y - meanY
            covXX += dx * dx
            covXY += dx * dy
            covYY += dy * dy
        }
        var pcaAngle = 0.5 * atan2(2.0 * covXY, covXX - covYY)
        let houghAngle = peak.angleDegrees * .pi / 180.0
        if abs(normalizedAngleDegrees((pcaAngle - houghAngle) * 180.0 / .pi)) > 20.0 {
            pcaAngle = houghAngle
        }
        let dx = cos(pcaAngle)
        let dy = sin(pcaAngle)
        let halfLength = length / 2.0
        return AULineSegment(
            start: AUPoint(x: meanX - dx * halfLength, y: meanY - dy * halfLength),
            end: AUPoint(x: meanX + dx * halfLength, y: meanY + dy * halfLength)
        )
    }

    private static func appendAxisCandidate(
        angleDegrees: Double,
        strength: Double,
        candidates: inout [Double],
        weights: inout [Double]
    ) {
        let hDev = angleDegrees
        if abs(hDev) <= 22.0 {
            let weight = strength * strength * max(0.0, 1.0 - abs(hDev) / 25.0)
            candidates.append(hDev)
            weights.append(weight)
        }

        let vDev = verticalDeviationDegrees(angleDegrees)
        if abs(vDev) <= 22.0 {
            let weight = strength * strength * max(0.0, 1.0 - abs(vDev) / 25.0)
            candidates.append(vDev)
            weights.append(weight)
        }
    }

    private static func weightedAxisEstimate(candidates: [Double], weights: [Double]) -> (rollRadians: Double?, confidence: Double) {
        let totalWeight = weights.reduce(0.0, +)
        guard !candidates.isEmpty, totalWeight > 0.0 else {
            return (nil, 0.0)
        }

        var sumX = 0.0
        var sumY = 0.0
        for (angle, weight) in zip(candidates, weights) {
            let doubled = angle * 2.0 * .pi / 180.0
            sumX += cos(doubled) * weight
            sumY += sin(doubled) * weight
        }
        let imageAxisDegrees = atan2(sumY, sumX) * 180.0 / .pi / 2.0
        let deviations = candidates.map { abs(wrapDegrees($0 - imageAxisDegrees)) }.sorted()
        let mad = median(deviations) ?? 0.0
        // The classical verifiers estimate the image axis angle. GeoCalib roll uses
        // the opposite sign convention, matching the Python gate's aligned=-pred.
        return (-imageAxisDegrees * .pi / 180.0, totalWeight / (1.0 + mad))
    }

    private static func blurred5x5(_ image: AUGrayscaleImage) -> AUGrayscaleImage {
        let weights = [1.0, 4.0, 6.0, 4.0, 1.0]
        var horizontal = Array(repeating: Double(0), count: image.width * image.height)
        var output = Array(repeating: UInt8(0), count: image.width * image.height)
        for y in 0..<image.height {
            for x in 0..<image.width {
                var sum = 0.0
                for k in 0..<weights.count {
                    sum += grayValue(image, x: x + k - 2, y: y) * weights[k]
                }
                horizontal[y * image.width + x] = sum / 16.0
            }
        }
        for y in 0..<image.height {
            for x in 0..<image.width {
                var sum = 0.0
                for k in 0..<weights.count {
                    let sy = reflect101(y + k - 2, length: image.height)
                    sum += horizontal[sy * image.width + x] * weights[k]
                }
                output[y * image.width + x] = UInt8(min(255.0, max(0.0, round(sum / 16.0))))
            }
        }
        return AUGrayscaleImage(width: image.width, height: image.height, pixels: output)
    }

    private static func boundedVerifierImage(_ image: AUGrayscaleImage, maximumDimension: Int) -> AUGrayscaleImage {
        guard image.width > 0,
              image.height > 0,
              image.pixels.count == image.width * image.height,
              max(image.width, image.height) > maximumDimension else {
            return image
        }

        let scale = Double(maximumDimension) / Double(max(image.width, image.height))
        let outputWidth = max(1, Int((Double(image.width) * scale).rounded()))
        let outputHeight = max(1, Int((Double(image.height) * scale).rounded()))
        var output = Array(repeating: UInt8(0), count: outputWidth * outputHeight)

        for y in 0..<outputHeight {
            let sourceY = min(image.height - 1, Int((Double(y) + 0.5) / scale))
            for x in 0..<outputWidth {
                let sourceX = min(image.width - 1, Int((Double(x) + 0.5) / scale))
                output[y * outputWidth + x] = image.pixels[sourceY * image.width + sourceX]
            }
        }

        return AUGrayscaleImage(width: outputWidth, height: outputHeight, pixels: output)
    }
}

private func clamp(_ value: Int, lower: Int, upper: Int) -> Int {
    min(max(value, lower), upper)
}

private func reflect101(_ value: Int, length: Int) -> Int {
    guard length > 1 else {
        return 0
    }
    var result = value
    let last = length - 1
    while result < 0 || result > last {
        if result < 0 {
            result = -result
        } else {
            result = 2 * last - result
        }
    }
    return result
}

private func grayValue(_ image: AUGrayscaleImage, x: Int, y: Int) -> Double {
    let sx = reflect101(x, length: image.width)
    let sy = reflect101(y, length: image.height)
    return Double(image.pixels[sy * image.width + sx])
}

private func lineAngleDegrees(_ line: AULineSegment) -> Double {
    normalizedAngleDegrees(atan2(line.end.y - line.start.y, line.end.x - line.start.x) * 180.0 / .pi)
}

private func normalizedAngleDegrees(_ angle: Double) -> Double {
    var wrapped = (angle + 90.0).truncatingRemainder(dividingBy: 180.0)
    if wrapped < 0 {
        wrapped += 180.0
    }
    return wrapped - 90.0
}

private func verticalDeviationDegrees(_ angle: Double) -> Double {
    angle >= 0.0 ? angle - 90.0 : angle + 90.0
}

private func wrapDegrees(_ angle: Double) -> Double {
    var wrapped = (angle + 180.0).truncatingRemainder(dividingBy: 360.0)
    if wrapped < 0 {
        wrapped += 360.0
    }
    return wrapped - 180.0
}

private func wrapRadians(_ angle: Double) -> Double {
    wrapDegrees(angle * 180.0 / .pi) * .pi / 180.0
}

private func percentile(_ sortedValues: [Double], percent: Double) -> Double? {
    guard !sortedValues.isEmpty else {
        return nil
    }
    if sortedValues.count == 1 {
        return sortedValues[0]
    }
    let position = Double(sortedValues.count - 1) * percent / 100.0
    let lower = Int(floor(position))
    let upper = Int(ceil(position))
    if lower == upper {
        return sortedValues[lower]
    }
    let fraction = position - Double(lower)
    return sortedValues[lower] * (1.0 - fraction) + sortedValues[upper] * fraction
}

private func median(_ sortedValues: [Double]) -> Double? {
    guard !sortedValues.isEmpty else {
        return nil
    }
    let mid = sortedValues.count / 2
    if sortedValues.count % 2 == 0 {
        return (sortedValues[mid - 1] + sortedValues[mid]) / 2.0
    }
    return sortedValues[mid]
}
