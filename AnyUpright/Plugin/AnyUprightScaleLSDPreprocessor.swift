//
//  AnyUprightScaleLSDPreprocessor.swift
//  AnyUpright
//

import Foundation

struct AUScaleLSDRGBAImage {
    var width: Int
    var height: Int
    var pixels: [UInt8]
}

enum AnyUprightScaleLSDPreprocessor {
    static let inputSize = 512

    static func normalizedGrayscaleNCHW(from image: AUScaleLSDRGBAImage) -> [Float]? {
        guard image.width > 0,
              image.height > 0,
              image.pixels.count == image.width * image.height * 4 else {
            return nil
        }

        let sourceCount = image.width * image.height
        var grayscale = [Float](repeating: 0.0, count: sourceCount)
        for index in 0..<sourceCount {
            let base = index * 4
            grayscale[index] = (
                Float(image.pixels[base]) * 0.299
                    + Float(image.pixels[base + 1]) * 0.587
                    + Float(image.pixels[base + 2]) * 0.114
            ) / 255.0
        }

        var output = [Float](repeating: 0.0, count: inputSize * inputSize)
        let scaleX = Double(image.width) / Double(inputSize)
        let scaleY = Double(image.height) / Double(inputSize)
        for outputY in 0..<inputSize {
            let sourceY = (Double(outputY) + 0.5) * scaleY - 0.5
            let lowerY = min(image.height - 1, max(0, Int(floor(sourceY))))
            let upperY = min(image.height - 1, lowerY + 1)
            let yWeight = Float(min(1.0, max(0.0, sourceY - Double(lowerY))))
            for outputX in 0..<inputSize {
                let sourceX = (Double(outputX) + 0.5) * scaleX - 0.5
                let lowerX = min(image.width - 1, max(0, Int(floor(sourceX))))
                let upperX = min(image.width - 1, lowerX + 1)
                let xWeight = Float(min(1.0, max(0.0, sourceX - Double(lowerX))))
                let top = mix(
                    grayscale[lowerY * image.width + lowerX],
                    grayscale[lowerY * image.width + upperX],
                    weight: xWeight
                )
                let bottom = mix(
                    grayscale[upperY * image.width + lowerX],
                    grayscale[upperY * image.width + upperX],
                    weight: xWeight
                )
                output[outputY * inputSize + outputX] = mix(top, bottom, weight: yWeight)
            }
        }
        return output
    }

    static func detectedCandidates(
        from lines: [AUScaleLSDLineSegment],
        imageSize: AUSize
    ) -> [UprightDetectedCandidate] {
        let maximumScore = max(1.0, lines.map(\.score).max() ?? 1.0)
        let scoreScale = log1p(maximumScore)
        return lines.map { line in
            let dx = abs(line.end.x - line.start.x)
            let dy = abs(line.end.y - line.start.y)
            let orientation: UprightGuideOrientation = dy >= dx ? .vertical : .horizontal
            let object = AnyUprightUprightCandidates.objectLine(
                from: AULineSegment(start: line.start, end: line.end),
                size: imageSize
            )
            return UprightDetectedCandidate(
                orientation: orientation,
                start: object.start,
                end: object.end,
                score: scoreScale > 0.0 ? log1p(max(0.0, line.score)) / scoreScale : 0.0
            )
        }
    }

    private static func mix(_ first: Float, _ second: Float, weight: Float) -> Float {
        first + (second - first) * weight
    }
}
