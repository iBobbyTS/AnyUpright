//
//  AnyUprightAnalysisStatusTextRenderer.swift
//  AnyUpright
//

import AppKit
import CoreText
import Metal
import MetalKit
import simd

final class AUAnalysisStatusTextRenderer {
    static let shared = AUAnalysisStatusTextRenderer()

    private struct PipelineKey: Hashable {
        var registryID: UInt64
        var pixelFormat: MTLPixelFormat
    }

    private struct TextureKey: Hashable {
        var registryID: UInt64
        var status: AUAnalysisDisplayStatus
        var fontPixelSize: Int
    }

    private struct TextTexture {
        var texture: MTLTexture
        var width: Int
        var height: Int
    }

    private let cacheLock = NSLock()
    private var pipelines: [PipelineKey: MTLRenderPipelineState] = [:]
    private var textures: [TextureKey: TextTexture] = [:]

    private init() {}

    func encode(
        status: AUAnalysisDisplayStatus,
        commandBuffer: MTLCommandBuffer,
        device: MTLDevice,
        drawableTexture: MTLTexture,
        imageRect: AUAnalysisStatusRect,
        tileRect: AUAnalysisStatusRect
    ) {
        guard status != .none,
              let textTexture = textTexture(status: status, imageHeight: imageRect.height, device: device),
              let quad = AUAnalysisStatusOverlayLayout.quad(
                  imageRect: imageRect,
                  tileRect: tileRect,
                  cardWidth: Double(textTexture.width),
                  cardHeight: Double(textTexture.height)
              ),
              let pipeline = pipeline(device: device, pixelFormat: drawableTexture.pixelFormat) else {
            return
        }

        var vertices = zip(quad.positions, quad.textureCoordinates).map {
            AnyUprightTextureOverlayVertex2D(position: $0.0, textureCoordinate: $0.1)
        }
        var viewportSize = simd_uint2(UInt32(drawableTexture.width), UInt32(drawableTexture.height))

        let colorAttachment = MTLRenderPassColorAttachmentDescriptor()
        colorAttachment.texture = drawableTexture
        colorAttachment.loadAction = .load
        colorAttachment.storeAction = .store

        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0] = colorAttachment
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            return
        }
        encoder.label = "AnyUpright Analysis Status"
        encoder.setViewport(MTLViewport(
            originX: 0.0,
            originY: 0.0,
            width: Double(drawableTexture.width),
            height: Double(drawableTexture.height),
            znear: -1.0,
            zfar: 1.0
        ))
        encoder.setRenderPipelineState(pipeline)
        encoder.setVertexBytes(
            &vertices,
            length: MemoryLayout<AnyUprightTextureOverlayVertex2D>.stride * vertices.count,
            index: Int(AUVII_Vertices.rawValue)
        )
        encoder.setVertexBytes(
            &viewportSize,
            length: MemoryLayout.size(ofValue: viewportSize),
            index: Int(AUVII_ViewportSize.rawValue)
        )
        encoder.setFragmentTexture(textTexture.texture, index: Int(AUTI_InputImage.rawValue))
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: vertices.count)
        encoder.endEncoding()
    }

    private func textTexture(
        status: AUAnalysisDisplayStatus,
        imageHeight: Double,
        device: MTLDevice
    ) -> TextTexture? {
        let fontPixelSize = Int(round(min(72.0, max(24.0, imageHeight * 0.032))))
        let key = TextureKey(
            registryID: device.registryID,
            status: status,
            fontPixelSize: fontPixelSize
        )
        cacheLock.lock()
        if let cached = textures[key] {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()

        guard let message = status.message,
              let image = makeTextImage(message: message, fontPixelSize: fontPixelSize) else {
            return nil
        }
        do {
            let texture = try MTKTextureLoader(device: device).newTexture(
                cgImage: image,
                options: [
                    .SRGB: false,
                    .origin: MTKTextureLoader.Origin.topLeft,
                ]
            )
            let result = TextTexture(texture: texture, width: image.width, height: image.height)
            cacheLock.lock()
            textures[key] = result
            cacheLock.unlock()
            return result
        } catch {
            NSLog("Unable to create AnyUpright analysis status texture: %@", String(describing: error))
            return nil
        }
    }

    private func makeTextImage(message: String, fontPixelSize: Int) -> CGImage? {
        let font = NSFont.systemFont(ofSize: CGFloat(fontPixelSize), weight: .semibold)
        let attributed = NSAttributedString(
            string: message,
            attributes: [
                .font: font,
                .foregroundColor: NSColor.white,
            ]
        )
        let line = CTLineCreateWithAttributedString(attributed)
        var ascent: CGFloat = 0.0
        var descent: CGFloat = 0.0
        var leading: CGFloat = 0.0
        let textWidth = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
        let horizontalPadding = CGFloat(fontPixelSize) * 0.72
        let verticalPadding = CGFloat(fontPixelSize) * 0.42
        let width = max(1, Int(ceil(textWidth + horizontalPadding * 2.0)))
        let height = max(1, Int(ceil(ascent + descent + leading + verticalPadding * 2.0)))

        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.setFillColor(NSColor.black.withAlphaComponent(0.72).cgColor)
        let bounds = CGRect(x: 0.0, y: 0.0, width: CGFloat(width), height: CGFloat(height))
        let radius = CGFloat(fontPixelSize) * 0.42
        context.addPath(CGPath(roundedRect: bounds, cornerWidth: radius, cornerHeight: radius, transform: nil))
        context.fillPath()
        context.textPosition = CGPoint(
            x: (CGFloat(width) - textWidth) * 0.5,
            y: verticalPadding + descent
        )
        CTLineDraw(line, context)
        return context.makeImage()
    }

    private func pipeline(device: MTLDevice, pixelFormat: MTLPixelFormat) -> MTLRenderPipelineState? {
        let key = PipelineKey(registryID: device.registryID, pixelFormat: pixelFormat)
        cacheLock.lock()
        if let cached = pipelines[key] {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()

        guard let library = device.makeDefaultLibrary(),
              let vertexFunction = library.makeFunction(name: "anyUprightTextureOverlayVertex"),
              let fragmentFunction = library.makeFunction(name: "anyUprightTextureOverlayFragment") else {
            return nil
        }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = "AnyUprightAnalysisStatus"
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.colorAttachments[0].pixelFormat = pixelFormat
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].rgbBlendOperation = .add
        descriptor.colorAttachments[0].alphaBlendOperation = .add
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .one
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha

        do {
            let result = try device.makeRenderPipelineState(descriptor: descriptor)
            cacheLock.lock()
            pipelines[key] = result
            cacheLock.unlock()
            return result
        } catch {
            NSLog("Unable to create AnyUpright analysis status pipeline: %@", String(describing: error))
            return nil
        }
    }
}
