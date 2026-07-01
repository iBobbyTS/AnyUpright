import Foundation
import AppKit
import ImageIO
import UniformTypeIdentifiers
import Metal
import simd

struct Point {
    var x: Double
    var y: Double
}

struct Line {
    var start: Point
    var end: Point
}

struct Vertex {
    var position: SIMD2<Float>
    var outputCoordinate: SIMD2<Float>
}

enum RenderError: Error, CustomStringConvertible {
    case message(String)
    var description: String {
        switch self {
        case .message(let text): return text
        }
    }
}

func matrix(
    _ a: Double, _ b: Double, _ c: Double,
    _ d: Double, _ e: Double, _ f: Double,
    _ g: Double, _ h: Double, _ i: Double
) -> simd_double3x3 {
    simd_double3x3(columns: (
        SIMD3<Double>(a, d, g),
        SIMD3<Double>(b, e, h),
        SIMD3<Double>(c, f, i)
    ))
}

func intersection(_ lhs: Line, _ rhs: Line) throws -> Point {
    let ax = lhs.end.x - lhs.start.x
    let ay = lhs.end.y - lhs.start.y
    let bx = rhs.end.x - rhs.start.x
    let by = rhs.end.y - rhs.start.y
    let denom = ax * by - ay * bx
    guard abs(denom) > 1.0e-9 else {
        throw RenderError.message("guide lines are parallel")
    }
    let t = ((rhs.start.x - lhs.start.x) * by - (rhs.start.y - lhs.start.y) * bx) / denom
    return Point(x: lhs.start.x + t * ax, y: lhs.start.y + t * ay)
}

func guidedVerticalOutputToSourceMatrix(normalizedImageLines: [Line], size: CGSize) throws -> simd_double3x3 {
    let imageLines = normalizedImageLines.map { line in
        Line(
            start: Point(x: line.start.x * size.width, y: line.start.y * size.height),
            end: Point(x: line.end.x * size.width, y: line.end.y * size.height)
        )
    }
    guard imageLines.count >= 2 else {
        throw RenderError.message("need at least two vertical guide lines")
    }
    let vp = try intersection(imageLines[0], imageLines[1])
    let anchorY = size.height / 2.0
    let verticalStrength = 1.0 / (vp.y - anchorY)
    let toAnchor = matrix(
        1, 0, -vp.x,
        0, 1, -anchorY,
        0, 0, 1
    )
    let perspective = matrix(
        1, 0, 0,
        0, 1, 0,
        0, verticalStrength, 1
    )
    let fromAnchor = matrix(
        1, 0, vp.x,
        0, 1, anchorY,
        0, 0, 1
    )
    return fromAnchor * perspective * toAnchor
}

func transform(_ p: Point, by m: simd_double3x3) -> Point {
    let v = m * SIMD3<Double>(p.x, p.y, 1.0)
    return Point(x: v.x / v.z, y: v.y / v.z)
}

func outputFrameMapsInsideSource(_ m: simd_double3x3, outputSize: CGSize, sourceSize: CGSize) -> Bool {
    let corners = [
        Point(x: 0, y: 0),
        Point(x: outputSize.width, y: 0),
        Point(x: outputSize.width, y: outputSize.height),
        Point(x: 0, y: outputSize.height)
    ]
    return corners.allSatisfy { corner in
        let p = transform(corner, by: m)
        return p.x >= -0.0001 && p.y >= -0.0001 && p.x <= sourceSize.width + 0.0001 && p.y <= sourceSize.height + 0.0001
    }
}

func centerUnzoomMatrix(scale: Double, size: CGSize) -> simd_double3x3 {
    let cx = size.width / 2.0
    let cy = size.height / 2.0
    return matrix(
        1.0 / scale, 0, cx - cx / scale,
        0, 1.0 / scale, cy - cy / scale,
        0, 0, 1
    )
}

func autoCropMatrix(_ outputToSource: simd_double3x3, outputSize: CGSize, sourceSize: CGSize, maximumScale: Double = 8.0) -> simd_double3x3 {
    if outputFrameMapsInsideSource(outputToSource, outputSize: outputSize, sourceSize: sourceSize) {
        return outputToSource
    }

    var lower = 1.0
    var upper = 1.0
    while upper < maximumScale {
        upper *= 1.5
        let candidate = outputToSource * centerUnzoomMatrix(scale: upper, size: outputSize)
        if outputFrameMapsInsideSource(candidate, outputSize: outputSize, sourceSize: sourceSize) {
            break
        }
    }
    upper = min(upper, maximumScale)
    var candidate = outputToSource * centerUnzoomMatrix(scale: upper, size: outputSize)
    guard outputFrameMapsInsideSource(candidate, outputSize: outputSize, sourceSize: sourceSize) else {
        return outputToSource
    }
    for _ in 0..<40 {
        let mid = (lower + upper) / 2.0
        let midCandidate = outputToSource * centerUnzoomMatrix(scale: mid, size: outputSize)
        if outputFrameMapsInsideSource(midCandidate, outputSize: outputSize, sourceSize: sourceSize) {
            upper = mid
            candidate = midCandidate
        } else {
            lower = mid
        }
    }
    return candidate
}

func adaptMatrix(_ stableMatrix: simd_double3x3, outputSize: CGSize, sourceSize: CGSize, correctionOutputSize: CGSize, correctionSourceSize: CGSize, fillFrame: Bool) -> simd_double3x3 {
    let corrected = fillFrame ? autoCropMatrix(stableMatrix, outputSize: correctionOutputSize, sourceSize: correctionSourceSize) : stableMatrix
    let currentOutputToCorrectionOutput = matrix(
        correctionOutputSize.width / outputSize.width, 0, 0,
        0, correctionOutputSize.height / outputSize.height, 0,
        0, 0, 1
    )
    let correctionSourceToCurrentSource = matrix(
        sourceSize.width / correctionSourceSize.width, 0, 0,
        0, sourceSize.height / correctionSourceSize.height, 0,
        0, 0, 1
    )
    return correctionSourceToCurrentSource * corrected * currentOutputToCorrectionOutput
}

func verticalFlipMatrix(size: CGSize) -> simd_double3x3 {
    matrix(
        1, 0, 0,
        0, -1, size.height,
        0, 0, 1
    )
}

func loadImageRGBA(_ url: URL, width: Int, height: Int) throws -> [UInt8] {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        throw RenderError.message("failed to load image: \(url.path)")
    }
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    guard let context = CGContext(
        data: &pixels,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw RenderError.message("failed to create CGContext")
    }
    context.interpolationQuality = .high
    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
    return pixels
}

func verticallyFlippedCopy(_ pixels: [UInt8], width: Int, height: Int) -> [UInt8] {
    var out = [UInt8](repeating: 0, count: pixels.count)
    let rowBytes = width * 4
    for y in 0..<height {
        let src = y * rowBytes
        let dst = (height - 1 - y) * rowBytes
        out[dst..<dst + rowBytes] = pixels[src..<src + rowBytes]
    }
    return out
}

func saveRGBA(_ pixels: [UInt8], width: Int, height: Int, to url: URL) throws {
    var data = pixels
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    guard let provider = CGDataProvider(data: Data(data) as CFData),
          let cgImage = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
          ),
          let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw RenderError.message("failed to create output image")
    }
    CGImageDestinationAddImage(destination, cgImage, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw RenderError.message("failed to write output: \(url.path)")
    }
}

func toFloat3x3(_ m: simd_double3x3) -> simd_float3x3 {
    simd_float3x3(columns: (
        SIMD3<Float>(Float(m.columns.0.x), Float(m.columns.0.y), Float(m.columns.0.z)),
        SIMD3<Float>(Float(m.columns.1.x), Float(m.columns.1.y), Float(m.columns.1.z)),
        SIMD3<Float>(Float(m.columns.2.x), Float(m.columns.2.y), Float(m.columns.2.z))
    ))
}

let inputURL = URL(fileURLWithPath: "/Users/ibobby/Downloads/IMG_1118.HEIC")
let outputURL = URL(fileURLWithPath: "/Users/ibobby/Downloads/IMG_1118-out.png")
let stableSize = CGSize(width: 5712, height: 4284)
let renderSize = CGSize(width: 2880, height: 2160)
let outputWidth = Int(renderSize.width)
let outputHeight = Int(renderSize.height)
let fillFrame = true

// Values read from /Users/ibobby/Movies/Motion Templates.localized/Effects.localized/AnyUpright/Upright/Upright.moef.
let objectGuideLines = [
    Line(start: Point(x: 0.12514082923444944, y: 0.46618675719365832), end: Point(x: 0.088474057913030077, y: 0.75269211742454889)),
    Line(start: Point(x: 0.79751348206477957, y: 0.48268191503817148), end: Point(x: 0.86493466540219344, y: 0.76445081387884484))
]
let imageGuideLines = objectGuideLines.map { line in
    Line(
        start: Point(x: line.start.x, y: 1.0 - line.start.y),
        end: Point(x: line.end.x, y: 1.0 - line.end.y)
    )
}
let stableMatrix = try guidedVerticalOutputToSourceMatrix(normalizedImageLines: imageGuideLines, size: stableSize)
let renderMatrix = adaptMatrix(
    stableMatrix,
    outputSize: renderSize,
    sourceSize: renderSize,
    correctionOutputSize: stableSize,
    correctionSourceSize: stableSize,
    fillFrame: fillFrame
)
let shaderMatrix = verticalFlipMatrix(size: renderSize) * renderMatrix * verticalFlipMatrix(size: renderSize)
print("stable matrix:")
for row in 0..<3 {
    print(String(format: "%.6f %.6f %.6f", stableMatrix[row, 0], stableMatrix[row, 1], stableMatrix[row, 2]))
}
print("render matrix:")
for row in 0..<3 {
    print(String(format: "%.6f %.6f %.6f", renderMatrix[row, 0], renderMatrix[row, 1], renderMatrix[row, 2]))
}
print("shader matrix without shader y flips:")
for row in 0..<3 {
    print(String(format: "%.6f %.6f %.6f", shaderMatrix[row, 0], shaderMatrix[row, 1], shaderMatrix[row, 2]))
}

let sourcePixelsTopOrigin = try loadImageRGBA(inputURL, width: outputWidth, height: outputHeight)
// FxPlug input textures observed in Motion require source-image Y to cross a texture-boundary flip.
let fxPlugLikeTexturePixels = verticallyFlippedCopy(sourcePixelsTopOrigin, width: outputWidth, height: outputHeight)

guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
    throw RenderError.message("Metal device unavailable")
}
let shader = """
#include <metal_stdlib>
#include <simd/simd.h>
using namespace metal;
struct Vertex { float2 position; float2 outputCoordinate; };
struct Raster { float4 position [[position]]; float2 outputCoordinate; };
struct State {
    float3x3 outputToSource;
    float2 outputSize;
    float2 inputSize;
    float2 inputTextureSize;
};
static float2 inputTextureUV(float2 sourcePixel, constant State& state) {
    float2 texturePixel = sourcePixel;
    return texturePixel / state.inputTextureSize;
}
static float coverageForSource(float2 sourcePixel, constant State& state) {
    float2 sourceSize = max(state.inputSize, float2(1.0));
    float outside = max(max(-sourcePixel.x, sourcePixel.x - sourceSize.x), max(-sourcePixel.y, sourcePixel.y - sourceSize.y));
    float aa = max(fwidth(outside), 0.0001);
    return 1.0 - smoothstep(-aa, aa, outside);
}
vertex Raster vmain(uint vid [[vertex_id]], constant Vertex* verts [[buffer(0)]], constant uint2& viewport [[buffer(1)]]) {
    Raster out;
    float2 p = verts[vid].position;
    float2 vp = float2(viewport);
    out.position = float4(p / (vp / 2.0), 0.0, 1.0);
    out.outputCoordinate = verts[vid].outputCoordinate;
    return out;
}
fragment float4 fmain(Raster in [[stage_in]], texture2d<half> input [[texture(0)]], constant State& state [[buffer(0)]]) {
    constexpr sampler s(mag_filter::linear, min_filter::linear, address::clamp_to_edge);
    float2 outputCoordinate = clamp(in.outputCoordinate, float2(0.0), state.outputSize);
    float3 homogeneous = state.outputToSource * float3(outputCoordinate, 1.0);
    if (fabs(homogeneous.z) < 0.000001) {
        return float4(0.0, 0.0, 0.0, 1.0);
    }
    float2 sourcePixel = homogeneous.xy / homogeneous.z;
    float4 color = float4(input.sample(s, clamp(inputTextureUV(sourcePixel, state), float2(0.0), float2(1.0))));
    color.rgb *= coverageForSource(sourcePixel, state);
    color.a = 1.0;
    return color;
}
"""
let library = try device.makeLibrary(source: shader, options: nil)
let pipelineDesc = MTLRenderPipelineDescriptor()
pipelineDesc.vertexFunction = library.makeFunction(name: "vmain")
pipelineDesc.fragmentFunction = library.makeFunction(name: "fmain")
pipelineDesc.colorAttachments[0].pixelFormat = .rgba8Unorm
let pipeline = try device.makeRenderPipelineState(descriptor: pipelineDesc)
let sourceDesc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: outputWidth, height: outputHeight, mipmapped: false)
sourceDesc.usage = [.shaderRead]
sourceDesc.storageMode = .shared
let inputTexture = device.makeTexture(descriptor: sourceDesc)!
inputTexture.replace(region: MTLRegionMake2D(0, 0, outputWidth, outputHeight), mipmapLevel: 0, withBytes: fxPlugLikeTexturePixels, bytesPerRow: outputWidth * 4)
let outputDesc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: outputWidth, height: outputHeight, mipmapped: false)
outputDesc.usage = [.renderTarget]
outputDesc.storageMode = .shared
let outputTexture = device.makeTexture(descriptor: outputDesc)!
let pass = MTLRenderPassDescriptor()
pass.colorAttachments[0].texture = outputTexture
pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
pass.colorAttachments[0].loadAction = .clear
pass.colorAttachments[0].storeAction = .store
var vertices = [
    Vertex(position: SIMD2<Float>(Float(outputWidth) / 2.0, Float(-outputHeight) / 2.0), outputCoordinate: SIMD2<Float>(Float(outputWidth), Float(outputHeight))),
    Vertex(position: SIMD2<Float>(Float(-outputWidth) / 2.0, Float(-outputHeight) / 2.0), outputCoordinate: SIMD2<Float>(0, Float(outputHeight))),
    Vertex(position: SIMD2<Float>(Float(outputWidth) / 2.0, Float(outputHeight) / 2.0), outputCoordinate: SIMD2<Float>(Float(outputWidth), 0)),
    Vertex(position: SIMD2<Float>(Float(-outputWidth) / 2.0, Float(outputHeight) / 2.0), outputCoordinate: SIMD2<Float>(0, 0))
]
var viewport = SIMD2<UInt32>(UInt32(outputWidth), UInt32(outputHeight))
struct ShaderState {
    var outputToSource: simd_float3x3
    var outputSize: SIMD2<Float>
    var inputSize: SIMD2<Float>
    var inputTextureSize: SIMD2<Float>
}
var state = ShaderState(
    outputToSource: toFloat3x3(shaderMatrix),
    outputSize: SIMD2<Float>(Float(outputWidth), Float(outputHeight)),
    inputSize: SIMD2<Float>(Float(outputWidth), Float(outputHeight)),
    inputTextureSize: SIMD2<Float>(Float(outputWidth), Float(outputHeight))
)
let commandBuffer = queue.makeCommandBuffer()!
let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass)!
encoder.setViewport(MTLViewport(originX: 0, originY: 0, width: Double(outputWidth), height: Double(outputHeight), znear: -1, zfar: 1))
encoder.setRenderPipelineState(pipeline)
encoder.setVertexBytes(&vertices, length: MemoryLayout<Vertex>.stride * vertices.count, index: 0)
encoder.setVertexBytes(&viewport, length: MemoryLayout.size(ofValue: viewport), index: 1)
encoder.setFragmentTexture(inputTexture, index: 0)
encoder.setFragmentBytes(&state, length: MemoryLayout<ShaderState>.stride, index: 0)
encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: vertices.count)
encoder.endEncoding()
commandBuffer.commit()
commandBuffer.waitUntilCompleted()
if let error = commandBuffer.error {
    throw error
}
var outputPixels = [UInt8](repeating: 0, count: outputWidth * outputHeight * 4)
outputTexture.getBytes(&outputPixels, bytesPerRow: outputWidth * 4, from: MTLRegionMake2D(0, 0, outputWidth, outputHeight), mipmapLevel: 0)
let pngPixelsTopOrigin = verticallyFlippedCopy(outputPixels, width: outputWidth, height: outputHeight)
try saveRGBA(pngPixelsTopOrigin, width: outputWidth, height: outputHeight, to: outputURL)
print("wrote \(outputURL.path)")
