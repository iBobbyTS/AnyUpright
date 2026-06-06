//
//  validate-warp-previews.swift
//  AnyUpright
//

import CoreGraphics
import Foundation
import ImageIO

enum WarpPreviewValidationFailure: Error, CustomStringConvertible {
    case failed(String)

    var description: String {
        switch self {
        case .failed(let message):
            return message
        }
    }
}

struct PreviewExpectation {
    var fileName: String
    var minimumLitPixelRatio: Double
}

struct PreviewImage {
    var width: Int
    var height: Int
    var pixels: [UInt8]
}

struct ValidateWarpPreviews {
    static func run() throws {
        let directory = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? ".agent-work/warp-previews")
        let expected = [
            PreviewExpectation(fileName: "horizon-fill-preview.png", minimumLitPixelRatio: 0.20),
            PreviewExpectation(fileName: "quad-source-adjuster-preview.png", minimumLitPixelRatio: 0.10),
            PreviewExpectation(fileName: "quad-source-apply-preview.png", minimumLitPixelRatio: 0.10),
            PreviewExpectation(fileName: "quad-output-corners-preview.png", minimumLitPixelRatio: 0.10),
            PreviewExpectation(fileName: "upright-centered-preview.png", minimumLitPixelRatio: 0.10)
        ]

        for item in expected {
            let image = try loadRGBA(directory.appendingPathComponent(item.fileName))
            try assertTrue(image.width == 1920 && image.height == 1080, "\(item.fileName) should be 1920x1080, got \(image.width)x\(image.height)")

            let litRatio = litPixelRatio(image)
            try assertTrue(
                litRatio >= item.minimumLitPixelRatio,
                "\(item.fileName) looks blank or mostly black: lit ratio \(String(format: "%.3f", litRatio))"
            )
        }

        print("AnyUpright warp preview validation passed")
    }

    private static func loadRGBA(_ url: URL) throws -> PreviewImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw WarpPreviewValidationFailure.failed("Unable to read preview at \(url.path)")
        }

        var rgba = Array(repeating: UInt8(0), count: image.width * image.height * 4)
        guard let context = CGContext(
            data: &rgba,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: image.width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw WarpPreviewValidationFailure.failed("Unable to create bitmap context for \(url.path)")
        }

        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return PreviewImage(width: image.width, height: image.height, pixels: rgba)
    }

    private static func litPixelRatio(_ image: PreviewImage) -> Double {
        guard image.width > 0, image.height > 0 else {
            return 0.0
        }

        var litPixels = 0
        let pixelCount = image.width * image.height
        for index in 0..<pixelCount {
            let base = index * 4
            let red = Int(image.pixels[base])
            let green = Int(image.pixels[base + 1])
            let blue = Int(image.pixels[base + 2])
            if red + green + blue > 30 {
                litPixels += 1
            }
        }

        return Double(litPixels) / Double(pixelCount)
    }

    private static func assertTrue(_ value: Bool, _ label: String) throws {
        guard value else {
            throw WarpPreviewValidationFailure.failed(label)
        }
    }
}

do {
    try ValidateWarpPreviews.run()
} catch {
    FileHandle.standardError.write(Data("\(error)\n".utf8))
    exit(1)
}
