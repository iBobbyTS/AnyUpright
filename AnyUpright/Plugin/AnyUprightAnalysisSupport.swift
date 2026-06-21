//
//  AnyUprightAnalysisSupport.swift
//  AnyUpright
//

import Foundation
import AppKit
import CoreImage
import IOSurface
import Vision

func singleFrameAnalysisRange(near requestedTime: CMTime, within inputTimeRange: CMTimeRange) -> CMTimeRange {
    let analysisWindow = CMTime(seconds: 0.05, preferredTimescale: 600)
    let duration = CMTimeCompare(inputTimeRange.duration, analysisWindow) < 0 ? inputTimeRange.duration : analysisWindow
    var start = inputTimeRange.start

    if requestedTime.isValid,
       requestedTime.isNumeric,
       CMTimeRangeContainsTime(inputTimeRange, time: requestedTime) {
        let latestStart = CMTimeSubtract(CMTimeRangeGetEnd(inputTimeRange), duration)
        start = CMTimeCompare(requestedTime, latestStart) > 0 ? latestStart : requestedTime
    }

    return CMTimeRange(start: start, duration: duration)
}

func parameterWriteTime(preferred: CMTime, fallback: CMTime) -> CMTime {
    if preferred.isValid, preferred.isNumeric {
        return preferred
    }

    return fallback
}

struct HorizonAnalysisScratchState {
    var detectedRotationRadians: Double?
    var detectedRotationTime = CMTime.zero
    var requestedAnalysisTime = CMTime.zero
}

struct UprightAnalysisScratchState {
    var pendingAnalysisMode: UprightAnalysisMode?
    var detectedVerticalPerspective: Double?
    var detectedHorizontalPerspective: Double?
    var detectedRotationRadians: Double?
    var detectedCandidates: [UprightDetectedCandidate] = []
    var detectedPerspectiveTime = CMTime.zero
    var requestedAnalysisTime = CMTime.zero
}

struct QuadAnalysisScratchState {
    var hasPendingSourceQuadDetection = false
    var detectedSourcePrimitives = QuadDetectedSourcePrimitives()
    var detectedSourceSize = AUSize(width: 1.0, height: 1.0)
    var detectedSourceQuadTime = CMTime.zero
    var requestedAnalysisTime = CMTime.zero
}

struct AURGBFloatImage {
    var width: Int
    var height: Int
    var pixelsNCHW: [Float]
}

enum AnyUprightAnalysisImage {
    static func ciImage(from frame: FxImageTile) -> CIImage? {
        guard let ioSurface = frame.ioSurface else {
            return nil
        }

        let colorSpace = frame.colorSpace.map { $0 as Any }
        return CIImage(ioSurface: ioSurface, options: colorSpace.map { [.colorSpace: $0] } ?? [:])
    }

    static func grayscaleImage(from frame: FxImageTile, maxDimension: Int, context: CIContext) -> AUGrayscaleImage? {
        guard let sourceImage = ciImage(from: frame) else {
            return nil
        }

        let bounds = frame.imagePixelBounds
        let sourceWidth = max(1, Int(bounds.right - bounds.left))
        let sourceHeight = max(1, Int(bounds.top - bounds.bottom))
        let scale = min(1.0, Double(maxDimension) / Double(max(sourceWidth, sourceHeight)))
        let width = max(1, Int(round(Double(sourceWidth) * scale)))
        let height = max(1, Int(round(Double(sourceHeight) * scale)))
        let image = sourceImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        var rgba = Array(repeating: UInt8(0), count: width * height * 4)

        context.render(
            image,
            toBitmap: &rgba,
            rowBytes: width * 4,
            bounds: CGRect(x: 0, y: 0, width: width, height: height),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )

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

    static func rgbFloatImage(from frame: FxImageTile, maxDimension: Int? = nil, context: CIContext) -> AURGBFloatImage? {
        guard let sourceImage = ciImage(from: frame) else {
            return nil
        }

        let bounds = frame.imagePixelBounds
        let sourceWidth = max(1, Int(bounds.right - bounds.left))
        let sourceHeight = max(1, Int(bounds.top - bounds.bottom))
        let scale: Double
        if let maxDimension {
            scale = min(1.0, Double(maxDimension) / Double(max(sourceWidth, sourceHeight)))
        } else {
            scale = 1.0
        }
        let width = max(1, Int(round(Double(sourceWidth) * scale)))
        let height = max(1, Int(round(Double(sourceHeight) * scale)))
        let image = sourceImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        var rgba = Array(repeating: UInt8(0), count: width * height * 4)

        context.render(
            image,
            toBitmap: &rgba,
            rowBytes: width * 4,
            bounds: CGRect(x: 0, y: 0, width: width, height: height),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )

        var rgb = Array(repeating: Float(0), count: width * height * 3)
        let planeSize = width * height
        for index in 0..<planeSize {
            let base = index * 4
            rgb[index] = Float(rgba[base]) / 255.0
            rgb[planeSize + index] = Float(rgba[base + 1]) / 255.0
            rgb[2 * planeSize + index] = Float(rgba[base + 2]) / 255.0
        }

        return AURGBFloatImage(width: width, height: height, pixelsNCHW: rgb)
    }
}
