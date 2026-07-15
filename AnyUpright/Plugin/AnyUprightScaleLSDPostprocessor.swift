//
//  AnyUprightScaleLSDPostprocessor.swift
//  AnyUpright
//

import Foundation

struct AUScaleLSDPostprocessConfiguration: Equatable {
    var distanceThreshold: Float = 5.0
    var junctionToLineSquaredDistanceThreshold: Float = 10.0
    var junctionHeatmapThreshold: Float = 0.008
    var maximumJunctions = 512
    var lineSupportThreshold = 10
}

struct AUScaleLSDLineSegment: Equatable {
    var start: AUPoint
    var end: AUPoint
    var score: Double
}

enum AUScaleLSDPostprocessError: Error, CustomStringConvertible {
    case invalidShape([Int])
    case invalidElementCount(expected: Int, actual: Int)
    case invalidImageSize(width: Int, height: Int)

    var description: String {
        switch self {
        case .invalidShape(let shape):
            return "Expected ScaleLSD dense logits shaped [1, 9, H, W] or [9, H, W], got \(shape)"
        case .invalidElementCount(let expected, let actual):
            return "Expected \(expected) ScaleLSD dense-logit values, got \(actual)"
        case .invalidImageSize(let width, let height):
            return "ScaleLSD image dimensions must be positive, got \(width)x\(height)"
        }
    }
}

enum AnyUprightScaleLSDPostprocessor {
    private struct Junction {
        var x: Float
        var y: Float
        var score: Float
        var denseIndex: Int
    }

    static func decode(
        denseLogits: [Float],
        shape: [Int],
        imageWidth: Int,
        imageHeight: Int,
        configuration: AUScaleLSDPostprocessConfiguration = AUScaleLSDPostprocessConfiguration()
    ) throws -> [AUScaleLSDLineSegment] {
        guard imageWidth > 0, imageHeight > 0 else {
            throw AUScaleLSDPostprocessError.invalidImageSize(width: imageWidth, height: imageHeight)
        }
        let dimensions: (channels: Int, height: Int, width: Int)
        if shape.count == 4, shape[0] == 1 {
            dimensions = (shape[1], shape[2], shape[3])
        } else if shape.count == 3 {
            dimensions = (shape[0], shape[1], shape[2])
        } else {
            throw AUScaleLSDPostprocessError.invalidShape(shape)
        }
        guard dimensions.channels == 9, dimensions.height > 0, dimensions.width > 0 else {
            throw AUScaleLSDPostprocessError.invalidShape(shape)
        }
        let planeSize = dimensions.height * dimensions.width
        let expectedCount = dimensions.channels * planeSize
        guard denseLogits.count == expectedCount else {
            throw AUScaleLSDPostprocessError.invalidElementCount(expected: expectedCount, actual: denseLogits.count)
        }

        func value(channel: Int, index: Int) -> Float {
            denseLogits[channel * planeSize + index]
        }

        var junctions: [Junction] = []
        junctions.reserveCapacity(configuration.maximumJunctions)
        for index in 0..<planeSize {
            let score = sigmoid(value(channel: 6, index: index) - value(channel: 5, index: index))
            guard score > configuration.junctionHeatmapThreshold else {
                continue
            }
            let x = Float(index % dimensions.width) + sigmoid(value(channel: 7, index: index))
            let y = Float(index / dimensions.width) + sigmoid(value(channel: 8, index: index))
            junctions.append(Junction(x: x, y: y, score: score, denseIndex: index))
        }
        junctions.sort {
            if $0.score != $1.score {
                return $0.score > $1.score
            }
            return $0.denseIndex < $1.denseIndex
        }
        if junctions.count > configuration.maximumJunctions {
            junctions.removeSubrange(configuration.maximumJunctions..<junctions.count)
        }
        guard junctions.count >= 2 else {
            return []
        }

        let junctionCount = junctions.count
        var pairSupport: [Int: Int] = [:]
        pairSupport.reserveCapacity(junctionCount * 2)
        for index in 0..<planeSize {
            let x0 = Float(index % dimensions.width)
            let y0 = Float(index / dimensions.width)
            let md = (sigmoid(value(channel: 0, index: index)) - 0.5) * 2.0 * Float.pi
            let startTilt = sigmoid(value(channel: 1, index: index)) * Float.pi / 2.0
            let endTilt = -sigmoid(value(channel: 2, index: index)) * Float.pi / 2.0
            let distance = min(1.0, max(0.0, sigmoid(value(channel: 3, index: index)))) * configuration.distanceThreshold
            let cosine = cosf(md)
            let sine = sinf(md)
            let startTangent = tanf(startTilt)
            let endTangent = tanf(endTilt)

            let startX = clamp((cosine - sine * startTangent) * distance + x0, lower: 0, upper: Float(dimensions.width - 1))
            let startY = clamp((sine + cosine * startTangent) * distance + y0, lower: 0, upper: Float(dimensions.height - 1))
            let endX = clamp((cosine - sine * endTangent) * distance + x0, lower: 0, upper: Float(dimensions.width - 1))
            let endY = clamp((sine + cosine * endTangent) * distance + y0, lower: 0, upper: Float(dimensions.height - 1))

            let first = nearestJunction(toX: startX, y: startY, junctions: junctions)
            let second = nearestJunction(toX: endX, y: endY, junctions: junctions)
            guard first.index != second.index,
                  first.squaredDistance < configuration.junctionToLineSquaredDistanceThreshold,
                  second.squaredDistance < configuration.junctionToLineSquaredDistanceThreshold else {
                continue
            }
            let lower = min(first.index, second.index)
            let upper = max(first.index, second.index)
            pairSupport[lower * junctionCount + upper, default: 0] += 1
        }

        let scaleX = Float(imageWidth) / Float(dimensions.width)
        let scaleY = Float(imageHeight) / Float(dimensions.height)
        return pairSupport.keys.sorted().compactMap { key in
            guard let support = pairSupport[key], support > configuration.lineSupportThreshold else {
                return nil
            }
            let first = junctions[key / junctionCount]
            let second = junctions[key % junctionCount]
            return AUScaleLSDLineSegment(
                start: AUPoint(x: Double(first.x * scaleX), y: Double(first.y * scaleY)),
                end: AUPoint(x: Double(second.x * scaleX), y: Double(second.y * scaleY)),
                score: Double(support)
            )
        }
    }

    private static func nearestJunction(toX x: Float, y: Float, junctions: [Junction]) -> (index: Int, squaredDistance: Float) {
        var bestIndex = 0
        var bestDistance = Float.greatestFiniteMagnitude
        for (index, junction) in junctions.enumerated() {
            let dx = junction.x - x
            let dy = junction.y - y
            let distance = dx * dx + dy * dy
            if distance < bestDistance {
                bestIndex = index
                bestDistance = distance
            }
        }
        return (bestIndex, bestDistance)
    }

    private static func sigmoid(_ value: Float) -> Float {
        1.0 / (1.0 + expf(-value))
    }

    private static func clamp(_ value: Float, lower: Float, upper: Float) -> Float {
        min(upper, max(lower, value))
    }
}
