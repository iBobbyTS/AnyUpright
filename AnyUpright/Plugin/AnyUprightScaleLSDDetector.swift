//
//  AnyUprightScaleLSDDetector.swift
//  AnyUpright
//

import CoreImage
import CoreML
import Foundation

enum AUScaleLSDDetectorError: Error, CustomStringConvertible {
    case missingFrameImage
    case missingModel([URL])
    case invalidInput

    var description: String {
        switch self {
        case .missingFrameImage:
            return "Missing frame image for ScaleLSD detection"
        case .missingModel(let urls):
            return "Missing ScaleLSD Core ML model at \(urls.map(\.path).joined(separator: ", "))"
        case .invalidInput:
            return "Could not build the fixed-512 ScaleLSD input"
        }
    }
}

private final class AUScaleLSDResourceAnchor: NSObject {}

enum AnyUprightScaleLSDDetector {
    private static let inputSize = 512
    private static let sessionLock = NSLock()
    private static var cachedModelURL: URL?
    private static var cachedSession: AUScaleLSDCoreMLSession?

    static func detectCandidates(
        in frame: FxImageTile,
        request: UprightAnalysisRequest,
        context: CIContext
    ) throws -> [UprightDetectedCandidate] {
        let source = try renderSourceRGBA(from: frame, context: context)
        guard let input = AnyUprightScaleLSDPreprocessor.normalizedGrayscaleNCHW(from: source) else {
            throw AUScaleLSDDetectorError.invalidInput
        }
        let dense = try session().run(inputNCHW: input)
        let lines = try AnyUprightScaleLSDPostprocessor.decode(
            denseLogits: dense.values,
            shape: dense.shape,
            imageWidth: source.width,
            imageHeight: source.height
        )
        let candidates = AnyUprightScaleLSDPreprocessor.detectedCandidates(
            from: lines,
            imageSize: AUSize(width: Double(source.width), height: Double(source.height))
        )
        return AnyUprightUprightCandidates.analysisCandidates(from: candidates, request: request)
    }

    private static func session() throws -> AUScaleLSDCoreMLSession {
        let modelURL = try resolvedModelURL()
        sessionLock.lock()
        defer { sessionLock.unlock() }
        if let cachedSession, cachedModelURL == modelURL {
            return cachedSession
        }
        let session = try AUScaleLSDCoreMLSession(modelURL: modelURL, computeUnits: .all)
        cachedModelURL = modelURL
        cachedSession = session
        return session
    }

    private static func resolvedModelURL() throws -> URL {
        let roots = [
            Bundle(for: AUScaleLSDResourceAnchor.self).resourceURL,
            Bundle.main.resourceURL,
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
        ].compactMap { $0 }
        let candidates = roots.flatMap { root in
            [
                root.appendingPathComponent("scalelsd_neural_forward.mlmodelc", isDirectory: true),
                root.appendingPathComponent("ScaleLSDCoreML/scalelsd_neural_forward.mlmodelc", isDirectory: true),
                root.appendingPathComponent("Plugin/ScaleLSDCoreML/scalelsd_neural_forward.mlmodelc", isDirectory: true),
                root.appendingPathComponent("AnyUpright/Plugin/ScaleLSDCoreML/scalelsd_neural_forward.mlmodelc", isDirectory: true),
            ]
        }
        for candidate in candidates where FileManager.default.fileExists(atPath: candidate.path) {
            return candidate
        }
        throw AUScaleLSDDetectorError.missingModel(candidates)
    }

    private static func renderSourceRGBA(
        from frame: FxImageTile,
        context: CIContext
    ) throws -> AUScaleLSDRGBAImage {
        guard let sourceImage = AnyUprightAnalysisImage.ciImage(from: frame) else {
            throw AUScaleLSDDetectorError.missingFrameImage
        }
        let bounds = frame.imagePixelBounds
        let sourceWidth = max(1, Int(bounds.right - bounds.left))
        let sourceHeight = max(1, Int(bounds.top - bounds.bottom))
        let originNormalized = sourceImage.transformed(
            by: CGAffineTransform(
                translationX: -CGFloat(bounds.left),
                y: -CGFloat(bounds.bottom)
            )
        )
        let analysisImage = originNormalized.transformed(
            by: CGAffineTransform(
                scaleX: CGFloat(inputSize) / CGFloat(sourceWidth),
                y: CGFloat(inputSize) / CGFloat(sourceHeight)
            )
        )
        var pixels = [UInt8](repeating: 0, count: inputSize * inputSize * 4)
        context.render(
            analysisImage,
            toBitmap: &pixels,
            rowBytes: inputSize * 4,
            bounds: CGRect(x: 0, y: 0, width: inputSize, height: inputSize),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        return AUScaleLSDRGBAImage(width: inputSize, height: inputSize, pixels: pixels)
    }
}
