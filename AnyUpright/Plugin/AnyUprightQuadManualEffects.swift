//
//  AnyUprightQuadManualEffects.swift
//  AnyUpright
//

import Foundation
import AppKit
import CoreImage
import IOSurface
import Vision

class AnyUprightQuadModePlugIn: AnyUprightWarpEffect {
    var fixedQuadMode: AUQuadTransformMode {
        fatalError("Subclasses must choose a fixed Quad mode.")
    }

    var showsSourceEditMode: Bool {
        fixedQuadMode == .sourceQuad
    }

    var showsCornerParameters: Bool {
        fixedQuadMode == .outputCorners
    }

    override func addEffectParameters(_ paramAPI: FxParameterCreationAPI_v5) throws {
        addFixedModeParameter(paramAPI)

        if showsSourceEditMode {
            paramAPI.addToggleButton(
                withName: "Edit Mode",
                parameterID: QuadParam.showCornerAdjuster.rawValue,
                defaultValue: true,
                parameterFlags: defaultFlags()
            )
        } else {
            paramAPI.addToggleButton(
                withName: "Edit Mode",
                parameterID: QuadParam.showCornerAdjuster.rawValue,
                defaultValue: false,
                parameterFlags: hiddenFlags()
            )
        }

        let cornerGroupFlags = showsCornerParameters ? collapsedFlags() : hiddenCollapsedFlags()
        addCornerParameters(paramAPI, title: "Top Left", groupID: QuadGroup.topLeft.rawValue, percentX: .topLeftPercentX, percentY: .topLeftPercentY, pixelX: .topLeftPixelX, pixelY: .topLeftPixelY, groupFlags: cornerGroupFlags)
        addCornerParameters(paramAPI, title: "Top Right", groupID: QuadGroup.topRight.rawValue, percentX: .topRightPercentX, percentY: .topRightPercentY, pixelX: .topRightPixelX, pixelY: .topRightPixelY, groupFlags: cornerGroupFlags)
        addCornerParameters(paramAPI, title: "Bottom Right", groupID: QuadGroup.bottomRight.rawValue, percentX: .bottomRightPercentX, percentY: .bottomRightPercentY, pixelX: .bottomRightPixelX, pixelY: .bottomRightPixelY, groupFlags: cornerGroupFlags)
        addCornerParameters(paramAPI, title: "Bottom Left", groupID: QuadGroup.bottomLeft.rawValue, percentX: .bottomLeftPercentX, percentY: .bottomLeftPercentY, pixelX: .bottomLeftPixelX, pixelY: .bottomLeftPixelY, groupFlags: cornerGroupFlags)
    }

    override func state(at renderTime: CMTime) -> AnyUprightParameterState {
        quadParameterState(at: renderTime, paramAPI: parameterRetrievalAPI(), fixedMode: fixedQuadMode)
    }

    private func addFixedModeParameter(_ paramAPI: FxParameterCreationAPI_v5) {
        paramAPI.addPopupMenu(
            withName: "Mode",
            parameterID: QuadParam.mode.rawValue,
            defaultValue: UInt32(fixedQuadMode.rawValue),
            menuEntries: ["Output Corners", "Source Quad"],
            parameterFlags: hiddenFlags()
        )
    }

    private func addCornerParameters(_ paramAPI: FxParameterCreationAPI_v5, title: String, groupID: UInt32, percentX: QuadParam, percentY: QuadParam, pixelX: QuadParam, pixelY: QuadParam, groupFlags: FxParameterFlags) {
        paramAPI.startParameterSubGroup(title, parameterID: groupID, parameterFlags: groupFlags)
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

    private func hiddenFlags() -> FxParameterFlags {
        FxParameterFlags(kFxParameterFlag_HIDDEN)
    }

    private func hiddenCollapsedFlags() -> FxParameterFlags {
        FxParameterFlags(kFxParameterFlag_HIDDEN | kFxParameterFlag_COLLAPSED)
    }
}

@objc(AnyUprightQuadManualPlugIn)
class AnyUprightQuadManualPlugIn: AnyUprightQuadModePlugIn, FxAnalyzer, FxCustomParameterViewHost_v2 {
    private static var retainedDetectSourceQuadButtonViews: [AnyUprightDetectSourceQuadButtonView] = []

    private let analysisLock = NSLock()
    private var analysisState = QuadAnalysisScratchState()

    override func addEffectParameters(_ paramAPI: FxParameterCreationAPI_v5) throws {
        paramAPI.addCustomParameter(
            withName: "Detect Source Quad",
            parameterID: QuadParam.detectSourceQuad.rawValue,
            defaultValue: NSData(),
            parameterFlags: FxParameterFlags(
                kFxParameterFlag_NOT_ANIMATABLE |
                kFxParameterFlag_CUSTOM_UI |
                kFxParameterFlag_USE_FULL_VIEW_WIDTH
            )
        )
        try super.addEffectParameters(paramAPI)
    }

    override var fixedQuadMode: AUQuadTransformMode {
        .sourceQuad
    }

    @objc(classForCustomParameterID:)
    func classForCustomParameterID(_ parameterID: UInt32) -> AnyClass {
        guard parameterID == QuadParam.detectSourceQuad.rawValue else {
            return NSObject.self
        }

        return NSData.self
    }

    @objc(classesForCustomParameterID:)
    func classesForCustomParameterID(_ parameterID: UInt32) -> NSSet {
        guard parameterID == QuadParam.detectSourceQuad.rawValue else {
            return NSSet(object: NSObject.self)
        }

        return NSSet(object: NSData.self)
    }

    @objc(createViewForParameterID:)
    func createView(forParameterID parameterID: UInt32) -> NSView? {
        guard parameterID == QuadParam.detectSourceQuad.rawValue else {
            return nil
        }

        let view = AnyUprightDetectSourceQuadButtonView(plugin: self)
        // FxPlug hosts can release the plug-in object while custom inspector NSViews
        // are still unwinding, so keep returned views alive for the XPC lifetime.
        Self.retainedDetectSourceQuadButtonViews.append(view)
        return view
    }

    func detectSourceQuadFromButton(_ sender: AnyObject) {
        guard let actionAPI = _apiManager.api(for: FxCustomParameterActionAPI_v4.self) as? FxCustomParameterActionAPI_v4 else {
            startSourceQuadDetection(at: currentParameterTime())
            return
        }

        actionAPI.startAction(sender)
        defer {
            actionAPI.endAction(sender)
        }
        let time = actionAPI.currentTime()
        startSourceQuadDetection(at: time)
    }

    private func startSourceQuadDetection(at time: CMTime) {
        analysisLock.lock()
        analysisState.requestedAnalysisTime = time.isValid && time.isNumeric ? time : currentParameterTime()
        analysisLock.unlock()

        guard let analysisAPI = _apiManager.api(for: FxAnalysisAPI.self) as? FxAnalysisAPI else {
            return
        }

        try? analysisAPI.startForwardAnalysis(kFxAnalysisLocation_CPU)
    }

    func desiredAnalysisTimeRange(_ desiredRange: UnsafeMutablePointer<CMTimeRange>, forInputWith inputTimeRange: CMTimeRange) throws {
        analysisLock.lock()
        let requestedTime = analysisState.requestedAnalysisTime
        analysisLock.unlock()
        desiredRange.pointee = singleFrameAnalysisRange(near: requestedTime, within: inputTimeRange)
    }

    func setupAnalysis(for analysisRange: CMTimeRange, frameDuration: CMTime) throws {
        analysisLock.lock()
        analysisState.detectedSourceQuad = nil
        analysisState.detectedSourceQuadTime = analysisRange.start
        analysisLock.unlock()
    }

    func analyzeFrame(_ frame: FxImageTile, at frameTime: CMTime) throws {
        analysisLock.lock()
        let alreadyDetected = analysisState.detectedSourceQuad != nil
        analysisLock.unlock()

        if alreadyDetected {
            return
        }

        guard let image = AnyUprightAnalysisImage.ciImage(from: frame) else {
            return
        }

        let bounds = frame.imagePixelBounds
        let size = AUSize(
            width: Double(max(1, bounds.right - bounds.left)),
            height: Double(max(1, bounds.top - bounds.bottom))
        )
        guard let quad = detectedSourceQuad(in: image, size: size) else {
            return
        }

        analysisLock.lock()
        analysisState.detectedSourceQuad = QuadDetectedSourceQuad(quad: quad, size: size)
        analysisState.detectedSourceQuadTime = frameTime
        analysisLock.unlock()
    }

    func cleanupAnalysis() throws {
        analysisLock.lock()
        let detected = analysisState.detectedSourceQuad
        let detectedTime = analysisState.detectedSourceQuadTime
        let requestedTime = analysisState.requestedAnalysisTime
        analysisLock.unlock()

        let writeTime = parameterWriteTime(preferred: requestedTime, fallback: detectedTime)
        guard let detected,
              let settingAPI = _apiManager.api(for: FxParameterSettingAPI_v5.self) as? FxParameterSettingAPI_v5 else {
            return
        }

        let offsets = AnyUprightGeometry.sourceQuadOffsets(forSourceQuad: detected.quad, size: detected.size)
        performParameterAction {
            settingAPI.setBoolValue(true, toParameter: QuadParam.showCornerAdjuster.rawValue, at: writeTime)
            writeDetectedSourceQuadOffsets(offsets, settingAPI: settingAPI, time: writeTime)
        }
    }

    private func detectedSourceQuad(in image: CIImage, size: AUSize) -> AUQuad? {
        let request = VNDetectRectanglesRequest()
        request.maximumObservations = 6
        request.minimumConfidence = 0.45
        request.minimumSize = 0.05
        request.quadratureTolerance = 45.0

        let handler = VNImageRequestHandler(ciImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }

        var best: (quad: AUQuad, score: Double)?
        for observation in request.results ?? [] {
            let quad = sourceQuad(from: observation, size: size)
            guard isUsableDetectedSourceQuad(quad, size: size) else {
                continue
            }

            let score = detectedSourceQuadScore(quad, confidence: Double(observation.confidence))
            if best == nil || score > best!.score {
                best = (quad, score)
            }
        }

        return best?.quad
    }

    private func sourceQuad(from observation: VNRectangleObservation, size: AUSize) -> AUQuad {
        let normalized = AUQuad(
            topLeft: normalizedPoint(observation.topLeft),
            topRight: normalizedPoint(observation.topRight),
            bottomRight: normalizedPoint(observation.bottomRight),
            bottomLeft: normalizedPoint(observation.bottomLeft)
        )
        return AnyUprightGeometry.imageQuad(fromNormalizedLowerLeftQuad: normalized, size: size)
    }

    private func normalizedPoint(_ point: CGPoint) -> AUPoint {
        AUPoint(
            x: min(1.0, max(0.0, Double(point.x))),
            y: min(1.0, max(0.0, Double(point.y)))
        )
    }

    private func detectedSourceQuadScore(_ quad: AUQuad, confidence: Double) -> Double {
        polygonArea(quad) * max(0.0, confidence)
    }

    private func isUsableDetectedSourceQuad(_ quad: AUQuad, size: AUSize) -> Bool {
        let points = [quad.topLeft, quad.topRight, quad.bottomRight, quad.bottomLeft]
        guard points.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else {
            return false
        }

        let frameArea = max(1.0, size.width * size.height)
        return polygonArea(quad) / frameArea >= 0.01
    }

    private func polygonArea(_ quad: AUQuad) -> Double {
        let points = [quad.topLeft, quad.topRight, quad.bottomRight, quad.bottomLeft]
        var area = 0.0
        for index in 0..<points.count {
            let current = points[index]
            let next = points[(index + 1) % points.count]
            area += current.x * next.y - next.x * current.y
        }
        return abs(area) / 2.0
    }

    private func writeDetectedSourceQuadOffsets(_ offsets: AUCornerOffsets, settingAPI: FxParameterSettingAPI_v5, time: CMTime) {
        writeDetectedSourceCorner(percent: offsets.topLeftPercent, percentX: .topLeftPercentX, percentY: .topLeftPercentY, pixelX: .topLeftPixelX, pixelY: .topLeftPixelY, settingAPI: settingAPI, time: time)
        writeDetectedSourceCorner(percent: offsets.topRightPercent, percentX: .topRightPercentX, percentY: .topRightPercentY, pixelX: .topRightPixelX, pixelY: .topRightPixelY, settingAPI: settingAPI, time: time)
        writeDetectedSourceCorner(percent: offsets.bottomRightPercent, percentX: .bottomRightPercentX, percentY: .bottomRightPercentY, pixelX: .bottomRightPixelX, pixelY: .bottomRightPixelY, settingAPI: settingAPI, time: time)
        writeDetectedSourceCorner(percent: offsets.bottomLeftPercent, percentX: .bottomLeftPercentX, percentY: .bottomLeftPercentY, pixelX: .bottomLeftPixelX, pixelY: .bottomLeftPixelY, settingAPI: settingAPI, time: time)
    }

    private func writeDetectedSourceCorner(
        percent: AUPoint,
        percentX: QuadParam,
        percentY: QuadParam,
        pixelX: QuadParam,
        pixelY: QuadParam,
        settingAPI: FxParameterSettingAPI_v5,
        time: CMTime
    ) {
        settingAPI.setFloatValue(percent.x, toParameter: percentX.rawValue, at: time)
        settingAPI.setFloatValue(percent.y, toParameter: percentY.rawValue, at: time)
        settingAPI.setFloatValue(0.0, toParameter: pixelX.rawValue, at: time)
        settingAPI.setFloatValue(0.0, toParameter: pixelY.rawValue, at: time)
    }
}

private final class AnyUprightDetectSourceQuadButtonView: NSView {
    private static let rowContentWidth: CGFloat = 300.0
    private static let buttonSize = NSSize(width: 220.0, height: 26.0)

    private weak var plugin: AnyUprightQuadManualPlugIn?
    private let button: NSButton

    init(plugin: AnyUprightQuadManualPlugIn) {
        self.plugin = plugin
        self.button = NSButton(title: "Detect Edge and Corner", target: nil, action: nil)
        super.init(frame: NSRect(x: 0.0, y: 0.0, width: Self.rowContentWidth, height: 32.0))

        button.bezelStyle = .rounded
        button.setButtonType(.momentaryPushIn)
        button.target = self
        button.action = #selector(detectSourceQuad)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)

        addSubview(button)
        updateButtonFrame()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: Self.rowContentWidth, height: 32.0)
    }

    override func layout() {
        super.layout()
        updateButtonFrame()
    }

    private func updateButtonFrame() {
        // FCP sizes this custom view from its intrinsic width, so make the view a
        // wider row canvas and center the momentary button within it.
        let x = max(0.0, (bounds.width - Self.buttonSize.width) / 2.0)
        let y = max(0.0, (bounds.height - Self.buttonSize.height) / 2.0)
        button.frame = NSRect(
            x: x,
            y: y,
            width: Self.buttonSize.width,
            height: Self.buttonSize.height
        )
    }

    @objc private func detectSourceQuad() {
        plugin?.detectSourceQuadFromButton(self)
    }
}

@objc(AnyUprightQuadOutputCornersPlugIn)
class AnyUprightQuadOutputCornersPlugIn: AnyUprightQuadModePlugIn {
    override var fixedQuadMode: AUQuadTransformMode {
        .outputCorners
    }
}
