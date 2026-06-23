//
//  AnyUprightMLSDCoreMLDetector.swift
//  AnyUpright
//

import CoreImage
import CoreML
import Dispatch
import Foundation

enum AUMLSDCoreMLDetectorError: Error, CustomStringConvertible {
    case missingResourceBundle
    case missingModel([URL])
    case invalidModel(String)
    case invalidInput(String)
    case missingOutput(String)
    case missingFrameImage

    var description: String {
        switch self {
        case .missingResourceBundle:
            return "Missing M-LSD Core ML resource bundle"
        case .missingModel(let urls):
            return "Missing M-LSD Core ML model at \(urls.map(\.path).joined(separator: ", "))"
        case .invalidModel(let message):
            return "Invalid M-LSD Core ML model: \(message)"
        case .invalidInput(let message):
            return "Invalid M-LSD Core ML input: \(message)"
        case .missingOutput(let name):
            return "Missing M-LSD Core ML output: \(name)"
        case .missingFrameImage:
            return "Missing frame image for M-LSD detection"
        }
    }
}

private struct AUMLSDLineSegment {
    var x1: Double
    var y1: Double
    var x2: Double
    var y2: Double
    var score: Double

    var length: Double {
        hypot(x2 - x1, y2 - y1)
    }

    var midpoint: AUPoint {
        AUPoint(x: (x1 + x2) * 0.5, y: (y1 + y2) * 0.5)
    }
}

private struct AUMLSDCandidate {
    var orientation: UprightGuideOrientation
    var segment: AUMLSDLineSegment
    var score: Double
}

private struct AUMLSDRGBAImage {
    var width: Int
    var height: Int
    var pixels: [UInt8]
}

private struct AUMLSDResizeWeights {
    var indices: [Int]
    var weights: [Double]
}

enum AnyUprightMLSDCoreMLDetector {
    private static let inputSize = 512
    private static let maxDeviationDegrees = 30.0
    private static let guidePairMinimumSeparationRatio = 0.15
    private static let guidePairMinimumLengthRatio = 0.12
    private static let scoreThreshold = 0.05
    private static let distanceThreshold = 20.0
    private static let topK = 500

    private static let sessionLock = NSLock()
    private static var cachedModelURL: URL?
    private static var cachedSession: AUMLSDCoreMLSession?

    static func detectCandidates(
        in frame: FxImageTile,
        mode: UprightAnalysisMode,
        context: CIContext
    ) throws -> [UprightDetectedCandidate] {
        let source = try renderSourceRGBA(from: frame, context: context)
        let input = makeInputNCHW(from: source)
        let output = try session().run(inputNCHW: input)
        let decoded = decodeLines(
            output: output.values,
            shape: output.shape,
            imageWidth: source.width,
            imageHeight: source.height
        )
        let limit = AnyUprightUprightCandidates.slotLimit(isFullMode: mode == .detectFullCandidates)
        var candidates: [UprightDetectedCandidate] = []
        candidates.reserveCapacity(AnyUprightUprightCandidates.slotCount)

        if mode.includesVertical {
            candidates.append(contentsOf: filterCandidates(
                decoded,
                orientation: .vertical,
                width: source.width,
                height: source.height,
                limit: limit
            ).map { detectedCandidate(from: $0, width: source.width, height: source.height) })
        }
        if mode.includesHorizontal {
            candidates.append(contentsOf: filterCandidates(
                decoded,
                orientation: .horizontal,
                width: source.width,
                height: source.height,
                limit: limit
            ).map { detectedCandidate(from: $0, width: source.width, height: source.height) })
        }

        return Array(candidates.prefix(AnyUprightUprightCandidates.slotCount))
    }

    private static func session() throws -> AUMLSDCoreMLSession {
        let modelURL = try resolvedModelURL()
        sessionLock.lock()
        defer { sessionLock.unlock() }

        if let cachedSession, cachedModelURL == modelURL {
            return cachedSession
        }

        let session = try AUMLSDCoreMLSession(modelURL: modelURL, computeUnits: .all)
        cachedModelURL = modelURL
        cachedSession = session
        return session
    }

    private static func resolvedModelURL() throws -> URL {
        let bundle = Bundle(for: AnyUprightUprightPlugIn.self)
        guard let resourceURL = bundle.resourceURL else {
            throw AUMLSDCoreMLDetectorError.missingResourceBundle
        }

        let candidates = [
            resourceURL.appendingPathComponent("mlsd_large_512_fp32.mlmodelc", isDirectory: true),
            resourceURL.appendingPathComponent("MLSDCoreML/mlsd_large_512_fp32.mlmodelc", isDirectory: true),
            resourceURL.appendingPathComponent("mlsd_large_512_fp32.mlpackage", isDirectory: true),
            resourceURL.appendingPathComponent("MLSDCoreML/mlsd_large_512_fp32.mlpackage", isDirectory: true),
            resourceURL.appendingPathComponent("mlsd_large_512_fp32.mlmodel"),
            resourceURL.appendingPathComponent("MLSDCoreML/mlsd_large_512_fp32.mlmodel")
        ]

        for url in candidates where FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        throw AUMLSDCoreMLDetectorError.missingModel(candidates)
    }

    private static func renderSourceRGBA(from frame: FxImageTile, context: CIContext) throws -> AUMLSDRGBAImage {
        guard let sourceImage = AnyUprightAnalysisImage.ciImage(from: frame) else {
            throw AUMLSDCoreMLDetectorError.missingFrameImage
        }

        let bounds = frame.imagePixelBounds
        let width = max(1, Int(bounds.right - bounds.left))
        let height = max(1, Int(bounds.top - bounds.bottom))
        var rgba = Array(repeating: UInt8(0), count: width * height * 4)

        context.render(
            sourceImage,
            toBitmap: &rgba,
            rowBytes: width * 4,
            bounds: CGRect(x: 0, y: 0, width: width, height: height),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )

        return AUMLSDRGBAImage(width: width, height: height, pixels: rgba)
    }

    private static func makeInputNCHW(from source: AUMLSDRGBAImage) -> [Float] {
        let resizedRGB = areaResizeRGB(
            sourceRGBA: source.pixels,
            sourceWidth: source.width,
            sourceHeight: source.height,
            targetWidth: inputSize,
            targetHeight: inputSize
        )
        let plane = inputSize * inputSize
        var result = Array(repeating: Float(0), count: plane * 4)
        let constantPlaneValue = Float(1.0 / 127.5 - 1.0)

        for y in 0..<inputSize {
            for x in 0..<inputSize {
                let pixelIndex = (y * inputSize + x) * 3
                let valueIndex = y * inputSize + x
                result[valueIndex] = Float(resizedRGB[pixelIndex]) / 127.5 - 1.0
                result[plane + valueIndex] = Float(resizedRGB[pixelIndex + 1]) / 127.5 - 1.0
                result[plane * 2 + valueIndex] = Float(resizedRGB[pixelIndex + 2]) / 127.5 - 1.0
                result[plane * 3 + valueIndex] = constantPlaneValue
            }
        }

        return result
    }

    private static func areaResizeRGB(
        sourceRGBA: [UInt8],
        sourceWidth: Int,
        sourceHeight: Int,
        targetWidth: Int,
        targetHeight: Int
    ) -> [UInt8] {
        let xWeights = makeAreaWeights(source: sourceWidth, target: targetWidth)
        let yWeights = makeAreaWeights(source: sourceHeight, target: targetHeight)
        let scaleArea = Double(sourceWidth * sourceHeight) / Double(targetWidth * targetHeight)
        var output = Array(repeating: UInt8(0), count: targetWidth * targetHeight * 3)

        for y in 0..<targetHeight {
            let yWeight = yWeights[y]
            for x in 0..<targetWidth {
                let xWeight = xWeights[x]
                var red = 0.0
                var green = 0.0
                var blue = 0.0

                for (yOffset, sy) in yWeight.indices.enumerated() {
                    let wy = yWeight.weights[yOffset]
                    let row = sy * sourceWidth
                    for (xOffset, sx) in xWeight.indices.enumerated() {
                        let weight = wy * xWeight.weights[xOffset]
                        let sourceIndex = (row + sx) * 4
                        red += Double(sourceRGBA[sourceIndex]) * weight
                        green += Double(sourceRGBA[sourceIndex + 1]) * weight
                        blue += Double(sourceRGBA[sourceIndex + 2]) * weight
                    }
                }

                let destinationIndex = (y * targetWidth + x) * 3
                output[destinationIndex] = UInt8(clamp((red / scaleArea).rounded(.toNearestOrEven), 0.0, 255.0))
                output[destinationIndex + 1] = UInt8(clamp((green / scaleArea).rounded(.toNearestOrEven), 0.0, 255.0))
                output[destinationIndex + 2] = UInt8(clamp((blue / scaleArea).rounded(.toNearestOrEven), 0.0, 255.0))
            }
        }

        return output
    }

    private static func makeAreaWeights(source: Int, target: Int) -> [AUMLSDResizeWeights] {
        let scale = Double(source) / Double(target)
        return (0..<target).map { destination in
            let start = Double(destination) * scale
            let end = Double(destination + 1) * scale
            let first = max(0, Int(floor(start)))
            let last = min(source - 1, Int(ceil(end)) - 1)
            var indices: [Int] = []
            var weights: [Double] = []

            for sourceIndex in first...last {
                let overlap = max(0.0, min(end, Double(sourceIndex + 1)) - max(start, Double(sourceIndex)))
                if overlap > 0.0 {
                    indices.append(sourceIndex)
                    weights.append(overlap)
                }
            }

            return AUMLSDResizeWeights(indices: indices, weights: weights)
        }
    }

    private static func decodeLines(
        output: [Float],
        shape: [Int],
        imageWidth: Int,
        imageHeight: Int
    ) -> [AUMLSDLineSegment] {
        let normalizedShape: (channels: Int, height: Int, width: Int)
        if shape.count == 4 {
            normalizedShape = (shape[1], shape[2], shape[3])
        } else if shape.count == 3 {
            normalizedShape = (shape[0], shape[1], shape[2])
        } else {
            return []
        }
        guard normalizedShape.channels >= 5 else {
            return []
        }

        let height = normalizedShape.height
        let width = normalizedShape.width
        let channelStride = height * width

        func value(channel: Int, y: Int, x: Int) -> Float {
            output[channel * channelStride + y * width + x]
        }

        var peaks: [(score: Double, y: Int, x: Int)] = []
        peaks.reserveCapacity(height * width / 16)
        for y in 0..<height {
            for x in 0..<width {
                let center = sigmoid(Double(value(channel: 0, y: y, x: x)))
                var isPeak = true
                for yy in max(0, y - 1)...min(height - 1, y + 1) {
                    for xx in max(0, x - 1)...min(width - 1, x + 1) {
                        if sigmoid(Double(value(channel: 0, y: yy, x: xx))) > center {
                            isPeak = false
                            break
                        }
                    }
                    if !isPeak {
                        break
                    }
                }
                if isPeak {
                    peaks.append((center, y, x))
                }
            }
        }
        peaks.sort { $0.score > $1.score }
        if peaks.count > topK {
            peaks.removeSubrange(topK..<peaks.count)
        }

        let hRatio = Double(imageHeight) / Double(inputSize)
        let wRatio = Double(imageWidth) / Double(inputSize)
        var result: [AUMLSDLineSegment] = []
        result.reserveCapacity(peaks.count)
        for peak in peaks {
            let x = Double(peak.x)
            let y = Double(peak.y)
            let dx1 = Double(value(channel: 1, y: peak.y, x: peak.x))
            let dy1 = Double(value(channel: 2, y: peak.y, x: peak.x))
            let dx2 = Double(value(channel: 3, y: peak.y, x: peak.x))
            let dy2 = Double(value(channel: 4, y: peak.y, x: peak.x))
            let distance = hypot(dx1 - dx2, dy1 - dy2)
            guard peak.score > scoreThreshold, distance > distanceThreshold else {
                continue
            }

            let segment = AUMLSDLineSegment(
                x1: 2.0 * (x + dx1) * wRatio,
                y1: 2.0 * (y + dy1) * hRatio,
                x2: 2.0 * (x + dx2) * wRatio,
                y2: 2.0 * (y + dy2) * hRatio,
                score: peak.score
            )
            if segment.length >= 8.0 {
                result.append(segment)
            }
        }

        return result
    }

    private static func filterCandidates(
        _ segments: [AUMLSDLineSegment],
        orientation: UprightGuideOrientation,
        width: Int,
        height: Int,
        limit: Int
    ) -> [AUMLSDCandidate] {
        let axis = orientation == .vertical ? Double(height) : Double(width)
        let minLength = axis * 0.10
        var candidates: [AUMLSDCandidate] = []

        for segment in segments {
            guard let clipped = clipSegmentToImage(segment, width: width, height: height) else {
                continue
            }
            guard clipped.length >= minLength else {
                continue
            }
            let deviation = signedDeviation(clipped, orientation: orientation)
            guard abs(deviation) < radians(maxDeviationDegrees) else {
                continue
            }
            let score = candidateScore(clipped, orientation: orientation, width: width, height: height)
            candidates.append(AUMLSDCandidate(
                orientation: orientation,
                segment: AUMLSDLineSegment(
                    x1: clipped.x1,
                    y1: clipped.y1,
                    x2: clipped.x2,
                    y2: clipped.y2,
                    score: score
                ),
                score: score
            ))
        }

        return suppressSimilar(
            promoteBestGuidePair(candidates, orientation: orientation, width: width, height: height),
            limit: limit
        )
    }

    private static func detectedCandidate(from candidate: AUMLSDCandidate, width: Int, height: Int) -> UprightDetectedCandidate {
        let line = AULineSegment(
            start: AUPoint(x: candidate.segment.x1, y: candidate.segment.y1),
            end: AUPoint(x: candidate.segment.x2, y: candidate.segment.y2)
        )
        let object = AnyUprightUprightCandidates.objectLine(
            from: line,
            size: AUSize(width: Double(width), height: Double(height))
        )
        return UprightDetectedCandidate(
            orientation: candidate.orientation,
            start: object.start,
            end: object.end,
            score: min(1.0, max(0.0, candidate.score))
        )
    }

    private static func clipSegmentToImage(_ segment: AUMLSDLineSegment, width: Int, height: Int) -> AUMLSDLineSegment? {
        let xmin = 0.0
        let ymin = 0.0
        let xmax = Double(max(0, width - 1))
        let ymax = Double(max(0, height - 1))
        let dx = segment.x2 - segment.x1
        let dy = segment.y2 - segment.y1
        let p = [-dx, dx, -dy, dy]
        let q = [segment.x1 - xmin, xmax - segment.x1, segment.y1 - ymin, ymax - segment.y1]
        var u1 = 0.0
        var u2 = 1.0

        for (pi, qi) in zip(p, q) {
            if abs(pi) < 1e-9 {
                if qi < 0.0 {
                    return nil
                }
                continue
            }
            let t = qi / pi
            if pi < 0.0 {
                u1 = max(u1, t)
            } else {
                u2 = min(u2, t)
            }
            if u1 > u2 {
                return nil
            }
        }

        let clipped = AUMLSDLineSegment(
            x1: segment.x1 + u1 * dx,
            y1: segment.y1 + u1 * dy,
            x2: segment.x1 + u2 * dx,
            y2: segment.y1 + u2 * dy,
            score: segment.score
        )
        return clipped.length >= 1.0 ? clipped : nil
    }

    private static func candidateScore(_ segment: AUMLSDLineSegment, orientation: UprightGuideOrientation, width: Int, height: Int) -> Double {
        let maxDeviation = radians(maxDeviationDegrees)
        let deviation = abs(signedDeviation(segment, orientation: orientation))
        let angleScore = max(0.0, 1.0 - deviation / maxDeviation)
        let axis = orientation == .vertical ? Double(height) : Double(width)
        let lengthScore = min(1.0, segment.length / max(1.0, axis * 0.45))
        let midpoint = segment.midpoint
        let centerX = 1.0 - min(1.0, abs(midpoint.x - Double(width) * 0.5) / (Double(width) * 0.5))
        let centerY = 1.0 - min(1.0, abs(midpoint.y - Double(height) * 0.5) / (Double(height) * 0.5))
        let centerScore = 0.5 + 0.25 * centerX + 0.25 * centerY
        return (0.35 + 0.65 * angleScore) * (0.25 + 0.75 * lengthScore) * centerScore
    }

    private static func promoteBestGuidePair(
        _ candidates: [AUMLSDCandidate],
        orientation: UprightGuideOrientation,
        width: Int,
        height: Int
    ) -> [AUMLSDCandidate] {
        var sorted = candidates.sorted { sortKey($0, $1, orientation: orientation) }
        let pair = bestGuidePair(sorted, orientation: orientation, width: width, height: height, topN: min(80, sorted.count))
        guard let first = pair.firstIndex, let second = pair.secondIndex else {
            return sorted
        }

        let promoted = [sorted[first], sorted[second]]
        sorted.remove(at: max(first, second))
        sorted.remove(at: min(first, second))
        return promoted + sorted
    }

    private static func bestGuidePair(
        _ candidates: [AUMLSDCandidate],
        orientation: UprightGuideOrientation,
        width: Int,
        height: Int,
        topN: Int
    ) -> (score: Double, firstIndex: Int?, secondIndex: Int?) {
        let axis = orientation == .vertical ? Double(height) : Double(width)
        let perpendicular = orientation == .vertical ? Double(width) : Double(height)
        let minLength = axis * guidePairMinimumLengthRatio
        let minSeparation = perpendicular * guidePairMinimumSeparationRatio
        let pool = Array(candidates.prefix(topN))
        var best = (score: 0.0, firstIndex: Optional<Int>.none, secondIndex: Optional<Int>.none)

        for firstIndex in 0..<pool.count {
            guard pool[firstIndex].segment.length >= minLength else {
                continue
            }
            for secondIndex in (firstIndex + 1)..<pool.count {
                guard pool[secondIndex].segment.length >= minLength else {
                    continue
                }
                let firstMid = pool[firstIndex].segment.midpoint
                let secondMid = pool[secondIndex].segment.midpoint
                let separation = orientation == .vertical ? abs(firstMid.x - secondMid.x) : abs(firstMid.y - secondMid.y)
                guard separation >= minSeparation else {
                    continue
                }
                let score = guidePairScore(pool[firstIndex].segment, pool[secondIndex].segment, orientation: orientation, width: width, height: height)
                if score > best.score {
                    best = (score, firstIndex, secondIndex)
                }
            }
        }

        return best
    }

    private static func guidePairScore(
        _ first: AUMLSDLineSegment,
        _ second: AUMLSDLineSegment,
        orientation: UprightGuideOrientation,
        width: Int,
        height: Int
    ) -> Double {
        let axis = orientation == .vertical ? Double(height) : Double(width)
        let perpendicular = orientation == .vertical ? Double(width) : Double(height)
        let firstMid = first.midpoint
        let secondMid = second.midpoint
        let separation = orientation == .vertical ? abs(firstMid.x - secondMid.x) : abs(firstMid.y - secondMid.y)
        let separationScore = min(1.0, separation / max(1.0, perpendicular * 0.40))
        let firstLength = min(1.0, first.length / max(1.0, axis * 0.35))
        let secondLength = min(1.0, second.length / max(1.0, axis * 0.35))
        let lengthScore = min(firstLength, secondLength)
        let firstAngle = 1.0 - min(1.0, abs(degrees(signedDeviation(first, orientation: orientation))) / maxDeviationDegrees)
        let secondAngle = 1.0 - min(1.0, abs(degrees(signedDeviation(second, orientation: orientation))) / maxDeviationDegrees)
        let angleScore = 0.5 * (firstAngle + secondAngle)
        let center = (orientation == .vertical ? Double(width) : Double(height)) * 0.5
        let a = orientation == .vertical ? firstMid.x : firstMid.y
        let b = orientation == .vertical ? secondMid.x : secondMid.y
        let centerSpanScore = (a - center) * (b - center) <= 0.0 ? 1.0 : 0.75
        return (0.40 * separationScore + 0.35 * lengthScore + 0.25 * angleScore) * centerSpanScore
    }

    private static func suppressSimilar(_ candidates: [AUMLSDCandidate], limit: Int) -> [AUMLSDCandidate] {
        var selected: [AUMLSDCandidate] = []
        for candidate in candidates {
            let midpoint = candidate.segment.midpoint
            let tooClose = selected.contains { existing in
                let existingMidpoint = existing.segment.midpoint
                return hypot(midpoint.x - existingMidpoint.x, midpoint.y - existingMidpoint.y) < 24.0 &&
                    degrees(angleDiff(candidate.segment, existing.segment)) < 4.0
            }
            if tooClose {
                continue
            }
            selected.append(candidate)
            if selected.count >= limit {
                break
            }
        }
        return selected
    }

    private static func sortKey(_ lhs: AUMLSDCandidate, _ rhs: AUMLSDCandidate, orientation: UprightGuideOrientation) -> Bool {
        if lhs.score != rhs.score {
            return lhs.score > rhs.score
        }
        let lhsDeviation = abs(signedDeviation(lhs.segment, orientation: orientation))
        let rhsDeviation = abs(signedDeviation(rhs.segment, orientation: orientation))
        if lhsDeviation != rhsDeviation {
            return lhsDeviation < rhsDeviation
        }
        return lhs.segment.length > rhs.segment.length
    }

    private static func signedDeviation(_ segment: AUMLSDLineSegment, orientation: UprightGuideOrientation) -> Double {
        let angle = normalizedAngle(atan2(segment.y2 - segment.y1, segment.x2 - segment.x1))
        switch orientation {
        case .horizontal:
            return angle
        case .vertical:
            if angle >= 0.0 {
                return angle - .pi / 2.0
            }
            return angle + .pi / 2.0
        }
    }

    private static func angleDiff(_ first: AUMLSDLineSegment, _ second: AUMLSDLineSegment) -> Double {
        abs(normalizedAngle(lineAngle(first) - lineAngle(second)))
    }

    private static func lineAngle(_ segment: AUMLSDLineSegment) -> Double {
        normalizedAngle(atan2(segment.y2 - segment.y1, segment.x2 - segment.x1))
    }

    private static func normalizedAngle(_ angle: Double) -> Double {
        var result = angle
        while result <= -.pi / 2.0 {
            result += .pi
        }
        while result > .pi / 2.0 {
            result -= .pi
        }
        return result
    }

    private static func sigmoid(_ value: Double) -> Double {
        1.0 / (1.0 + exp(-value))
    }

    private static func radians(_ degrees: Double) -> Double {
        degrees * .pi / 180.0
    }

    private static func degrees(_ radians: Double) -> Double {
        radians * 180.0 / .pi
    }

    private static func clamp(_ value: Double, _ lower: Double, _ upper: Double) -> Double {
        min(upper, max(lower, value))
    }
}

private final class AUMLSDCoreMLSession {
    private let model: MLModel
    private let inputName: String
    private let inputShape: [Int]
    private let inputElementCount: Int
    private let inputArray: MLMultiArray
    private let inputProvider: MLDictionaryFeatureProvider
    private let outputName: String
    private let predictionLock = NSLock()

    init(modelURL: URL, computeUnits: MLComputeUnits) throws {
        let configuration = MLModelConfiguration()
        configuration.computeUnits = computeUnits

        let loadURL: URL
        if modelURL.pathExtension == "mlmodelc" {
            loadURL = modelURL
        } else {
            loadURL = try MLModel.compileModel(at: modelURL)
        }
        model = try MLModel(contentsOf: loadURL, configuration: configuration)

        guard let input = model.modelDescription.inputDescriptionsByName.first(where: { $0.value.type == .multiArray }) ??
            model.modelDescription.inputDescriptionsByName.first else {
            throw AUMLSDCoreMLDetectorError.invalidModel("model has no inputs")
        }
        inputName = input.key
        inputShape = try Self.multiArrayShape(input.value, name: input.key)
        inputElementCount = inputShape.reduce(1, *)
        guard inputElementCount == 1 * 4 * 512 * 512 else {
            throw AUMLSDCoreMLDetectorError.invalidModel("expected [1, 4, 512, 512] input, got \(inputShape)")
        }
        inputArray = try MLMultiArray(shape: inputShape.map { NSNumber(value: $0) }, dataType: .float32)
        inputProvider = try MLDictionaryFeatureProvider(dictionary: [inputName: MLFeatureValue(multiArray: inputArray)])

        let multiArrayOutputs = model.modelDescription.outputDescriptionsByName.filter { $0.value.type == .multiArray }
        guard let output = multiArrayOutputs.first(where: { description in
            guard let shape = try? Self.multiArrayShape(description.value, name: description.key) else {
                return false
            }
            return shape.contains(where: { $0 >= 5 }) && shape.reduce(1, *) >= 5 * 128 * 128
        }) ?? multiArrayOutputs.first else {
            throw AUMLSDCoreMLDetectorError.invalidModel("model has no MultiArray output")
        }
        outputName = output.key
    }

    func run(inputNCHW: [Float]) throws -> (values: [Float], shape: [Int]) {
        guard inputNCHW.count == inputElementCount else {
            throw AUMLSDCoreMLDetectorError.invalidInput("expected \(inputElementCount) floats, got \(inputNCHW.count)")
        }

        predictionLock.lock()
        defer { predictionLock.unlock() }

        let pointer = inputArray.dataPointer.bindMemory(to: Float.self, capacity: inputElementCount)
        inputNCHW.withUnsafeBufferPointer { source in
            pointer.update(from: source.baseAddress!, count: inputElementCount)
        }
        let output = try model.prediction(from: inputProvider)
        guard let multiArray = output.featureValue(for: outputName)?.multiArrayValue else {
            throw AUMLSDCoreMLDetectorError.missingOutput(outputName)
        }
        let shape = multiArray.shape.map { $0.intValue }
        return (try Self.floatArray(from: multiArray), shape)
    }

    private static func multiArrayShape(_ description: MLFeatureDescription, name: String) throws -> [Int] {
        guard description.type == .multiArray,
              let constraint = description.multiArrayConstraint else {
            throw AUMLSDCoreMLDetectorError.invalidModel("\(name) is not a MultiArray")
        }
        guard constraint.dataType == .float32 else {
            throw AUMLSDCoreMLDetectorError.invalidModel("\(name) is \(constraint.dataType), expected Float32")
        }
        return constraint.shape.map { $0.intValue }
    }

    private static func floatArray(from array: MLMultiArray) throws -> [Float] {
        guard array.dataType == .float32 else {
            throw AUMLSDCoreMLDetectorError.invalidModel("output is \(array.dataType), expected Float32")
        }
        let shape = array.shape.map { $0.intValue }
        let count = shape.reduce(1, *)
        let strides = array.strides.map { $0.intValue }
        var expectedStride = 1
        var expected = Array(repeating: 0, count: shape.count)
        for index in stride(from: shape.count - 1, through: 0, by: -1) {
            expected[index] = expectedStride
            expectedStride *= shape[index]
        }

        let pointer = array.dataPointer.bindMemory(to: Float.self, capacity: array.count)
        if strides == expected {
            return Array(UnsafeBufferPointer(start: pointer, count: count))
        }

        var output: [Float] = []
        output.reserveCapacity(count)
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
