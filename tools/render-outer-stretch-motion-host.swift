//
//  render-outer-stretch-motion-host.swift
//  AnyUpright
//
//  Runs the production Outer Stretch preview and OSC texture shaders, then
//  applies Motion's observed Y-flipped composition of the returned OSC surface.
//

import CoreGraphics
import Foundation
import ImageIO
import Metal
import UniformTypeIdentifiers

enum MotionHostSimulationFailure: Error, CustomStringConvertible {
    case failed(String)

    var description: String {
        switch self {
        case .failed(let message):
            return message
        }
    }
}

@main
struct RenderOuterStretchMotionHost {
    static func main() throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard arguments.count == 2 else {
            throw MotionHostSimulationFailure.failed(
                "Usage: render-outer-stretch-motion-host <production-metallib> <output-png>"
            )
        }

        let metallibURL = URL(fileURLWithPath: arguments[0])
        let outputURL = URL(fileURLWithPath: arguments[1])
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let commandBuffer = queue.makeCommandBuffer() else {
            throw MotionHostSimulationFailure.failed("Metal is unavailable")
        }
        let library = try device.makeLibrary(URL: metallibURL)

        let canvasSize = AUSize(width: 1200.0, height: 900.0)
        let logicalCorners = AUStretchCorners(
            topLeft: AUPoint(x: -192.0, y: -162.0),
            topRight: AUPoint(x: 1200.0, y: 0.0),
            bottomRight: AUPoint(x: 1200.0, y: 900.0),
            bottomLeft: AUPoint(x: 0.0, y: 900.0)
        )
        let physicalCorners = AnyUprightGeometry.verticallyFlippedPixelSelection(
            logicalCorners,
            size: canvasSize
        )
        guard let layout = AUOuterStretchOSCPreviewLayout.make(
            corners: physicalCorners,
            outputSize: canvasSize
        ) else {
            throw MotionHostSimulationFailure.failed("Fixture should extend outside the canvas")
        }

        let sourceTexture = try makeBlueSourceTexture(device: device, size: canvasSize)
        var warpState = makeWarpState(
            logicalCorners: logicalCorners,
            physicalCorners: physicalCorners,
            canvasSize: canvasSize
        )
        let previewTexture = try encodeProductionPreviewPass(
            commandBuffer: commandBuffer,
            device: device,
            library: library,
            inputTexture: sourceTexture,
            warpState: &warpState,
            layout: layout
        )

        let leftMargin = 240.0
        let rightMargin = 80.0
        let topMargin = 220.0
        let bottomMargin = 220.0
        let surfaceSize = AUSize(
            width: leftMargin + canvasSize.width + rightMargin,
            height: topMargin + canvasSize.height + bottomMargin
        )
        let canvasOrigin = AUPoint(x: leftMargin, y: bottomMargin)
        let canvasCorners = layout.objectFrame.map { objectPoint in
            AUPoint(
                x: canvasOrigin.x + objectPoint.x * canvasSize.width,
                y: canvasOrigin.y + objectPoint.y * canvasSize.height
            )
        }
        let oscSurface = try encodeProductionOSCTexturePass(
            commandBuffer: commandBuffer,
            device: device,
            library: library,
            previewTexture: previewTexture,
            canvasCorners: canvasCorners,
            surfaceSize: surfaceSize
        )

        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        guard commandBuffer.status == .completed else {
            throw MotionHostSimulationFailure.failed(
                "Metal command buffer failed: \(commandBuffer.error.map(String.init(describing:)) ?? "unknown")"
            )
        }

        let result = try motionCompositedImage(
            oscSurface: oscSurface,
            surfaceSize: surfaceSize,
            canvasSize: canvasSize,
            canvasOrigin: canvasOrigin
        )
        try savePNG(result.pixels, width: Int(surfaceSize.width), height: Int(surfaceSize.height), url: outputURL)
        print(
            "Motion host simulation: layoutPhysical=(\(layout.physicalBounds.left),\(layout.physicalBounds.top))-" +
            "(\(layout.physicalBounds.right),\(layout.physicalBounds.bottom)) " +
            "objectFrame=\(layout.objectFrame) exteriorAbove=\(result.exteriorAbove) " +
            "exteriorBelow=\(result.exteriorBelow) output=\(outputURL.path)"
        )
    }

    private static func makeBlueSourceTexture(device: MTLDevice, size: AUSize) throws -> MTLTexture {
        let width = Int(size.width)
        let height = Int(size.height)
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Float,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.storageMode = .shared
        descriptor.usage = [.shaderRead]
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw MotionHostSimulationFailure.failed("Unable to create source texture")
        }

        let blue: [UInt16] = [
            Float16(0.015).bitPattern,
            Float16(0.02).bitPattern,
            Float16(0.80).bitPattern,
            Float16(1.0).bitPattern
        ]
        var pixels = Array(repeating: UInt16(0), count: width * height * 4)
        for index in 0..<(width * height) {
            pixels[index * 4] = blue[0]
            pixels[index * 4 + 1] = blue[1]
            pixels[index * 4 + 2] = blue[2]
            pixels[index * 4 + 3] = blue[3]
        }
        pixels.withUnsafeBytes { bytes in
            texture.replace(
                region: MTLRegionMake2D(0, 0, width, height),
                mipmapLevel: 0,
                withBytes: bytes.baseAddress!,
                bytesPerRow: width * 4 * MemoryLayout<UInt16>.stride
            )
        }
        return texture
    }

    private static func makeWarpState(
        logicalCorners: AUStretchCorners,
        physicalCorners: AUStretchCorners,
        canvasSize: AUSize
    ) -> AnyUprightWarpState {
        let logicalOutputToSource = AnyUprightGeometry.homography(
            from: logicalCorners,
            to: AUStretchCorners.fullFrame(canvasSize)
        )
        let textureMapping = AUTextureCoordinateMapping(
            imageOriginInTexture: AUPoint(x: 0.0, y: 0.0),
            textureSize: canvasSize
        )
        let outputToTexture = AnyUprightGeometry.renderBoundaryAdjustedOutputToTextureMatrix(
            logicalOutputToSource,
            outputSize: canvasSize,
            sourceSize: canvasSize,
            textureMapping: textureMapping
        )
        let identity = matrix_identity_float3x3
        return AnyUprightWarpState(
            outputToSource: outputToTexture,
            selectionOutputToRect: identity,
            outputSize: vector_float2(Float(canvasSize.width), Float(canvasSize.height)),
            inputSize: vector_float2(Float(canvasSize.width), Float(canvasSize.height)),
            imageCoordinateMin: vector_float2(0.0, 0.0),
            imageCoordinateMax: vector_float2(Float(canvasSize.width), Float(canvasSize.height)),
            inputImageOriginInTexture: vector_float2(0.0, 0.0),
            inputTextureSize: vector_float2(Float(canvasSize.width), Float(canvasSize.height)),
            stretchTopLeft: vector_float2(Float(physicalCorners.topLeft.x), Float(physicalCorners.topLeft.y)),
            stretchTopRight: vector_float2(Float(physicalCorners.topRight.x), Float(physicalCorners.topRight.y)),
            stretchBottomRight: vector_float2(Float(physicalCorners.bottomRight.x), Float(physicalCorners.bottomRight.y)),
            stretchBottomLeft: vector_float2(Float(physicalCorners.bottomLeft.x), Float(physicalCorners.bottomLeft.y)),
            renderMode: Int32(AURM_OuterStretch),
            usesNearestSampling: 0,
            reserved1: 0,
            reserved2: 0
        )
    }

    private static func encodeProductionPreviewPass(
        commandBuffer: MTLCommandBuffer,
        device: MTLDevice,
        library: MTLLibrary,
        inputTexture: MTLTexture,
        warpState: inout AnyUprightWarpState,
        layout: AUOuterStretchOSCPreviewLayout
    ) throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Float,
            width: layout.textureWidth,
            height: layout.textureHeight,
            mipmapped: false
        )
        descriptor.storageMode = .private
        descriptor.usage = [.renderTarget, .shaderRead]
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw MotionHostSimulationFailure.failed("Unable to create preview texture")
        }
        let pipeline = try makePipeline(
            device: device,
            library: library,
            vertex: "anyUprightWarpVertex",
            fragment: "anyUprightOuterStretchOSCPreviewFragment",
            pixelFormat: texture.pixelFormat,
            blending: false
        )
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 0.0)
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else {
            throw MotionHostSimulationFailure.failed("Unable to encode preview pass")
        }
        var vertices = layout.offscreenVertices.map {
            AnyUprightVertex2D(
                position: vector_float2(Float($0.position.x), Float($0.position.y)),
                outputCoordinate: vector_float2(Float($0.outputCoordinate.x), Float($0.outputCoordinate.y))
            )
        }
        var viewport = simd_uint2(UInt32(layout.textureWidth), UInt32(layout.textureHeight))
        encoder.setViewport(MTLViewport(originX: 0.0, originY: 0.0, width: Double(layout.textureWidth), height: Double(layout.textureHeight), znear: -1.0, zfar: 1.0))
        encoder.setRenderPipelineState(pipeline)
        encoder.setVertexBytes(&vertices, length: MemoryLayout<AnyUprightVertex2D>.stride * vertices.count, index: Int(AUVII_Vertices.rawValue))
        encoder.setVertexBytes(&viewport, length: MemoryLayout.size(ofValue: viewport), index: Int(AUVII_ViewportSize.rawValue))
        encoder.setFragmentTexture(inputTexture, index: Int(AUTI_InputImage.rawValue))
        encoder.setFragmentBytes(&warpState, length: MemoryLayout<AnyUprightWarpState>.stride, index: Int(AUFII_WarpState.rawValue))
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: vertices.count)
        encoder.endEncoding()
        return texture
    }

    private static func encodeProductionOSCTexturePass(
        commandBuffer: MTLCommandBuffer,
        device: MTLDevice,
        library: MTLLibrary,
        previewTexture: MTLTexture,
        canvasCorners: [AUPoint],
        surfaceSize: AUSize
    ) throws -> MTLTexture {
        let width = Int(surfaceSize.width)
        let height = Int(surfaceSize.height)
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Float,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.storageMode = .shared
        descriptor.usage = [.renderTarget, .shaderRead]
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw MotionHostSimulationFailure.failed("Unable to create OSC surface")
        }
        let pipeline = try makePipeline(
            device: device,
            library: library,
            vertex: "anyUprightTextureOverlayVertex",
            fragment: "anyUprightTextureOverlayFragment",
            pixelFormat: texture.pixelFormat,
            blending: true
        )
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 0.0)
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else {
            throw MotionHostSimulationFailure.failed("Unable to encode OSC texture pass")
        }
        var vertices = AUOuterStretchOSCPreviewLayout.textureOverlayVertices(
            surfacePixels: canvasCorners,
            surfaceSize: surfaceSize
        ).map {
            AnyUprightTextureOverlayVertex2D(
                position: vector_float2(Float($0.position.x), Float($0.position.y)),
                textureCoordinate: vector_float2(Float($0.textureCoordinate.x), Float($0.textureCoordinate.y))
            )
        }
        var viewport = simd_uint2(UInt32(width), UInt32(height))
        encoder.setViewport(MTLViewport(originX: 0.0, originY: 0.0, width: Double(width), height: Double(height), znear: -1.0, zfar: 1.0))
        encoder.setRenderPipelineState(pipeline)
        encoder.setVertexBytes(&vertices, length: MemoryLayout<AnyUprightTextureOverlayVertex2D>.stride * vertices.count, index: Int(AUVII_Vertices.rawValue))
        encoder.setVertexBytes(&viewport, length: MemoryLayout.size(ofValue: viewport), index: Int(AUVII_ViewportSize.rawValue))
        encoder.setFragmentTexture(previewTexture, index: Int(AUTI_InputImage.rawValue))
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: vertices.count)
        encoder.endEncoding()
        return texture
    }

    private static func makePipeline(
        device: MTLDevice,
        library: MTLLibrary,
        vertex: String,
        fragment: String,
        pixelFormat: MTLPixelFormat,
        blending: Bool
    ) throws -> MTLRenderPipelineState {
        guard let vertexFunction = library.makeFunction(name: vertex),
              let fragmentFunction = library.makeFunction(name: fragment) else {
            throw MotionHostSimulationFailure.failed("Missing production Metal functions \(vertex)/\(fragment)")
        }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.colorAttachments[0].pixelFormat = pixelFormat
        if blending {
            descriptor.colorAttachments[0].isBlendingEnabled = true
            descriptor.colorAttachments[0].rgbBlendOperation = .add
            descriptor.colorAttachments[0].alphaBlendOperation = .add
            descriptor.colorAttachments[0].sourceRGBBlendFactor = .one
            descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
            descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
            descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        }
        return try device.makeRenderPipelineState(descriptor: descriptor)
    }

    private static func motionCompositedImage(
        oscSurface: MTLTexture,
        surfaceSize: AUSize,
        canvasSize: AUSize,
        canvasOrigin: AUPoint
    ) throws -> (pixels: [UInt8], exteriorAbove: Int, exteriorBelow: Int) {
        let width = Int(surfaceSize.width)
        let height = Int(surfaceSize.height)
        var raw = Array(repeating: UInt16(0), count: width * height * 4)
        raw.withUnsafeMutableBytes { bytes in
            oscSurface.getBytes(
                bytes.baseAddress!,
                bytesPerRow: width * 4 * MemoryLayout<UInt16>.stride,
                from: MTLRegionMake2D(0, 0, width, height),
                mipmapLevel: 0
            )
        }

        let displayedCanvasLeft = Int(canvasOrigin.x)
        let displayedCanvasTop = height - Int(canvasOrigin.y + canvasSize.height)
        let displayedCanvasRight = displayedCanvasLeft + Int(canvasSize.width)
        let displayedCanvasBottom = displayedCanvasTop + Int(canvasSize.height)
        var output = Array(repeating: UInt8(0), count: width * height * 4)
        var exteriorAbove = 0
        var exteriorBelow = 0

        for y in 0..<height {
            let rawY = height - 1 - y
            for x in 0..<width {
                let index = (y * width + x) * 4
                let rawIndex = (rawY * width + x) * 4
                var background = SIMD3<Float>(0.055, 0.055, 0.055)
                if x >= displayedCanvasLeft, x < displayedCanvasRight,
                   y >= displayedCanvasTop, y < displayedCanvasBottom {
                    background = SIMD3<Float>(0.015, 0.02, 0.80)
                }
                let source = SIMD3<Float>(
                    Float(Float16(bitPattern: raw[rawIndex])),
                    Float(Float16(bitPattern: raw[rawIndex + 1])),
                    Float(Float16(bitPattern: raw[rawIndex + 2]))
                )
                let alpha = min(1.0, max(0.0, Float(Float16(bitPattern: raw[rawIndex + 3]))))
                let color = source + background * (1.0 - alpha)
                output[index] = UInt8(clamping: Int((min(1.0, max(0.0, color.x)) * 255.0).rounded()))
                output[index + 1] = UInt8(clamping: Int((min(1.0, max(0.0, color.y)) * 255.0).rounded()))
                output[index + 2] = UInt8(clamping: Int((min(1.0, max(0.0, color.z)) * 255.0).rounded()))
                output[index + 3] = 255

                if alpha > 0.01 {
                    if y < displayedCanvasTop {
                        exteriorAbove += 1
                    } else if y >= displayedCanvasBottom {
                        exteriorBelow += 1
                    }
                }
            }
        }
        return (output, exteriorAbove, exteriorBelow)
    }

    private static func savePNG(_ pixels: [UInt8], width: Int, height: Int, url: URL) throws {
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let image = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              ),
              let destination = CGImageDestinationCreateWithURL(
                url as CFURL,
                UTType.png.identifier as CFString,
                1,
                nil
              ) else {
            throw MotionHostSimulationFailure.failed("Unable to create PNG output")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw MotionHostSimulationFailure.failed("Unable to write PNG output")
        }
    }
}
