//
//  AnyUprightManualEffects.swift
//  AnyUpright
//

import Foundation
import CoreImage
import Vision

private enum HorizonParam: UInt32 {
    case rotation = 100
    case fillFrame = 101
    case analyze = 102
}

private enum QuadParam: UInt32 {
    case mode = 198
    case applySourceQuad = 199
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

private enum QuadOSCPart: Int {
    case none = 0
    case topLeft = 1
    case topRight = 2
    case bottomRight = 3
    case bottomLeft = 4
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
}

private enum UprightGuideOrientation: Int32 {
    case vertical = 0
    case horizontal = 1
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

@objc(AnyUprightHorizonManualPlugIn)
class AnyUprightHorizonManualPlugIn: AnyUprightWarpEffect, FxAnalyzer {
    private let analysisLock = NSLock()
    private var detectedRotationDegrees: Double?
    private var detectedRotationTime = CMTime.zero

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
        let paramAPI = parameterRetrievalAPI()
        var result = AnyUprightParameterState(effectKind: AnyUprightEffectKind.horizon.rawValue)
        var rotation = 0.0
        var fillFrame = ObjCBool(false)

        paramAPI.getFloatValue(&rotation, fromParameter: HorizonParam.rotation.rawValue, at: renderTime)
        paramAPI.getBoolValue(&fillFrame, fromParameter: HorizonParam.fillFrame.rawValue, at: renderTime)

        result.rotationRadians = Float(rotation)
        result.fillFrame = fillFrame.boolValue ? 1 : 0
        return result
    }

    @objc private func analyzeHorizon() {
        guard let analysisAPI = _apiManager.api(for: FxAnalysisAPI.self) as? FxAnalysisAPI else {
            return
        }

        try? analysisAPI.startForwardAnalysis(kFxAnalysisLocation_CPU)
    }

    func desiredAnalysisTimeRange(_ desiredRange: UnsafeMutablePointer<CMTimeRange>, forInputWith inputTimeRange: CMTimeRange) throws {
        let singleFrameHint = CMTime(value: 1, timescale: 600)
        let duration = CMTimeCompare(inputTimeRange.duration, singleFrameHint) < 0 ? inputTimeRange.duration : singleFrameHint
        desiredRange.pointee = CMTimeRange(start: inputTimeRange.start, duration: duration)
    }

    func setupAnalysis(for analysisRange: CMTimeRange, frameDuration: CMTime) throws {
        analysisLock.lock()
        detectedRotationDegrees = nil
        detectedRotationTime = analysisRange.start
        analysisLock.unlock()
    }

    func analyzeFrame(_ frame: FxImageTile, at frameTime: CMTime) throws {
        guard let ioSurface = frame.ioSurface else {
            return
        }

        let colorSpace = frame.colorSpace.map { $0 as Any }
        let image = CIImage(ioSurface: ioSurface, options: colorSpace.map { [.colorSpace: $0] } ?? [:])
        let request = VNDetectHorizonRequest()
        let handler = VNImageRequestHandler(ciImage: image, options: [:])
        try handler.perform([request])

        guard let observation = request.results?.first as? VNHorizonObservation else {
            return
        }

        let bounds = frame.imagePixelBounds
        let width = max(1, Int(bounds.right - bounds.left))
        let height = max(1, Int(bounds.top - bounds.bottom))
        let transform = observation.transform(forImageWidth: width, height: height)
        let rotationRadians = atan2(Double(transform.b), Double(transform.a))

        analysisLock.lock()
        detectedRotationDegrees = rotationRadians * 180.0 / .pi
        detectedRotationTime = frameTime
        analysisLock.unlock()
    }

    func cleanupAnalysis() throws {
        analysisLock.lock()
        let rotationDegrees = detectedRotationDegrees
        let rotationTime = detectedRotationTime
        analysisLock.unlock()

        guard let rotationDegrees,
              let settingAPI = _apiManager.api(for: FxParameterSettingAPI_v5.self) as? FxParameterSettingAPI_v5 else {
            return
        }

        settingAPI.setFloatValue(rotationDegrees, toParameter: HorizonParam.rotation.rawValue, at: rotationTime)
    }
}

@objc(AnyUprightQuadManualPlugIn)
class AnyUprightQuadManualPlugIn: AnyUprightWarpEffect, FxOnScreenControl_v4 {
    private let overlayRenderer = AnyUprightOSCOverlayRenderer()

    override func addEffectParameters(_ paramAPI: FxParameterCreationAPI_v5) throws {
        paramAPI.addPopupMenu(
            withName: "Mode",
            parameterID: QuadParam.mode.rawValue,
            defaultValue: UInt32(AUQuadTransformMode.outputCorners.rawValue),
            menuEntries: ["Output Corners", "Source Quad"],
            parameterFlags: defaultFlags()
        )
        paramAPI.addToggleButton(
            withName: "Apply Source Quad",
            parameterID: QuadParam.applySourceQuad.rawValue,
            defaultValue: false,
            parameterFlags: defaultFlags()
        )
        addCornerParameters(paramAPI, title: "Top Left", groupID: 220, percentX: .topLeftPercentX, percentY: .topLeftPercentY, pixelX: .topLeftPixelX, pixelY: .topLeftPixelY)
        addCornerParameters(paramAPI, title: "Top Right", groupID: 221, percentX: .topRightPercentX, percentY: .topRightPercentY, pixelX: .topRightPixelX, pixelY: .topRightPixelY)
        addCornerParameters(paramAPI, title: "Bottom Right", groupID: 222, percentX: .bottomRightPercentX, percentY: .bottomRightPercentY, pixelX: .bottomRightPixelX, pixelY: .bottomRightPixelY)
        addCornerParameters(paramAPI, title: "Bottom Left", groupID: 223, percentX: .bottomLeftPercentX, percentY: .bottomLeftPercentY, pixelX: .bottomLeftPixelX, pixelY: .bottomLeftPixelY)
    }

    override func state(at renderTime: CMTime) -> AnyUprightParameterState {
        let paramAPI = parameterRetrievalAPI()
        var result = AnyUprightParameterState(effectKind: AnyUprightEffectKind.quad.rawValue)
        var mode = Int32(AUQuadTransformMode.outputCorners.rawValue)
        var applySourceQuad = ObjCBool(false)

        paramAPI.getIntValue(&mode, fromParameter: QuadParam.mode.rawValue, at: renderTime)
        paramAPI.getBoolValue(&applySourceQuad, fromParameter: QuadParam.applySourceQuad.rawValue, at: renderTime)
        result.quadMode = mode
        result.applySourceQuad = applySourceQuad.boolValue ? 1 : 0

        result.topLeftPercentX = floatParam(paramAPI, .topLeftPercentX, renderTime)
        result.topLeftPercentY = floatParam(paramAPI, .topLeftPercentY, renderTime)
        result.topLeftPixelX = floatParam(paramAPI, .topLeftPixelX, renderTime)
        result.topLeftPixelY = floatParam(paramAPI, .topLeftPixelY, renderTime)

        result.topRightPercentX = floatParam(paramAPI, .topRightPercentX, renderTime)
        result.topRightPercentY = floatParam(paramAPI, .topRightPercentY, renderTime)
        result.topRightPixelX = floatParam(paramAPI, .topRightPixelX, renderTime)
        result.topRightPixelY = floatParam(paramAPI, .topRightPixelY, renderTime)

        result.bottomRightPercentX = floatParam(paramAPI, .bottomRightPercentX, renderTime)
        result.bottomRightPercentY = floatParam(paramAPI, .bottomRightPercentY, renderTime)
        result.bottomRightPixelX = floatParam(paramAPI, .bottomRightPixelX, renderTime)
        result.bottomRightPixelY = floatParam(paramAPI, .bottomRightPixelY, renderTime)

        result.bottomLeftPercentX = floatParam(paramAPI, .bottomLeftPercentX, renderTime)
        result.bottomLeftPercentY = floatParam(paramAPI, .bottomLeftPercentY, renderTime)
        result.bottomLeftPixelX = floatParam(paramAPI, .bottomLeftPixelX, renderTime)
        result.bottomLeftPixelY = floatParam(paramAPI, .bottomLeftPixelY, renderTime)

        return result
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

    private func floatParam(_ paramAPI: FxParameterRetrievalAPI_v6, _ param: QuadParam, _ time: CMTime) -> Float {
        var value = 0.0
        paramAPI.getFloatValue(&value, fromParameter: param.rawValue, at: time)
        return Float(value)
    }

    func drawingCoordinates() -> FxDrawingCoordinates {
        FxDrawingCoordinates(kFxDrawingCoordinates_OBJECT)
    }

    func drawOSC(withWidth width: Int, height: Int, activePart: Int, destinationImage: FxImageTile, at time: CMTime) {
        let size = AUSize(width: max(1.0, Double(width)), height: max(1.0, Double(height)))
        let points = quadObjectPoints(at: time, size: size)
        let handles = [
            AUOSCHandle(point: points.topLeft, part: QuadOSCPart.topLeft.rawValue),
            AUOSCHandle(point: points.topRight, part: QuadOSCPart.topRight.rawValue),
            AUOSCHandle(point: points.bottomRight, part: QuadOSCPart.bottomRight.rawValue),
            AUOSCHandle(point: points.bottomLeft, part: QuadOSCPart.bottomLeft.rawValue)
        ]
        overlayRenderer.renderQuad(
            points: [points.topLeft, points.topRight, points.bottomRight, points.bottomLeft],
            handles: handles,
            activePart: activePart,
            destinationImage: destinationImage
        )
    }

    func hitTestOSC(atMousePositionX mousePositionX: Double, mousePositionY: Double, activePart: UnsafeMutablePointer<Int>?, at time: CMTime) {
        let size = objectPixelSizeForOSC()
        let points = quadObjectPoints(at: time, size: size)
        let handles = [
            AUOSCHandle(point: points.topLeft, part: QuadOSCPart.topLeft.rawValue),
            AUOSCHandle(point: points.topRight, part: QuadOSCPart.topRight.rawValue),
            AUOSCHandle(point: points.bottomRight, part: QuadOSCPart.bottomRight.rawValue),
            AUOSCHandle(point: points.bottomLeft, part: QuadOSCPart.bottomLeft.rawValue)
        ]
        let mouse = AUPoint(x: mousePositionX, y: mousePositionY)
        let hitRadius = 12.0

        activePart?.pointee = QuadOSCPart.none.rawValue
        for handle in handles {
            let dx = (mouse.x - handle.point.x) * size.width
            let dy = (mouse.y - handle.point.y) * size.height
            if hypot(dx, dy) <= hitRadius {
                activePart?.pointee = handle.part
                return
            }
        }
    }

    func mouseDown(atPositionX mousePositionX: Double, positionY mousePositionY: Double, activePart: Int, modifiers: FxModifierKeys, forceUpdate: UnsafeMutablePointer<ObjCBool>?, at time: CMTime) {
        forceUpdate?.pointee = true
    }

    func mouseDragged(atPositionX mousePositionX: Double, positionY mousePositionY: Double, activePart: Int, modifiers: FxModifierKeys, forceUpdate: UnsafeMutablePointer<ObjCBool>?, at time: CMTime) {
        guard let part = QuadOSCPart(rawValue: activePart),
              part != .none,
              let settingAPI = _apiManager.api(for: FxParameterSettingAPI_v5.self) as? FxParameterSettingAPI_v5 else {
            forceUpdate?.pointee = false
            return
        }

        let size = objectPixelSizeForOSC()
        let point = AUPoint(x: mousePositionX, y: mousePositionY)
        setCorner(point, part: part, size: size, settingAPI: settingAPI, time: time)
        forceUpdate?.pointee = true
    }

    func mouseUp(atPositionX mousePositionX: Double, positionY mousePositionY: Double, activePart: Int, modifiers: FxModifierKeys, forceUpdate: UnsafeMutablePointer<ObjCBool>?, at time: CMTime) {
        forceUpdate?.pointee = true
    }

    func keyDown(atPositionX mousePositionX: Double, positionY mousePositionY: Double, keyPressed: UInt16, modifiers: FxModifierKeys, forceUpdate: UnsafeMutablePointer<ObjCBool>?, didHandle: UnsafeMutablePointer<ObjCBool>?, at time: CMTime) {
        forceUpdate?.pointee = false
        didHandle?.pointee = false
    }

    func keyUp(atPositionX mousePositionX: Double, positionY mousePositionY: Double, keyPressed: UInt16, modifiers: FxModifierKeys, forceUpdate: UnsafeMutablePointer<ObjCBool>?, didHandle: UnsafeMutablePointer<ObjCBool>?, at time: CMTime) {
        forceUpdate?.pointee = false
        didHandle?.pointee = false
    }

    private func quadObjectPoints(at time: CMTime, size: AUSize) -> AUQuad {
        let paramAPI = parameterRetrievalAPI()
        return AUQuad(
            topLeft: objectPoint(
                base: AUPoint(x: 0.0, y: 1.0),
                percentX: .topLeftPercentX,
                percentY: .topLeftPercentY,
                pixelX: .topLeftPixelX,
                pixelY: .topLeftPixelY,
                paramAPI: paramAPI,
                time: time,
                size: size
            ),
            topRight: objectPoint(
                base: AUPoint(x: 1.0, y: 1.0),
                percentX: .topRightPercentX,
                percentY: .topRightPercentY,
                pixelX: .topRightPixelX,
                pixelY: .topRightPixelY,
                paramAPI: paramAPI,
                time: time,
                size: size
            ),
            bottomRight: objectPoint(
                base: AUPoint(x: 1.0, y: 0.0),
                percentX: .bottomRightPercentX,
                percentY: .bottomRightPercentY,
                pixelX: .bottomRightPixelX,
                pixelY: .bottomRightPixelY,
                paramAPI: paramAPI,
                time: time,
                size: size
            ),
            bottomLeft: objectPoint(
                base: AUPoint(x: 0.0, y: 0.0),
                percentX: .bottomLeftPercentX,
                percentY: .bottomLeftPercentY,
                pixelX: .bottomLeftPixelX,
                pixelY: .bottomLeftPixelY,
                paramAPI: paramAPI,
                time: time,
                size: size
            )
        )
    }

    private func objectPoint(base: AUPoint, percentX: QuadParam, percentY: QuadParam, pixelX: QuadParam, pixelY: QuadParam, paramAPI: FxParameterRetrievalAPI_v6, time: CMTime, size: AUSize) -> AUPoint {
        AUPoint(
            x: base.x + Double(floatParam(paramAPI, percentX, time)) + Double(floatParam(paramAPI, pixelX, time)) / size.width,
            y: base.y + Double(floatParam(paramAPI, percentY, time)) + Double(floatParam(paramAPI, pixelY, time)) / size.height
        )
    }

    private func setCorner(_ point: AUPoint, part: QuadOSCPart, size: AUSize, settingAPI: FxParameterSettingAPI_v5, time: CMTime) {
        let paramAPI = parameterRetrievalAPI()
        let ids: (base: AUPoint, percentX: QuadParam, percentY: QuadParam, pixelX: QuadParam, pixelY: QuadParam)

        switch part {
        case .topLeft:
            ids = (AUPoint(x: 0.0, y: 1.0), .topLeftPercentX, .topLeftPercentY, .topLeftPixelX, .topLeftPixelY)
        case .topRight:
            ids = (AUPoint(x: 1.0, y: 1.0), .topRightPercentX, .topRightPercentY, .topRightPixelX, .topRightPixelY)
        case .bottomRight:
            ids = (AUPoint(x: 1.0, y: 0.0), .bottomRightPercentX, .bottomRightPercentY, .bottomRightPixelX, .bottomRightPixelY)
        case .bottomLeft:
            ids = (AUPoint(x: 0.0, y: 0.0), .bottomLeftPercentX, .bottomLeftPercentY, .bottomLeftPixelX, .bottomLeftPixelY)
        case .none:
            return
        }

        let percentX = Double(floatParam(paramAPI, ids.percentX, time))
        let percentY = Double(floatParam(paramAPI, ids.percentY, time))
        let pixelX = (point.x - ids.base.x - percentX) * size.width
        let pixelY = (point.y - ids.base.y - percentY) * size.height

        settingAPI.setFloatValue(pixelX, toParameter: ids.pixelX.rawValue, at: time)
        settingAPI.setFloatValue(pixelY, toParameter: ids.pixelY.rawValue, at: time)
    }

}

@objc(AnyUprightUprightManualPlugIn)
class AnyUprightUprightManualPlugIn: AnyUprightWarpEffect, FxAnalyzer, FxOnScreenControl_v4 {
    private static let guideSpecs = [
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

    private let overlayRenderer = AnyUprightOSCOverlayRenderer()
    private let analysisLock = NSLock()
    private let analysisContext = CIContext(options: nil)
    private var pendingAnalysisMode: UprightAnalysisMode?
    private var detectedVerticalPerspective: Double?
    private var detectedHorizontalPerspective: Double?
    private var detectedPerspectiveTime = CMTime.zero

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
    }

    private func addGuideParameters(_ paramAPI: FxParameterCreationAPI_v5) {
        paramAPI.startParameterSubGroup("Guides", parameterID: 390, parameterFlags: collapsedFlags())
        for (index, spec) in Self.guideSpecs.enumerated() {
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

    override func state(at renderTime: CMTime) -> AnyUprightParameterState {
        let paramAPI = parameterRetrievalAPI()
        var result = AnyUprightParameterState(effectKind: AnyUprightEffectKind.upright.rawValue)
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
        analysisLock.unlock()

        guard let analysisAPI = _apiManager.api(for: FxAnalysisAPI.self) as? FxAnalysisAPI else {
            return
        }

        try? analysisAPI.startForwardAnalysis(kFxAnalysisLocation_CPU)
    }

    func desiredAnalysisTimeRange(_ desiredRange: UnsafeMutablePointer<CMTimeRange>, forInputWith inputTimeRange: CMTimeRange) throws {
        let singleFrameHint = CMTime(value: 1, timescale: 600)
        let duration = CMTimeCompare(inputTimeRange.duration, singleFrameHint) < 0 ? inputTimeRange.duration : singleFrameHint
        desiredRange.pointee = CMTimeRange(start: inputTimeRange.start, duration: duration)
    }

    func setupAnalysis(for analysisRange: CMTimeRange, frameDuration: CMTime) throws {
        analysisLock.lock()
        detectedVerticalPerspective = nil
        detectedHorizontalPerspective = nil
        detectedPerspectiveTime = analysisRange.start
        analysisLock.unlock()
    }

    func analyzeFrame(_ frame: FxImageTile, at frameTime: CMTime) throws {
        analysisLock.lock()
        let mode = pendingAnalysisMode
        analysisLock.unlock()

        guard let mode,
              let grayscaleImage = grayscaleImage(from: frame, maxDimension: 360) else {
            return
        }

        let size = AUSize(width: Double(grayscaleImage.width), height: Double(grayscaleImage.height))
        var verticalPerspective: Double?
        var horizontalPerspective: Double?

        if mode == .vertical || mode == .full {
            let lines = AnyUprightLineDetection.detectLineSegments(
                in: grayscaleImage,
                options: AULineDetectionOptions(
                    orientation: .vertical,
                    edgeThreshold: 40.0,
                    voteThreshold: max(20, grayscaleImage.height / 5),
                    maxLines: 30
                )
            )
            let references = AnyUprightGeometry.bestReferenceLines(from: lines, orientation: .vertical, maximumCount: 2, minimumLength: Double(grayscaleImage.height) * 0.25)
            verticalPerspective = AnyUprightGeometry.estimateVerticalPerspective(from: references, size: size)
        }

        if mode == .horizontal || mode == .full {
            let lines = AnyUprightLineDetection.detectLineSegments(
                in: grayscaleImage,
                options: AULineDetectionOptions(
                    orientation: .horizontal,
                    edgeThreshold: 40.0,
                    voteThreshold: max(20, grayscaleImage.width / 5),
                    maxLines: 30
                )
            )
            let references = AnyUprightGeometry.bestReferenceLines(from: lines, orientation: .horizontal, maximumCount: 2, minimumLength: Double(grayscaleImage.width) * 0.25)
            horizontalPerspective = AnyUprightGeometry.estimateHorizontalPerspective(from: references, size: size)
        }

        analysisLock.lock()
        detectedVerticalPerspective = verticalPerspective
        detectedHorizontalPerspective = horizontalPerspective
        detectedPerspectiveTime = frameTime
        analysisLock.unlock()
    }

    func cleanupAnalysis() throws {
        analysisLock.lock()
        let vertical = detectedVerticalPerspective
        let horizontal = detectedHorizontalPerspective
        let time = detectedPerspectiveTime
        pendingAnalysisMode = nil
        analysisLock.unlock()

        guard let settingAPI = _apiManager.api(for: FxParameterSettingAPI_v5.self) as? FxParameterSettingAPI_v5 else {
            return
        }

        if let vertical {
            settingAPI.setFloatValue(vertical, toParameter: UprightParam.verticalPerspective.rawValue, at: time)
        }
        if let horizontal {
            settingAPI.setFloatValue(horizontal, toParameter: UprightParam.horizontalPerspective.rawValue, at: time)
        }
    }

    private func applyGuided(_ mode: UprightAnalysisMode) {
        let time = currentParameterTime()
        let guides = guideLines(at: time)
        let verticalLines = guides
            .filter { $0.orientation == .vertical }
            .map { imageLine(from: $0, size: AUSize(width: 1.0, height: 1.0)) }
        let horizontalLines = guides
            .filter { $0.orientation == .horizontal }
            .map { imageLine(from: $0, size: AUSize(width: 1.0, height: 1.0)) }

        guard let settingAPI = _apiManager.api(for: FxParameterSettingAPI_v5.self) as? FxParameterSettingAPI_v5 else {
            return
        }

        if mode == .vertical || mode == .full,
           let vertical = AnyUprightGeometry.estimateVerticalPerspective(from: verticalLines, size: AUSize(width: 1.0, height: 1.0)) {
            settingAPI.setFloatValue(vertical, toParameter: UprightParam.verticalPerspective.rawValue, at: time)
        }

        if mode == .horizontal || mode == .full,
           let horizontal = AnyUprightGeometry.estimateHorizontalPerspective(from: horizontalLines, size: AUSize(width: 1.0, height: 1.0)) {
            settingAPI.setFloatValue(horizontal, toParameter: UprightParam.horizontalPerspective.rawValue, at: time)
        }

        guard mode == .full else {
            return
        }

        let rotationLines = horizontalLines.isEmpty ? verticalLines : horizontalLines
        let rotationOrientation: AUReferenceOrientation = horizontalLines.isEmpty ? .vertical : .horizontal
        if let rotation = AnyUprightGeometry.rotationCorrectionRadians(from: rotationLines, orientation: rotationOrientation) {
            settingAPI.setFloatValue(rotation * 180.0 / .pi, toParameter: UprightParam.rotation.rawValue, at: time)
        }
    }

    func drawingCoordinates() -> FxDrawingCoordinates {
        FxDrawingCoordinates(kFxDrawingCoordinates_OBJECT)
    }

    func drawOSC(withWidth width: Int, height: Int, activePart: Int, destinationImage: FxImageTile, at time: CMTime) {
        let guides = guideLines(at: time)
        let segments = guides.map { ($0.start, $0.end) }
        let handles = guides.flatMap {
            [
                AUOSCHandle(point: $0.start, part: $0.spec.startPart.rawValue),
                AUOSCHandle(point: $0.end, part: $0.spec.endPart.rawValue)
            ]
        }
        overlayRenderer.renderSegments(
            segments,
            handles: handles,
            activePart: activePart,
            destinationImage: destinationImage
        )
    }

    func hitTestOSC(atMousePositionX mousePositionX: Double, mousePositionY: Double, activePart: UnsafeMutablePointer<Int>?, at time: CMTime) {
        let size = objectPixelSizeForOSC()
        let mouse = AUPoint(x: mousePositionX, y: mousePositionY)
        activePart?.pointee = UprightOSCPart.none.rawValue

        for guide in guideLines(at: time) {
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
    }

    func mouseDown(atPositionX mousePositionX: Double, positionY mousePositionY: Double, activePart: Int, modifiers: FxModifierKeys, forceUpdate: UnsafeMutablePointer<ObjCBool>?, at time: CMTime) {
        forceUpdate?.pointee = true
    }

    func mouseDragged(atPositionX mousePositionX: Double, positionY mousePositionY: Double, activePart: Int, modifiers: FxModifierKeys, forceUpdate: UnsafeMutablePointer<ObjCBool>?, at time: CMTime) {
        guard let part = UprightOSCPart(rawValue: activePart),
              let endpoint = endpointParameter(for: part),
              let settingAPI = _apiManager.api(for: FxParameterSettingAPI_v5.self) as? FxParameterSettingAPI_v5 else {
            forceUpdate?.pointee = false
            return
        }

        settingAPI.setXValue(mousePositionX, yValue: mousePositionY, toParameter: endpoint.rawValue, at: time)
        forceUpdate?.pointee = true
    }

    func mouseUp(atPositionX mousePositionX: Double, positionY mousePositionY: Double, activePart: Int, modifiers: FxModifierKeys, forceUpdate: UnsafeMutablePointer<ObjCBool>?, at time: CMTime) {
        forceUpdate?.pointee = true
    }

    func keyDown(atPositionX mousePositionX: Double, positionY mousePositionY: Double, keyPressed: UInt16, modifiers: FxModifierKeys, forceUpdate: UnsafeMutablePointer<ObjCBool>?, didHandle: UnsafeMutablePointer<ObjCBool>?, at time: CMTime) {
        forceUpdate?.pointee = false
        didHandle?.pointee = false
    }

    func keyUp(atPositionX mousePositionX: Double, positionY mousePositionY: Double, keyPressed: UInt16, modifiers: FxModifierKeys, forceUpdate: UnsafeMutablePointer<ObjCBool>?, didHandle: UnsafeMutablePointer<ObjCBool>?, at time: CMTime) {
        forceUpdate?.pointee = false
        didHandle?.pointee = false
    }

    private func guideLines(at time: CMTime) -> [UprightGuideLine] {
        let paramAPI = parameterRetrievalAPI()
        return Self.guideSpecs.compactMap { spec in
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
                start: pointParam(paramAPI, spec.start, defaultValue: spec.defaultStart, time: time),
                end: pointParam(paramAPI, spec.end, defaultValue: spec.defaultEnd, time: time)
            )
        }
    }

    private func pointParam(_ paramAPI: FxParameterRetrievalAPI_v6, _ param: UprightParam, defaultValue: AUPoint, time: CMTime) -> AUPoint {
        var x = defaultValue.x
        var y = defaultValue.y
        paramAPI.getXValue(&x, yValue: &y, fromParameter: param.rawValue, at: time)
        return AUPoint(x: x, y: y)
    }

    private func endpointParameter(for part: UprightOSCPart) -> UprightParam? {
        for spec in Self.guideSpecs {
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

    private func grayscaleImage(from frame: FxImageTile, maxDimension: Int) -> AUGrayscaleImage? {
        guard let ioSurface = frame.ioSurface else {
            return nil
        }

        let bounds = frame.imagePixelBounds
        let sourceWidth = max(1, Int(bounds.right - bounds.left))
        let sourceHeight = max(1, Int(bounds.top - bounds.bottom))
        let scale = min(1.0, Double(maxDimension) / Double(max(sourceWidth, sourceHeight)))
        let width = max(1, Int(round(Double(sourceWidth) * scale)))
        let height = max(1, Int(round(Double(sourceHeight) * scale)))
        let colorSpace = frame.colorSpace.map { $0 as Any }
        let image = CIImage(ioSurface: ioSurface, options: colorSpace.map { [.colorSpace: $0] } ?? [:])
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        var rgba = Array(repeating: UInt8(0), count: width * height * 4)

        analysisContext.render(
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
