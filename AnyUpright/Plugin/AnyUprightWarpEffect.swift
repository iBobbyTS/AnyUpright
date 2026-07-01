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
    var stableInputWidth: Float = 0.0
    var stableInputHeight: Float = 0.0
    var stableOutputWidth: Float = 0.0
    var stableOutputHeight: Float = 0.0

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

    func parameterRetrievalAPIv7() -> FxParameterRetrievalAPI_v7? {
        _apiManager?.api(for: FxParameterRetrievalAPI_v7.self) as? FxParameterRetrievalAPI_v7
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
    private let stableRenderSizeLock = NSLock()
    private var cachedUprightStableRenderSize: AUSize?

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

    var needsFullBuffer: Bool {
        false
    }

    var pixelTransformSupport: FxPixelTransformSupport {
        FxPixelTransformSupport(kFxPixelTransform_ScaleTranslate)
    }

    func properties(_ properties: AutoreleasingUnsafeMutablePointer<NSDictionary>?) throws {
        let swiftProps = [
            kFxPropertyKey_MayRemapTime: NSNumber(booleanLiteral: false),
            kFxPropertyKey_NeedsFullBuffer: NSNumber(booleanLiteral: needsFullBuffer),
            kFxPropertyKey_PixelTransformSupport: NSNumber(value: pixelTransformSupport),
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
        sourceTileRect.pointee = fxRect(from: bounds)
    }

    func renderDestinationImage(_ destinationImage: FxImageTile, sourceImages: [FxImageTile], pluginState: Data?, at renderTime: CMTime) throws {
        let sourceImage = sourceImages[0]
        let parameterState = runtimeParameterState(
            from: state(from: pluginState),
            sourceImage: sourceImage,
            destinationImage: destinationImage,
            renderTime: renderTime
        )
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
        debugLogUprightRender(
            parameterState: parameterState,
            sourceImage: sourceImage,
            sourceTexture: inputTexture,
            destinationImage: destinationImage,
            destinationTexture: outputTexture,
            outputBounds: outputBounds,
            warpState: warpState,
            renderTime: renderTime
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

    func parameterRetrievalAPIv7() -> FxParameterRetrievalAPI_v7? {
        _apiManager?.api(for: FxParameterRetrievalAPI_v7.self) as? FxParameterRetrievalAPI_v7
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

    func populateStableRenderSizes(_ state: inout AnyUprightParameterState, at renderTime: CMTime) {
        var inputCandidates: [AUSize] = []
        var outputCandidates: [AUSize] = []

        if let sourceImageSize = stableRenderSizeFromEffectSourceImage(at: renderTime) {
            inputCandidates.append(sourceImageSize)
            outputCandidates.append(sourceImageSize)
        }

        guard let oscAPI = _apiManager.api(for: FxOnScreenControlAPI_v4.self) as? FxOnScreenControlAPI_v4 else {
            applyStableRenderSizes(
                to: &state,
                inputCandidates: inputCandidates,
                outputCandidates: outputCandidates
            )
            return
        }

        var inputWidth: UInt = 0
        var inputHeight: UInt = 0
        var inputPixelAspectRatio = 1.0
        oscAPI.inputWidth(&inputWidth, height: &inputHeight, pixelAspectRatio: &inputPixelAspectRatio)

        var outputWidth: UInt = 0
        var outputHeight: UInt = 0
        var outputPixelAspectRatio = 1.0
        oscAPI.objectWidth(&outputWidth, height: &outputHeight, pixelAspectRatio: &outputPixelAspectRatio)

        if inputWidth > 0, inputHeight > 0 {
            inputCandidates.append(AUSize(width: Double(inputWidth), height: Double(inputHeight)))
        } else if outputWidth > 0, outputHeight > 0 {
            inputCandidates.append(AUSize(width: Double(outputWidth), height: Double(outputHeight)))
        }

        if outputWidth > 0, outputHeight > 0 {
            outputCandidates.append(AUSize(width: Double(outputWidth), height: Double(outputHeight)))
        } else if inputWidth > 0, inputHeight > 0 {
            outputCandidates.append(AUSize(width: Double(inputWidth), height: Double(inputHeight)))
        }

        applyStableRenderSizes(
            to: &state,
            inputCandidates: inputCandidates,
            outputCandidates: outputCandidates
        )
    }

    private func stableRenderSizeFromEffectSourceImage(at renderTime: CMTime) -> AUSize? {
        guard let paramAPI = parameterRetrievalAPIv7() else {
            return nil
        }

        var imageSize = CGSize.zero
        try? paramAPI.imageSize(&imageSize, fromParameter: 0, at: renderTime)
        guard imageSize.width > 0.0,
              imageSize.height > 0.0 else {
            return nil
        }

        return AUSize(width: imageSize.width, height: imageSize.height)
    }

    private func applyStableRenderSizes(
        to state: inout AnyUprightParameterState,
        inputCandidates: [AUSize],
        outputCandidates: [AUSize]
    ) {
        if let stableInputSize = mergedStableRenderSize(from: inputCandidates) {
            state.stableInputWidth = Float(stableInputSize.width)
            state.stableInputHeight = Float(stableInputSize.height)
        }

        if let stableOutputSize = mergedStableRenderSize(from: outputCandidates) {
            state.stableOutputWidth = Float(stableOutputSize.width)
            state.stableOutputHeight = Float(stableOutputSize.height)
        }
    }

    private func mergedStableRenderSize(from candidates: [AUSize]) -> AUSize? {
        candidates.reduce(nil) { partial, candidate in
            guard candidate.width > 0.0,
                  candidate.height > 0.0 else {
                return partial
            }

            return AnyUprightGeometry.mergedStableIdealizedImageSize(cached: partial, candidate: candidate)
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

            let stableOutputSize = stableOutputSize(from: state, fallback: outputSize)
            let stableInputSize = stableInputSize(from: state, fallback: sourceSize)
            return AnyUprightGeometry.uprightAppliedOutputToCurrentSourceMatrix(
                vertical: Double(state.verticalPerspective),
                horizontal: Double(state.horizontalPerspective),
                rotationRadians: Double(state.rotationRadians),
                fillFrame: state.fillFrame != 0,
                outputSize: outputSize,
                sourceSize: sourceSize,
                correctionOutputSize: stableOutputSize,
                correctionSourceSize: stableInputSize
            )

        case .none:
            return AnyUprightGeometry.homography(from: AUQuad.fullFrame(outputSize), to: AUQuad.fullFrame(sourceSize))
        }
    }

    private func stableOutputSize(from state: AnyUprightParameterState, fallback: AUSize) -> AUSize {
        let width = Double(state.stableOutputWidth)
        let height = Double(state.stableOutputHeight)
        guard width > 0.0, height > 0.0 else {
            return fallback
        }
        return AUSize(width: width, height: height)
    }

    private func stableInputSize(from state: AnyUprightParameterState, fallback: AUSize) -> AUSize {
        let width = Double(state.stableInputWidth)
        let height = Double(state.stableInputHeight)
        guard width > 0.0, height > 0.0 else {
            return fallback
        }
        return AUSize(width: width, height: height)
    }

    private func runtimeParameterState(
        from state: AnyUprightParameterState,
        sourceImage: FxImageTile,
        destinationImage: FxImageTile,
        renderTime: CMTime
    ) -> AnyUprightParameterState {
        guard AnyUprightEffectKind(rawValue: state.effectKind) == .upright else {
            return state
        }

        var result = state
        guard let renderSize = cachedStableRenderSize(from: idealizedImageSize(from: sourceImage) ?? idealizedImageSize(from: destinationImage)) else {
            return result
        }

        let stateInputSize = AUSize(width: Double(result.stableInputWidth), height: Double(result.stableInputHeight))
        let stateOutputSize = AUSize(width: Double(result.stableOutputWidth), height: Double(result.stableOutputHeight))
        let sourceImageSize = stableRenderSizeFromEffectSourceImage(at: renderTime)
        if let stableInputSize = mergedStableRenderSize(from: [stateInputSize, sourceImageSize, renderSize].compactMap { $0 }) {
            result.stableInputWidth = Float(stableInputSize.width)
            result.stableInputHeight = Float(stableInputSize.height)
        }
        if let stableOutputSize = mergedStableRenderSize(from: [stateOutputSize, sourceImageSize, renderSize].compactMap { $0 }) {
            result.stableOutputWidth = Float(stableOutputSize.width)
            result.stableOutputHeight = Float(stableOutputSize.height)
        }
        return result
    }

    private func cachedStableRenderSize(from candidate: AUSize?) -> AUSize? {
        stableRenderSizeLock.lock()
        defer { stableRenderSizeLock.unlock() }

        guard let candidate,
              candidate.width > 0.0,
              candidate.height > 0.0 else {
            return cachedUprightStableRenderSize
        }

        guard let cached = cachedUprightStableRenderSize else {
            cachedUprightStableRenderSize = candidate
            return candidate
        }

        let merged = AnyUprightGeometry.mergedStableIdealizedImageSize(cached: cached, candidate: candidate)
        cachedUprightStableRenderSize = merged
        return merged
    }

    private func idealizedImageSize(from image: FxImageTile) -> AUSize? {
        let bounds = image.imagePixelBounds
        let width = Double(bounds.right - bounds.left)
        let height = Double(bounds.top - bounds.bottom)
        guard width > 0.0,
              height > 0.0,
              let transform = image.pixelTransform else {
            return nil
        }

        let values = transform.matrix().pointee
        let scaleX = abs(values.0.0)
        let scaleY = abs(values.1.1)
        guard scaleX > 0.000001,
              scaleY > 0.000001 else {
            return nil
        }

        return AnyUprightGeometry.stableIdealizedImageSize(
            imageBounds: pixelBounds(from: bounds),
            pixelTransformScaleX: scaleX,
            pixelTransformScaleY: scaleY,
            pixelTransformTranslateX: values.0.3,
            pixelTransformTranslateY: values.1.3
        )
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

    private func fxRect(from bounds: AUPixelBounds) -> FxRect {
        FxRect(left: bounds.left, bottom: bounds.bottom, right: bounds.right, top: bounds.top)
    }

    private func debugLogUprightRender(
        parameterState: AnyUprightParameterState,
        sourceImage: FxImageTile,
        sourceTexture: MTLTexture,
        destinationImage: FxImageTile,
        destinationTexture: MTLTexture,
        outputBounds: AUOutputCoordinateBounds,
        warpState: AnyUprightWarpState,
        renderTime: CMTime
    ) {
        guard AnyUprightEffectKind(rawValue: parameterState.effectKind) == .upright,
              FileManager.default.fileExists(atPath: "/tmp/AnyUprightUprightRender.debug") else {
            return
        }

        let outputSize = AUSize(width: Double(warpState.outputSize.x), height: Double(warpState.outputSize.y))
        let sourceSize = AUSize(width: Double(warpState.inputSize.x), height: Double(warpState.inputSize.y))
        let samplePoints = [
            ("tileTL", AUPoint(x: outputBounds.left, y: outputBounds.top)),
            ("tileTR", AUPoint(x: outputBounds.right, y: outputBounds.top)),
            ("tileBR", AUPoint(x: outputBounds.right, y: outputBounds.bottom)),
            ("tileBL", AUPoint(x: outputBounds.left, y: outputBounds.bottom)),
            (
                "tileCenter",
                AUPoint(
                    x: (outputBounds.left + outputBounds.right) / 2.0,
                    y: (outputBounds.top + outputBounds.bottom) / 2.0
                )
            ),
            ("imageCenter", AUPoint(x: outputSize.width / 2.0, y: outputSize.height / 2.0))
        ]
        let mappedSamples = samplePoints.map { name, point in
            let mapped = AnyUprightGeometry.transform(point, by: warpState.outputToSource)
            return String(
                format: "%@ out=%@ src=%@",
                name,
                debugPoint(point),
                debugPoint(mapped)
            )
        }
        .joined(separator: " | ")
        let transformSamples = debugTransformSamples(
            sourceImage: sourceImage,
            destinationImage: destinationImage,
            outputBounds: outputBounds
        )

        let message = String(
            format: "time=%@ fill=%d edit=%d v=%.6f h=%.6f rot=%.6f renderMode=%d stableIn=(%.2fx%.2f) stableOut=(%.2fx%.2f) srcImage=%@ srcTile=%@ dstImage=%@ dstTile=%@ srcOrigin=%lu dstOrigin=%lu srcPT=%@ srcInvPT=%@ dstPT=%@ dstInvPT=%@ transformSamples=%@ srcTex=%dx%d dstTex=%dx%d outBounds=(l=%.2f,r=%.2f,t=%.2f,b=%.2f) outSize=%@ srcSize=%@ texOrigin=%@ texSize=%@ matrix=%@ samples=%@",
            debugTime(renderTime),
            parameterState.fillFrame,
            parameterState.showCornerAdjuster,
            parameterState.verticalPerspective,
            parameterState.horizontalPerspective,
            parameterState.rotationRadians,
            warpState.renderMode,
            parameterState.stableInputWidth,
            parameterState.stableInputHeight,
            parameterState.stableOutputWidth,
            parameterState.stableOutputHeight,
            debugRect(sourceImage.imagePixelBounds),
            debugRect(sourceImage.tilePixelBounds),
            debugRect(destinationImage.imagePixelBounds),
            debugRect(destinationImage.tilePixelBounds),
            sourceImage.imageOrigin,
            destinationImage.imageOrigin,
            debugMatrix44(sourceImage.pixelTransform),
            debugMatrix44(sourceImage.inversePixelTransform),
            debugMatrix44(destinationImage.pixelTransform),
            debugMatrix44(destinationImage.inversePixelTransform),
            transformSamples,
            sourceTexture.width,
            sourceTexture.height,
            destinationTexture.width,
            destinationTexture.height,
            outputBounds.left,
            outputBounds.right,
            outputBounds.top,
            outputBounds.bottom,
            debugSize(outputSize),
            debugSize(sourceSize),
            debugVector(warpState.inputImageOriginInTexture),
            debugVector(warpState.inputTextureSize),
            debugMatrix(warpState.outputToSource),
            mappedSamples
        )
        debugAppendUprightRenderLog(message)
    }

    private func debugTransformSamples(sourceImage: FxImageTile, destinationImage: FxImageTile, outputBounds: AUOutputCoordinateBounds) -> String {
        let samplePoints = [
            ("dstImageTL", CGPoint(x: CGFloat(destinationImage.imagePixelBounds.left), y: CGFloat(destinationImage.imagePixelBounds.top))),
            ("dstImageBR", CGPoint(x: CGFloat(destinationImage.imagePixelBounds.right), y: CGFloat(destinationImage.imagePixelBounds.bottom))),
            ("dstTileTL", CGPoint(x: CGFloat(destinationImage.tilePixelBounds.left), y: CGFloat(destinationImage.tilePixelBounds.top))),
            ("dstTileBR", CGPoint(x: CGFloat(destinationImage.tilePixelBounds.right), y: CGFloat(destinationImage.tilePixelBounds.bottom))),
            ("outTL", CGPoint(x: CGFloat(outputBounds.left), y: CGFloat(outputBounds.top))),
            ("outBR", CGPoint(x: CGFloat(outputBounds.right), y: CGFloat(outputBounds.bottom)))
        ]

        let dstSamples = samplePoints.map { name, point in
            let transformed = destinationImage.pixelTransform.transform2DPoint(point)
            let inverse = destinationImage.inversePixelTransform.transform2DPoint(transformed)
            return String(
                format: "%@ dstPT=%@ dstInvBack=%@",
                name,
                debugCGPoint(transformed),
                debugCGPoint(inverse)
            )
        }
        .joined(separator: " | ")

        let srcImageTL = CGPoint(x: CGFloat(sourceImage.imagePixelBounds.left), y: CGFloat(sourceImage.imagePixelBounds.top))
        let srcImageBR = CGPoint(x: CGFloat(sourceImage.imagePixelBounds.right), y: CGFloat(sourceImage.imagePixelBounds.bottom))
        return String(
            format: "%@ | srcImageTL=%@ srcImageBR=%@",
            dstSamples,
            debugCGPoint(sourceImage.pixelTransform.transform2DPoint(srcImageTL)),
            debugCGPoint(sourceImage.pixelTransform.transform2DPoint(srcImageBR))
        )
    }

    private func debugAppendUprightRenderLog(_ message: String) {
        let logPath = "/tmp/AnyUprightUprightRender.log"
        let timestamp = String(format: "%.3f", Date().timeIntervalSince1970)
        guard let data = "[\(timestamp)] \(message)\n".data(using: .utf8) else {
            return
        }

        if FileManager.default.fileExists(atPath: logPath),
           let handle = try? FileHandle(forWritingTo: URL(fileURLWithPath: logPath)) {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
            try? handle.close()
        } else {
            try? data.write(to: URL(fileURLWithPath: logPath))
        }
    }

    private func debugRect(_ rect: FxRect) -> String {
        String(format: "(%d,%d,%d,%d)", rect.left, rect.bottom, rect.right, rect.top)
    }

    private func debugPoint(_ point: AUPoint) -> String {
        String(format: "(%.2f,%.2f)", point.x, point.y)
    }

    private func debugCGPoint(_ point: CGPoint) -> String {
        String(format: "(%.2f,%.2f)", point.x, point.y)
    }

    private func debugSize(_ size: AUSize) -> String {
        String(format: "(%.2fx%.2f)", size.width, size.height)
    }

    private func debugVector(_ vector: vector_float2) -> String {
        String(format: "(%.2f,%.2f)", vector.x, vector.y)
    }

    private func debugMatrix(_ matrix: simd_float3x3) -> String {
        String(
            format: "[%.6f %.6f %.6f; %.6f %.6f %.6f; %.6f %.6f %.6f]",
            matrix.columns.0.x,
            matrix.columns.1.x,
            matrix.columns.2.x,
            matrix.columns.0.y,
            matrix.columns.1.y,
            matrix.columns.2.y,
            matrix.columns.0.z,
            matrix.columns.1.z,
            matrix.columns.2.z
        )
    }

    private func debugMatrix44(_ matrix: FxMatrix44?) -> String {
        guard let matrix else {
            return "nil"
        }

        let raw = matrix.matrix()
        let values = raw.pointee
        return String(
            format: "[%.6f %.6f %.6f %.6f; %.6f %.6f %.6f %.6f; %.6f %.6f %.6f %.6f; %.6f %.6f %.6f %.6f]",
            values.0.0,
            values.0.1,
            values.0.2,
            values.0.3,
            values.1.0,
            values.1.1,
            values.1.2,
            values.1.3,
            values.2.0,
            values.2.1,
            values.2.2,
            values.2.3,
            values.3.0,
            values.3.1,
            values.3.2,
            values.3.3
        )
    }

    private func debugTime(_ time: CMTime) -> String {
        String(
            format: "value=%lld/timescale=%d/sec=%.6f/flags=%u",
            time.value,
            time.timescale,
            time.seconds,
            time.flags.rawValue
        )
    }
}
