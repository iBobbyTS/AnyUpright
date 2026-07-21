//
//  AnyUprightUprightEffect.swift
//  AnyUpright
//

import Foundation
import AppKit
import CoreImage
import Dispatch
import IOSurface
import simd
import Vision

@objc(AnyUprightUprightPlugIn)
class AnyUprightUprightPlugIn: AnyUprightWarpEffect, FxAnalyzer {
    private static let analysisDebugLogLock = NSLock()
    private let analysisLock = NSLock()
    private let controlModeLock = NSLock()
    private let analysisContext = CIContext(options: nil)
    private var analysisState = UprightAnalysisScratchState()
    private var previousControlMode: UprightControlMode?

    override var needsFullBuffer: Bool {
        true
    }

    override func addEffectParameters(_ paramAPI: FxParameterCreationAPI_v5) throws {
        addUprightWorkflowParameters(paramAPI, defaultFlags: defaultFlags())
        addLegacyCorrectionResultParameters(paramAPI)
        addUprightGuideParameters(paramAPI, collapsedFlags: hiddenCollapsedFlags(), defaultFlags: hiddenFlags())
        addUprightCandidateParameters(paramAPI, collapsedFlags: hiddenCollapsedFlags(), defaultFlags: hiddenFlags())
    }

    func pluginInstanceAddedToDocument() {
        let time = currentParameterTime()
        let controlMode = uprightControlMode(at: time, paramAPI: parameterRetrievalAPI())
        controlModeLock.lock()
        previousControlMode = controlMode
        controlModeLock.unlock()
    }

    func parameterChanged(_ paramID: UInt32, at time: CMTime) throws {
        guard paramID == UprightParam.controlMode.rawValue else {
            return
        }

        let paramAPI = parameterRetrievalAPI()
        let currentControlMode = uprightControlMode(at: time, paramAPI: paramAPI)
        controlModeLock.lock()
        let sourceControlMode = previousControlMode
        previousControlMode = currentControlMode
        controlModeLock.unlock()

        guard currentControlMode == .manual,
              let sourceControlMode,
              sourceControlMode != .manual,
              let settingAPI = parameterSettingAPI() else {
            return
        }

        let correctionMode = uprightCorrectionMode(at: time, paramAPI: paramAPI)
        let transfers = AnyUprightUprightCandidates.manualGuideTransfers(
            from: uprightCandidateLines(at: time, paramAPI: paramAPI),
            sourceControlMode: sourceControlMode,
            correctionMode: correctionMode
        )
        writeUprightManualGuides(transfers, settingAPI: settingAPI, time: time)
    }

    private func addLegacyCorrectionResultParameters(_ paramAPI: FxParameterCreationAPI_v5) {
        // Keep the parameter IDs readable for existing Motion/FCP documents; rendering no longer consumes them.
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

        let correctionMode = uprightCorrectionMode(at: renderTime, paramAPI: paramAPI)
        let controlMode = uprightControlMode(at: renderTime, paramAPI: paramAPI)
        let editMode = uprightEditMode(at: renderTime, paramAPI: paramAPI)
        result.fillFrame = uprightAutoCrop(at: renderTime, paramAPI: paramAPI) ? 1 : 0
        result.showCornerAdjuster = editMode ? 1 : 0
        result.uprightCorrectionMode = correctionMode.rawValue
        result.uprightControlMode = controlMode.rawValue

        let manualGuides = uprightGuideLines(at: renderTime, paramAPI: paramAPI)
        let manualReferences = referenceLines(from: manualGuides, correctionMode: correctionMode)
        let references = AnyUprightUprightCandidates.selectedReferenceLines(
            manualReferences: manualReferences,
            from: uprightCandidateLines(at: renderTime, paramAPI: paramAPI),
            controlMode: controlMode,
            correctionMode: correctionMode
        )
        storeUprightReferenceLines(references, in: &result)
        let referenceSize = correctionReferenceSize(from: result)
        let hasMatrix = !editMode && applyUprightReferenceMatrix(
            from: references,
            correctionMode: correctionMode,
            referenceSize: referenceSize,
            to: &result
        )
        debugLogReferenceLines(
            controlMode: controlMode,
            guides: controlMode == .manual ? manualGuides : [],
            references: references,
            correctionMode: correctionMode,
            hasMatrix: hasMatrix,
            referenceSize: referenceSize
        )
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
              let correctionMode = UprightCorrectionMode(rawValue: result.uprightCorrectionMode) else {
            return result
        }

        let references = uprightReferenceLines(from: result, correctionMode: correctionMode)
        let referenceSize = correctionReferenceSize(from: result)
        let hasMatrix = applyUprightReferenceMatrix(
            from: references,
            correctionMode: correctionMode,
            referenceSize: referenceSize,
            to: &result
        )
        debugLogReferenceLines(
            controlMode: UprightControlMode(rawValue: result.uprightControlMode) ?? .manual,
            guides: [],
            references: references,
            correctionMode: correctionMode,
            hasMatrix: hasMatrix,
            referenceSize: referenceSize
        )
        return result
    }

    @objc func analyze() {
        let startNanos = Self.analysisNowNanos()
        let time = currentParameterTime()
        let paramAPI = parameterRetrievalAPI()
        let correctionMode = uprightCorrectionMode(at: time, paramAPI: paramAPI)
        let controlMode = uprightControlMode(at: time, paramAPI: paramAPI)
        analysisDebugLog(
            String(
                format: "analyze_start time=%@ correction_mode=%d control_mode=%d",
                String(describing: time),
                correctionMode.rawValue,
                controlMode.rawValue
            )
        )
        guard controlMode != .manual else {
            analysisDebugLog(String(format: "analyze_manual_return elapsed_ms=%.3f", Self.analysisElapsedMilliseconds(since: startNanos)))
            return
        }

        startAnalysis(UprightAnalysisRequest(correctionMode: correctionMode, controlMode: controlMode))
        analysisDebugLog(String(format: "analyze_request_submitted elapsed_ms=%.3f", Self.analysisElapsedMilliseconds(since: startNanos)))
    }

    private func startAnalysis(_ request: UprightAnalysisRequest) {
        analysisLock.lock()
        analysisState.pendingAnalysisRequest = request
        analysisState.requestedAnalysisTime = currentParameterTime()
        analysisLock.unlock()

        guard let analysisAPI = _apiManager.api(for: FxAnalysisAPI.self) as? FxAnalysisAPI else {
            return
        }

        let startNanos = Self.analysisNowNanos()
        do {
            try analysisAPI.startForwardAnalysis(kFxAnalysisLocation_CPU)
            analysisDebugLog(String(format: "start_forward_return elapsed_ms=%.3f", Self.analysisElapsedMilliseconds(since: startNanos)))
        } catch {
            analysisDebugLog("start_forward_error error=\(String(describing: error))")
        }
    }

    func desiredAnalysisTimeRange(_ desiredRange: UnsafeMutablePointer<CMTimeRange>, forInputWith inputTimeRange: CMTimeRange) throws {
        analysisLock.lock()
        let requestedTime = analysisState.requestedAnalysisTime
        analysisLock.unlock()
        let range = singleFrameAnalysisRange(near: requestedTime, within: inputTimeRange)
        desiredRange.pointee = range
        analysisDebugLog(
            "desired_range start=\(range.start) duration=\(range.duration) input_start=\(inputTimeRange.start) input_duration=\(inputTimeRange.duration)"
        )
    }

    func setupAnalysis(for analysisRange: CMTimeRange, frameDuration: CMTime) throws {
        analysisLock.lock()
        analysisState.hasAnalyzedFrame = false
        analysisState.detectedCandidates = []
        analysisState.detectedPerspectiveTime = analysisRange.start
        analysisLock.unlock()
        analysisDebugLog("setup_analysis range_start=\(analysisRange.start) range_duration=\(analysisRange.duration) frame_duration=\(frameDuration)")
    }

    func analyzeFrame(_ frame: FxImageTile, at frameTime: CMTime) throws {
        let frameStartNanos = Self.analysisNowNanos()
        analysisLock.lock()
        let request = analysisState.pendingAnalysisRequest
        let alreadyAnalyzed = analysisState.hasAnalyzedFrame
        if request != nil && !alreadyAnalyzed {
            analysisState.hasAnalyzedFrame = true
        }
        analysisLock.unlock()

        guard let request else {
            return
        }
        guard !alreadyAnalyzed else {
            analysisDebugLog("analyze_frame_skip already_analyzed time=\(frameTime)")
            return
        }
        let sourceReferenceSize = analysisReferenceSize(from: frame)
        let bounds = frame.imagePixelBounds
        analysisDebugLog(
            "analyze_frame_start time=\(frameTime) bounds=\(bounds) reference=\(sourceReferenceSize.width)x\(sourceReferenceSize.height)"
        )

        if request.shouldUseCandidateDetection {
            let detectorStartNanos = Self.analysisNowNanos()
            do {
                let scaleLSDCandidates = try AnyUprightScaleLSDDetector.detectCandidates(
                    in: frame,
                    request: request,
                    context: analysisContext
                )
                storeDetectedCandidates(
                    scaleLSDCandidates,
                    request: request,
                    time: frameTime
                )
                analysisDebugLog(
                    String(
                        format: "scalelsd_success candidates=%d detector_ms=%.3f frame_ms=%.3f",
                        scaleLSDCandidates.count,
                        Self.analysisElapsedMilliseconds(since: detectorStartNanos),
                        Self.analysisElapsedMilliseconds(since: frameStartNanos)
                    )
                )
                return
            } catch {
                analysisDebugLog(
                    String(
                        format: "scalelsd_error error=%@ detector_ms=%.3f",
                        String(describing: error),
                        Self.analysisElapsedMilliseconds(since: detectorStartNanos)
                    )
                )
                // Preserve the existing detector chain when the local ScaleLSD resource is absent.
            }
            let mlsdStartNanos = Self.analysisNowNanos()
            do {
                let mlsdCandidates = try AnyUprightMLSDCoreMLDetector.detectCandidates(
                    in: frame,
                    request: request,
                    context: analysisContext
                )
                storeDetectedCandidates(
                    mlsdCandidates,
                    request: request,
                    time: frameTime
                )
                analysisDebugLog(
                    String(
                        format: "mlsd_success candidates=%d detector_ms=%.3f frame_ms=%.3f",
                        mlsdCandidates.count,
                        Self.analysisElapsedMilliseconds(since: mlsdStartNanos),
                        Self.analysisElapsedMilliseconds(since: frameStartNanos)
                    )
                )
                return
            } catch {
                analysisDebugLog(
                    String(
                        format: "mlsd_error error=%@ detector_ms=%.3f",
                        String(describing: error),
                        Self.analysisElapsedMilliseconds(since: mlsdStartNanos)
                    )
                )
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

        storeDetectedCandidates(
            candidates,
            request: request,
            time: frameTime
        )
        analysisDebugLog(
            String(
                format: "hough_success candidates=%d frame_ms=%.3f",
                candidates.count,
                Self.analysisElapsedMilliseconds(since: frameStartNanos)
            )
        )
    }

    private func storeDetectedCandidates(
        _ candidates: [UprightDetectedCandidate],
        request: UprightAnalysisRequest,
        time: CMTime
    ) {
        let ranked = AnyUprightUprightCandidates.analysisCandidates(
            from: candidates,
            request: request
        )
        analysisLock.lock()
        analysisState.detectedCandidates = Array(ranked.prefix(AnyUprightUprightCandidates.slotCount))
        analysisState.detectedPerspectiveTime = time
        analysisLock.unlock()
    }

    func cleanupAnalysis() throws {
        let cleanupStartNanos = Self.analysisNowNanos()
        analysisLock.lock()
        let request = analysisState.pendingAnalysisRequest
        let candidates = analysisState.detectedCandidates
        let time = parameterWriteTime(preferred: analysisState.requestedAnalysisTime, fallback: analysisState.detectedPerspectiveTime)
        analysisState.pendingAnalysisRequest = nil
        analysisLock.unlock()

        guard let request,
              let settingAPI = _apiManager.api(for: FxParameterSettingAPI_v5.self) as? FxParameterSettingAPI_v5 else {
            analysisDebugLog("cleanup_skipped missing_request_or_setting_api")
            return
        }

        writeUprightCandidateSlots(
            candidates,
            correctionMode: request.correctionMode,
            controlMode: request.controlMode,
            settingAPI: settingAPI,
            time: time
        )

        analysisDebugLog(
            String(
                format: "cleanup_done candidates=%d control_mode=%d elapsed_ms=%.3f",
                candidates.count,
                request.controlMode.rawValue,
                Self.analysisElapsedMilliseconds(since: cleanupStartNanos)
            )
        )
    }

    private func applyUprightReferenceMatrix(
        from references: UprightReferenceLines,
        correctionMode: UprightCorrectionMode,
        referenceSize: AUSize,
        to state: inout AnyUprightParameterState
    ) -> Bool {
        state.uprightReferenceMatrixEnabled = 0
        let matrix = AnyUprightGeometry.guidedUprightOutputToSourceMatrix(
            verticalLines: references.vertical,
            horizontalLines: references.horizontal,
            mode: guidedUprightMode(from: correctionMode),
            size: referenceSize
        )
        guard let matrix else {
            return false
        }

        state.uprightReferenceMatrixEnabled = 1
        storeUprightReferenceMatrix(matrix, in: &state)
        state.verticalPerspective = 0.0
        state.horizontalPerspective = 0.0
        state.rotationRadians = 0.0
        return true
    }

    private func guidedUprightMode(from correctionMode: UprightCorrectionMode) -> AUGuidedUprightMode {
        switch correctionMode {
        case .vertical:
            return .vertical
        case .horizontal:
            return .horizontal
        case .full:
            return .full
        }
    }

    private func storeUprightReferenceMatrix(_ matrix: simd_float3x3, in state: inout AnyUprightParameterState) {
        state.uprightReferenceMatrixA = matrix.columns.0.x
        state.uprightReferenceMatrixB = matrix.columns.1.x
        state.uprightReferenceMatrixC = matrix.columns.2.x
        state.uprightReferenceMatrixD = matrix.columns.0.y
        state.uprightReferenceMatrixE = matrix.columns.1.y
        state.uprightReferenceMatrixF = matrix.columns.2.y
        state.uprightReferenceMatrixG = matrix.columns.0.z
        state.uprightReferenceMatrixH = matrix.columns.1.z
        state.uprightReferenceMatrixI = matrix.columns.2.z
    }

    private func storeUprightReferenceLines(
        _ references: UprightReferenceLines,
        in state: inout AnyUprightParameterState
    ) {
        let lines = references.vertical.map { (UprightGuideOrientation.vertical, $0) }
            + references.horizontal.map { (UprightGuideOrientation.horizontal, $0) }
        state.uprightReferenceLineCount = Int32(min(lines.count, 4))

        for (index, entry) in lines.prefix(4).enumerated() {
            setUprightReferenceLine(entry.1, orientation: entry.0, index: index, in: &state)
        }
    }

    private func setUprightReferenceLine(
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
            state.uprightReferenceLine1Orientation = rawOrientation
            state.uprightReferenceLine1StartX = startX
            state.uprightReferenceLine1StartY = startY
            state.uprightReferenceLine1EndX = endX
            state.uprightReferenceLine1EndY = endY
        case 1:
            state.uprightReferenceLine2Orientation = rawOrientation
            state.uprightReferenceLine2StartX = startX
            state.uprightReferenceLine2StartY = startY
            state.uprightReferenceLine2EndX = endX
            state.uprightReferenceLine2EndY = endY
        case 2:
            state.uprightReferenceLine3Orientation = rawOrientation
            state.uprightReferenceLine3StartX = startX
            state.uprightReferenceLine3StartY = startY
            state.uprightReferenceLine3EndX = endX
            state.uprightReferenceLine3EndY = endY
        case 3:
            state.uprightReferenceLine4Orientation = rawOrientation
            state.uprightReferenceLine4StartX = startX
            state.uprightReferenceLine4StartY = startY
            state.uprightReferenceLine4EndX = endX
            state.uprightReferenceLine4EndY = endY
        default:
            break
        }
    }

    private func uprightReferenceLines(
        from state: AnyUprightParameterState,
        correctionMode: UprightCorrectionMode
    ) -> UprightReferenceLines {
        var verticalLines: [AULineSegment] = []
        var horizontalLines: [AULineSegment] = []
        for index in 0..<min(Int(state.uprightReferenceLineCount), 4) {
            guard let entry = uprightReferenceLine(from: state, index: index) else {
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
        return UprightReferenceLines(vertical: verticalLines, horizontal: horizontalLines)
    }

    private func uprightReferenceLine(
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
            rawOrientation = state.uprightReferenceLine1Orientation
            startX = state.uprightReferenceLine1StartX
            startY = state.uprightReferenceLine1StartY
            endX = state.uprightReferenceLine1EndX
            endY = state.uprightReferenceLine1EndY
        case 1:
            rawOrientation = state.uprightReferenceLine2Orientation
            startX = state.uprightReferenceLine2StartX
            startY = state.uprightReferenceLine2StartY
            endX = state.uprightReferenceLine2EndX
            endY = state.uprightReferenceLine2EndY
        case 2:
            rawOrientation = state.uprightReferenceLine3Orientation
            startX = state.uprightReferenceLine3StartX
            startY = state.uprightReferenceLine3StartY
            endX = state.uprightReferenceLine3EndX
            endY = state.uprightReferenceLine3EndY
        case 3:
            rawOrientation = state.uprightReferenceLine4Orientation
            startX = state.uprightReferenceLine4StartX
            startY = state.uprightReferenceLine4StartY
            endX = state.uprightReferenceLine4EndX
            endY = state.uprightReferenceLine4EndY
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
    ) -> UprightReferenceLines {
        let verticalLines = guides
            .filter { $0.enabled && $0.orientation == .vertical && correctionMode.includesVertical }
            .map { imageLine(from: $0, size: AUSize(width: 1.0, height: 1.0)) }
        let horizontalLines = guides
            .filter { $0.enabled && $0.orientation == .horizontal && correctionMode.includesHorizontal }
            .map { imageLine(from: $0, size: AUSize(width: 1.0, height: 1.0)) }
        return UprightReferenceLines(vertical: verticalLines, horizontal: horizontalLines)
    }

    private func analysisReferenceSize(from frame: FxImageTile) -> AUSize {
        let bounds = frame.imagePixelBounds
        return AUSize(
            width: max(1.0, Double(bounds.right - bounds.left)),
            height: max(1.0, Double(bounds.top - bounds.bottom))
        )
    }

    private func debugLogReferenceLines(
        controlMode: UprightControlMode,
        guides: [UprightGuideLine],
        references: UprightReferenceLines,
        correctionMode: UprightCorrectionMode,
        hasMatrix: Bool,
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
        let verticalDescription = debugLineDescription(references.vertical)
        let horizontalDescription = debugLineDescription(references.horizontal)
        let message = String(
            format: "reference-lines control_mode=%d direction=%d ref=(%.2fx%.2f) matrix=%@ guides=[%@] verticalImage=[%@] horizontalImage=[%@]",
            controlMode.rawValue,
            correctionMode.rawValue,
            referenceSize.width,
            referenceSize.height,
            hasMatrix ? "direct" : "identity",
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

    private static func analysisNowNanos() -> UInt64 {
        DispatchTime.now().uptimeNanoseconds
    }

    private static func analysisElapsedMilliseconds(since startNanos: UInt64) -> Double {
        Double(analysisNowNanos() - startNanos) / 1_000_000.0
    }

    private func analysisDebugLog(_ message: String) {
        guard FileManager.default.fileExists(atPath: "/tmp/AnyUprightUprightAnalysis.debug") else {
            return
        }

        let logPath = "/tmp/AnyUprightUprightAnalysis.log"
        let timestamp = String(format: "%.3f", Date().timeIntervalSince1970)
        guard let data = "[\(timestamp)] \(message)\n".data(using: .utf8) else {
            return
        }

        Self.analysisDebugLogLock.lock()
        defer { Self.analysisDebugLogLock.unlock() }

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
