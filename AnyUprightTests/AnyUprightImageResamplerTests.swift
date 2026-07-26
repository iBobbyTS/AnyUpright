import Darwin
import Foundation
import Metal
import MetalPerformanceShaders

private struct TestFailure: Error, CustomStringConvertible {
    let description: String
}

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() {
        throw TestFailure(description: message)
    }
}

private func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) throws {
    try expect(actual == expected, "\(message): expected \(expected), got \(actual)")
}

private func expectNear(_ actual: Double, _ expected: Double, tolerance: Double, _ message: String) throws {
    try expect(abs(actual - expected) <= tolerance, "\(message): expected \(expected), got \(actual)")
}

@main
enum AnyUprightImageResamplerTests {
    static func main() {
        do {
            try testStretchGeometry()
            try testLandscapeAspectFillGeometryMatchesGeoCalibContract()
            try testPortraitAspectFillGeometryMatchesGeoCalibContract()
            try testInvalidDimensions()
            try testAnalysisDeviceResolverUsesSystemDefaultForZeroRegistryID()
            try testAnalysisDeviceResolverPrefersExactRegistryMatch()
            try testAnalysisDeviceResolverFallsBackForUnknownRegistryID()
            try testConstantColorGPUResampling()
            try testGrayscaleNormalizationClampsHDRInput()
            try testBGRA8ChannelOrder()
            try testAspectFillCenterCropGPUTransform()
            try testPaddedTextureUsesOnlyValidSourceBounds()
            try testCheckerboardGPUDownsampling()
            print("AnyUprightImageResamplerTests passed")
        } catch {
            fputs("AnyUprightImageResamplerTests failed: \(error)\n", stderr)
            exit(1)
        }
    }

    private static func testStretchGeometry() throws {
        let geometry = try AUImageResamplingGeometry(
            sourceWidth: 5712,
            sourceHeight: 4284,
            targetWidth: 512,
            targetHeight: 512,
            layout: .stretch
        )
        try expectEqual(geometry.resizedWidth, 512, "stretch width")
        try expectEqual(geometry.resizedHeight, 512, "stretch height")
        try expectEqual(geometry.cropLeft, 0, "stretch crop left")
        try expectEqual(geometry.cropTop, 0, "stretch crop top")
        try expectNear(geometry.scaleTransform.scaleX, 512.0 / 5712.0, tolerance: 1e-12, "stretch scale x")
        try expectNear(geometry.scaleTransform.scaleY, 512.0 / 4284.0, tolerance: 1e-12, "stretch scale y")
    }

    private static func testLandscapeAspectFillGeometryMatchesGeoCalibContract() throws {
        let geometry = try AUImageResamplingGeometry(
            sourceWidth: 1920,
            sourceHeight: 1080,
            targetWidth: 544,
            targetHeight: 320,
            layout: .aspectFillCenterCrop
        )
        try expectEqual(geometry.resizedWidth, 568, "landscape resized width")
        try expectEqual(geometry.resizedHeight, 320, "landscape resized height")
        try expectEqual(geometry.cropLeft, 12, "landscape crop left")
        try expectEqual(geometry.cropTop, 0, "landscape crop top")
        try expectNear(geometry.scaleTransform.translateX, -12.0, tolerance: 0.0, "landscape translation x")
    }

    private static func testPortraitAspectFillGeometryMatchesGeoCalibContract() throws {
        let geometry = try AUImageResamplingGeometry(
            sourceWidth: 1080,
            sourceHeight: 1920,
            targetWidth: 320,
            targetHeight: 544,
            layout: .aspectFillCenterCrop
        )
        try expectEqual(geometry.resizedWidth, 320, "portrait resized width")
        try expectEqual(geometry.resizedHeight, 568, "portrait resized height")
        try expectEqual(geometry.cropLeft, 0, "portrait crop left")
        try expectEqual(geometry.cropTop, 12, "portrait crop top")
        try expectNear(geometry.scaleTransform.translateY, -12.0, tolerance: 0.0, "portrait translation y")
    }

    private static func testInvalidDimensions() throws {
        do {
            _ = try AUImageResamplingGeometry(
                sourceWidth: 0,
                sourceHeight: 1080,
                targetWidth: 512,
                targetHeight: 512,
                layout: .stretch
            )
            throw TestFailure(description: "zero source width should fail")
        } catch AUImageResamplingError.invalidDimensions {
            return
        }
    }

    private static func testAnalysisDeviceResolverUsesSystemDefaultForZeroRegistryID() throws {
        let device = try requireDevice()
        let resolved = AUAppleSiliconMetalDeviceResolver.resolve(
            preferredRegistryID: 0,
            availableDevices: [],
            systemDefaultDevice: device
        )
        try expectEqual(resolved?.registryID, device.registryID, "zero registry ID should use system default device")
    }

    private static func testAnalysisDeviceResolverPrefersExactRegistryMatch() throws {
        let device = try requireDevice()
        let resolved = AUAppleSiliconMetalDeviceResolver.resolve(
            preferredRegistryID: device.registryID,
            availableDevices: [device],
            systemDefaultDevice: nil
        )
        try expectEqual(resolved?.registryID, device.registryID, "exact registry ID should use matching device")
    }

    private static func testAnalysisDeviceResolverFallsBackForUnknownRegistryID() throws {
        let device = try requireDevice()
        let unknownRegistryID = device.registryID == UInt64.max ? device.registryID - 1 : device.registryID + 1
        let resolved = AUAppleSiliconMetalDeviceResolver.resolve(
            preferredRegistryID: unknownRegistryID,
            availableDevices: [device],
            systemDefaultDevice: device
        )
        try expectEqual(resolved?.registryID, device.registryID, "unknown registry ID should use system default device")
    }

    private static func testConstantColorGPUResampling() throws {
        let device = try requireDevice()
        let source = try makeTexture(
            device: device,
            width: 32,
            height: 24,
            pixels: Array(repeating: SIMD4<Float>(0.2, 0.4, 0.6, 1.0), count: 32 * 24)
        )
        guard let queue = device.makeCommandQueue() else {
            throw TestFailure(description: "could not create Metal command queue")
        }

        let rgb = try AUAppleSiliconImageResampler.resample(
            sourceTexture: source,
            sourceWidth: 32,
            sourceHeight: 24,
            targetWidth: 8,
            targetHeight: 8,
            layout: .stretch,
            channels: .rgb,
            commandQueue: queue
        )
        try expectEqual(rgb.shape, [1, 3, 8, 8], "RGB tensor shape")
        let center = 4 * 8 + 4
        try expectNear(Double(rgb.values[center]), 0.2, tolerance: 0.002, "red channel")
        try expectNear(Double(rgb.values[64 + center]), 0.4, tolerance: 0.002, "green channel")
        try expectNear(Double(rgb.values[128 + center]), 0.6, tolerance: 0.002, "blue channel")

        let grayscale = try AUAppleSiliconImageResampler.resample(
            sourceTexture: source,
            sourceWidth: 32,
            sourceHeight: 24,
            targetWidth: 8,
            targetHeight: 8,
            layout: .aspectFillCenterCrop,
            channels: .grayscale,
            commandQueue: queue
        )
        try expectEqual(grayscale.shape, [1, 1, 8, 8], "grayscale tensor shape")
        let expectedGray = 0.2 * 0.299 + 0.4 * 0.587 + 0.6 * 0.114
        try expectNear(Double(grayscale.values[center]), expectedGray, tolerance: 0.002, "grayscale weights")
    }

    private static func testCheckerboardGPUDownsampling() throws {
        let device = try requireDevice()
        let size = 64
        let pixels = (0..<(size * size)).map { index -> SIMD4<Float> in
            let x = index % size
            let y = index / size
            let value: Float = (x + y).isMultiple(of: 2) ? 0.0 : 1.0
            return SIMD4<Float>(value, value, value, 1.0)
        }
        let source = try makeTexture(device: device, width: size, height: size, pixels: pixels)
        guard let queue = device.makeCommandQueue() else {
            throw TestFailure(description: "could not create Metal command queue")
        }
        let result = try AUAppleSiliconImageResampler.resample(
            sourceTexture: source,
            sourceWidth: size,
            sourceHeight: size,
            targetWidth: 8,
            targetHeight: 8,
            layout: .stretch,
            channels: .grayscale,
            commandQueue: queue
        )

        for y in 2..<6 {
            for x in 2..<6 {
                try expectNear(
                    Double(result.values[y * 8 + x]),
                    0.5,
                    tolerance: 0.08,
                    "checkerboard center should be antialiased"
                )
            }
        }
    }

    private static func testGrayscaleNormalizationClampsHDRInput() throws {
        let device = try requireDevice()
        let source = try makeTexture(
            device: device,
            width: 4,
            height: 4,
            pixels: Array(repeating: SIMD4<Float>(2.0, 2.0, 2.0, 1.0), count: 16)
        )
        guard let queue = device.makeCommandQueue() else {
            throw TestFailure(description: "could not create Metal command queue")
        }
        let result = try AUAppleSiliconImageResampler.resample(
            sourceTexture: source,
            sourceWidth: 4,
            sourceHeight: 4,
            targetWidth: 2,
            targetHeight: 2,
            layout: .stretch,
            channels: .grayscale,
            commandQueue: queue
        )
        try expect(result.values.allSatisfy { $0 == 1.0 }, "ScaleLSD grayscale tensor must remain normalized")
    }

    private static func testBGRA8ChannelOrder() throws {
        let device = try requireDevice()
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: 4,
            height: 4,
            mipmapped: false
        )
        descriptor.storageMode = .shared
        descriptor.usage = [.shaderRead]
        guard let texture = device.makeTexture(descriptor: descriptor),
              let queue = device.makeCommandQueue() else {
            throw TestFailure(description: "could not create BGRA8 test resources")
        }
        let bgra = Array(repeating: UInt8(0), count: 4 * 4 * 4)
        var pixels = bgra
        for index in 0..<(4 * 4) {
            pixels[index * 4] = 51
            pixels[index * 4 + 1] = 102
            pixels[index * 4 + 2] = 204
            pixels[index * 4 + 3] = 255
        }
        pixels.withUnsafeBytes { bytes in
            texture.replace(
                region: MTLRegionMake2D(0, 0, 4, 4),
                mipmapLevel: 0,
                withBytes: bytes.baseAddress!,
                bytesPerRow: 4 * 4
            )
        }

        let result = try AUAppleSiliconImageResampler.resample(
            sourceTexture: texture,
            sourceWidth: 4,
            sourceHeight: 4,
            targetWidth: 2,
            targetHeight: 2,
            layout: .stretch,
            channels: .rgb,
            commandQueue: queue
        )
        try expectNear(Double(result.values[0]), 0.8, tolerance: 0.01, "BGRA red channel")
        try expectNear(Double(result.values[4]), 0.4, tolerance: 0.01, "BGRA green channel")
        try expectNear(Double(result.values[8]), 0.2, tolerance: 0.01, "BGRA blue channel")
    }

    private static func testAspectFillCenterCropGPUTransform() throws {
        let device = try requireDevice()
        let width = 8
        let height = 4
        let pixels = (0..<(width * height)).map { index -> SIMD4<Float> in
            let value = Float(index % width) / Float(width - 1)
            return SIMD4<Float>(value, 0.0, 0.0, 1.0)
        }
        let source = try makeTexture(device: device, width: width, height: height, pixels: pixels)
        guard let queue = device.makeCommandQueue() else {
            throw TestFailure(description: "could not create Metal command queue")
        }
        let result = try AUAppleSiliconImageResampler.resample(
            sourceTexture: source,
            sourceWidth: width,
            sourceHeight: height,
            targetWidth: 4,
            targetHeight: 4,
            layout: .aspectFillCenterCrop,
            channels: .rgb,
            commandQueue: queue
        )

        try expectNear(Double(result.values[2 * 4]), 2.0 / 7.0, tolerance: 0.03, "center crop left source position")
        try expectNear(Double(result.values[2 * 4 + 3]), 5.0 / 7.0, tolerance: 0.03, "center crop right source position")
    }

    private static func testPaddedTextureUsesOnlyValidSourceBounds() throws {
        let device = try requireDevice()
        let size = 8
        var pixels = Array(repeating: SIMD4<Float>(0.0, 1.0, 0.0, 1.0), count: size * size)
        for y in 0..<4 {
            for x in 0..<4 {
                pixels[y * size + x] = SIMD4<Float>(1.0, 0.0, 0.0, 1.0)
            }
        }
        let source = try makeTexture(device: device, width: size, height: size, pixels: pixels)
        guard let queue = device.makeCommandQueue() else {
            throw TestFailure(description: "could not create Metal command queue")
        }
        let result = try AUAppleSiliconImageResampler.resample(
            sourceTexture: source,
            sourceWidth: 4,
            sourceHeight: 4,
            targetWidth: 2,
            targetHeight: 2,
            layout: .stretch,
            channels: .rgb,
            commandQueue: queue
        )

        try expect(result.values[0..<4].allSatisfy { abs($0 - 1.0) < 0.01 }, "valid source region should remain red")
        try expect(result.values[4..<12].allSatisfy { abs($0) < 0.01 }, "padded green region must not enter the tensor")
    }

    private static func requireDevice() throws -> MTLDevice {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw TestFailure(description: "Apple Silicon Metal device is unavailable")
        }
        return device
    }

    private static func makeTexture(
        device: MTLDevice,
        width: Int,
        height: Int,
        pixels: [SIMD4<Float>]
    ) throws -> MTLTexture {
        try expectEqual(pixels.count, width * height, "source pixel count")
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba32Float,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.storageMode = .shared
        descriptor.usage = [.shaderRead]
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw TestFailure(description: "could not create source texture")
        }
        pixels.withUnsafeBytes { bytes in
            texture.replace(
                region: MTLRegionMake2D(0, 0, width, height),
                mipmapLevel: 0,
                withBytes: bytes.baseAddress!,
                bytesPerRow: width * MemoryLayout<SIMD4<Float>>.stride
            )
        }
        return texture
    }
}
