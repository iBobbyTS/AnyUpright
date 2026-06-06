//
//  render-warp-previews.swift
//  AnyUpright
//

import CoreGraphics
import Foundation
import ImageIO
import simd

enum WarpPreviewFailure: Error, CustomStringConvertible {
    case failed(String)

    var description: String {
        switch self {
        case .failed(let message):
            return message
        }
    }
}

struct RGBAImage {
    var width: Int
    var height: Int
    var pixels: [UInt8]

    func sample(x: Double, y: Double) -> (UInt8, UInt8, UInt8, UInt8) {
        guard x >= 0.0, y >= 0.0, x <= Double(width - 1), y <= Double(height - 1) else {
            return (0, 0, 0, 255)
        }

        let left = Int(floor(x))
        let top = Int(floor(y))
        let right = min(width - 1, left + 1)
        let bottom = min(height - 1, top + 1)
        let tx = x - Double(left)
        let ty = y - Double(top)

        let c00 = pixel(x: left, y: top)
        let c10 = pixel(x: right, y: top)
        let c01 = pixel(x: left, y: bottom)
        let c11 = pixel(x: right, y: bottom)

        func mix(_ a: UInt8, _ b: UInt8, _ c: UInt8, _ d: UInt8) -> UInt8 {
            let topValue = Double(a) * (1.0 - tx) + Double(b) * tx
            let bottomValue = Double(c) * (1.0 - tx) + Double(d) * tx
            return UInt8(min(255.0, max(0.0, topValue * (1.0 - ty) + bottomValue * ty)))
        }

        return (
            mix(c00.0, c10.0, c01.0, c11.0),
            mix(c00.1, c10.1, c01.1, c11.1),
            mix(c00.2, c10.2, c01.2, c11.2),
            mix(c00.3, c10.3, c01.3, c11.3)
        )
    }

    private func pixel(x: Int, y: Int) -> (UInt8, UInt8, UInt8, UInt8) {
        let index = (y * width + x) * 4
        return (pixels[index], pixels[index + 1], pixels[index + 2], pixels[index + 3])
    }
}

@main
struct RenderWarpPreviews {
    static func main() throws {
        let assetDirectory = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? ".agent-work/test-assets")
        let outputDirectory = URL(fileURLWithPath: CommandLine.arguments.dropFirst().dropFirst().first ?? ".agent-work/warp-previews")
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        try renderHorizonPreview(assetDirectory: assetDirectory, outputDirectory: outputDirectory)
        try renderQuadSourcePreview(assetDirectory: assetDirectory, outputDirectory: outputDirectory)
        try renderQuadOutputPreview(assetDirectory: assetDirectory, outputDirectory: outputDirectory)
        try renderUprightPreview(assetDirectory: assetDirectory, outputDirectory: outputDirectory)

        print("Rendered AnyUpright warp previews in \(outputDirectory.path)")
    }

    private static func renderHorizonPreview(assetDirectory: URL, outputDirectory: URL) throws {
        let image = try loadRGBA(assetDirectory.appendingPathComponent("horizon-tilted-8deg.png"))
        let size = AUSize(width: Double(image.width), height: Double(image.height))
        let angle = degreesToRadians(-8.0)
        let matrix = AnyUprightGeometry.rotationOutputToSource(angleRadians: angle, fillFrame: true, size: size)
        try assertTrue(AnyUprightGeometry.rotationScaleToFill(angleRadians: angle, size: size) > 1.0, "horizon fill should zoom rotated image")
        try saveWarped(image, outputSize: size, outputToSource: matrix, url: outputDirectory.appendingPathComponent("horizon-fill-preview.png"))
    }

    private static func renderQuadSourcePreview(assetDirectory: URL, outputDirectory: URL) throws {
        let image = try loadRGBA(assetDirectory.appendingPathComponent("quad-phone-screen.png"))
        let size = AUSize(width: Double(image.width), height: Double(image.height))
        let sourceQuad = AUQuad(
            topLeft: AUPoint(x: 520.0, y: 210.0),
            topRight: AUPoint(x: 1390.0, y: 305.0),
            bottomRight: AUPoint(x: 1285.0, y: 890.0),
            bottomLeft: AUPoint(x: 430.0, y: 790.0)
        )
        let offsets = pixelOffsets(for: sourceQuad, base: AnyUprightGeometry.sourceQuadDefault(size), size: size)
        let previewMatrix = AnyUprightGeometry.quadOutputToSourceMatrix(
            from: offsets,
            mode: .sourceQuad,
            showCornerAdjuster: true,
            outputSize: size,
            sourceSize: size
        )
        try assertMaps(previewMatrix, AUPoint(x: 321.0, y: 654.0), to: AUPoint(x: 321.0, y: 654.0), label: "source quad edit preview should keep image still")

        let appliedMatrix = AnyUprightGeometry.quadOutputToSourceMatrix(
            from: offsets,
            mode: .sourceQuad,
            showCornerAdjuster: false,
            outputSize: size,
            sourceSize: size
        )
        try assertMaps(appliedMatrix, AUPoint(x: 0.0, y: 0.0), to: sourceQuad.topLeft, label: "source quad top-left maps to source")
        try assertMaps(appliedMatrix, AUPoint(x: size.width, y: size.height), to: sourceQuad.bottomRight, label: "source quad bottom-right maps to source")
        try saveWarped(image, outputSize: size, outputToSource: appliedMatrix, url: outputDirectory.appendingPathComponent("quad-source-apply-preview.png"))

        let mirrorMatrix = AnyUprightGeometry.quadOutputToSourceMatrix(
            from: offsets,
            mode: .sourceQuad,
            stretchMode: .mirrorHorizontal,
            showCornerAdjuster: false,
            outputSize: size,
            sourceSize: size
        )
        let selectionToRect = AnyUprightGeometry.quadSelectionToOutputRectMatrix(
            from: offsets,
            outputSize: size,
            sourceSize: size
        )
        let outsidePoint = AUPoint(x: 30.0, y: 30.0)
        let insidePoint = sourceQuad.topLeft
        try assertTrue(!isInsideSelection(outsidePoint, selectionToRect: selectionToRect, outputSize: size), "source quad mirror outside probe should be outside")
        try assertTrue(isInsideSelection(insidePoint, selectionToRect: selectionToRect, outputSize: size), "source quad mirror inside probe should be inside")
        try assertMaps(mirrorMatrix, sourceQuad.topLeft, to: sourceQuad.topRight, label: "source quad horizontal mirror top-left")
        try saveSelectionOverOriginal(
            image,
            outputSize: size,
            selectionToRect: selectionToRect,
            selectionOutputToSource: mirrorMatrix,
            fallbackOutputToSource: AnyUprightGeometry.identityOutputToSourceMatrix(outputSize: size, sourceSize: size),
            url: outputDirectory.appendingPathComponent("quad-source-mirror-horizontal-preview.png")
        )
    }

    private static func renderQuadOutputPreview(assetDirectory: URL, outputDirectory: URL) throws {
        let image = try loadRGBA(assetDirectory.appendingPathComponent("quad-phone-screen.png"))
        let size = AUSize(width: Double(image.width), height: Double(image.height))
        var offsets = AUCornerOffsets()
        offsets.topLeftPixels = AUPoint(x: 180.0, y: -80.0)
        offsets.topRightPixels = AUPoint(x: -120.0, y: -40.0)
        offsets.bottomRightPixels = AUPoint(x: -260.0, y: 140.0)
        offsets.bottomLeftPixels = AUPoint(x: 120.0, y: 60.0)
        let outputQuad = AnyUprightGeometry.quad(from: offsets, size: size)
        let matrix = AnyUprightGeometry.quadOutputToSourceMatrix(
            from: offsets,
            mode: .outputCorners,
            showCornerAdjuster: false,
            outputSize: size,
            sourceSize: size
        )
        try assertMaps(matrix, outputQuad.topLeft, to: AUPoint(x: 0.0, y: 0.0), label: "output corner top-left maps to source frame")
        try saveWarped(image, outputSize: size, outputToSource: matrix, url: outputDirectory.appendingPathComponent("quad-output-corners-preview.png"))
    }

    private static func renderUprightPreview(assetDirectory: URL, outputDirectory: URL) throws {
        let image = try loadRGBA(assetDirectory.appendingPathComponent("upright-facade-perspective.png"))
        let size = AUSize(width: Double(image.width), height: Double(image.height))
        let outputQuad = AnyUprightGeometry.uprightQuad(vertical: 0.45, horizontal: -0.25, size: size)
        let verticalOnlyQuad = AnyUprightGeometry.uprightQuad(vertical: 0.45, horizontal: 0.0, size: size)
        let horizontalOnlyQuad = AnyUprightGeometry.uprightQuad(vertical: 0.0, horizontal: -0.25, size: size)
        let perspective = AnyUprightGeometry.uprightOutputToSourceMatrix(vertical: 0.45, horizontal: -0.25, size: size)
        let rotation = AnyUprightGeometry.rotationOutputToSource(angleRadians: degreesToRadians(-2.0), fillFrame: false, size: size)
        let matrix = AnyUprightGeometry.multiply(perspective, rotation)

        try assertTrue(verticalOnlyQuad.topLeft.x > 0.0 && verticalOnlyQuad.bottomLeft.x < 0.0, "positive vertical perspective should move top inward and bottom outward")
        try assertTrue(horizontalOnlyQuad.topRight.y < 0.0 && horizontalOnlyQuad.bottomRight.y > size.height, "negative horizontal perspective should move right side outward around centerline")
        try assertMaps(perspective, AUPoint(x: size.width / 2.0, y: size.height / 2.0), to: AUPoint(x: size.width / 2.0, y: size.height / 2.0), label: "upright perspective should keep center anchored")
        try assertMaps(AnyUprightGeometry.homography(from: outputQuad, to: AUQuad.fullFrame(size)), AUPoint(x: size.width / 2.0, y: size.height / 2.0), to: AUPoint(x: size.width / 2.0, y: size.height / 2.0), label: "derived upright quad should keep center anchored")
        try saveWarped(image, outputSize: size, outputToSource: matrix, url: outputDirectory.appendingPathComponent("upright-centered-preview.png"))
    }

    private static func pixelOffsets(for quad: AUQuad, size: AUSize) -> AUCornerOffsets {
        pixelOffsets(for: quad, base: AUQuad.fullFrame(size), size: size)
    }

    private static func pixelOffsets(for quad: AUQuad, base: AUQuad, size: AUSize) -> AUCornerOffsets {
        func offset(base: AUPoint, target: AUPoint) -> AUPoint {
            AUPoint(x: target.x - base.x, y: base.y - target.y)
        }

        var offsets = AUCornerOffsets()
        offsets.topLeftPixels = offset(base: base.topLeft, target: quad.topLeft)
        offsets.topRightPixels = offset(base: base.topRight, target: quad.topRight)
        offsets.bottomRightPixels = offset(base: base.bottomRight, target: quad.bottomRight)
        offsets.bottomLeftPixels = offset(base: base.bottomLeft, target: quad.bottomLeft)
        return offsets
    }

    private static func saveWarped(_ image: RGBAImage, outputSize: AUSize, outputToSource: simd_float3x3, url: URL) throws {
        let outputWidth = Int(outputSize.width.rounded())
        let outputHeight = Int(outputSize.height.rounded())
        var rgba = Array(repeating: UInt8(0), count: outputWidth * outputHeight * 4)

        for y in 0..<outputHeight {
            for x in 0..<outputWidth {
                let source = AnyUprightGeometry.transform(AUPoint(x: Double(x), y: Double(y)), by: outputToSource)
                let color = image.sample(x: source.x, y: source.y)
                let index = (y * outputWidth + x) * 4
                rgba[index] = color.0
                rgba[index + 1] = color.1
                rgba[index + 2] = color.2
                rgba[index + 3] = color.3
            }
        }

        try saveRGBA(RGBAImage(width: outputWidth, height: outputHeight, pixels: rgba), url: url)
    }

    private static func saveSelectionOverOriginal(
        _ image: RGBAImage,
        outputSize: AUSize,
        selectionToRect: simd_float3x3,
        selectionOutputToSource: simd_float3x3,
        fallbackOutputToSource: simd_float3x3,
        url: URL
    ) throws {
        let outputWidth = Int(outputSize.width.rounded())
        let outputHeight = Int(outputSize.height.rounded())
        var rgba = Array(repeating: UInt8(0), count: outputWidth * outputHeight * 4)

        for y in 0..<outputHeight {
            for x in 0..<outputWidth {
                let outputPoint = AUPoint(x: Double(x), y: Double(y))
                let matrix = isInsideSelection(outputPoint, selectionToRect: selectionToRect, outputSize: outputSize)
                    ? selectionOutputToSource
                    : fallbackOutputToSource
                let source = AnyUprightGeometry.transform(outputPoint, by: matrix)
                let color = image.sample(x: source.x, y: source.y)
                let index = (y * outputWidth + x) * 4
                rgba[index] = color.0
                rgba[index + 1] = color.1
                rgba[index + 2] = color.2
                rgba[index + 3] = color.3
            }
        }

        try saveRGBA(RGBAImage(width: outputWidth, height: outputHeight, pixels: rgba), url: url)
    }

    private static func isInsideSelection(_ point: AUPoint, selectionToRect: simd_float3x3, outputSize: AUSize) -> Bool {
        let rectPoint = AnyUprightGeometry.transform(point, by: selectionToRect)
        return rectPoint.x >= 0.0 &&
            rectPoint.x <= outputSize.width &&
            rectPoint.y >= 0.0 &&
            rectPoint.y <= outputSize.height
    }

    private static func loadRGBA(_ url: URL) throws -> RGBAImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw WarpPreviewFailure.failed("Unable to read image at \(url.path)")
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
            throw WarpPreviewFailure.failed("Unable to create bitmap context for \(url.path)")
        }

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return RGBAImage(width: image.width, height: image.height, pixels: rgba)
    }

    private static func saveRGBA(_ image: RGBAImage, url: URL) throws {
        var pixels = image.pixels
        guard let context = CGContext(
            data: &pixels,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: image.width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let cgImage = context.makeImage() else {
            throw WarpPreviewFailure.failed("Unable to create output image for \(url.path)")
        }

        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
            throw WarpPreviewFailure.failed("Unable to create PNG destination for \(url.path)")
        }
        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw WarpPreviewFailure.failed("Unable to write \(url.path)")
        }
    }

    private static func assertMaps(_ matrix: simd_float3x3, _ point: AUPoint, to expected: AUPoint, label: String) throws {
        let actual = AnyUprightGeometry.transform(point, by: matrix)
        try assertApprox(actual.x, expected.x, "\(label) x", accuracy: 0.02)
        try assertApprox(actual.y, expected.y, "\(label) y", accuracy: 0.02)
    }

    private static func assertApprox(_ actual: Double, _ expected: Double, _ label: String, accuracy: Double) throws {
        guard abs(actual - expected) <= accuracy else {
            throw WarpPreviewFailure.failed("\(label): expected \(expected), got \(actual)")
        }
    }

    private static func assertTrue(_ value: Bool, _ label: String) throws {
        guard value else {
            throw WarpPreviewFailure.failed(label)
        }
    }

    private static func degreesToRadians(_ degrees: Double) -> Double {
        degrees * .pi / 180.0
    }
}
