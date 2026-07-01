//
//  AnyUprightUprightEffect.swift
//  AnyUpright
//

import Foundation
import AppKit
import CoreImage
import IOSurface
import simd
import Vision

@objc(AnyUprightUprightPlugIn)
class AnyUprightUprightPlugIn: AnyUprightWarpEffect, FxAnalyzer {
    private let analysisLock = NSLock()
    private let analysisContext = CIContext(options: nil)
    private var analysisState = UprightAnalysisScratchState()

    override var needsFullBuffer: Bool {
        true
    }

    override func addEffectParameters(_ paramAPI: FxParameterCreationAPI_v5) throws {
        addUprightWorkflowParameters(paramAPI, defaultFlags: defaultFlags())
        addHiddenCorrectionResultParameters(paramAPI)
        addUprightGuideParameters(paramAPI, collapsedFlags: hiddenCollapsedFlags(), defaultFlags: hiddenFlags())
        addUprightCandidateParameters(paramAPI, collapsedFlags: hiddenCollapsedFlags(), defaultFlags: hiddenFlags())
    }

    private func addHiddenCorrectionResultParameters(_ paramAPI: FxParameterCreationAPI_v5) {
        paramAPI.addPercentSlider(
            withName: "Vertical Perspective",
            parameterID: UprightParam.verticalPerspective.rawValue,
            defaultValue: 0.0,
            parameterMin: -1.0,
            parameterMax: 1.0,
            sliderMin: -0.5,
            sliderMax: 0.5,
            delta: 0.01,
            parameterFlags: hiddenFlags()
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
            parameterFlags: hiddenFlags()
        )
        paramAPI.addAngleSlider(
            withName: "Rotation",
            parameterID: UprightParam.rotation.rawValue,
            defaultDegrees: 0.0,
            parameterMinDegrees: -45.0,
            parameterMaxDegrees: 45.0,
            parameterFlags: hiddenFlags()
        )
    }

    private func hiddenFlags() -> FxParameterFlags {
        FxParameterFlags(kFxParameterFlag_HIDDEN)
    }

    private func hiddenCollapsedFlags() -> FxParameterFlags {
        FxParameterFlags(kFxParameterFlag_HIDDEN | kFxParameterFlag_COLLAPSED)
    }

    override func state(at renderTime: CMTime) -> AnyUprightParameterState {
        var result = AnyUprightParameterState(effectKind: AnyUprightEffectKind.upright.rawValue)
        populateStableRenderSizes(&result, at: renderTime)
        guard let paramAPI = parameterRetrievalAPI() else {
            return result
        }

        var vertical = 0.0
        var horizontal = 0.0
        var rotation = 0.0

        paramAPI.getFloatValue(&vertical, fromParameter: UprightParam.verticalPerspective.rawValue, at: renderTime)
        paramAPI.getFloatValue(&horizontal, fromParameter: UprightParam.horizontalPerspective.rawValue, at: renderTime)
        paramAPI.getFloatValue(&rotation, fromParameter: UprightParam.rotation.rawValue, at: renderTime)

        let correctionMode = uprightCorrectionMode(at: renderTime, paramAPI: paramAPI)
        let controlMode = uprightControlMode(at: renderTime, paramAPI: paramAPI)
        let editMode = uprightEditMode(at: renderTime, paramAPI: paramAPI)
        result.fillFrame = uprightAutoCrop(at: renderTime, paramAPI: paramAPI) ? 1 : 0
        result.showCornerAdjuster = editMode ? 1 : 0
        result.uprightCorrectionMode = correctionMode.rawValue
        result.uprightControlMode = controlMode.rawValue

        if controlMode == .manual && !editMode {
            let references = manualGuideReferences(
                at: renderTime,
                paramAPI: paramAPI,
                correctionMode: correctionMode
            )
            storeManualGuideReferences(references, in: &result)
            let referenceSize = correctionReferenceSize(from: result)
            let usesDirectManualMatrix = applyManualMatrixOverride(
                from: references,
                correctionMode: correctionMode,
                referenceSize: referenceSize,
                to: &result
            )
            let correction = usesDirectManualMatrix ? .zero : correction(
                fromManualReferences: references,
                correctionMode: correctionMode,
                referenceSize: referenceSize
            )
            debugLogManualGuides(
                guides: references.guides,
                verticalLines: references.vertical,
                horizontalLines: references.horizontal,
                correction: correction,
                correctionMode: correctionMode,
                usesDirectManualMatrix: usesDirectManualMatrix,
                referenceSize: referenceSize
            )
            if !usesDirectManualMatrix {
                result.verticalPerspective = Float(correction.verticalPerspective)
                result.horizontalPerspective = Float(correction.horizontalPerspective)
                result.rotationRadians = correctionMode == .full ? Float(correction.rotationRadians) : 0.0
            }
            return result
        }

        result.verticalPerspective = correctionMode.includesVertical ? Float(vertical) : 0.0
        result.horizontalPerspective = correctionMode.includesHorizontal ? Float(horizontal) : 0.0
        result.rotationRadians = correctionMode == .full ? Float(rotation) : 0.0
        return result
    }

    override func runtimeParameterState(
        from state: AnyUprightParameterState,
        sourceImage: FxImageTile,
        destinationImage: FxImageTile,
        renderTime: CMTime
    ) -> AnyUprightParameterState {
        var result = super.runtimeParameterState(
            from: state,
            sourceImage: sourceImage,
            destinationImage: destinationImage,
            renderTime: renderTime
        )
        guard result.showCornerAdjuster == 0,
              UprightControlMode(rawValue: result.uprightControlMode) == .manual,
              let correctionMode = UprightCorrectionMode(rawValue: result.uprightCorrectionMode) else {
            return result
        }

        let references = manualGuideReferences(from: result, correctionMode: correctionMode)
        let referenceSize = correctionReferenceSize(from: result)
        let usesDirectManualMatrix = applyManualMatrixOverride(
            from: references,
            correctionMode: correctionMode,
            referenceSize: referenceSize,
            to: &result
        )
        let correction = usesDirectManualMatrix ? .zero : correction(
            fromManualReferences: references,
            correctionMode: correctionMode,
            referenceSize: referenceSize
        )
        debugLogManualGuides(
            guides: [],
            verticalLines: references.vertical,
            horizontalLines: references.horizontal,
            correction: correction,
            correctionMode: correctionMode,
            usesDirectManualMatrix: usesDirectManualMatrix,
            referenceSize: referenceSize
        )
        if !usesDirectManualMatrix {
            result.verticalPerspective = Float(correction.verticalPerspective)
            result.horizontalPerspective = Float(correction.horizontalPerspective)
            result.rotationRadians = correctionMode == .full ? Float(correction.rotationRadians) : 0.0
        }
        return result
    }

    @objc func analyze() {
        let time = currentParameterTime()
        let paramAPI = parameterRetrievalAPI()
        let correctionMode = uprightCorrectionMode(at: time, paramAPI: paramAPI)
        let controlMode = uprightControlMode(at: time, paramAPI: paramAPI)
        guard controlMode != .manual else {
            applyGuided(correctionMode, time: time)
            return
        }

        startAnalysis(UprightAnalysisRequest(correctionMode: correctionMode, controlMode: controlMode))
    }

    private func startAnalysis(_ request: UprightAnalysisRequest) {
        analysisLock.lock()
        analysisState.pendingAnalysisRequest = request
        analysisState.requestedAnalysisTime = currentParameterTime()
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
        analysisState.detectedVerticalPerspective = nil
        analysisState.detectedHorizontalPerspective = nil
        analysisState.detectedRotationRadians = nil
        analysisState.detectedCandidates = []
        analysisState.detectedReferenceSize = AUSize(width: 1000.0, height: 1000.0)
        analysisState.detectedPerspectiveTime = analysisRange.start
        analysisLock.unlock()
    }

    func analyzeFrame(_ frame: FxImageTile, at frameTime: CMTime) throws {
        analysisLock.lock()
        let request = analysisState.pendingAnalysisRequest
        analysisLock.unlock()

        guard let request else {
            return
        }
        let sourceReferenceSize = analysisReferenceSize(from: frame)

        if request.shouldUseCandidateDetection {
            do {
                let mlsdCandidates = try AnyUprightMLSDCoreMLDetector.detectCandidates(
                    in: frame,
                    request: request,
                    context: analysisContext
                )
                analysisLock.lock()
                analysisState.detectedCandidates = mlsdCandidates
                analysisState.detectedReferenceSize = sourceReferenceSize
                analysisState.detectedPerspectiveTime = frameTime
                analysisLock.unlock()
                return
            } catch {
                // Keep local development usable before the ignored M-LSD model bundle is installed.
            }
        }

        guard let grayscaleImage = AnyUprightAnalysisImage.grayscaleImage(from: frame, maxDimension: 360, context: analysisContext) else {
            return
        }

        let size = AUSize(width: Double(grayscaleImage.width), height: Double(grayscaleImage.height))
        var candidates: [UprightDetectedCandidate] = []

        if request.includesVertical {
            let lines = AnyUprightLineDetection.detectLineSegments(
                in: grayscaleImage,
                options: AULineDetectionOptions(
                    orientation: .vertical,
                    edgeThreshold: 40.0,
                    voteThreshold: max(20, grayscaleImage.height / 5),
                    maxLines: candidateLimit(for: request)
                )
            )
            let lineCandidates = AnyUprightGeometry.lineCandidates(
                from: lines,
                orientation: .vertical,
                minimumLength: Double(grayscaleImage.height) * 0.25
            )

            candidates.append(contentsOf: AnyUprightUprightCandidates.detectedCandidates(
                from: Array(lineCandidates.prefix(candidateLimit(for: request))),
                orientation: .vertical,
                size: size
            ))
        }

        if request.includesHorizontal {
            let lines = AnyUprightLineDetection.detectLineSegments(
                in: grayscaleImage,
                options: AULineDetectionOptions(
                    orientation: .horizontal,
                    edgeThreshold: 40.0,
                    voteThreshold: max(20, grayscaleImage.width / 5),
                    maxLines: candidateLimit(for: request)
                )
            )
            let lineCandidates = AnyUprightGeometry.lineCandidates(
                from: lines,
                orientation: .horizontal,
                minimumLength: Double(grayscaleImage.width) * 0.25
            )

            candidates.append(contentsOf: AnyUprightUprightCandidates.detectedCandidates(
                from: Array(lineCandidates.prefix(candidateLimit(for: request))),
                orientation: .horizontal,
                size: size
            ))
        }

        analysisLock.lock()
        analysisState.detectedCandidates = Array(candidates.prefix(AnyUprightUprightCandidates.slotCount))
        analysisState.detectedReferenceSize = sourceReferenceSize
        analysisState.detectedPerspectiveTime = frameTime
        analysisLock.unlock()
    }

    func cleanupAnalysis() throws {
        analysisLock.lock()
        let request = analysisState.pendingAnalysisRequest
        let candidates = analysisState.detectedCandidates
        let referenceSize = analysisState.detectedReferenceSize
        let time = parameterWriteTime(preferred: analysisState.requestedAnalysisTime, fallback: analysisState.detectedPerspectiveTime)
        analysisState.pendingAnalysisRequest = nil
        analysisLock.unlock()

        guard let request,
              let settingAPI = _apiManager.api(for: FxParameterSettingAPI_v5.self) as? FxParameterSettingAPI_v5 else {
            return
        }

        writeUprightCandidateSlots(
            candidates,
            correctionMode: request.correctionMode,
            controlMode: request.controlMode,
            settingAPI: settingAPI,
            time: time
        )

        if request.controlMode == .automatic {
            let selectedIndexes = AnyUprightUprightCandidates.automaticSelectedIndexes(
                from: candidates,
                correctionMode: request.correctionMode
            )
            let selectedCandidates = candidates.enumerated()
                .filter { selectedIndexes.contains($0.offset) }
                .map(\.element)
            let verticalLines = selectedDetectedImageLines(from: selectedCandidates, orientation: .vertical, correctionMode: request.correctionMode)
            let horizontalLines = selectedDetectedImageLines(from: selectedCandidates, orientation: .horizontal, correctionMode: request.correctionMode)
            writeUprightCorrection(
                verticalLines: verticalLines,
                horizontalLines: horizontalLines,
                correctionMode: request.correctionMode,
                settingAPI: settingAPI,
                time: time,
                referenceSize: referenceSize
            )
        }
    }

    private func applyGuided(_ correctionMode: UprightCorrectionMode, time: CMTime) {
        let guides = uprightGuideLines(at: time, paramAPI: parameterRetrievalAPI())
        let references = referenceLines(
            from: guides,
            correctionMode: correctionMode
        )

        applyReferences(
            verticalLines: references.vertical,
            horizontalLines: references.horizontal,
            correctionMode: correctionMode,
            time: time
        )
    }

    private func applySelected(_ correctionMode: UprightCorrectionMode, time: CMTime) {
        let candidates = uprightCandidateLines(at: time, paramAPI: parameterRetrievalAPI())
        let verticalLines = AnyUprightUprightCandidates.selectedImageLines(from: candidates, orientation: .vertical)
        let horizontalLines = AnyUprightUprightCandidates.selectedImageLines(from: candidates, orientation: .horizontal)

        applyReferences(verticalLines: verticalLines, horizontalLines: horizontalLines, correctionMode: correctionMode, time: time)
    }

    private func applyReferences(verticalLines: [AULineSegment], horizontalLines: [AULineSegment], correctionMode: UprightCorrectionMode, time: CMTime) {
        guard let settingAPI = _apiManager.api(for: FxParameterSettingAPI_v5.self) as? FxParameterSettingAPI_v5 else {
            return
        }

        writeUprightCorrection(
            verticalLines: verticalLines,
            horizontalLines: horizontalLines,
            correctionMode: correctionMode,
            settingAPI: settingAPI,
            time: time,
            referenceSize: objectPixelSizeForOSC(defaultSize: AUSize(width: 1000.0, height: 1000.0))
        )
    }

    private func manualGuideReferences(
        at time: CMTime,
        paramAPI: FxParameterRetrievalAPI_v6,
        correctionMode: UprightCorrectionMode
    ) -> (guides: [UprightGuideLine], vertical: [AULineSegment], horizontal: [AULineSegment]) {
        let guides = uprightGuideLines(at: time, paramAPI: paramAPI)
        let references = referenceLines(from: guides, correctionMode: correctionMode)
        return (guides, references.vertical, references.horizontal)
    }

    private func correction(
        fromManualReferences references: (guides: [UprightGuideLine], vertical: [AULineSegment], horizontal: [AULineSegment]),
        correctionMode: UprightCorrectionMode,
        referenceSize: AUSize
    ) -> UprightCorrectionValues {
        AnyUprightUprightCandidates.correctionValues(
            verticalLines: references.vertical,
            horizontalLines: references.horizontal,
            correctionMode: correctionMode,
            referenceSize: referenceSize
        )
    }

    private func applyManualMatrixOverride(
        from references: (guides: [UprightGuideLine], vertical: [AULineSegment], horizontal: [AULineSegment]),
        correctionMode: UprightCorrectionMode,
        referenceSize: AUSize,
        to state: inout AnyUprightParameterState
    ) -> Bool {
        state.uprightManualMatrixEnabled = 0
        guard correctionMode == .vertical,
              references.vertical.count >= 2,
              let matrix = AnyUprightGeometry.guidedVerticalOutputToSourceMatrix(
                fromNormalizedImageLines: references.vertical,
                size: referenceSize
              ) else {
            return false
        }

        state.uprightManualMatrixEnabled = 1
        storeManualMatrix(matrix, in: &state)
        state.verticalPerspective = 0.0
        state.horizontalPerspective = 0.0
        state.rotationRadians = 0.0
        return true
    }

    private func storeManualMatrix(_ matrix: simd_float3x3, in state: inout AnyUprightParameterState) {
        state.uprightManualMatrixA = matrix.columns.0.x
        state.uprightManualMatrixB = matrix.columns.1.x
        state.uprightManualMatrixC = matrix.columns.2.x
        state.uprightManualMatrixD = matrix.columns.0.y
        state.uprightManualMatrixE = matrix.columns.1.y
        state.uprightManualMatrixF = matrix.columns.2.y
        state.uprightManualMatrixG = matrix.columns.0.z
        state.uprightManualMatrixH = matrix.columns.1.z
        state.uprightManualMatrixI = matrix.columns.2.z
    }

    private func storeManualGuideReferences(
        _ references: (guides: [UprightGuideLine], vertical: [AULineSegment], horizontal: [AULineSegment]),
        in state: inout AnyUprightParameterState
    ) {
        let lines = references.vertical.map { (UprightGuideOrientation.vertical, $0) }
            + references.horizontal.map { (UprightGuideOrientation.horizontal, $0) }
        state.uprightManualLineCount = Int32(min(lines.count, 4))

        for (index, entry) in lines.prefix(4).enumerated() {
            setManualGuideReference(entry.1, orientation: entry.0, index: index, in: &state)
        }
    }

    private func setManualGuideReference(
        _ line: AULineSegment,
        orientation: UprightGuideOrientation,
        index: Int,
        in state: inout AnyUprightParameterState
    ) {
        let rawOrientation = orientation.rawValue
        let startX = Float(line.start.x)
        let startY = Float(line.start.y)
        let endX = Float(line.end.x)
        let endY = Float(line.end.y)

        switch index {
        case 0:
            state.uprightManualLine1Orientation = rawOrientation
            state.uprightManualLine1StartX = startX
            state.uprightManualLine1StartY = startY
            state.uprightManualLine1EndX = endX
            state.uprightManualLine1EndY = endY
        case 1:
            state.uprightManualLine2Orientation = rawOrientation
            state.uprightManualLine2StartX = startX
            state.uprightManualLine2StartY = startY
            state.uprightManualLine2EndX = endX
            state.uprightManualLine2EndY = endY
        case 2:
            state.uprightManualLine3Orientation = rawOrientation
            state.uprightManualLine3StartX = startX
            state.uprightManualLine3StartY = startY
            state.uprightManualLine3EndX = endX
            state.uprightManualLine3EndY = endY
        case 3:
            state.uprightManualLine4Orientation = rawOrientation
            state.uprightManualLine4StartX = startX
            state.uprightManualLine4StartY = startY
            state.uprightManualLine4EndX = endX
            state.uprightManualLine4EndY = endY
        default:
            break
        }
    }

    private func manualGuideReferences(
        from state: AnyUprightParameterState,
        correctionMode: UprightCorrectionMode
    ) -> (guides: [UprightGuideLine], vertical: [AULineSegment], horizontal: [AULineSegment]) {
        var verticalLines: [AULineSegment] = []
        var horizontalLines: [AULineSegment] = []
        for index in 0..<min(Int(state.uprightManualLineCount), 4) {
            guard let entry = manualGuideReference(from: state, index: index) else {
                continue
            }
            switch entry.orientation {
            case .vertical where correctionMode.includesVertical:
                verticalLines.append(entry.line)
            case .horizontal where correctionMode.includesHorizontal:
                horizontalLines.append(entry.line)
            default:
                break
            }
        }
        return ([], verticalLines, horizontalLines)
    }

    private func manualGuideReference(
        from state: AnyUprightParameterState,
        index: Int
    ) -> (orientation: UprightGuideOrientation, line: AULineSegment)? {
        let rawOrientation: Int32
        let startX: Float
        let startY: Float
        let endX: Float
        let endY: Float

        switch index {
        case 0:
            rawOrientation = state.uprightManualLine1Orientation
            startX = state.uprightManualLine1StartX
            startY = state.uprightManualLine1StartY
            endX = state.uprightManualLine1EndX
            endY = state.uprightManualLine1EndY
        case 1:
            rawOrientation = state.uprightManualLine2Orientation
            startX = state.uprightManualLine2StartX
            startY = state.uprightManualLine2StartY
            endX = state.uprightManualLine2EndX
            endY = state.uprightManualLine2EndY
        case 2:
            rawOrientation = state.uprightManualLine3Orientation
            startX = state.uprightManualLine3StartX
            startY = state.uprightManualLine3StartY
            endX = state.uprightManualLine3EndX
            endY = state.uprightManualLine3EndY
        case 3:
            rawOrientation = state.uprightManualLine4Orientation
            startX = state.uprightManualLine4StartX
            startY = state.uprightManualLine4StartY
            endX = state.uprightManualLine4EndX
            endY = state.uprightManualLine4EndY
        default:
            return nil
        }

        guard let orientation = UprightGuideOrientation(rawValue: rawOrientation) else {
            return nil
        }
        return (
            orientation,
            AULineSegment(
                start: AUPoint(x: Double(startX), y: Double(startY)),
                end: AUPoint(x: Double(endX), y: Double(endY))
            )
        )
    }

    private func correctionReferenceSize(from state: AnyUprightParameterState) -> AUSize {
        let width = Double(state.stableInputWidth)
        let height = Double(state.stableInputHeight)
        guard width > 0.0, height > 0.0 else {
            return objectPixelSizeForOSC(defaultSize: AUSize(width: 1000.0, height: 1000.0))
        }
        return AUSize(width: width, height: height)
    }

    private func referenceLines(
        from guides: [UprightGuideLine],
        correctionMode: UprightCorrectionMode
    ) -> (vertical: [AULineSegment], horizontal: [AULineSegment]) {
        let verticalLines = guides
            .filter { $0.enabled && $0.orientation == .vertical && correctionMode.includesVertical }
            .map { imageLine(from: $0, size: AUSize(width: 1.0, height: 1.0)) }
        let horizontalLines = guides
            .filter { $0.enabled && $0.orientation == .horizontal && correctionMode.includesHorizontal }
            .map { imageLine(from: $0, size: AUSize(width: 1.0, height: 1.0)) }
        return (verticalLines, horizontalLines)
    }

    private func selectedDetectedImageLines(from candidates: [UprightDetectedCandidate], orientation: UprightGuideOrientation, correctionMode: UprightCorrectionMode) -> [AULineSegment] {
        let selected = candidates
            .filter { $0.orientation == orientation }
            .sorted {
                if $0.score == $1.score {
                    return $0.start.x < $1.start.x
                }
                return $0.score > $1.score
            }
            .prefix(2)

        guard (orientation == .vertical && correctionMode.includesVertical)
            || (orientation == .horizontal && correctionMode.includesHorizontal) else {
            return []
        }

        return selected.map {
            AULineSegment(
                start: AUPoint(x: $0.start.x, y: 1.0 - $0.start.y),
                end: AUPoint(x: $0.end.x, y: 1.0 - $0.end.y)
            )
        }
    }

    private func analysisReferenceSize(from frame: FxImageTile) -> AUSize {
        let bounds = frame.imagePixelBounds
        return AUSize(
            width: max(1.0, Double(bounds.right - bounds.left)),
            height: max(1.0, Double(bounds.top - bounds.bottom))
        )
    }

    private func debugLogManualGuides(
        guides: [UprightGuideLine],
        verticalLines: [AULineSegment],
        horizontalLines: [AULineSegment],
        correction: UprightCorrectionValues,
        correctionMode: UprightCorrectionMode,
        usesDirectManualMatrix: Bool,
        referenceSize: AUSize
    ) {
        guard FileManager.default.fileExists(atPath: "/tmp/AnyUprightUprightRender.debug") else {
            return
        }

        let guideDescription = guides.map {
            String(
                format: "g%d enabled=%d orientation=%d object=(%.6f,%.6f)->(%.6f,%.6f)",
                $0.spec.linePart.rawValue,
                $0.enabled ? 1 : 0,
                $0.orientation.rawValue,
                $0.start.x,
                $0.start.y,
                $0.end.x,
                $0.end.y
            )
        }.joined(separator: " | ")
        let verticalDescription = debugLineDescription(verticalLines)
        let horizontalDescription = debugLineDescription(horizontalLines)
        let message = String(
            format: "manual-guides mode=%d ref=(%.2fx%.2f) matrix=%@ correction=(v=%.6f,h=%.6f,rot=%.6f) guides=[%@] verticalImage=[%@] horizontalImage=[%@]",
            correctionMode.rawValue,
            referenceSize.width,
            referenceSize.height,
            usesDirectManualMatrix ? "direct" : "parameter",
            correction.verticalPerspective,
            correction.horizontalPerspective,
            correction.rotationRadians,
            guideDescription,
            verticalDescription,
            horizontalDescription
        )
        debugAppendUprightLog(message)
    }

    private func debugLineDescription(_ lines: [AULineSegment]) -> String {
        lines.map {
            String(
                format: "(%.6f,%.6f)->(%.6f,%.6f)",
                $0.start.x,
                $0.start.y,
                $0.end.x,
                $0.end.y
            )
        }.joined(separator: " | ")
    }

    private func debugAppendUprightLog(_ message: String) {
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

    private func candidateLimit(for request: UprightAnalysisRequest) -> Int {
        AnyUprightUprightCandidates.slotLimit(isFullMode: request.correctionMode == .full)
    }

}
