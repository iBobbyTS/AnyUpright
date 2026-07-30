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
    private let controlModeLock = NSLock()
    private let analysisContext = CIContext(options: nil)
    private let analysisTransaction = AUFxAnalysisTransaction<UprightAnalysisRequest, [UprightDetectedCandidate]>()
    private var previousControlMode: UprightControlMode?

    override var needsFullBuffer: Bool {
        true
    }

    override func addEffectParameters(_ paramAPI: FxParameterCreationAPI_v5) throws {
        addAnalysisDisplayStatusParameter(paramAPI)
        addUprightWorkflowParameters(paramAPI, defaultFlags: defaultFlags())
        addLegacyCorrectionResultParameters(paramAPI)
        addUprightGuideParameters(paramAPI, collapsedFlags: hiddenCollapsedFlags(), defaultFlags: hiddenFlags())
        addUprightCandidateParameters(paramAPI, collapsedFlags: hiddenCollapsedFlags(), defaultFlags: hiddenFlags())
        AnyUprightScaleLSDDetector.prepareCoreMLCacheForPluginAdd()
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
        let startNanos = AUMonotonicClock.nowNanos()
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
            analysisDebugLog(String(format: "analyze_manual_return elapsed_ms=%.3f", AUMonotonicClock.elapsedMilliseconds(since: startNanos)))
            return
        }

        startAnalysis(
            UprightAnalysisRequest(correctionMode: correctionMode, controlMode: controlMode),
            requestedTimelineTime: time
        )
        analysisDebugLog(String(format: "analyze_request_submitted elapsed_ms=%.3f", AUMonotonicClock.elapsedMilliseconds(since: startNanos)))
    }

    private func startAnalysis(_ request: UprightAnalysisRequest, requestedTimelineTime: CMTime) {
        guard let analysisAPI = _apiManager.api(for: FxAnalysisAPI.self) as? FxAnalysisAPI else {
            analysisDebugLog("start_forward_missing_analysis_api")
            return
        }
        let startNanos = AUMonotonicClock.nowNanos()
        do {
            let disposition = try analysisTransaction.start(
                request: request,
                requestedTimelineTime: requestedTimelineTime,
                analysisStartNanos: startNanos,
                hostIsBusy: {
                    let state = analysisAPI.analysisStateForEffect()
                    return state == kFxAnalysisState_AnalysisRequested || state == kFxAnalysisState_AnalysisStarted
                },
                willStart: {
                    self.setAnalysisDisplayStatus(.modelLoading, at: requestedTimelineTime)
                },
                startForwardAnalysis: { try analysisAPI.startForwardAnalysis(kFxAnalysisLocation_CPU) }
            )
            switch disposition {
            case .started:
                analysisDebugLog(String(format: "start_forward_return elapsed_ms=%.3f", AUMonotonicClock.elapsedMilliseconds(since: startNanos)))
            case .localBusy:
                analysisDebugLog("start_forward_ignored_busy local=true")
            case .hostBusy:
                analysisDebugLog("start_forward_ignored_busy host=true")
            case .invalidTimelineTime:
                analysisDebugLog("start_forward_invalid_timeline_time time=\(requestedTimelineTime)")
            }
        } catch {
            setAnalysisDisplayStatus(.none, at: requestedTimelineTime)
            analysisDebugLog("start_forward_error error=\(String(describing: error))")
        }
    }

    func desiredAnalysisTimeRange(_ desiredRange: UnsafeMutablePointer<CMTimeRange>, forInputWith inputTimeRange: CMTimeRange) throws {
        let requestedTimelineTime = analysisTransaction.requestedTimelineTime ?? currentParameterTime()
        guard let timingAPI = _apiManager.api(for: FxTimingAPI_v4.self) as? FxTimingAPI_v4 else {
            analysisTransaction.cancelCurrentRequest()
            setAnalysisDisplayStatus(.none, at: requestedTimelineTime)
            throw uprightAnalysisError("FxTimingAPI_v4 is unavailable")
        }
        do {
            let details = try analysisTransaction.desiredRange(
                within: inputTimeRange,
                inputTimeFromTimeline: { timelineTime in
                    var inputTime = CMTime.invalid
                    timingAPI.inputTime(&inputTime, fromTimelineTime: timelineTime)
                    return inputTime
                },
                sampleDuration: {
                    var duration = CMTime.invalid
                    timingAPI.sampleDuration(&duration)
                    return duration
                }
            )
            if details.usedFallbackSampleDuration {
                analysisDebugLog("desired_range_invalid_sample_duration value=\(details.sampleDuration) fallback=0.05s")
            }
            desiredRange.pointee = details.range
            analysisDebugLog(
                "desired_range timeline=\(details.requestedTimelineTime) input=\(details.inputTime) sample_duration=\(details.sampleDuration) start=\(details.range.start) duration=\(details.range.duration) input_start=\(inputTimeRange.start) input_duration=\(inputTimeRange.duration)"
            )
        } catch {
            setAnalysisDisplayStatus(.none, at: requestedTimelineTime)
            throw uprightAnalysisError(String(describing: error))
        }
    }

    func setupAnalysis(for analysisRange: CMTimeRange, frameDuration: CMTime) throws {
        _ = analysisTransaction.setupAnalysis(range: analysisRange)
        analysisDebugLog("setup_analysis range_start=\(analysisRange.start) range_duration=\(analysisRange.duration) frame_duration=\(frameDuration)")
    }

    func analyzeFrame(_ frame: FxImageTile, at frameTime: CMTime) throws {
        let frameStartNanos = AUMonotonicClock.nowNanos()
        let bounds = frame.imagePixelBounds
        guard let claim = analysisTransaction.claimFrame(
            hasIOSurface: frame.ioSurface != nil,
            hasNonEmptyPixelBounds: bounds.right > bounds.left && bounds.top > bounds.bottom
        ) else {
            let structurallyUsable = frame.ioSurface != nil && bounds.right > bounds.left && bounds.top > bounds.bottom
            let receivedFrameCount = analysisTransaction.receivedFrameCount
            analysisDebugLog("analyze_frame_skip time=\(frameTime) usable=\(structurallyUsable) callback=\(receivedFrameCount)")
            return
        }
        let request = claim.request
        let sourceReferenceSize = analysisReferenceSize(from: frame)
        analysisDebugLog(
            "analyze_frame_start time=\(frameTime) bounds=\(bounds) reference=\(sourceReferenceSize.width)x\(sourceReferenceSize.height)"
        )

        if request.shouldUseCandidateDetection {
            let detectorStartNanos = AUMonotonicClock.nowNanos()
            do {
                let scaleLSDCandidates = try AnyUprightScaleLSDDetector.detectCandidates(
                    in: frame,
                    request: request,
                    statusChanged: { [weak self] status in
                        self?.setAnalysisDisplayStatus(status, at: claim.requestedTimelineTime)
                    }
                )
                storeDetectedCandidates(
                    scaleLSDCandidates,
                    request: request,
                    time: frameTime,
                    token: claim.token
                )
                analysisDebugLog(
                    String(
                        format: "scalelsd_success candidates=%d detector_ms=%.3f frame_ms=%.3f",
                        scaleLSDCandidates.count,
                        AUMonotonicClock.elapsedMilliseconds(since: detectorStartNanos),
                        AUMonotonicClock.elapsedMilliseconds(since: frameStartNanos)
                    )
                )
                return
            } catch {
                analysisDebugLog(
                    String(
                        format: "scalelsd_error error=%@ detector_ms=%.3f",
                        String(describing: error),
                        AUMonotonicClock.elapsedMilliseconds(since: detectorStartNanos)
                    )
                )
                analysisTransaction.relinquishFrame(token: claim.token)
                return
            }
        }

        guard let grayscaleImage = AnyUprightAnalysisImage.grayscaleImage(from: frame, maxDimension: 360, context: analysisContext) else {
            analysisTransaction.relinquishFrame(token: claim.token)
            let receivedFrameCount = analysisTransaction.receivedFrameCount
            analysisDebugLog("analyze_frame_preparation_failed callback=\(receivedFrameCount); waiting_for_next_callback")
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
            time: frameTime,
            token: claim.token
        )
        analysisDebugLog(
            String(
                format: "hough_success candidates=%d frame_ms=%.3f",
                candidates.count,
                AUMonotonicClock.elapsedMilliseconds(since: frameStartNanos)
            )
        )
    }

    private func storeDetectedCandidates(
        _ candidates: [UprightDetectedCandidate],
        request: UprightAnalysisRequest,
        time: CMTime,
        token: AUFxAnalysisTransactionToken
    ) {
        let ranked = AnyUprightUprightCandidates.analysisCandidates(
            from: candidates,
            request: request
        )
        analysisTransaction.complete(
            token: token,
            outcome: .produced(Array(ranked.prefix(AnyUprightUprightCandidates.slotCount))),
            inputFrameTime: time
        )
    }

    func cleanupAnalysis() throws {
        let cleanupStartNanos = AUMonotonicClock.nowNanos()
        let snapshot = analysisTransaction.cleanup()
        defer {
            setAnalysisDisplayStatus(
                .none,
                at: snapshot?.requestedTimelineTime ?? currentParameterTime()
            )
        }
        guard let snapshot else {
            analysisDebugLog("cleanup_skipped missing_request")
            return
        }
        guard case .produced(let candidates) = snapshot.outcome else {
            analysisDebugLog("cleanup_preserved_existing_candidates no_analysis_result input_frame_time=\(snapshot.inputFrameTime)")
            return
        }
        guard snapshot.requestedTimelineTime.isValid, snapshot.requestedTimelineTime.isNumeric else {
            analysisDebugLog("cleanup_preserved_existing_candidates invalid_timeline_time=\(snapshot.requestedTimelineTime)")
            return
        }
        guard
              let settingAPI = _apiManager.api(for: FxParameterSettingAPI_v5.self) as? FxParameterSettingAPI_v5 else {
            analysisDebugLog("cleanup_skipped missing_setting_api")
            return
        }

        writeUprightCandidateSlots(
            candidates,
            correctionMode: snapshot.request.correctionMode,
            controlMode: snapshot.request.controlMode,
            settingAPI: settingAPI,
            time: snapshot.requestedTimelineTime
        )

        analysisDebugLog(
            String(
                format: "cleanup_done candidates=%d control_mode=%d elapsed_ms=%.3f",
                candidates.count,
                snapshot.request.controlMode.rawValue,
                AUMonotonicClock.elapsedMilliseconds(since: cleanupStartNanos)
            )
        )
    }

    private func uprightAnalysisError(_ message: String) -> NSError {
        NSError(
            domain: "AnyUpright.FxAnalysis",
            code: 2,
            userInfo: [NSLocalizedDescriptionKey: "Upright analysis: \(message)"]
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

    private func analysisDebugLog(_ message: String) {
        AUAnalysisDiagnostics.upright.log(message)
    }

    private func candidateLimit(for request: UprightAnalysisRequest) -> Int {
        AnyUprightUprightCandidates.slotLimit(isFullMode: request.correctionMode == .full)
    }

}
