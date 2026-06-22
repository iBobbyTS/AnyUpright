//
//  AnyUprightQuadManualEffects.swift
//  AnyUpright
//

import Foundation
import CoreImage
import IOSurface

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
            addQuadChooseFromDetections(paramAPI, parameterFlags: defaultFlags())
            addQuadSourceDetectionScoreThreshold(paramAPI, parameterFlags: defaultFlags())
        } else {
            paramAPI.addToggleButton(
                withName: "Edit Mode",
                parameterID: QuadParam.showCornerAdjuster.rawValue,
                defaultValue: false,
                parameterFlags: hiddenFlags()
            )
            addQuadChooseFromDetections(paramAPI, parameterFlags: hiddenFlags())
        }

        let cornerGroupFlags = showsCornerParameters ? collapsedFlags() : hiddenCollapsedFlags()
        addCornerParameters(paramAPI, title: "Top Left", groupID: QuadGroup.topLeft.rawValue, percentX: .topLeftPercentX, percentY: .topLeftPercentY, pixelX: .topLeftPixelX, pixelY: .topLeftPixelY, groupFlags: cornerGroupFlags)
        addCornerParameters(paramAPI, title: "Top Right", groupID: QuadGroup.topRight.rawValue, percentX: .topRightPercentX, percentY: .topRightPercentY, pixelX: .topRightPixelX, pixelY: .topRightPixelY, groupFlags: cornerGroupFlags)
        addCornerParameters(paramAPI, title: "Bottom Right", groupID: QuadGroup.bottomRight.rawValue, percentX: .bottomRightPercentX, percentY: .bottomRightPercentY, pixelX: .bottomRightPixelX, pixelY: .bottomRightPixelY, groupFlags: cornerGroupFlags)
        addCornerParameters(paramAPI, title: "Bottom Left", groupID: QuadGroup.bottomLeft.rawValue, percentX: .bottomLeftPercentX, percentY: .bottomLeftPercentY, pixelX: .bottomLeftPixelX, pixelY: .bottomLeftPixelY, groupFlags: cornerGroupFlags)

        if showsSourceEditMode {
            addQuadSourceDetectionPrimitiveParameters(paramAPI, collapsedFlags: hiddenCollapsedFlags(), hiddenFlags: hiddenFlags())
        }
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
class AnyUprightQuadManualPlugIn: AnyUprightQuadModePlugIn, FxAnalyzer {
    private let analysisLock = NSLock()
    private let analysisContext = CIContext(options: nil)
    private var analysisState = QuadAnalysisScratchState()

    override func addEffectParameters(_ paramAPI: FxParameterCreationAPI_v5) throws {
        paramAPI.addPushButton(
            withName: "Detect Edge and Corner",
            parameterID: QuadParam.detectSourceQuad.rawValue,
            selector: #selector(detectSourceQuad),
            parameterFlags: defaultFlags()
        )
        try super.addEffectParameters(paramAPI)
    }

    override var fixedQuadMode: AUQuadTransformMode {
        .sourceQuad
    }

    @objc private func detectSourceQuad() {
        startSourceQuadDetection(at: currentParameterTime())
    }

    private func startSourceQuadDetection(at time: CMTime) {
        analysisLock.lock()
        analysisState.hasPendingSourceQuadDetection = true
        analysisState.detectedSourcePrimitives = QuadDetectedSourcePrimitives()
        analysisState.requestedAnalysisTime = time.isValid && time.isNumeric ? time : currentParameterTime()
        analysisLock.unlock()
        quadAnalysisDebugLog("start requested=\(analysisState.requestedAnalysisTime)")

        guard let analysisAPI = _apiManager.api(for: FxAnalysisAPI.self) as? FxAnalysisAPI else {
            quadAnalysisDebugLog("start missing FxAnalysisAPI")
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
        analysisState.detectedSourcePrimitives = QuadDetectedSourcePrimitives()
        analysisState.detectedSourceSize = AUSize(width: 1.0, height: 1.0)
        analysisState.detectedSourceQuadTime = analysisRange.start
        analysisLock.unlock()
    }

    func analyzeFrame(_ frame: FxImageTile, at frameTime: CMTime) throws {
        analysisLock.lock()
        let alreadyDetected = !analysisState.detectedSourcePrimitives.edges.isEmpty || !analysisState.detectedSourcePrimitives.corners.isEmpty
        analysisLock.unlock()

        if alreadyDetected {
            return
        }

        guard let image = AnyUprightAnalysisImage.grayscaleImage(from: frame, maxDimension: 540, context: analysisContext) else {
            quadAnalysisDebugLog("analyze no grayscale frame")
            return
        }
        let size = AUSize(width: Double(image.width), height: Double(image.height))
        let primitives = detectedSourcePrimitives(in: image)
        quadAnalysisDebugLog("analyze image=\(image.width)x\(image.height) edges=\(primitives.edges.count) corners=\(primitives.corners.count)")

        analysisLock.lock()
        analysisState.detectedSourcePrimitives = primitives
        analysisState.detectedSourceSize = size
        analysisState.detectedSourceQuadTime = frameTime
        analysisLock.unlock()
    }

    func cleanupAnalysis() throws {
        analysisLock.lock()
        let pending = analysisState.hasPendingSourceQuadDetection
        let primitives = analysisState.detectedSourcePrimitives
        let detectedSize = analysisState.detectedSourceSize
        let detectedTime = analysisState.detectedSourceQuadTime
        let requestedTime = analysisState.requestedAnalysisTime
        analysisState.hasPendingSourceQuadDetection = false
        analysisLock.unlock()

        let writeTime = parameterWriteTime(preferred: requestedTime, fallback: detectedTime)
        guard pending,
              let settingAPI = _apiManager.api(for: FxParameterSettingAPI_v5.self) as? FxParameterSettingAPI_v5 else {
            return
        }

        performParameterAction {
            settingAPI.setBoolValue(true, toParameter: QuadParam.showCornerAdjuster.rawValue, at: writeTime)
            settingAPI.setBoolValue(true, toParameter: QuadParam.chooseFromDetections.rawValue, at: writeTime)
            writeQuadSourceDetectionPrimitives(primitives, size: detectedSize, settingAPI: settingAPI, time: writeTime)
        }
        quadAnalysisDebugLog("cleanup pending=\(pending) writeTime=\(writeTime) edges=\(primitives.edges.count) corners=\(primitives.corners.count)")
    }

    private func detectedSourcePrimitives(in image: AUGrayscaleImage) -> QuadDetectedSourcePrimitives {
        let vertical = detectedSourceEdges(in: image, orientation: .vertical)
        let horizontal = detectedSourceEdges(in: image, orientation: .horizontal)
        let selectedEdges = Array((vertical + horizontal)
            .sorted { $0.score > $1.score }
            .prefix(AnyUprightQuadSourceDetectionEdges.slotCount))
        let maxEdgeScore = selectedEdges.reduce(0.0) { max($0, $1.score) }
        let normalizedEdges = selectedEdges.map { edge in
            QuadDetectedSourceEdge(
                line: edge.line,
                score: AnyUprightGeometry.normalizedScore(edge.score, maximum: maxEdgeScore)
            )
        }
        let corners = detectedSourceCorners(from: selectedEdges, size: AUSize(width: Double(image.width), height: Double(image.height)))
        let maxCornerScore = corners.reduce(0.0) { max($0, $1.score) }
        let normalizedCorners = corners.map { corner in
            QuadDetectedSourceCorner(
                point: corner.point,
                score: AnyUprightGeometry.normalizedScore(corner.score, maximum: maxCornerScore)
            )
        }

        return QuadDetectedSourcePrimitives(edges: normalizedEdges, corners: normalizedCorners)
    }

    private func detectedSourceEdges(in image: AUGrayscaleImage, orientation: AUReferenceOrientation) -> [AUDetectedLineSegment] {
        let minimumLength: Double
        let voteThreshold: Int
        switch orientation {
        case .horizontal:
            minimumLength = max(16.0, Double(image.width) * 0.08)
            voteThreshold = max(16, image.width / 12)
        case .vertical:
            minimumLength = max(16.0, Double(image.height) * 0.08)
            voteThreshold = max(16, image.height / 12)
        }

        return AnyUprightLineDetection.detectSupportedLineSegments(
            in: image,
            options: AULineDetectionOptions(
                orientation: orientation,
                maxDeviationRadians: .pi / 5.0,
                edgeThreshold: 36.0,
                voteThreshold: voteThreshold,
                maxLines: max(12, AnyUprightQuadSourceDetectionEdges.slotCount / 2),
                nonMaximumThetaRadius: 3,
                nonMaximumRhoRadius: 6
            )
        )
        .filter { $0.line.length >= minimumLength }
    }

    private func detectedSourceCorners(from edges: [AUDetectedLineSegment], size: AUSize) -> [QuadDetectedSourceCorner] {
        let vertical = edges.filter { $0.orientation == .vertical }
        let horizontal = edges.filter { $0.orientation == .horizontal }
        let tolerance = max(10.0, min(size.width, size.height) * 0.035)
        let mergeRadius = max(6.0, min(size.width, size.height) * 0.018)
        var rawCorners: [QuadDetectedSourceCorner] = []

        for verticalEdge in vertical {
            for horizontalEdge in horizontal {
                guard let point = AnyUprightGeometry.intersection(of: verticalEdge.line, and: horizontalEdge.line),
                      point.x >= 0.0,
                      point.x <= size.width - 1.0,
                      point.y >= 0.0,
                      point.y <= size.height - 1.0 else {
                    continue
                }

                let verticalDistance = verticalEdge.line.distance(to: point)
                let horizontalDistance = horizontalEdge.line.distance(to: point)
                let distance = max(verticalDistance, horizontalDistance)
                guard distance <= tolerance else {
                    continue
                }

                let proximity = max(0.25, 1.0 - distance / tolerance)
                rawCorners.append(QuadDetectedSourceCorner(
                    point: point,
                    score: (verticalEdge.score + horizontalEdge.score) * 0.5 * proximity
                ))
            }
        }

        var selected: [QuadDetectedSourceCorner] = []
        for corner in rawCorners.sorted(by: { $0.score > $1.score }) {
            let duplicate = selected.contains { existing in
                hypot(existing.point.x - corner.point.x, existing.point.y - corner.point.y) <= mergeRadius
            }
            if duplicate {
                continue
            }

            selected.append(corner)
            if selected.count >= AnyUprightQuadSourceDetectionCorners.slotCount {
                break
            }
        }

        return selected
    }

    private func quadAnalysisDebugLog(_ message: String) {
        let flagPath = "/tmp/AnyUprightQuadOSC.debug"
        guard FileManager.default.fileExists(atPath: flagPath) else {
            return
        }

        let logPath = "/tmp/AnyUprightQuadOSC.log"
        let line = "[\(Date().timeIntervalSince1970)] analysis \(message)\n"
        guard let data = line.data(using: .utf8) else {
            return
        }

        if FileManager.default.fileExists(atPath: logPath),
           let handle = try? FileHandle(forWritingTo: URL(fileURLWithPath: logPath)) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            _ = try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: URL(fileURLWithPath: logPath))
        }
    }
}

@objc(AnyUprightQuadOutputCornersPlugIn)
class AnyUprightQuadOutputCornersPlugIn: AnyUprightQuadModePlugIn {
    override var fixedQuadMode: AUQuadTransformMode {
        .outputCorners
    }
}
