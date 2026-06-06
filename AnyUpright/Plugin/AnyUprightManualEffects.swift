//
//  AnyUprightManualEffects.swift
//  AnyUpright
//

import Foundation
import AppKit
import CoreImage
import IOSurface
import Vision

private enum HorizonParam: UInt32 {
    case rotation = 100
    case fillFrame = 101
    case analyze = 102
}

private enum QuadParam: UInt32 {
    case sourceQuadStretchMode = 197
    case mode = 198
    case showCornerAdjuster = 199
    case topLeftPercentX = 200
    case topLeftPercentY = 201
    case topLeftPixelX = 202
    case topLeftPixelY = 203
    case topRightPercentX = 204
    case topRightPercentY = 205
    case topRightPixelX = 206
    case topRightPixelY = 207
    case bottomRightPercentX = 208
    case bottomRightPercentY = 209
    case bottomRightPixelX = 210
    case bottomRightPixelY = 211
    case bottomLeftPercentX = 212
    case bottomLeftPercentY = 213
    case bottomLeftPixelX = 214
    case bottomLeftPixelY = 215
}

private enum QuadGroup: UInt32, CaseIterable {
    case topLeft = 220
    case topRight = 221
    case bottomRight = 222
    case bottomLeft = 223
}

private enum QuadOSCPart: Int {
    case none = 0
    case topLeft = 1
    case topRight = 2
    case bottomRight = 3
    case bottomLeft = 4
    case quad = 5
}

private struct QuadOSCDragState {
    var part: QuadOSCPart
    var lastCanvasPoint: AUPoint
}

private enum UprightParam: UInt32 {
    case verticalPerspective = 300
    case horizontalPerspective = 301
    case rotation = 302
    case analyzeVertical = 303
    case analyzeHorizontal = 304
    case analyzeFull = 305
    case applyGuidedVertical = 306
    case applyGuidedHorizontal = 307
    case applyGuidedFull = 308
    case detectVerticalCandidates = 309
    case detectHorizontalCandidates = 310
    case detectFullCandidates = 311
    case applySelectedVertical = 312
    case applySelectedHorizontal = 313
    case applySelectedFull = 314

    case guide1Enabled = 320
    case guide1Orientation = 321
    case guide1Start = 322
    case guide1End = 323
    case guide2Enabled = 330
    case guide2Orientation = 331
    case guide2Start = 332
    case guide2End = 333
    case guide3Enabled = 340
    case guide3Orientation = 341
    case guide3Start = 342
    case guide3End = 343
    case guide4Enabled = 350
    case guide4Orientation = 351
    case guide4Start = 352
    case guide4End = 353
}

private enum UprightAnalysisMode {
    case vertical
    case horizontal
    case full
    case detectVerticalCandidates
    case detectHorizontalCandidates
    case detectFullCandidates

    var includesVertical: Bool {
        switch self {
        case .vertical, .full, .detectVerticalCandidates, .detectFullCandidates:
            return true
        case .horizontal, .detectHorizontalCandidates:
            return false
        }
    }

    var includesHorizontal: Bool {
        switch self {
        case .horizontal, .full, .detectHorizontalCandidates, .detectFullCandidates:
            return true
        case .vertical, .detectVerticalCandidates:
            return false
        }
    }

    var isCandidateDetection: Bool {
        switch self {
        case .detectVerticalCandidates, .detectHorizontalCandidates, .detectFullCandidates:
            return true
        case .vertical, .horizontal, .full:
            return false
        }
    }
}

private enum UprightOSCPart: Int {
    case none = 0
    case guide1Start = 1
    case guide1End = 2
    case guide2Start = 3
    case guide2End = 4
    case guide3Start = 5
    case guide3End = 6
    case guide4Start = 7
    case guide4End = 8
}

private struct UprightGuideSpec {
    var enabled: UprightParam
    var orientation: UprightParam
    var start: UprightParam
    var end: UprightParam
    var startPart: UprightOSCPart
    var endPart: UprightOSCPart
    var defaultOrientation: UprightGuideOrientation
    var defaultStart: AUPoint
    var defaultEnd: AUPoint
}

private struct UprightGuideLine {
    var spec: UprightGuideSpec
    var orientation: UprightGuideOrientation
    var start: AUPoint
    var end: AUPoint
}

private let uprightGuideSpecs = [
    UprightGuideSpec(
        enabled: .guide1Enabled,
        orientation: .guide1Orientation,
        start: .guide1Start,
        end: .guide1End,
        startPart: .guide1Start,
        endPart: .guide1End,
        defaultOrientation: .vertical,
        defaultStart: AUPoint(x: 0.35, y: 0.2),
        defaultEnd: AUPoint(x: 0.35, y: 0.8)
    ),
    UprightGuideSpec(
        enabled: .guide2Enabled,
        orientation: .guide2Orientation,
        start: .guide2Start,
        end: .guide2End,
        startPart: .guide2Start,
        endPart: .guide2End,
        defaultOrientation: .vertical,
        defaultStart: AUPoint(x: 0.65, y: 0.2),
        defaultEnd: AUPoint(x: 0.65, y: 0.8)
    ),
    UprightGuideSpec(
        enabled: .guide3Enabled,
        orientation: .guide3Orientation,
        start: .guide3Start,
        end: .guide3End,
        startPart: .guide3Start,
        endPart: .guide3End,
        defaultOrientation: .horizontal,
        defaultStart: AUPoint(x: 0.2, y: 0.35),
        defaultEnd: AUPoint(x: 0.8, y: 0.35)
    ),
    UprightGuideSpec(
        enabled: .guide4Enabled,
        orientation: .guide4Orientation,
        start: .guide4Start,
        end: .guide4End,
        startPart: .guide4Start,
        endPart: .guide4End,
        defaultOrientation: .horizontal,
        defaultStart: AUPoint(x: 0.2, y: 0.65),
        defaultEnd: AUPoint(x: 0.8, y: 0.65)
    )
]

private func singleFrameAnalysisRange(near requestedTime: CMTime, within inputTimeRange: CMTimeRange) -> CMTimeRange {
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

private func parameterWriteTime(preferred: CMTime, fallback: CMTime) -> CMTime {
    if preferred.isValid, preferred.isNumeric {
        return preferred
    }

    return fallback
}

private enum AnyUprightAnalysisImage {
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
}

@objc(AnyUprightHorizonManualPlugIn)
class AnyUprightHorizonManualPlugIn: AnyUprightWarpEffect, FxAnalyzer {
    private let analysisLock = NSLock()
    private let analysisContext = CIContext(options: nil)
    private var detectedRotationRadians: Double?
    private var detectedRotationTime = CMTime.zero
    private var requestedAnalysisTime = CMTime.zero

    override func addEffectParameters(_ paramAPI: FxParameterCreationAPI_v5) throws {
        paramAPI.addPushButton(
            withName: "Analyze Horizon",
            parameterID: HorizonParam.analyze.rawValue,
            selector: #selector(analyzeHorizon),
            parameterFlags: defaultFlags()
        )
        paramAPI.addAngleSlider(
            withName: "Rotation",
            parameterID: HorizonParam.rotation.rawValue,
            defaultDegrees: 0.0,
            parameterMinDegrees: -45.0,
            parameterMaxDegrees: 45.0,
            parameterFlags: defaultFlags()
        )
        paramAPI.addToggleButton(
            withName: "Fill Frame",
            parameterID: HorizonParam.fillFrame.rawValue,
            defaultValue: false,
            parameterFlags: defaultFlags()
        )
    }

    override func state(at renderTime: CMTime) -> AnyUprightParameterState {
        var result = AnyUprightParameterState(effectKind: AnyUprightEffectKind.horizon.rawValue)
        guard let paramAPI = parameterRetrievalAPI() else {
            return result
        }

        var rotation = 0.0
        var fillFrame = ObjCBool(false)

        paramAPI.getFloatValue(&rotation, fromParameter: HorizonParam.rotation.rawValue, at: renderTime)
        paramAPI.getBoolValue(&fillFrame, fromParameter: HorizonParam.fillFrame.rawValue, at: renderTime)

        result.rotationRadians = Float(rotation)
        result.fillFrame = fillFrame.boolValue ? 1 : 0
        return result
    }

    @objc private func analyzeHorizon() {
        analysisLock.lock()
        requestedAnalysisTime = currentParameterTime()
        analysisLock.unlock()

        guard let analysisAPI = _apiManager.api(for: FxAnalysisAPI.self) as? FxAnalysisAPI else {
            return
        }

        try? analysisAPI.startForwardAnalysis(kFxAnalysisLocation_CPU)
    }

    func desiredAnalysisTimeRange(_ desiredRange: UnsafeMutablePointer<CMTimeRange>, forInputWith inputTimeRange: CMTimeRange) throws {
        analysisLock.lock()
        let requestedTime = requestedAnalysisTime
        analysisLock.unlock()
        desiredRange.pointee = singleFrameAnalysisRange(near: requestedTime, within: inputTimeRange)
    }

    func setupAnalysis(for analysisRange: CMTimeRange, frameDuration: CMTime) throws {
        analysisLock.lock()
        detectedRotationRadians = nil
        detectedRotationTime = analysisRange.start
        analysisLock.unlock()
    }

    func analyzeFrame(_ frame: FxImageTile, at frameTime: CMTime) throws {
        analysisLock.lock()
        let alreadyDetected = detectedRotationRadians != nil
        analysisLock.unlock()

        if alreadyDetected {
            return
        }

        guard let image = AnyUprightAnalysisImage.ciImage(from: frame) else {
            return
        }

        let request = VNDetectHorizonRequest()
        let handler = VNImageRequestHandler(ciImage: image, options: [:])
        var rotationRadians: Double?

        do {
            try handler.perform([request])

            if let observation = request.results?.first as? VNHorizonObservation {
                let bounds = frame.imagePixelBounds
                let width = max(1, Int(bounds.right - bounds.left))
                let height = max(1, Int(bounds.top - bounds.bottom))
                let transform = observation.transform(forImageWidth: width, height: height)
                rotationRadians = atan2(Double(transform.b), Double(transform.a))
            }
        } catch {
            rotationRadians = nil
        }

        if rotationRadians == nil,
           let grayscaleImage = AnyUprightAnalysisImage.grayscaleImage(from: frame, maxDimension: 360, context: analysisContext) {
            let lines = AnyUprightLineDetection.detectLineSegments(
                in: grayscaleImage,
                options: AULineDetectionOptions(
                    orientation: .horizontal,
                    edgeThreshold: 40.0,
                    voteThreshold: max(20, grayscaleImage.width / 5),
                    maxLines: 40
                )
            )
            rotationRadians = AnyUprightGeometry.dominantHorizonCorrectionRadians(from: lines)
        }

        guard let rotationRadians else {
            return
        }

        analysisLock.lock()
        detectedRotationRadians = rotationRadians
        detectedRotationTime = frameTime
        analysisLock.unlock()
    }

    func cleanupAnalysis() throws {
        analysisLock.lock()
        let rotationRadians = detectedRotationRadians
        let rotationTime = detectedRotationTime
        let requestedTime = requestedAnalysisTime
        analysisLock.unlock()

        let writeTime = parameterWriteTime(preferred: requestedTime, fallback: rotationTime)
        guard let settingAPI = _apiManager.api(for: FxParameterSettingAPI_v5.self) as? FxParameterSettingAPI_v5 else {
            return
        }

        guard let rotationRadians else {
            return
        }

        _ = settingAPI.setFloatValue(rotationRadians, toParameter: HorizonParam.rotation.rawValue, at: writeTime)
    }
}

private func quadFloatParam(_ paramAPI: FxParameterRetrievalAPI_v6, _ param: QuadParam, _ time: CMTime) -> Float {
    var value = 0.0
    paramAPI.getFloatValue(&value, fromParameter: param.rawValue, at: time)
    return Float(value)
}

private func quadParameterState(at time: CMTime, paramAPI: FxParameterRetrievalAPI_v6?) -> AnyUprightParameterState {
    var result = AnyUprightParameterState(effectKind: AnyUprightEffectKind.quad.rawValue)
    guard let paramAPI else {
        return result
    }

    var mode = Int32(AUQuadTransformMode.outputCorners.rawValue)
    var showCornerAdjuster = ObjCBool(true)
    var stretchMode = Int32(AUSourceQuadStretchMode.stretch.rawValue)

    paramAPI.getIntValue(&stretchMode, fromParameter: QuadParam.sourceQuadStretchMode.rawValue, at: time)
    paramAPI.getIntValue(&mode, fromParameter: QuadParam.mode.rawValue, at: time)
    paramAPI.getBoolValue(&showCornerAdjuster, fromParameter: QuadParam.showCornerAdjuster.rawValue, at: time)
    result.sourceQuadStretchMode = stretchMode
    result.quadMode = mode
    result.showCornerAdjuster = showCornerAdjuster.boolValue ? 1 : 0

    result.topLeftPercentX = quadFloatParam(paramAPI, .topLeftPercentX, time)
    result.topLeftPercentY = quadFloatParam(paramAPI, .topLeftPercentY, time)
    result.topLeftPixelX = quadFloatParam(paramAPI, .topLeftPixelX, time)
    result.topLeftPixelY = quadFloatParam(paramAPI, .topLeftPixelY, time)

    result.topRightPercentX = quadFloatParam(paramAPI, .topRightPercentX, time)
    result.topRightPercentY = quadFloatParam(paramAPI, .topRightPercentY, time)
    result.topRightPixelX = quadFloatParam(paramAPI, .topRightPixelX, time)
    result.topRightPixelY = quadFloatParam(paramAPI, .topRightPixelY, time)

    result.bottomRightPercentX = quadFloatParam(paramAPI, .bottomRightPercentX, time)
    result.bottomRightPercentY = quadFloatParam(paramAPI, .bottomRightPercentY, time)
    result.bottomRightPixelX = quadFloatParam(paramAPI, .bottomRightPixelX, time)
    result.bottomRightPixelY = quadFloatParam(paramAPI, .bottomRightPixelY, time)

    result.bottomLeftPercentX = quadFloatParam(paramAPI, .bottomLeftPercentX, time)
    result.bottomLeftPercentY = quadFloatParam(paramAPI, .bottomLeftPercentY, time)
    result.bottomLeftPixelX = quadFloatParam(paramAPI, .bottomLeftPixelX, time)
    result.bottomLeftPixelY = quadFloatParam(paramAPI, .bottomLeftPixelY, time)

    return result
}

private func quadMode(from state: AnyUprightParameterState) -> AUQuadTransformMode {
    AUQuadTransformMode(rawValue: state.quadMode) ?? .outputCorners
}

private func shouldShowQuadCornerAdjuster(from state: AnyUprightParameterState, mode: AUQuadTransformMode) -> Bool {
    mode == .sourceQuad && state.showCornerAdjuster != 0
}

private func quadCornerOffsets(from state: AnyUprightParameterState) -> AUCornerOffsets {
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

private func quadObjectPoints(from state: AnyUprightParameterState, size: AUSize, mode: AUQuadTransformMode) -> AUQuad {
    switch mode {
    case .outputCorners:
        return AnyUprightGeometry.quadObjectPoints(from: quadCornerOffsets(from: state), size: size)
    case .sourceQuad:
        return AnyUprightGeometry.sourceQuadObjectPoints(from: quadCornerOffsets(from: state), size: size)
    }
}

@objc(AnyUprightQuadManualPlugIn)
class AnyUprightQuadManualPlugIn: AnyUprightWarpEffect {
    override func addEffectParameters(_ paramAPI: FxParameterCreationAPI_v5) throws {
        paramAPI.addPopupMenu(
            withName: "Mode",
            parameterID: QuadParam.mode.rawValue,
            defaultValue: UInt32(AUQuadTransformMode.outputCorners.rawValue),
            menuEntries: ["Output Corners", "Source Quad"],
            parameterFlags: defaultFlags()
        )
        paramAPI.addPopupMenu(
            withName: "Stretch Mode",
            parameterID: QuadParam.sourceQuadStretchMode.rawValue,
            defaultValue: UInt32(AUSourceQuadStretchMode.stretch.rawValue),
            menuEntries: ["Stretch to Frame", "Mirror Horizontal", "Mirror Vertical"],
            parameterFlags: showCornerAdjusterHiddenFlags()
        )
        paramAPI.addToggleButton(
            withName: "Show Corner Adjuster",
            parameterID: QuadParam.showCornerAdjuster.rawValue,
            defaultValue: true,
            parameterFlags: showCornerAdjusterHiddenFlags()
        )
        addCornerParameters(paramAPI, title: "Top Left", groupID: QuadGroup.topLeft.rawValue, percentX: .topLeftPercentX, percentY: .topLeftPercentY, pixelX: .topLeftPixelX, pixelY: .topLeftPixelY)
        addCornerParameters(paramAPI, title: "Top Right", groupID: QuadGroup.topRight.rawValue, percentX: .topRightPercentX, percentY: .topRightPercentY, pixelX: .topRightPixelX, pixelY: .topRightPixelY)
        addCornerParameters(paramAPI, title: "Bottom Right", groupID: QuadGroup.bottomRight.rawValue, percentX: .bottomRightPercentX, percentY: .bottomRightPercentY, pixelX: .bottomRightPixelX, pixelY: .bottomRightPixelY)
        addCornerParameters(paramAPI, title: "Bottom Left", groupID: QuadGroup.bottomLeft.rawValue, percentX: .bottomLeftPercentX, percentY: .bottomLeftPercentY, pixelX: .bottomLeftPixelX, pixelY: .bottomLeftPixelY)
    }

    override func state(at renderTime: CMTime) -> AnyUprightParameterState {
        quadParameterState(at: renderTime, paramAPI: parameterRetrievalAPI())
    }

    func pluginInstanceAddedToDocument() {
        syncQuadInspectorVisibility(at: currentParameterTime())
    }

    @objc(finishInitialSetup:)
    func finishInitialSetup(_ error: AutoreleasingUnsafeMutablePointer<NSError?>?) -> Bool {
        syncQuadInspectorVisibility(at: currentParameterTime())
        return true
    }

    func parameterChanged(_ paramID: UInt32, at time: CMTime) throws {
        guard paramID == QuadParam.mode.rawValue else {
            return
        }

        syncQuadInspectorVisibility(at: time)
    }

    private func addCornerParameters(_ paramAPI: FxParameterCreationAPI_v5, title: String, groupID: UInt32, percentX: QuadParam, percentY: QuadParam, pixelX: QuadParam, pixelY: QuadParam) {
        paramAPI.startParameterSubGroup(title, parameterID: groupID, parameterFlags: collapsedFlags())
        addPercentSlider(paramAPI, name: "\(title) X %", id: percentX.rawValue)
        addPercentSlider(paramAPI, name: "\(title) Y %", id: percentY.rawValue)
        addPixelSlider(paramAPI, name: "\(title) X px", id: pixelX.rawValue)
        addPixelSlider(paramAPI, name: "\(title) Y px", id: pixelY.rawValue)
        paramAPI.endParameterSubGroup()
    }

    private func addPercentSlider(_ paramAPI: FxParameterCreationAPI_v5, name: String, id: UInt32) {
        paramAPI.addPercentSlider(
            withName: name,
            parameterID: id,
            defaultValue: 0.0,
            parameterMin: -1.0,
            parameterMax: 1.0,
            sliderMin: -0.5,
            sliderMax: 0.5,
            delta: 0.01,
            parameterFlags: defaultFlags()
        )
    }

    private func addPixelSlider(_ paramAPI: FxParameterCreationAPI_v5, name: String, id: UInt32) {
        paramAPI.addFloatSlider(
            withName: name,
            parameterID: id,
            defaultValue: 0.0,
            parameterMin: -10000.0,
            parameterMax: 10000.0,
            sliderMin: -500.0,
            sliderMax: 500.0,
            delta: 1.0,
            parameterFlags: defaultFlags()
        )
    }

    private func syncQuadInspectorVisibility(at time: CMTime) {
        var mode = Int32(AUQuadTransformMode.outputCorners.rawValue)
        if let paramAPI = parameterRetrievalAPI() {
            paramAPI.getIntValue(&mode, fromParameter: QuadParam.mode.rawValue, at: time)
        }

        guard let settingAPI = _apiManager.api(for: FxParameterSettingAPI_v5.self) as? FxParameterSettingAPI_v5 else {
            return
        }

        let selectedMode = AUQuadTransformMode(rawValue: mode) ?? .outputCorners
        let isSourceQuad = selectedMode == .sourceQuad

        _ = settingAPI.setParameterFlags(isSourceQuad ? defaultFlags() : showCornerAdjusterHiddenFlags(), toParameter: QuadParam.sourceQuadStretchMode.rawValue)
        _ = settingAPI.setParameterFlags(isSourceQuad ? defaultFlags() : showCornerAdjusterHiddenFlags(), toParameter: QuadParam.showCornerAdjuster.rawValue)

        let cornerFlags = isSourceQuad ? hiddenCollapsedFlags() : collapsedFlags()
        for group in QuadGroup.allCases {
            _ = settingAPI.setParameterFlags(cornerFlags, toParameter: group.rawValue)
        }
    }

    private func showCornerAdjusterHiddenFlags() -> FxParameterFlags {
        FxParameterFlags(kFxParameterFlag_HIDDEN)
    }

    private func hiddenCollapsedFlags() -> FxParameterFlags {
        FxParameterFlags(kFxParameterFlag_HIDDEN | kFxParameterFlag_COLLAPSED)
    }
}

@objc(AnyUprightQuadManualOSCPlugIn)
class AnyUprightQuadManualOSCPlugIn: AnyUprightOSCPlugIn, FxOnScreenControl_v4 {
    private let overlayRenderer = AnyUprightOSCOverlayRenderer()
    private let dragStateLock = NSLock()
    private let surfaceSizeLock = NSLock()
    private var dragState: QuadOSCDragState?
    private var lastSurfaceSize = AUSize(width: 1.0, height: 1.0)

    required init?(apiManager: PROAPIAccessing) {
        super.init(apiManager: apiManager)
    }

    @objc(drawingCoordinates)
    func drawingCoordinates() -> FxDrawingCoordinates {
        return FxDrawingCoordinates(kFxDrawingCoordinates_CANVAS)
    }

    @objc(drawOSCWithWidth:height:activePart:destinationImage:atTime:)
    func drawOSC(withWidth width: Int, height: Int, activePart: Int, destinationImage: FxImageTile, at time: CMTime) {
        let state = quadParameterState(at: time, paramAPI: parameterRetrievalAPI())
        let mode = quadMode(from: state)
        guard shouldShowQuadCornerAdjuster(from: state, mode: mode) else {
            return
        }

        let objectSize = objectPixelSizeForOSC()
        let objectPoints = quadObjectPoints(from: state, size: objectSize, mode: mode)
        let canvasPoints = quadCanvasPoints(from: objectPoints)
        let canvasFrame = objectCanvasFrame()
        updateLastSurfaceSize(from: destinationImage, fallback: AUSize(width: Double(width), height: Double(height)))
        let handles = [
            AUOSCHandle(point: canvasPoints.topLeft, part: QuadOSCPart.topLeft.rawValue),
            AUOSCHandle(point: canvasPoints.topRight, part: QuadOSCPart.topRight.rawValue),
            AUOSCHandle(point: canvasPoints.bottomRight, part: QuadOSCPart.bottomRight.rawValue),
            AUOSCHandle(point: canvasPoints.bottomLeft, part: QuadOSCPart.bottomLeft.rawValue)
        ]
        let orderedPoints = [canvasPoints.topLeft, canvasPoints.topRight, canvasPoints.bottomRight, canvasPoints.bottomLeft]

        overlayRenderer.renderQuadAdjuster(
            points: orderedPoints,
            handles: handles,
            activePart: activePart,
            destinationImage: destinationImage,
            destinationSize: AUSize(width: Double(width), height: Double(height)),
            canvasFrame: canvasFrame,
            coordinateSpace: .pixels,
            dimmingFrame: canvasFrame
        )
    }

    @objc(hitTestOSCAtMousePositionX:mousePositionY:activePart:atTime:)
    func hitTestOSC(atMousePositionX mousePositionX: Double, mousePositionY: Double, activePart: UnsafeMutablePointer<Int>?, at time: CMTime) {
        let state = quadParameterState(at: time, paramAPI: parameterRetrievalAPI())
        let mode = quadMode(from: state)
        guard shouldShowQuadCornerAdjuster(from: state, mode: mode) else {
            activePart?.pointee = QuadOSCPart.none.rawValue
            return
        }

        let size = objectPixelSizeForOSC()
        let objectPoints = quadObjectPoints(from: state, size: size, mode: mode)
        let canvasPoints = quadCanvasPoints(from: objectPoints)
        let canvasFrame = objectCanvasFrame()
        let handles = [
            AUOSCHandle(point: canvasPoints.topLeft, part: QuadOSCPart.topLeft.rawValue),
            AUOSCHandle(point: canvasPoints.topRight, part: QuadOSCPart.topRight.rawValue),
            AUOSCHandle(point: canvasPoints.bottomRight, part: QuadOSCPart.bottomRight.rawValue),
            AUOSCHandle(point: canvasPoints.bottomLeft, part: QuadOSCPart.bottomLeft.rawValue)
        ]
        let eventPoint = AUPoint(x: mousePositionX, y: mousePositionY)
        let mouse = eventMapper(for: canvasFrame)?.canvasPoint(fromEventPoint: eventPoint) ?? eventPoint
        let hitRadius = 24.0
        var matchedPart = QuadOSCPart.none.rawValue
        for handle in handles {
            let dx = mouse.x - handle.point.x
            let dy = mouse.y - handle.point.y
            let distance = hypot(dx, dy)
            if distance <= hitRadius {
                matchedPart = handle.part
                break
            }
        }
        if matchedPart == QuadOSCPart.none.rawValue,
           isPoint(mouse, insideQuad: [canvasPoints.topLeft, canvasPoints.topRight, canvasPoints.bottomRight, canvasPoints.bottomLeft]) {
            matchedPart = QuadOSCPart.quad.rawValue
        }
        activePart?.pointee = matchedPart
    }

    @objc(mouseDownAtPositionX:positionY:activePart:modifiers:forceUpdate:atTime:)
    func mouseDown(atPositionX mousePositionX: Double, positionY mousePositionY: Double, activePart: Int, modifiers: FxModifierKeys, forceUpdate: UnsafeMutablePointer<ObjCBool>?, at time: CMTime) {
        let state = quadParameterState(at: time, paramAPI: parameterRetrievalAPI())
        let mode = quadMode(from: state)
        let eventPoint = AUPoint(x: mousePositionX, y: mousePositionY)
        let mouse = eventMapper(for: objectCanvasFrame())?.canvasPoint(fromEventPoint: eventPoint) ?? eventPoint

        guard shouldShowQuadCornerAdjuster(from: state, mode: mode),
              let part = QuadOSCPart(rawValue: activePart),
              part != .none else {
            setDragState(nil)
            forceUpdate?.pointee = false
            return
        }

        setDragState(QuadOSCDragState(part: part, lastCanvasPoint: mouse))
        forceUpdate?.pointee = true
    }

    @objc(mouseDraggedAtPositionX:positionY:activePart:modifiers:forceUpdate:atTime:)
    func mouseDragged(atPositionX mousePositionX: Double, positionY mousePositionY: Double, activePart: Int, modifiers: FxModifierKeys, forceUpdate: UnsafeMutablePointer<ObjCBool>?, at time: CMTime) {
        let state = quadParameterState(at: time, paramAPI: parameterRetrievalAPI())
        let mode = quadMode(from: state)
        let storedState = currentDragState()
        let part = validDragPart(from: activePart) ?? storedState?.part

        guard shouldShowQuadCornerAdjuster(from: state, mode: mode),
              let part,
              let settingAPI = parameterSettingAPI() else {
            forceUpdate?.pointee = false
            return
        }

        let size = objectPixelSizeForOSC()
        let eventPoint = AUPoint(x: mousePositionX, y: mousePositionY)
        let canvasPoint = eventMapper(for: objectCanvasFrame())?.canvasPoint(fromEventPoint: eventPoint) ?? eventPoint
        let draggedObjectPoint = objectPoint(fromCanvasPoint: canvasPoint)
        if part == .quad, let previousCanvasPoint = storedState?.lastCanvasPoint {
            let previousObjectPoint = objectPoint(fromCanvasPoint: previousCanvasPoint)
            let pixelDelta = AUPoint(
                x: (draggedObjectPoint.x - previousObjectPoint.x) * size.width,
                y: (draggedObjectPoint.y - previousObjectPoint.y) * size.height
            )
            translateQuad(from: state, pixelDelta: pixelDelta, settingAPI: settingAPI, time: time)
            setDragState(QuadOSCDragState(part: part, lastCanvasPoint: canvasPoint))
            forceUpdate?.pointee = true
            return
        }

        setDragState(QuadOSCDragState(part: part, lastCanvasPoint: canvasPoint))
        setCorner(draggedObjectPoint, part: part, mode: mode, offsets: quadCornerOffsets(from: state), size: size, settingAPI: settingAPI, time: time)
        forceUpdate?.pointee = true
    }

    @objc(mouseUpAtPositionX:positionY:activePart:modifiers:forceUpdate:atTime:)
    func mouseUp(atPositionX mousePositionX: Double, positionY mousePositionY: Double, activePart: Int, modifiers: FxModifierKeys, forceUpdate: UnsafeMutablePointer<ObjCBool>?, at time: CMTime) {
        setDragState(nil)
        forceUpdate?.pointee = true
    }

    @objc(mouseEnteredAtPositionX:positionY:modifiers:forceUpdate:atTime:)
    func mouseEntered(atPositionX mousePositionX: Double, positionY mousePositionY: Double, modifiers: FxModifierKeys, forceUpdate: UnsafeMutablePointer<ObjCBool>?, at time: CMTime) {
        forceUpdate?.pointee = false
    }

    @objc(mouseMovedAtPositionX:positionY:activePart:modifiers:forceUpdate:atTime:)
    func mouseMoved(atPositionX mousePositionX: Double, positionY mousePositionY: Double, activePart: Int, modifiers: FxModifierKeys, forceUpdate: UnsafeMutablePointer<ObjCBool>?, at time: CMTime) {
        if validDragPart(from: activePart) != nil {
            setCursor(NSCursor.pointingHand)
        } else {
            setCursor(NSCursor.arrow)
        }
        forceUpdate?.pointee = false
    }

    @objc(mouseExitedAtPositionX:positionY:modifiers:forceUpdate:atTime:)
    func mouseExited(atPositionX mousePositionX: Double, positionY mousePositionY: Double, modifiers: FxModifierKeys, forceUpdate: UnsafeMutablePointer<ObjCBool>?, at time: CMTime) {
        setCursor(NSCursor.arrow)
        forceUpdate?.pointee = false
    }

    @objc(keyDownAtPositionX:positionY:keyPressed:modifiers:forceUpdate:didHandle:atTime:)
    func keyDown(atPositionX mousePositionX: Double, positionY mousePositionY: Double, keyPressed: UInt16, modifiers: FxModifierKeys, forceUpdate: UnsafeMutablePointer<ObjCBool>?, didHandle: UnsafeMutablePointer<ObjCBool>?, at time: CMTime) {
        forceUpdate?.pointee = false
        didHandle?.pointee = false
    }

    @objc(keyUpAtPositionX:positionY:keyPressed:modifiers:forceUpdate:didHandle:atTime:)
    func keyUp(atPositionX mousePositionX: Double, positionY mousePositionY: Double, keyPressed: UInt16, modifiers: FxModifierKeys, forceUpdate: UnsafeMutablePointer<ObjCBool>?, didHandle: UnsafeMutablePointer<ObjCBool>?, at time: CMTime) {
        forceUpdate?.pointee = false
        didHandle?.pointee = false
    }

    private func quadCanvasPoints(from objectPoints: AUQuad) -> AUQuad {
        AUQuad(
            topLeft: canvasPoint(fromObjectPoint: objectPoints.topLeft),
            topRight: canvasPoint(fromObjectPoint: objectPoints.topRight),
            bottomRight: canvasPoint(fromObjectPoint: objectPoints.bottomRight),
            bottomLeft: canvasPoint(fromObjectPoint: objectPoints.bottomLeft)
        )
    }

    private func objectCanvasFrame() -> [AUPoint] {
        [
            canvasPoint(fromObjectPoint: AUPoint(x: 0.0, y: 1.0)),
            canvasPoint(fromObjectPoint: AUPoint(x: 1.0, y: 1.0)),
            canvasPoint(fromObjectPoint: AUPoint(x: 1.0, y: 0.0)),
            canvasPoint(fromObjectPoint: AUPoint(x: 0.0, y: 0.0))
        ]
    }

    private func canvasPoint(fromObjectPoint point: AUPoint) -> AUPoint {
        convertPoint(point, from: kFxDrawingCoordinates_OBJECT, to: kFxDrawingCoordinates_CANVAS)
    }

    private func objectPoint(fromCanvasPoint point: AUPoint) -> AUPoint {
        convertPoint(point, from: kFxDrawingCoordinates_CANVAS, to: kFxDrawingCoordinates_OBJECT)
    }

    private func convertPoint(_ point: AUPoint, from fromSpace: Int, to toSpace: Int) -> AUPoint {
        guard let oscAPI = _apiManager.api(for: FxOnScreenControlAPI_v4.self) as? FxOnScreenControlAPI_v4 else {
            return point
        }

        var x = 0.0
        var y = 0.0
        oscAPI.convertPoint(
            fromSpace: FxDrawingCoordinates(fromSpace),
            fromX: point.x,
            fromY: point.y,
            toSpace: FxDrawingCoordinates(toSpace),
            toX: &x,
            toY: &y
        )
        return AUPoint(x: x, y: y)
    }

    private func setCursor(_ cursor: NSCursor) {
        guard let oscAPI = _apiManager.api(for: FxOnScreenControlAPI_v4.self) as? FxOnScreenControlAPI_v4 else {
            return
        }

        oscAPI.setCursor(cursor)
    }

    private func setDragState(_ state: QuadOSCDragState?) {
        dragStateLock.lock()
        dragState = state
        dragStateLock.unlock()
    }

    private func currentDragState() -> QuadOSCDragState? {
        dragStateLock.lock()
        let state = dragState
        dragStateLock.unlock()
        return state
    }

    private func updateLastSurfaceSize(from image: FxImageTile, fallback: AUSize) {
        let width = Double(image.ioSurface.map { IOSurfaceGetWidth($0) } ?? Int(max(1.0, fallback.width)))
        let height = Double(image.ioSurface.map { IOSurfaceGetHeight($0) } ?? Int(max(1.0, fallback.height)))

        surfaceSizeLock.lock()
        lastSurfaceSize = AUSize(width: max(1.0, width), height: max(1.0, height))
        surfaceSizeLock.unlock()
    }

    private func currentSurfaceSize() -> AUSize {
        surfaceSizeLock.lock()
        let size = lastSurfaceSize
        surfaceSizeLock.unlock()
        return size
    }

    private func eventMapper(for canvasFrame: [AUPoint]) -> AUCanvasSurfaceMapper? {
        let surfaceSize = currentSurfaceSize()
        guard surfaceSize.width > 1.0, surfaceSize.height > 1.0 else {
            return nil
        }

        return AUCanvasSurfaceMapper(canvasFrame: canvasFrame, surfaceSize: surfaceSize)
    }

    private func validDragPart(from rawValue: Int) -> QuadOSCPart? {
        guard let part = QuadOSCPart(rawValue: rawValue), part != .none else {
            return nil
        }
        return part
    }

    private func setCorner(_ point: AUPoint, part: QuadOSCPart, mode: AUQuadTransformMode, offsets: AUCornerOffsets, size: AUSize, settingAPI: FxParameterSettingAPI_v5, time: CMTime) {
        let ids: (corner: AUQuadCorner, pixelX: QuadParam, pixelY: QuadParam)

        switch part {
        case .topLeft:
            ids = (.topLeft, .topLeftPixelX, .topLeftPixelY)
        case .topRight:
            ids = (.topRight, .topRightPixelX, .topRightPixelY)
        case .bottomRight:
            ids = (.bottomRight, .bottomRightPixelX, .bottomRightPixelY)
        case .bottomLeft:
            ids = (.bottomLeft, .bottomLeftPixelX, .bottomLeftPixelY)
        case .none, .quad:
            return
        }

        switch mode {
        case .outputCorners:
            let pixels = AnyUprightGeometry.cornerPixelOffset(
                forObjectPoint: point,
                corner: ids.corner,
                offsets: offsets,
                size: size
            )
            settingAPI.setFloatValue(pixels.x, toParameter: ids.pixelX.rawValue, at: time)
            settingAPI.setFloatValue(pixels.y, toParameter: ids.pixelY.rawValue, at: time)

        case .sourceQuad:
            let pixels = AnyUprightGeometry.sourceCornerPixelOffset(
                forObjectPoint: point,
                corner: ids.corner,
                offsets: offsets,
                size: size
            )
            settingAPI.setFloatValue(pixels.x, toParameter: ids.pixelX.rawValue, at: time)
            settingAPI.setFloatValue(pixels.y, toParameter: ids.pixelY.rawValue, at: time)
        }
    }

    private func translateQuad(from state: AnyUprightParameterState, pixelDelta: AUPoint, settingAPI: FxParameterSettingAPI_v5, time: CMTime) {
        let offsets = quadCornerOffsets(from: state)
        settingAPI.setFloatValue(offsets.topLeftPixels.x + pixelDelta.x, toParameter: QuadParam.topLeftPixelX.rawValue, at: time)
        settingAPI.setFloatValue(offsets.topLeftPixels.y + pixelDelta.y, toParameter: QuadParam.topLeftPixelY.rawValue, at: time)
        settingAPI.setFloatValue(offsets.topRightPixels.x + pixelDelta.x, toParameter: QuadParam.topRightPixelX.rawValue, at: time)
        settingAPI.setFloatValue(offsets.topRightPixels.y + pixelDelta.y, toParameter: QuadParam.topRightPixelY.rawValue, at: time)
        settingAPI.setFloatValue(offsets.bottomRightPixels.x + pixelDelta.x, toParameter: QuadParam.bottomRightPixelX.rawValue, at: time)
        settingAPI.setFloatValue(offsets.bottomRightPixels.y + pixelDelta.y, toParameter: QuadParam.bottomRightPixelY.rawValue, at: time)
        settingAPI.setFloatValue(offsets.bottomLeftPixels.x + pixelDelta.x, toParameter: QuadParam.bottomLeftPixelX.rawValue, at: time)
        settingAPI.setFloatValue(offsets.bottomLeftPixels.y + pixelDelta.y, toParameter: QuadParam.bottomLeftPixelY.rawValue, at: time)
    }

    private func isPoint(_ point: AUPoint, insideQuad quad: [AUPoint]) -> Bool {
        guard quad.count == 4 else {
            return false
        }

        var hasPositive = false
        var hasNegative = false
        for index in 0..<quad.count {
            let current = quad[index]
            let next = quad[(index + 1) % quad.count]
            let cross = (next.x - current.x) * (point.y - current.y) - (next.y - current.y) * (point.x - current.x)
            hasPositive = hasPositive || cross > 0.0
            hasNegative = hasNegative || cross < 0.0
            if hasPositive && hasNegative {
                return false
            }
        }
        return true
    }
}

private func uprightGuideLines(at time: CMTime, paramAPI: FxParameterRetrievalAPI_v6?) -> [UprightGuideLine] {
    guard let paramAPI else {
        return []
    }

    return uprightGuideSpecs.compactMap { spec in
        var enabled = ObjCBool(false)
        var orientationRaw = Int32(spec.defaultOrientation.rawValue)
        paramAPI.getBoolValue(&enabled, fromParameter: spec.enabled.rawValue, at: time)
        paramAPI.getIntValue(&orientationRaw, fromParameter: spec.orientation.rawValue, at: time)
        guard enabled.boolValue else {
            return nil
        }

        return UprightGuideLine(
            spec: spec,
            orientation: UprightGuideOrientation(rawValue: orientationRaw) ?? spec.defaultOrientation,
            start: uprightPointParam(paramAPI, spec.start, defaultValue: spec.defaultStart, time: time),
            end: uprightPointParam(paramAPI, spec.end, defaultValue: spec.defaultEnd, time: time)
        )
    }
}

private func uprightCandidateLines(at time: CMTime, paramAPI: FxParameterRetrievalAPI_v6?) -> [UprightCandidateLine] {
    guard let paramAPI else {
        return []
    }

    return AnyUprightUprightCandidates.specs.compactMap { spec in
        var visible = ObjCBool(false)
        var selected = ObjCBool(false)
        var orientationRaw = Int32(UprightGuideOrientation.vertical.rawValue)
        paramAPI.getBoolValue(&visible, fromParameter: spec.visible, at: time)
        paramAPI.getBoolValue(&selected, fromParameter: spec.selected, at: time)
        paramAPI.getIntValue(&orientationRaw, fromParameter: spec.orientation, at: time)

        guard visible.boolValue else {
            return nil
        }

        return UprightCandidateLine(
            spec: spec,
            selected: selected.boolValue,
            orientation: UprightGuideOrientation(rawValue: orientationRaw) ?? .vertical,
            start: uprightPointParam(paramAPI, spec.start, defaultValue: AUPoint(x: 0.0, y: 0.0), time: time),
            end: uprightPointParam(paramAPI, spec.end, defaultValue: AUPoint(x: 0.0, y: 0.0), time: time)
        )
    }
}

private func uprightPointParam(_ paramAPI: FxParameterRetrievalAPI_v6, _ param: UprightParam, defaultValue: AUPoint, time: CMTime) -> AUPoint {
    uprightPointParam(paramAPI, param.rawValue, defaultValue: defaultValue, time: time)
}

private func uprightPointParam(_ paramAPI: FxParameterRetrievalAPI_v6, _ parameterID: UInt32, defaultValue: AUPoint, time: CMTime) -> AUPoint {
    var x = defaultValue.x
    var y = defaultValue.y
    paramAPI.getXValue(&x, yValue: &y, fromParameter: parameterID, at: time)
    return AUPoint(x: x, y: y)
}

private func endpointParameter(for part: UprightOSCPart) -> UprightParam? {
    for spec in uprightGuideSpecs {
        if spec.startPart == part {
            return spec.start
        }
        if spec.endPart == part {
            return spec.end
        }
    }
    return nil
}

private func imageLine(from guide: UprightGuideLine, size: AUSize) -> AULineSegment {
    AULineSegment(
        start: AUPoint(x: guide.start.x * size.width, y: (1.0 - guide.start.y) * size.height),
        end: AUPoint(x: guide.end.x * size.width, y: (1.0 - guide.end.y) * size.height)
    )
}

@objc(AnyUprightUprightManualPlugIn)
class AnyUprightUprightManualPlugIn: AnyUprightWarpEffect, FxAnalyzer {
    private let analysisLock = NSLock()
    private let analysisContext = CIContext(options: nil)
    private var pendingAnalysisMode: UprightAnalysisMode?
    private var detectedVerticalPerspective: Double?
    private var detectedHorizontalPerspective: Double?
    private var detectedRotationRadians: Double?
    private var detectedCandidates: [UprightDetectedCandidate] = []
    private var detectedPerspectiveTime = CMTime.zero
    private var requestedAnalysisTime = CMTime.zero

    override func addEffectParameters(_ paramAPI: FxParameterCreationAPI_v5) throws {
        paramAPI.addPushButton(
            withName: "Auto Vertical",
            parameterID: UprightParam.analyzeVertical.rawValue,
            selector: #selector(analyzeVertical),
            parameterFlags: defaultFlags()
        )
        paramAPI.addPushButton(
            withName: "Auto Horizontal",
            parameterID: UprightParam.analyzeHorizontal.rawValue,
            selector: #selector(analyzeHorizontal),
            parameterFlags: defaultFlags()
        )
        paramAPI.addPushButton(
            withName: "Auto Full",
            parameterID: UprightParam.analyzeFull.rawValue,
            selector: #selector(analyzeFull),
            parameterFlags: defaultFlags()
        )
        paramAPI.addPushButton(
            withName: "Detect Vertical Candidates",
            parameterID: UprightParam.detectVerticalCandidates.rawValue,
            selector: #selector(detectVerticalCandidates),
            parameterFlags: defaultFlags()
        )
        paramAPI.addPushButton(
            withName: "Detect Horizontal Candidates",
            parameterID: UprightParam.detectHorizontalCandidates.rawValue,
            selector: #selector(detectHorizontalCandidates),
            parameterFlags: defaultFlags()
        )
        paramAPI.addPushButton(
            withName: "Detect Full Candidates",
            parameterID: UprightParam.detectFullCandidates.rawValue,
            selector: #selector(detectFullCandidates),
            parameterFlags: defaultFlags()
        )
        paramAPI.addPushButton(
            withName: "Apply Selected Vertical",
            parameterID: UprightParam.applySelectedVertical.rawValue,
            selector: #selector(applySelectedVertical),
            parameterFlags: defaultFlags()
        )
        paramAPI.addPushButton(
            withName: "Apply Selected Horizontal",
            parameterID: UprightParam.applySelectedHorizontal.rawValue,
            selector: #selector(applySelectedHorizontal),
            parameterFlags: defaultFlags()
        )
        paramAPI.addPushButton(
            withName: "Apply Selected Full",
            parameterID: UprightParam.applySelectedFull.rawValue,
            selector: #selector(applySelectedFull),
            parameterFlags: defaultFlags()
        )
        paramAPI.addPushButton(
            withName: "Apply Guided Vertical",
            parameterID: UprightParam.applyGuidedVertical.rawValue,
            selector: #selector(applyGuidedVertical),
            parameterFlags: defaultFlags()
        )
        paramAPI.addPushButton(
            withName: "Apply Guided Horizontal",
            parameterID: UprightParam.applyGuidedHorizontal.rawValue,
            selector: #selector(applyGuidedHorizontal),
            parameterFlags: defaultFlags()
        )
        paramAPI.addPushButton(
            withName: "Apply Guided Full",
            parameterID: UprightParam.applyGuidedFull.rawValue,
            selector: #selector(applyGuidedFull),
            parameterFlags: defaultFlags()
        )
        paramAPI.addPercentSlider(
            withName: "Vertical Perspective",
            parameterID: UprightParam.verticalPerspective.rawValue,
            defaultValue: 0.0,
            parameterMin: -1.0,
            parameterMax: 1.0,
            sliderMin: -0.5,
            sliderMax: 0.5,
            delta: 0.01,
            parameterFlags: defaultFlags()
        )
        paramAPI.addPercentSlider(
            withName: "Horizontal Perspective",
            parameterID: UprightParam.horizontalPerspective.rawValue,
            defaultValue: 0.0,
            parameterMin: -1.0,
            parameterMax: 1.0,
            sliderMin: -0.5,
            sliderMax: 0.5,
            delta: 0.01,
            parameterFlags: defaultFlags()
        )
        paramAPI.addAngleSlider(
            withName: "Rotation",
            parameterID: UprightParam.rotation.rawValue,
            defaultDegrees: 0.0,
            parameterMinDegrees: -45.0,
            parameterMaxDegrees: 45.0,
            parameterFlags: defaultFlags()
        )
        addGuideParameters(paramAPI)
        addCandidateParameters(paramAPI)
    }

    private func addGuideParameters(_ paramAPI: FxParameterCreationAPI_v5) {
        paramAPI.startParameterSubGroup("Guides", parameterID: 390, parameterFlags: collapsedFlags())
        for (index, spec) in uprightGuideSpecs.enumerated() {
            let title = "Guide \(index + 1)"
            paramAPI.startParameterSubGroup(title, parameterID: UInt32(391 + index), parameterFlags: collapsedFlags())
            paramAPI.addToggleButton(
                withName: "\(title) Enabled",
                parameterID: spec.enabled.rawValue,
                defaultValue: true,
                parameterFlags: defaultFlags()
            )
            paramAPI.addPopupMenu(
                withName: "\(title) Orientation",
                parameterID: spec.orientation.rawValue,
                defaultValue: UInt32(spec.defaultOrientation.rawValue),
                menuEntries: ["Vertical", "Horizontal"],
                parameterFlags: defaultFlags()
            )
            paramAPI.addPointParameter(
                withName: "\(title) Start",
                parameterID: spec.start.rawValue,
                defaultX: spec.defaultStart.x,
                defaultY: spec.defaultStart.y,
                parameterFlags: defaultFlags()
            )
            paramAPI.addPointParameter(
                withName: "\(title) End",
                parameterID: spec.end.rawValue,
                defaultX: spec.defaultEnd.x,
                defaultY: spec.defaultEnd.y,
                parameterFlags: defaultFlags()
            )
            paramAPI.endParameterSubGroup()
        }
        paramAPI.endParameterSubGroup()
    }

    private func addCandidateParameters(_ paramAPI: FxParameterCreationAPI_v5) {
        paramAPI.startParameterSubGroup("Detected Candidates", parameterID: 420, parameterFlags: collapsedFlags())
        for (index, spec) in AnyUprightUprightCandidates.specs.enumerated() {
            let title = "Candidate \(index + 1)"
            paramAPI.startParameterSubGroup(title, parameterID: spec.group, parameterFlags: collapsedFlags())
            paramAPI.addToggleButton(
                withName: "\(title) Visible",
                parameterID: spec.visible,
                defaultValue: false,
                parameterFlags: defaultFlags()
            )
            paramAPI.addToggleButton(
                withName: "\(title) Selected",
                parameterID: spec.selected,
                defaultValue: false,
                parameterFlags: defaultFlags()
            )
            paramAPI.addPopupMenu(
                withName: "\(title) Orientation",
                parameterID: spec.orientation,
                defaultValue: UInt32(UprightGuideOrientation.vertical.rawValue),
                menuEntries: ["Vertical", "Horizontal"],
                parameterFlags: defaultFlags()
            )
            paramAPI.addPointParameter(
                withName: "\(title) Start",
                parameterID: spec.start,
                defaultX: 0.0,
                defaultY: 0.0,
                parameterFlags: defaultFlags()
            )
            paramAPI.addPointParameter(
                withName: "\(title) End",
                parameterID: spec.end,
                defaultX: 0.0,
                defaultY: 0.0,
                parameterFlags: defaultFlags()
            )
            paramAPI.endParameterSubGroup()
        }
        paramAPI.endParameterSubGroup()
    }

    override func state(at renderTime: CMTime) -> AnyUprightParameterState {
        var result = AnyUprightParameterState(effectKind: AnyUprightEffectKind.upright.rawValue)
        guard let paramAPI = parameterRetrievalAPI() else {
            return result
        }

        var vertical = 0.0
        var horizontal = 0.0
        var rotation = 0.0

        paramAPI.getFloatValue(&vertical, fromParameter: UprightParam.verticalPerspective.rawValue, at: renderTime)
        paramAPI.getFloatValue(&horizontal, fromParameter: UprightParam.horizontalPerspective.rawValue, at: renderTime)
        paramAPI.getFloatValue(&rotation, fromParameter: UprightParam.rotation.rawValue, at: renderTime)

        result.verticalPerspective = Float(vertical)
        result.horizontalPerspective = Float(horizontal)
        result.rotationRadians = Float(rotation)
        return result
    }

    @objc private func analyzeVertical() {
        startAnalysis(.vertical)
    }

    @objc private func analyzeHorizontal() {
        startAnalysis(.horizontal)
    }

    @objc private func analyzeFull() {
        startAnalysis(.full)
    }

    @objc private func detectVerticalCandidates() {
        startAnalysis(.detectVerticalCandidates)
    }

    @objc private func detectHorizontalCandidates() {
        startAnalysis(.detectHorizontalCandidates)
    }

    @objc private func detectFullCandidates() {
        startAnalysis(.detectFullCandidates)
    }

    @objc private func applySelectedVertical() {
        applySelected(.vertical)
    }

    @objc private func applySelectedHorizontal() {
        applySelected(.horizontal)
    }

    @objc private func applySelectedFull() {
        applySelected(.full)
    }

    @objc private func applyGuidedVertical() {
        applyGuided(.vertical)
    }

    @objc private func applyGuidedHorizontal() {
        applyGuided(.horizontal)
    }

    @objc private func applyGuidedFull() {
        applyGuided(.full)
    }

    private func startAnalysis(_ mode: UprightAnalysisMode) {
        analysisLock.lock()
        pendingAnalysisMode = mode
        requestedAnalysisTime = currentParameterTime()
        analysisLock.unlock()

        guard let analysisAPI = _apiManager.api(for: FxAnalysisAPI.self) as? FxAnalysisAPI else {
            return
        }

        try? analysisAPI.startForwardAnalysis(kFxAnalysisLocation_CPU)
    }

    func desiredAnalysisTimeRange(_ desiredRange: UnsafeMutablePointer<CMTimeRange>, forInputWith inputTimeRange: CMTimeRange) throws {
        analysisLock.lock()
        let requestedTime = requestedAnalysisTime
        analysisLock.unlock()
        desiredRange.pointee = singleFrameAnalysisRange(near: requestedTime, within: inputTimeRange)
    }

    func setupAnalysis(for analysisRange: CMTimeRange, frameDuration: CMTime) throws {
        analysisLock.lock()
        detectedVerticalPerspective = nil
        detectedHorizontalPerspective = nil
        detectedRotationRadians = nil
        detectedCandidates = []
        detectedPerspectiveTime = analysisRange.start
        analysisLock.unlock()
    }

    func analyzeFrame(_ frame: FxImageTile, at frameTime: CMTime) throws {
        analysisLock.lock()
        let mode = pendingAnalysisMode
        analysisLock.unlock()

        guard let mode,
              let grayscaleImage = AnyUprightAnalysisImage.grayscaleImage(from: frame, maxDimension: 360, context: analysisContext) else {
            return
        }

        let size = AUSize(width: Double(grayscaleImage.width), height: Double(grayscaleImage.height))
        var verticalPerspective: Double?
        var horizontalPerspective: Double?
        var rotationRadians: Double?
        var verticalReferenceLines: [AULineSegment] = []
        var horizontalReferenceLines: [AULineSegment] = []
        var candidates: [UprightDetectedCandidate] = []

        if mode.includesVertical {
            let lines = AnyUprightLineDetection.detectLineSegments(
                in: grayscaleImage,
                options: AULineDetectionOptions(
                    orientation: .vertical,
                    edgeThreshold: 40.0,
                    voteThreshold: max(20, grayscaleImage.height / 5),
                    maxLines: candidateLimit(for: mode)
                )
            )
            let lineCandidates = AnyUprightGeometry.lineCandidates(
                from: lines,
                orientation: .vertical,
                minimumLength: Double(grayscaleImage.height) * 0.25
            )

            if mode.isCandidateDetection {
                candidates.append(contentsOf: AnyUprightUprightCandidates.detectedCandidates(
                    from: Array(lineCandidates.prefix(candidateLimit(for: mode))),
                    orientation: .vertical,
                    size: size
                ))
            } else {
                let references = Array(lineCandidates.prefix(2).map(\.line))
                verticalReferenceLines = references
                verticalPerspective = AnyUprightGeometry.estimateVerticalPerspective(from: references, size: size)
            }
        }

        if mode.includesHorizontal {
            let lines = AnyUprightLineDetection.detectLineSegments(
                in: grayscaleImage,
                options: AULineDetectionOptions(
                    orientation: .horizontal,
                    edgeThreshold: 40.0,
                    voteThreshold: max(20, grayscaleImage.width / 5),
                    maxLines: candidateLimit(for: mode)
                )
            )
            let lineCandidates = AnyUprightGeometry.lineCandidates(
                from: lines,
                orientation: .horizontal,
                minimumLength: Double(grayscaleImage.width) * 0.25
            )

            if mode.isCandidateDetection {
                candidates.append(contentsOf: AnyUprightUprightCandidates.detectedCandidates(
                    from: Array(lineCandidates.prefix(candidateLimit(for: mode))),
                    orientation: .horizontal,
                    size: size
                ))
            } else {
                let references = Array(lineCandidates.prefix(2).map(\.line))
                horizontalReferenceLines = references
                horizontalPerspective = AnyUprightGeometry.estimateHorizontalPerspective(from: references, size: size)
            }
        }

        if mode == .full {
            let rotationLines = horizontalReferenceLines.isEmpty ? verticalReferenceLines : horizontalReferenceLines
            let rotationOrientation: AUReferenceOrientation = horizontalReferenceLines.isEmpty ? .vertical : .horizontal
            if let rotation = AnyUprightGeometry.rotationCorrectionRadians(from: rotationLines, orientation: rotationOrientation) {
                rotationRadians = rotation
            }
        }

        analysisLock.lock()
        detectedVerticalPerspective = verticalPerspective
        detectedHorizontalPerspective = horizontalPerspective
        detectedRotationRadians = rotationRadians
        detectedCandidates = Array(candidates.prefix(AnyUprightUprightCandidates.slotCount))
        detectedPerspectiveTime = frameTime
        analysisLock.unlock()
    }

    func cleanupAnalysis() throws {
        analysisLock.lock()
        let mode = pendingAnalysisMode
        let vertical = detectedVerticalPerspective
        let horizontal = detectedHorizontalPerspective
        let rotation = detectedRotationRadians
        let candidates = detectedCandidates
        let time = parameterWriteTime(preferred: requestedAnalysisTime, fallback: detectedPerspectiveTime)
        pendingAnalysisMode = nil
        analysisLock.unlock()

        guard let settingAPI = _apiManager.api(for: FxParameterSettingAPI_v5.self) as? FxParameterSettingAPI_v5 else {
            return
        }

        if mode?.isCandidateDetection == true {
            writeCandidateSlots(candidates, settingAPI: settingAPI, time: time)
            return
        }

        if let vertical {
            _ = settingAPI.setFloatValue(vertical, toParameter: UprightParam.verticalPerspective.rawValue, at: time)
        }
        if let horizontal {
            _ = settingAPI.setFloatValue(horizontal, toParameter: UprightParam.horizontalPerspective.rawValue, at: time)
        }
        if let rotation {
            _ = settingAPI.setFloatValue(rotation, toParameter: UprightParam.rotation.rawValue, at: time)
        }
    }

    private func applyGuided(_ mode: UprightAnalysisMode) {
        let time = currentParameterTime()
        let guides = uprightGuideLines(at: time, paramAPI: parameterRetrievalAPI())
        let verticalLines = guides
            .filter { $0.orientation == .vertical }
            .map { imageLine(from: $0, size: AUSize(width: 1.0, height: 1.0)) }
        let horizontalLines = guides
            .filter { $0.orientation == .horizontal }
            .map { imageLine(from: $0, size: AUSize(width: 1.0, height: 1.0)) }

        applyReferences(verticalLines: verticalLines, horizontalLines: horizontalLines, mode: mode, time: time)
    }

    private func applySelected(_ mode: UprightAnalysisMode) {
        let time = currentParameterTime()
        let candidates = uprightCandidateLines(at: time, paramAPI: parameterRetrievalAPI())
        let verticalLines = AnyUprightUprightCandidates.selectedImageLines(from: candidates, orientation: .vertical)
        let horizontalLines = AnyUprightUprightCandidates.selectedImageLines(from: candidates, orientation: .horizontal)

        applyReferences(verticalLines: verticalLines, horizontalLines: horizontalLines, mode: mode, time: time)
    }

    private func applyReferences(verticalLines: [AULineSegment], horizontalLines: [AULineSegment], mode: UprightAnalysisMode, time: CMTime) {
        guard let settingAPI = _apiManager.api(for: FxParameterSettingAPI_v5.self) as? FxParameterSettingAPI_v5 else {
            return
        }

        if mode.includesVertical,
           let vertical = AnyUprightGeometry.estimateVerticalPerspective(from: verticalLines, size: AUSize(width: 1.0, height: 1.0)) {
            settingAPI.setFloatValue(vertical, toParameter: UprightParam.verticalPerspective.rawValue, at: time)
        }

        if mode.includesHorizontal,
           let horizontal = AnyUprightGeometry.estimateHorizontalPerspective(from: horizontalLines, size: AUSize(width: 1.0, height: 1.0)) {
            settingAPI.setFloatValue(horizontal, toParameter: UprightParam.horizontalPerspective.rawValue, at: time)
        }

        guard mode == .full else {
            return
        }

        let rotationLines = horizontalLines.isEmpty ? verticalLines : horizontalLines
        let rotationOrientation: AUReferenceOrientation = horizontalLines.isEmpty ? .vertical : .horizontal
        if let rotation = AnyUprightGeometry.rotationCorrectionRadians(from: rotationLines, orientation: rotationOrientation) {
            settingAPI.setFloatValue(rotation, toParameter: UprightParam.rotation.rawValue, at: time)
        }
    }

    private func candidateLimit(for mode: UprightAnalysisMode) -> Int {
        AnyUprightUprightCandidates.slotLimit(isFullMode: mode == .detectFullCandidates)
    }

    private func writeCandidateSlots(_ candidates: [UprightDetectedCandidate], settingAPI: FxParameterSettingAPI_v5, time: CMTime) {
        var selectedCountByOrientation: [UprightGuideOrientation: Int] = [
            .vertical: 0,
            .horizontal: 0
        ]

        for (index, spec) in AnyUprightUprightCandidates.specs.enumerated() {
            guard index < candidates.count else {
                settingAPI.setBoolValue(false, toParameter: spec.visible, at: time)
                settingAPI.setBoolValue(false, toParameter: spec.selected, at: time)
                continue
            }

            let candidate = candidates[index]
            let selectedCount = selectedCountByOrientation[candidate.orientation, default: 0]
            let shouldPreselect = selectedCount < 2
            selectedCountByOrientation[candidate.orientation] = selectedCount + 1

            settingAPI.setBoolValue(true, toParameter: spec.visible, at: time)
            settingAPI.setBoolValue(shouldPreselect, toParameter: spec.selected, at: time)
            settingAPI.setIntValue(Int32(candidate.orientation.rawValue), toParameter: spec.orientation, at: time)
            settingAPI.setXValue(candidate.start.x, yValue: candidate.start.y, toParameter: spec.start, at: time)
            settingAPI.setXValue(candidate.end.x, yValue: candidate.end.y, toParameter: spec.end, at: time)
        }
    }

}

@objc(AnyUprightUprightManualOSCPlugIn)
class AnyUprightUprightManualOSCPlugIn: AnyUprightOSCPlugIn, FxOnScreenControl_v4 {
    private let overlayRenderer = AnyUprightOSCOverlayRenderer()

    @objc(drawingCoordinates)
    func drawingCoordinates() -> FxDrawingCoordinates {
        return FxDrawingCoordinates(kFxDrawingCoordinates_OBJECT)
    }

    @objc(drawOSCWithWidth:height:activePart:destinationImage:atTime:)
    func drawOSC(withWidth width: Int, height: Int, activePart: Int, destinationImage: FxImageTile, at time: CMTime) {
        let paramAPI = parameterRetrievalAPI()
        let guides = uprightGuideLines(at: time, paramAPI: paramAPI)
        let candidates = uprightCandidateLines(at: time, paramAPI: paramAPI)
        var segments = candidates.map { candidate in
            AUOSCStyledSegment(
                start: candidate.start,
                end: candidate.end,
                style: candidateStyle(candidate, activePart: activePart)
            )
        }
        segments.append(contentsOf: guides.map {
            AUOSCStyledSegment(start: $0.start, end: $0.end, style: guideStyle())
        })
        let handles = guides.flatMap {
            [
                AUOSCHandle(point: $0.start, part: $0.spec.startPart.rawValue),
                AUOSCHandle(point: $0.end, part: $0.spec.endPart.rawValue)
            ]
        }
        overlayRenderer.renderStyledSegments(
            segments,
            handles: handles,
            activePart: activePart,
            destinationImage: destinationImage,
            destinationSize: AUSize(width: max(1.0, Double(width)), height: max(1.0, Double(height)))
        )
    }

    @objc(hitTestOSCAtMousePositionX:mousePositionY:activePart:atTime:)
    func hitTestOSC(atMousePositionX mousePositionX: Double, mousePositionY: Double, activePart: UnsafeMutablePointer<Int>?, at time: CMTime) {
        let paramAPI = parameterRetrievalAPI()
        let size = objectPixelSizeForOSC()
        let mouse = AUPoint(x: mousePositionX, y: mousePositionY)
        activePart?.pointee = UprightOSCPart.none.rawValue

        for guide in uprightGuideLines(at: time, paramAPI: paramAPI) {
            let handles = [
                AUOSCHandle(point: guide.start, part: guide.spec.startPart.rawValue),
                AUOSCHandle(point: guide.end, part: guide.spec.endPart.rawValue)
            ]
            for handle in handles {
                let dx = (mouse.x - handle.point.x) * size.width
                let dy = (mouse.y - handle.point.y) * size.height
                if hypot(dx, dy) <= 12.0 {
                    activePart?.pointee = handle.part
                    return
                }
            }
        }

        for candidate in uprightCandidateLines(at: time, paramAPI: paramAPI) {
            if AnyUprightUprightCandidates.distanceFromPointToSegment(mouse, start: candidate.start, end: candidate.end, size: size) <= 8.0 {
                activePart?.pointee = candidate.spec.linePart
                return
            }
        }
    }

    @objc(mouseDownAtPositionX:positionY:activePart:modifiers:forceUpdate:atTime:)
    func mouseDown(atPositionX mousePositionX: Double, positionY mousePositionY: Double, activePart: Int, modifiers: FxModifierKeys, forceUpdate: UnsafeMutablePointer<ObjCBool>?, at time: CMTime) {
        if let candidateIndex = AnyUprightUprightCandidates.candidateIndex(for: activePart),
           let settingAPI = parameterSettingAPI() {
            let candidates = uprightCandidateLines(at: time, paramAPI: parameterRetrievalAPI())
            if let candidate = candidates.first(where: { $0.spec.linePart == activePart }) {
                let selected = AnyUprightUprightCandidates.selectionValueAfterToggling(candidate, within: candidates)
                settingAPI.setBoolValue(selected, toParameter: AnyUprightUprightCandidates.specs[candidateIndex].selected, at: time)
            }
        }
        forceUpdate?.pointee = true
    }

    @objc(mouseDraggedAtPositionX:positionY:activePart:modifiers:forceUpdate:atTime:)
    func mouseDragged(atPositionX mousePositionX: Double, positionY mousePositionY: Double, activePart: Int, modifiers: FxModifierKeys, forceUpdate: UnsafeMutablePointer<ObjCBool>?, at time: CMTime) {
        guard AnyUprightUprightCandidates.candidateIndex(for: activePart) == nil else {
            forceUpdate?.pointee = true
            return
        }

        guard let part = UprightOSCPart(rawValue: activePart),
              let endpoint = endpointParameter(for: part),
              let settingAPI = parameterSettingAPI() else {
            forceUpdate?.pointee = false
            return
        }

        settingAPI.setXValue(mousePositionX, yValue: mousePositionY, toParameter: endpoint.rawValue, at: time)
        forceUpdate?.pointee = true
    }

    @objc(mouseUpAtPositionX:positionY:activePart:modifiers:forceUpdate:atTime:)
    func mouseUp(atPositionX mousePositionX: Double, positionY mousePositionY: Double, activePart: Int, modifiers: FxModifierKeys, forceUpdate: UnsafeMutablePointer<ObjCBool>?, at time: CMTime) {
        forceUpdate?.pointee = true
    }

    @objc(keyDownAtPositionX:positionY:keyPressed:modifiers:forceUpdate:didHandle:atTime:)
    func keyDown(atPositionX mousePositionX: Double, positionY mousePositionY: Double, keyPressed: UInt16, modifiers: FxModifierKeys, forceUpdate: UnsafeMutablePointer<ObjCBool>?, didHandle: UnsafeMutablePointer<ObjCBool>?, at time: CMTime) {
        forceUpdate?.pointee = false
        didHandle?.pointee = false
    }

    @objc(keyUpAtPositionX:positionY:keyPressed:modifiers:forceUpdate:didHandle:atTime:)
    func keyUp(atPositionX mousePositionX: Double, positionY mousePositionY: Double, keyPressed: UInt16, modifiers: FxModifierKeys, forceUpdate: UnsafeMutablePointer<ObjCBool>?, didHandle: UnsafeMutablePointer<ObjCBool>?, at time: CMTime) {
        forceUpdate?.pointee = false
        didHandle?.pointee = false
    }

    private func guideStyle() -> AUOSCOverlayStyle {
        AUOSCOverlayStyle()
    }

    private func candidateStyle(_ candidate: UprightCandidateLine, activePart: Int) -> AUOSCOverlayStyle {
        var style = AUOSCOverlayStyle()
        style.lineThickness = candidate.selected ? 3.0 : 2.0
        style.lineColor = candidate.selected
            ? SIMD4<Float>(0.15, 0.9, 0.45, 0.95)
            : SIMD4<Float>(0.15, 0.65, 1.0, 0.8)
        if candidate.spec.linePart == activePart {
            style.lineColor = style.activeHandleColor
            style.lineThickness = 4.0
        }
        return style
    }
}
