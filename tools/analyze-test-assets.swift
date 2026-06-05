//
//  analyze-test-assets.swift
//  AnyUpright
//

import CoreGraphics
import Foundation
import ImageIO

enum AssetAnalysisFailure: Error, CustomStringConvertible {
    case failed(String)

    var description: String {
        switch self {
        case .failed(let message):
            return message
        }
    }
}

@main
struct AnalyzeTestAssets {
    static func main() throws {
        let assetDirectory = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? ".agent-work/test-assets")
        let horizon = try loadGrayscale(assetDirectory.appendingPathComponent("horizon-tilted-8deg.png"), maxDimension: 360)
        let upright = try loadGrayscale(assetDirectory.appendingPathComponent("upright-facade-perspective.png"), maxDimension: 360)

        try analyzeHorizon(horizon)
        try analyzeUpright(upright)

        print("AnyUpright asset analysis passed")
    }

    private static func analyzeHorizon(_ image: AUGrayscaleImage) throws {
        let lines = AnyUprightLineDetection.detectLineSegments(
            in: image,
            options: AULineDetectionOptions(
                orientation: .horizontal,
                edgeThreshold: 40.0,
                voteThreshold: max(20, image.width / 5),
                maxLines: 40
            )
        )
        let candidates = AnyUprightGeometry.lineCandidates(
            from: lines,
            orientation: .horizontal,
            minimumLength: Double(image.width) * 0.25
        )
        let correction = try unwrap(
            AnyUprightGeometry.dominantHorizonCorrectionRadians(from: lines),
            "horizon correction"
        )
        let correctionDegrees = correction * 180.0 / .pi
        let detectedAngles = lines.prefix(8).map { line in
            atan2(line.end.y - line.start.y, line.end.x - line.start.x) * 180.0 / .pi
        }
        let candidateAngles = candidates.prefix(5).map { candidate in
            candidate.signedDeviationRadians * 180.0 / .pi
        }

        try assertTrue(candidates.count >= 2, "expected at least two horizontal horizon candidates, got \(candidates.count)")
        try assertApprox(abs(correctionDegrees), 8.0, "horizon correction magnitude detected=\(detectedAngles) candidates=\(candidateAngles)", accuracy: 2.5)
        print(String(
            format: "Horizon: candidates=%d correction=%.2f deg houghAngles=%@ sortedAngles=%@",
            candidates.count,
            correctionDegrees,
            String(describing: detectedAngles),
            String(describing: candidateAngles)
        ))
    }

    private static func analyzeUpright(_ image: AUGrayscaleImage) throws {
        let verticalLines = AnyUprightLineDetection.detectLineSegments(
            in: image,
            options: AULineDetectionOptions(
                orientation: .vertical,
                edgeThreshold: 40.0,
                voteThreshold: max(20, image.height / 5),
                maxLines: 40
            )
        )
        let horizontalLines = AnyUprightLineDetection.detectLineSegments(
            in: image,
            options: AULineDetectionOptions(
                orientation: .horizontal,
                edgeThreshold: 40.0,
                voteThreshold: max(20, image.width / 5),
                maxLines: 40
            )
        )
        let verticalCandidates = AnyUprightGeometry.lineCandidates(
            from: verticalLines,
            orientation: .vertical,
            minimumLength: Double(image.height) * 0.25
        )
        let horizontalCandidates = AnyUprightGeometry.lineCandidates(
            from: horizontalLines,
            orientation: .horizontal,
            minimumLength: Double(image.width) * 0.25
        )
        let size = AUSize(width: Double(image.width), height: Double(image.height))
        let verticalPerspective = try unwrap(
            AnyUprightGeometry.estimateVerticalPerspective(from: Array(verticalCandidates.prefix(2).map(\.line)), size: size),
            "vertical perspective"
        )
        let horizontalPerspective = try unwrap(
            AnyUprightGeometry.estimateHorizontalPerspective(from: Array(horizontalCandidates.prefix(2).map(\.line)), size: size),
            "horizontal perspective"
        )

        try assertTrue(verticalCandidates.count >= 4, "expected at least four vertical upright candidates, got \(verticalCandidates.count)")
        try assertTrue(horizontalCandidates.count >= 4, "expected at least four horizontal upright candidates, got \(horizontalCandidates.count)")
        try assertTrue(abs(verticalPerspective) <= 1.0, "expected bounded vertical perspective estimate, got \(verticalPerspective)")
        try assertTrue(abs(horizontalPerspective) <= 1.0, "expected bounded horizontal perspective estimate, got \(horizontalPerspective)")
        print(String(format: "Upright: verticalCandidates=%d horizontalCandidates=%d vertical=%.3f horizontal=%.3f", verticalCandidates.count, horizontalCandidates.count, verticalPerspective, horizontalPerspective))
    }

    private static func loadGrayscale(_ url: URL, maxDimension: Int) throws -> AUGrayscaleImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw AssetAnalysisFailure.failed("Unable to read image at \(url.path)")
        }

        let scale = min(1.0, Double(maxDimension) / Double(max(image.width, image.height)))
        let width = max(1, Int(round(Double(image.width) * scale)))
        let height = max(1, Int(round(Double(image.height) * scale)))
        var rgba = Array(repeating: UInt8(0), count: width * height * 4)

        guard let context = CGContext(
            data: &rgba,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw AssetAnalysisFailure.failed("Unable to create analysis context for \(url.path)")
        }

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        var gray = Array(repeating: UInt8(0), count: width * height)
        for index in 0..<(width * height) {
            let base = index * 4
            let red = Double(rgba[base])
            let green = Double(rgba[base + 1])
            let blue = Double(rgba[base + 2])
            gray[index] = UInt8(min(255.0, max(0.0, red * 0.299 + green * 0.587 + blue * 0.114)))
        }

        return AUGrayscaleImage(width: width, height: height, pixels: gray)
    }

    private static func unwrap<T>(_ value: T?, _ label: String) throws -> T {
        guard let value else {
            throw AssetAnalysisFailure.failed("Expected \(label), got nil")
        }
        return value
    }

    private static func assertApprox(_ actual: Double, _ expected: Double, _ label: String, accuracy: Double) throws {
        guard abs(actual - expected) <= accuracy else {
            throw AssetAnalysisFailure.failed("\(label): expected \(expected), got \(actual)")
        }
    }

    private static func assertTrue(_ value: Bool, _ label: String) throws {
        guard value else {
            throw AssetAnalysisFailure.failed(label)
        }
    }
}
