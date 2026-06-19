//
//  AnyUprightLineDetection.swift
//  AnyUpright
//

import Foundation

struct AUGrayscaleImage {
    var width: Int
    var height: Int
    var pixels: [UInt8]

    func valueAt(x: Int, y: Int) -> Int {
        Int(pixels[y * width + x])
    }
}

struct AULineDetectionOptions {
    var orientation: AUReferenceOrientation
    var maxDeviationRadians: Double = .pi / 6.0
    var edgeThreshold: Double = 80.0
    var thetaStepRadians: Double = .pi / 180.0
    var rhoStep: Double = 2.0
    var voteThreshold: Int = 20
    var maxLines: Int = 40
    var nonMaximumThetaRadius: Int = 4
    var nonMaximumRhoRadius: Int = 8
}

struct AUDetectedLineSegment {
    var line: AULineSegment
    var score: Double
    var votes: Int
    var orientation: AUReferenceOrientation
}

enum AnyUprightLineDetection {
    private struct EdgePoint {
        var x: Int
        var y: Int
        var lineAngleRadians: Double
    }

    private struct HoughPeak {
        var angleRadians: Double
        var rho: Double
        var votes: Int
    }

    static func detectLineSegments(in image: AUGrayscaleImage, options: AULineDetectionOptions) -> [AULineSegment] {
        guard image.width >= 3, image.height >= 3, image.pixels.count == image.width * image.height else {
            return []
        }

        let edges = sobelEdges(in: image, threshold: options.edgeThreshold)
        guard !edges.isEmpty else {
            return []
        }

        return selectedHoughPeaks(from: edges, image: image, options: options).compactMap { peak in
            clippedLine(angleRadians: peak.angleRadians, rho: peak.rho, width: image.width, height: image.height)
        }
    }

    static func detectSupportedLineSegments(in image: AUGrayscaleImage, options: AULineDetectionOptions) -> [AUDetectedLineSegment] {
        guard image.width >= 3, image.height >= 3, image.pixels.count == image.width * image.height else {
            return []
        }

        let edges = sobelEdges(in: image, threshold: options.edgeThreshold)
        guard !edges.isEmpty else {
            return []
        }

        return selectedHoughPeaks(from: edges, image: image, options: options).compactMap { peak in
            guard let line = supportedLineSegment(
                for: peak,
                edges: edges,
                image: image,
                options: options
            ) else {
                return nil
            }

            return AUDetectedLineSegment(
                line: line,
                score: line.length * Double(peak.votes),
                votes: peak.votes,
                orientation: options.orientation
            )
        }
    }

    private static func selectedHoughPeaks(from edges: [EdgePoint], image: AUGrayscaleImage, options: AULineDetectionOptions) -> [HoughPeak] {
        let lineAngles = sampledLineAngles(for: options.orientation, maxDeviationRadians: options.maxDeviationRadians, step: options.thetaStepRadians)
        guard !lineAngles.isEmpty else {
            return []
        }

        let diagonal = hypot(Double(image.width), Double(image.height))
        let rhoMin = -diagonal
        let rhoCount = Int(ceil((diagonal * 2.0) / options.rhoStep)) + 1
        var accumulator = Array(repeating: 0, count: lineAngles.count * rhoCount)
        let angleTolerance = max(options.thetaStepRadians * 3.0, .pi / 18.0)

        for edge in edges {
            let x = Double(edge.x)
            let y = Double(edge.y)
            for (thetaIndex, angle) in lineAngles.enumerated() {
                guard angleDistance(edge.lineAngleRadians, angle) <= angleTolerance else {
                    continue
                }

                let normalX = -sin(angle)
                let normalY = cos(angle)
                let rho = x * normalX + y * normalY
                let rhoIndex = Int(round((rho - rhoMin) / options.rhoStep))
                guard rhoIndex >= 0, rhoIndex < rhoCount else {
                    continue
                }
                accumulator[thetaIndex * rhoCount + rhoIndex] += 1
            }
        }

        var peaks: [(thetaIndex: Int, rhoIndex: Int, votes: Int)] = []
        for thetaIndex in 0..<lineAngles.count {
            for rhoIndex in 0..<rhoCount {
                let votes = accumulator[thetaIndex * rhoCount + rhoIndex]
                if votes >= options.voteThreshold {
                    peaks.append((thetaIndex, rhoIndex, votes))
                }
            }
        }

        peaks.sort { $0.votes > $1.votes }
        var selected: [(thetaIndex: Int, rhoIndex: Int, votes: Int)] = []
        for peak in peaks {
            let overlaps = selected.contains { existing in
                abs(existing.thetaIndex - peak.thetaIndex) <= options.nonMaximumThetaRadius &&
                abs(existing.rhoIndex - peak.rhoIndex) <= options.nonMaximumRhoRadius
            }
            if overlaps {
                continue
            }

            selected.append(peak)
            if selected.count >= options.maxLines {
                break
            }
        }

        return selected.map { peak in
            HoughPeak(
                angleRadians: lineAngles[peak.thetaIndex],
                rho: rhoMin + Double(peak.rhoIndex) * options.rhoStep,
                votes: peak.votes
            )
        }
    }

    private static func supportedLineSegment(
        for peak: HoughPeak,
        edges: [EdgePoint],
        image: AUGrayscaleImage,
        options: AULineDetectionOptions
    ) -> AULineSegment? {
        let directionX = cos(peak.angleRadians)
        let directionY = sin(peak.angleRadians)
        let normalX = -sin(peak.angleRadians)
        let normalY = cos(peak.angleRadians)
        let angleTolerance = max(options.thetaStepRadians * 3.0, .pi / 18.0)
        let rhoTolerance = max(options.rhoStep * 1.5, 2.0)
        let maximumSupportGap = max(6.0, Double(min(image.width, image.height)) * 0.025)
        let support = edges.compactMap { edge -> Double? in
            guard angleDistance(edge.lineAngleRadians, peak.angleRadians) <= angleTolerance else {
                return nil
            }

            let x = Double(edge.x)
            let y = Double(edge.y)
            let rho = x * normalX + y * normalY
            guard abs(rho - peak.rho) <= rhoTolerance else {
                return nil
            }

            return x * directionX + y * directionY
        }.sorted()

        guard support.count >= 2 else {
            return nil
        }

        var bestStart = support[0]
        var bestEnd = support[0]
        var runStart = support[0]
        var runEnd = support[0]
        for value in support.dropFirst() {
            if value - runEnd <= maximumSupportGap {
                runEnd = value
            } else {
                if runEnd - runStart > bestEnd - bestStart {
                    bestStart = runStart
                    bestEnd = runEnd
                }
                runStart = value
                runEnd = value
            }
        }
        if runEnd - runStart > bestEnd - bestStart {
            bestStart = runStart
            bestEnd = runEnd
        }

        guard bestEnd - bestStart >= max(8.0, Double(min(image.width, image.height)) * 0.03) else {
            return nil
        }

        func point(at projection: Double) -> AUPoint {
            AUPoint(
                x: directionX * projection + normalX * peak.rho,
                y: directionY * projection + normalY * peak.rho
            )
        }

        return AULineSegment(
            start: clamped(point(at: bestStart), width: image.width, height: image.height),
            end: clamped(point(at: bestEnd), width: image.width, height: image.height)
        )
    }

    private static func clamped(_ point: AUPoint, width: Int, height: Int) -> AUPoint {
        AUPoint(
            x: min(max(point.x, 0.0), Double(max(0, width - 1))),
            y: min(max(point.y, 0.0), Double(max(0, height - 1)))
        )
    }

    private static func sobelEdges(in image: AUGrayscaleImage, threshold: Double) -> [EdgePoint] {
        var result: [EdgePoint] = []

        for y in 1..<(image.height - 1) {
            for x in 1..<(image.width - 1) {
                let topLeft = image.valueAt(x: x - 1, y: y - 1)
                let top = image.valueAt(x: x, y: y - 1)
                let topRight = image.valueAt(x: x + 1, y: y - 1)
                let left = image.valueAt(x: x - 1, y: y)
                let right = image.valueAt(x: x + 1, y: y)
                let bottomLeft = image.valueAt(x: x - 1, y: y + 1)
                let bottom = image.valueAt(x: x, y: y + 1)
                let bottomRight = image.valueAt(x: x + 1, y: y + 1)

                let gx = -topLeft + topRight - 2 * left + 2 * right - bottomLeft + bottomRight
                let gy = -topLeft - 2 * top - topRight + bottomLeft + 2 * bottom + bottomRight
                let magnitude = hypot(Double(gx), Double(gy))

                if magnitude >= threshold {
                    let gradientAngle = atan2(Double(gy), Double(gx))
                    result.append(EdgePoint(
                        x: x,
                        y: y,
                        lineAngleRadians: normalizedLineAngleRadians(gradientAngle + .pi / 2.0)
                    ))
                }
            }
        }

        return result
    }

    private static func sampledLineAngles(for orientation: AUReferenceOrientation, maxDeviationRadians: Double, step: Double) -> [Double] {
        let center: Double
        switch orientation {
        case .horizontal:
            center = 0.0
        case .vertical:
            center = .pi / 2.0
        }

        let lower = center - maxDeviationRadians
        let upper = center + maxDeviationRadians
        var result: [Double] = []
        var value = lower
        while value <= upper + 0.000001 {
            result.append(normalizedLineAngleRadians(value))
            value += step
        }
        return result
    }

    private static func clippedLine(angleRadians: Double, rho: Double, width: Int, height: Int) -> AULineSegment? {
        let maxX = Double(width - 1)
        let maxY = Double(height - 1)
        let normalX = -sin(angleRadians)
        let normalY = cos(angleRadians)
        var points: [AUPoint] = []

        if abs(normalY) > 0.000001 {
            let yAtLeft = rho / normalY
            appendIfInside(AUPoint(x: 0.0, y: yAtLeft), maxX: maxX, maxY: maxY, to: &points)

            let yAtRight = (rho - maxX * normalX) / normalY
            appendIfInside(AUPoint(x: maxX, y: yAtRight), maxX: maxX, maxY: maxY, to: &points)
        }

        if abs(normalX) > 0.000001 {
            let xAtTop = rho / normalX
            appendIfInside(AUPoint(x: xAtTop, y: 0.0), maxX: maxX, maxY: maxY, to: &points)

            let xAtBottom = (rho - maxY * normalY) / normalX
            appendIfInside(AUPoint(x: xAtBottom, y: maxY), maxX: maxX, maxY: maxY, to: &points)
        }

        let unique = uniquePoints(points)
        guard unique.count >= 2 else {
            return nil
        }

        var bestPair = (unique[0], unique[1])
        var bestDistance = -Double.infinity
        for firstIndex in 0..<unique.count {
            for secondIndex in (firstIndex + 1)..<unique.count {
                let first = unique[firstIndex]
                let second = unique[secondIndex]
                let distance = hypot(first.x - second.x, first.y - second.y)
                if distance > bestDistance {
                    bestDistance = distance
                    bestPair = (first, second)
                }
            }
        }

        return AULineSegment(start: bestPair.0, end: bestPair.1)
    }

    private static func appendIfInside(_ point: AUPoint, maxX: Double, maxY: Double, to points: inout [AUPoint]) {
        let tolerance = 0.001
        guard point.x >= -tolerance,
              point.x <= maxX + tolerance,
              point.y >= -tolerance,
              point.y <= maxY + tolerance else {
            return
        }

        points.append(AUPoint(
            x: min(max(point.x, 0.0), maxX),
            y: min(max(point.y, 0.0), maxY)
        ))
    }

    private static func uniquePoints(_ points: [AUPoint]) -> [AUPoint] {
        var result: [AUPoint] = []
        for point in points {
            let exists = result.contains { existing in
                abs(existing.x - point.x) < 0.001 && abs(existing.y - point.y) < 0.001
            }
            if !exists {
                result.append(point)
            }
        }
        return result
    }

    private static func normalizedLineAngleRadians(_ angle: Double) -> Double {
        var result = angle
        while result <= -.pi / 2.0 {
            result += .pi
        }
        while result > .pi / 2.0 {
            result -= .pi
        }
        return result
    }

    private static func angleDistance(_ lhs: Double, _ rhs: Double) -> Double {
        abs(normalizedLineAngleRadians(lhs - rhs))
    }
}
