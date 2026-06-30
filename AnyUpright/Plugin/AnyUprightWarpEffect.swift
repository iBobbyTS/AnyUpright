//
//  AnyUprightWarpEffect.swift
//  AnyUpright
//

import Foundation
import Metal
import simd

enum AnyUprightEffectKind: Int32 {
    case horizon = 1
    case quad = 2
    case upright = 3
}

struct AnyUprightParameterState {
    var effectKind: Int32 = 0
    var fillFrame: Int32 = 0
    var quadMode: Int32 = AUQuadTransformMode.innerStretch.rawValue
    var showCornerAdjuster: Int32 = 1
    var rotationRadians: Float = 0.0
    var verticalPerspective: Float = 0.0
    var horizontalPerspective: Float = 0.0

    var topLeftPercentX: Float = 0.0
    var topLeftPercentY: Float = 0.0
    var topLeftPixelX: Float = 0.0
    var topLeftPixelY: Float = 0.0

    var topRightPercentX: Float = 0.0
    var topRightPercentY: Float = 0.0
    var topRightPixelX: Float = 0.0
    var topRightPixelY: Float = 0.0

    var bottomRightPercentX: Float = 0.0
    var bottomRightPercentY: Float = 0.0
    var bottomRightPixelX: Float = 0.0
    var bottomRightPixelY: Float = 0.0

    var bottomLeftPercentX: Float = 0.0
    var bottomLeftPercentY: Float = 0.0
    var bottomLeftPixelX: Float = 0.0
    var bottomLeftPixelY: Float = 0.0
}

class AnyUprightOSCPlugIn: NSObject {
    let _apiManager: PROAPIAccessing!

    required init?(apiManager: PROAPIAccessing) {
        _apiManager = apiManager
        super.init()
    }

    func parameterRetrievalAPI() -> FxParameterRetrievalAPI_v6? {
        _apiManager?.api(for: FxParameterRetrievalAPI_v6.self) as? FxParameterRetrievalAPI_v6
    }

    func parameterSettingAPI() -> FxParameterSettingAPI_v5? {
        _apiManager?.api(for: FxParameterSettingAPI_v5.self) as? FxParameterSettingAPI_v5
    }

    func objectPixelSizeForOSC(defaultSize: AUSize = AUSize(width: 1920.0, height: 1080.0)) -> AUSize {
        guard let oscAPI = _apiManager.api(for: FxOnScreenControlAPI_v4.self) as? FxOnScreenControlAPI_v4 else {
            return defaultSize
        }

        var width: UInt = 0
        var height: UInt = 0
        var pixelAspectRatio = 1.0
        oscAPI.objectWidth(&width, height: &height, pixelAspectRatio: &pixelAspectRatio)
        return AUSize(width: max(1.0, Double(width)), height: max(1.0, Double(height)))
    }
}

class AnyUprightWarpEffect: NSObject, FxTileableEffect {
    let _apiManager: PROAPIAccessing!

    required init?(apiManager: PROAPIAccessing) {
        _apiManager = apiManager
    }

    func addParameters() throws {
        let paramAPI = _apiManager!.api(for: FxParameterCreationAPI_v5.self) as! FxParameterCreationAPI_v5
        try addEffectParameters(paramAPI)
    }

    func addEffectParameters(_ paramAPI: FxParameterCreationAPI_v5) throws {
        fatalError("Subclasses must add their parameters.")
    }

    func state(at renderTime: CMTime) -> AnyUprightParameterState {
        AnyUprightParameterState()
    }

    func properties(_ properties: AutoreleasingUnsafeMutablePointer<NSDictionary>?) throws {
        let swiftProps = [
            kFxPropertyKey_MayRemapTime: NSNumber(booleanLiteral: false),
            kFxPropertyKey_NeedsFullBuffer: NSNumber(booleanLiteral: false),
            kFxPropertyKey_PixelTransformSupport: NSNumber(value: kFxPixelTransform_ScaleTranslate),
            kFxPropertyKey_VariesWhenParamsAreStatic: NSNumber(booleanLiteral: false),
            kFxPropertyKey_ChangesOutputSize: NSNumber(booleanLiteral: false)
        ]
        properties?.pointee = NSDictionary(dictionary: swiftProps)
    }

    func pluginState(_ pluginState: AutoreleasingUnsafeMutablePointer<NSData>?, at renderTime: CMTime, quality qualityLevel: UInt) throws {
        var effectState = state(at: renderTime)
        pluginState?.pointee = NSData(bytes: &effectState, length: MemoryLayout<AnyUprightParameterState>.stride)
    }

    func destinationImageRect(_ destinationImageRect: UnsafeMutablePointer<FxRect>, sourceImages: [FxImageTile], destinationImage: FxImageTile, pluginState: Data?, at renderTime: CMTime) throws {
        destinationImageRect.pointee = sourceImages[0].imagePixelBounds
    }

    func sourceTileRect(_ sourceTileRect: UnsafeMutablePointer<FxRect>, sourceImageIndex: UInt, sourceImages: [FxImageTile], destinationTileRect: FxRect, destinationImage: FxImageTile, pluginState: Data?, at renderTime: CMTime) throws {
        let parameterState = state(from: pluginState)
        let usesIdentityPreview = usesIdentitySourcePreview(from: parameterState)
        let bounds = AnyUprightGeometry.sourceTileBounds(
            for: pixelBounds(from: sourceImages[Int(sourceImageIndex)].imagePixelBounds),
            destinationTileBounds: pixelBounds(from: destinationTileRect),
            usesIdentityPreview: usesIdentityPreview
        )
        sourceTileRect.pointee = FxRect(
            left: bounds.left,
            bottom: bounds.bottom,
            right: bounds.right,
            top: bounds.top
        )
    }

    func renderDestinationImage(_ destinationImage: FxImageTile, sourceImages: [FxImageTile], pluginState: Data?, at renderTime: CMTime) throws {
        let parameterState = state(from: pluginState)
        let sourceImage = sourceImages[0]
        let deviceCache = MetalDeviceCache.deviceCache
        let pixelFormat = MetalDeviceCache.FxMTLPixelFormat(for: destinationImage)
        guard let commandQueueLease = deviceCache.commandQueueLease(with: sourceImage.deviceRegistryID, pixelFormat: pixelFormat) else {
            return
        }
        defer { commandQueueLease.returnToCache() }

        guard let commandBuffer = commandQueueLease.commandQueue.makeCommandBuffer(),
              let inputDevice = deviceCache.device(with: sourceImage.deviceRegistryID),
              let outputDevice = deviceCache.device(with: destinationImage.deviceRegistryID),
              let inputTexture = sourceImage.metalTexture(for: inputDevice),
              let outputTexture = destinationImage.metalTexture(for: outputDevice),
              let pipelineState = deviceCache.pipelineState(with: sourceImage.deviceRegistryID, pixelFormat: pixelFormat) else {
            return
        }

        commandBuffer.label = "AnyUpright Warp Command Buffer"
        commandBuffer.enqueue()

        let colorAttachmentDescriptor = MTLRenderPassColorAttachmentDescriptor()
        colorAttachmentDescriptor.texture = outputTexture
        colorAttachmentDescriptor.clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 1.0)
        colorAttachmentDescriptor.loadAction = .clear
        colorAttachmentDescriptor.storeAction = .store

        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0] = colorAttachmentDescriptor

        guard let commandEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
            return
        }

        let imageBounds = destinationImage.imagePixelBounds
        let tileBounds = destinationImage.tilePixelBounds
        let tileWidth = tileBounds.right - tileBounds.left
        let tileHeight = tileBounds.top - tileBounds.bottom

        let outputBounds = AnyUprightGeometry.outputCoordinateBounds(
            for: pixelBounds(from: tileBounds),
            imageBounds: pixelBounds(from: imageBounds)
        )
        let outputLeft = Float(outputBounds.left)
        let outputRight = Float(outputBounds.right)
        let outputTop = Float(outputBounds.top)
        let outputBottom = Float(outputBounds.bottom)

        var vertices = [
            AnyUprightVertex2D(position: vector_float2(Float(tileWidth) / 2.0, Float(-tileHeight) / 2.0), outputCoordinate: vector_float2(outputRight, outputBottom)),
            AnyUprightVertex2D(position: vector_float2(Float(-tileWidth) / 2.0, Float(-tileHeight) / 2.0), outputCoordinate: vector_float2(outputLeft, outputBottom)),
            AnyUprightVertex2D(position: vector_float2(Float(tileWidth) / 2.0, Float(tileHeight) / 2.0), outputCoordinate: vector_float2(outputRight, outputTop)),
            AnyUprightVertex2D(position: vector_float2(Float(-tileWidth) / 2.0, Float(tileHeight) / 2.0), outputCoordinate: vector_float2(outputLeft, outputTop))
        ]

        var viewportSize = simd_uint2(UInt32(tileWidth), UInt32(tileHeight))
        var warpState = shaderState(
            from: parameterState,
            sourceImage: sourceImage,
            sourceTexture: inputTexture,
            destinationImage: destinationImage
        )

        let viewport = MTLViewport(originX: 0, originY: 0, width: Double(tileWidth), height: Double(tileHeight), znear: -1.0, zfar: 1.0)
        commandEncoder.setViewport(viewport)
        commandEncoder.setRenderPipelineState(pipelineState)
        commandEncoder.setVertexBytes(&vertices, length: MemoryLayout<AnyUprightVertex2D>.stride * vertices.count, index: Int(AUVII_Vertices.rawValue))
        commandEncoder.setVertexBytes(&viewportSize, length: MemoryLayout.size(ofValue: viewportSize), index: Int(AUVII_ViewportSize.rawValue))
        commandEncoder.setFragmentTexture(inputTexture, index: Int(AUTI_InputImage.rawValue))
        commandEncoder.setFragmentBytes(&warpState, length: MemoryLayout<AnyUprightWarpState>.stride, index: Int(AUFII_WarpState.rawValue))
        commandEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: vertices.count)

        commandEncoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }

    func parameterRetrievalAPI() -> FxParameterRetrievalAPI_v6? {
        _apiManager?.api(for: FxParameterRetrievalAPI_v6.self) as? FxParameterRetrievalAPI_v6
    }

    func parameterSettingAPI() -> FxParameterSettingAPI_v5? {
        _apiManager?.api(for: FxParameterSettingAPI_v5.self) as? FxParameterSettingAPI_v5
    }

    func defaultFlags() -> FxParameterFlags {
        FxParameterFlags(kFxParameterFlag_DEFAULT)
    }

    func collapsedFlags() -> FxParameterFlags {
        FxParameterFlags(kFxParameterFlag_COLLAPSED)
    }

    func currentParameterTime() -> CMTime {
        guard let actionAPI = _apiManager.api(for: FxCustomParameterActionAPI_v4.self) as? FxCustomParameterActionAPI_v4 else {
            return .zero
        }

        return actionAPI.currentTime()
    }

    func performParameterAction(_ body: () -> Void) {
        guard let actionAPI = _apiManager.api(for: FxCustomParameterActionAPI_v4.self) as? FxCustomParameterActionAPI_v4 else {
            body()
            return
        }

        actionAPI.startAction(self)
        body()
        actionAPI.endAction(self)
    }

    func objectPixelSizeForOSC(defaultSize: AUSize = AUSize(width: 1920.0, height: 1080.0)) -> AUSize {
        guard let oscAPI = _apiManager.api(for: FxOnScreenControlAPI_v4.self) as? FxOnScreenControlAPI_v4 else {
            return defaultSize
        }

        var width: UInt = 0
        var height: UInt = 0
        var pixelAspectRatio = 1.0
        oscAPI.objectWidth(&width, height: &height, pixelAspectRatio: &pixelAspectRatio)
        return AUSize(width: max(1.0, Double(width)), height: max(1.0, Double(height)))
    }

    private func state(from pluginState: Data?) -> AnyUprightParameterState {
        guard let pluginState,
              pluginState.count >= MemoryLayout<AnyUprightParameterState>.stride else {
            return AnyUprightParameterState()
        }

        return pluginState.withUnsafeBytes { ptr in
            ptr.load(as: AnyUprightParameterState.self)
        }
    }

    private func shaderState(
        from parameterState: AnyUprightParameterState,
        sourceImage: FxImageTile,
        sourceTexture: MTLTexture,
        destinationImage: FxImageTile
    ) -> AnyUprightWarpState {
        let destinationSize = size(from: destinationImage.imagePixelBounds)
        let sourceSize = size(from: sourceImage.imagePixelBounds)
        let inputTextureMapping = AnyUprightGeometry.textureCoordinateMapping(
            for: pixelBounds(from: sourceImage.imagePixelBounds),
            tileBounds: pixelBounds(from: sourceImage.tilePixelBounds),
            textureSize: AUSize(width: Double(sourceTexture.width), height: Double(sourceTexture.height))
        )
        let matrix = outputToSourceMatrix(from: parameterState, outputSize: destinationSize, sourceSize: sourceSize)
        let selectionToRect = selectionOutputToRectMatrix(from: parameterState, outputSize: destinationSize, sourceSize: sourceSize)
        let sourceHandles = innerStretchOutputHandles(from: parameterState, outputSize: destinationSize, sourceSize: sourceSize)
        let renderMode = renderMode(from: parameterState)

        return AnyUprightWarpState(
            outputToSource: matrix,
            selectionOutputToRect: selectionToRect,
            outputSize: vector_float2(Float(destinationSize.width), Float(destinationSize.height)),
            inputSize: vector_float2(Float(sourceSize.width), Float(sourceSize.height)),
            imageCoordinateMin: vector_float2(0.0, 0.0),
            imageCoordinateMax: vector_float2(Float(max(0.0, destinationSize.width)), Float(max(0.0, destinationSize.height))),
            inputImageOriginInTexture: vector_float2(Float(inputTextureMapping.imageOriginInTexture.x), Float(inputTextureMapping.imageOriginInTexture.y)),
            inputTextureSize: vector_float2(Float(max(1.0, inputTextureMapping.textureSize.width)), Float(max(1.0, inputTextureMapping.textureSize.height))),
            innerStretchTopLeft: vector_float2(Float(sourceHandles.topLeft.x), Float(sourceHandles.topLeft.y)),
            innerStretchTopRight: vector_float2(Float(sourceHandles.topRight.x), Float(sourceHandles.topRight.y)),
            innerStretchBottomRight: vector_float2(Float(sourceHandles.bottomRight.x), Float(sourceHandles.bottomRight.y)),
            innerStretchBottomLeft: vector_float2(Float(sourceHandles.bottomLeft.x), Float(sourceHandles.bottomLeft.y)),
            renderMode: renderMode,
            reserved0: 0,
            reserved1: 0,
            reserved2: 0
        )
    }

    private func outputToSourceMatrix(from state: AnyUprightParameterState, outputSize: AUSize, sourceSize: AUSize) -> simd_float3x3 {
        switch AnyUprightEffectKind(rawValue: state.effectKind) {
        case .horizon:
            return AnyUprightGeometry.rotationOutputToSource(
                angleRadians: Double(state.rotationRadians),
                fillFrame: state.fillFrame != 0,
                size: sourceSize
            )

        case .quad:
            let mode = AUQuadTransformMode(rawValue: state.quadMode) ?? .outputCorners
            return AnyUprightGeometry.quadOutputToSourceMatrix(
                from: cornerOffsets(from: state),
                mode: mode,
                showCornerAdjuster: state.showCornerAdjuster != 0,
                outputSize: outputSize,
                sourceSize: sourceSize
            )

        case .upright:
            guard state.showCornerAdjuster == 0 else {
                return AnyUprightGeometry.identityOutputToSourceMatrix(outputSize: outputSize, sourceSize: sourceSize)
            }

            return AnyUprightGeometry.uprightAppliedOutputToSourceMatrix(
                vertical: Double(state.verticalPerspective),
                horizontal: Double(state.horizontalPerspective),
                rotationRadians: Double(state.rotationRadians),
                fillFrame: state.fillFrame != 0,
                outputSize: outputSize,
                sourceSize: sourceSize
            )

        case .none:
            return AnyUprightGeometry.homography(from: AUQuad.fullFrame(outputSize), to: AUQuad.fullFrame(sourceSize))
        }
    }

    private func selectionOutputToRectMatrix(from state: AnyUprightParameterState, outputSize: AUSize, sourceSize: AUSize) -> simd_float3x3 {
        guard AnyUprightEffectKind(rawValue: state.effectKind) == .quad,
              AUQuadTransformMode(rawValue: state.quadMode) == .innerStretch else {
            return AnyUprightGeometry.identityOutputToSourceMatrix(outputSize: outputSize, sourceSize: outputSize)
        }

        return AnyUprightGeometry.quadSelectionToOutputRectMatrix(
            from: cornerOffsets(from: state),
            outputSize: outputSize,
            sourceSize: sourceSize
        )
    }

    private func innerStretchOutputHandles(from state: AnyUprightParameterState, outputSize: AUSize, sourceSize: AUSize) -> AUQuad {
        guard AnyUprightEffectKind(rawValue: state.effectKind) == .quad,
              AUQuadTransformMode(rawValue: state.quadMode) == .innerStretch else {
            return AUQuad.fullFrame(outputSize)
        }

        return AnyUprightGeometry.innerStretchOutputHandles(
            from: cornerOffsets(from: state),
            outputSize: outputSize,
            sourceSize: sourceSize
        )
    }

    private func renderMode(from state: AnyUprightParameterState) -> Int32 {
        if AnyUprightEffectKind(rawValue: state.effectKind) == .quad,
           AUQuadTransformMode(rawValue: state.quadMode) == .innerStretch,
           state.showCornerAdjuster != 0 {
            return Int32(AURM_InnerStretchAdjusterPreview)
        }

        return Int32(AURM_WarpFullFrame)
    }

    private func usesIdentitySourcePreview(from state: AnyUprightParameterState) -> Bool {
        if AnyUprightEffectKind(rawValue: state.effectKind) == .upright,
           state.showCornerAdjuster != 0 {
            return true
        }

        return renderMode(from: state) == Int32(AURM_InnerStretchAdjusterPreview)
    }

    func cornerOffsets(from state: AnyUprightParameterState) -> AUCornerOffsets {
        AUCornerOffsets(
            topLeftPercent: AUPoint(x: Double(state.topLeftPercentX), y: Double(state.topLeftPercentY)),
            topRightPercent: AUPoint(x: Double(state.topRightPercentX), y: Double(state.topRightPercentY)),
            bottomRightPercent: AUPoint(x: Double(state.bottomRightPercentX), y: Double(state.bottomRightPercentY)),
            bottomLeftPercent: AUPoint(x: Double(state.bottomLeftPercentX), y: Double(state.bottomLeftPercentY)),
            topLeftPixels: AUPoint(x: Double(state.topLeftPixelX), y: Double(state.topLeftPixelY)),
            topRightPixels: AUPoint(x: Double(state.topRightPixelX), y: Double(state.topRightPixelY)),
            bottomRightPixels: AUPoint(x: Double(state.bottomRightPixelX), y: Double(state.bottomRightPixelY)),
            bottomLeftPixels: AUPoint(x: Double(state.bottomLeftPixelX), y: Double(state.bottomLeftPixelY))
        )
    }

    private func size(from rect: FxRect) -> AUSize {
        AUSize(width: Double(rect.right - rect.left), height: Double(rect.top - rect.bottom))
    }

    private func pixelBounds(from rect: FxRect) -> AUPixelBounds {
        AUPixelBounds(left: rect.left, bottom: rect.bottom, right: rect.right, top: rect.top)
    }
}
