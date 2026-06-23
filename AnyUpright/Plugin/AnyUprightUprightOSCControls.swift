//
//  AnyUprightUprightOSCControls.swift
//  AnyUpright
//

import Foundation
import AppKit
import CoreImage
import IOSurface
import Vision

@objc(AnyUprightUprightOSCPlugIn)
class AnyUprightUprightOSCPlugIn: AnyUprightOSCPlugIn, FxOnScreenControl_v4 {
    private let overlayRenderer = AnyUprightOSCOverlayRenderer()

    @objc(drawingCoordinates)
    func drawingCoordinates() -> FxDrawingCoordinates {
        return FxDrawingCoordinates(kFxDrawingCoordinates_CANVAS)
    }

    @objc(drawOSCWithWidth:height:activePart:destinationImage:atTime:)
    func drawOSC(withWidth width: Int, height: Int, activePart: Int, destinationImage: FxImageTile, at time: CMTime) {
        let paramAPI = parameterRetrievalAPI()
        guard uprightEditMode(at: time, paramAPI: paramAPI) else {
            overlayRenderer.clear(destinationImage: destinationImage)
            return
        }

        let correctionMode = uprightCorrectionMode(at: time, paramAPI: paramAPI)
        let controlMode = uprightControlMode(at: time, paramAPI: paramAPI)
        let guides = controlMode == .manual ? manualGuides(at: time, paramAPI: paramAPI, correctionMode: correctionMode) : []
        let candidates = AnyUprightUprightCandidates.displayCandidates(
            from: uprightCandidateLines(at: time, paramAPI: paramAPI),
            controlMode: controlMode,
            correctionMode: correctionMode
        )
        let canvasCandidates = candidates.map { candidate in
            (
                candidate: candidate,
                start: canvasPoint(fromObjectPoint: candidate.start),
                end: canvasPoint(fromObjectPoint: candidate.end)
            )
        }
        let canvasGuides = guides.map { guide in
            (
                guide: guide,
                start: canvasPoint(fromObjectPoint: guide.start),
                end: canvasPoint(fromObjectPoint: guide.end)
            )
        }
        var segments = canvasCandidates.map { candidate in
            AUOSCStyledSegment(
                start: candidate.start,
                end: candidate.end,
                style: candidateStyle(candidate.candidate, activePart: activePart)
            )
        }
        segments.append(contentsOf: canvasGuides.map {
            AUOSCStyledSegment(start: $0.start, end: $0.end, style: guideStyle($0.guide, activePart: activePart))
        })
        let handles = canvasGuides.flatMap {
            let colorOverride: SIMD4<Float>? = $0.guide.enabled ? nil : disabledGuideColor()
            return [
                AUOSCHandle(point: $0.start, part: $0.guide.spec.startPart.rawValue, colorOverride: colorOverride),
                AUOSCHandle(point: $0.end, part: $0.guide.spec.endPart.rawValue, colorOverride: colorOverride)
            ]
        }
        guard !segments.isEmpty || !handles.isEmpty else {
            overlayRenderer.clear(destinationImage: destinationImage)
            return
        }

        overlayRenderer.renderStyledSegments(
            segments,
            handles: handles,
            activePart: activePart,
            destinationImage: destinationImage,
            destinationSize: AUSize(width: max(1.0, Double(width)), height: max(1.0, Double(height))),
            canvasFrame: objectCanvasFrame(),
            coordinateSpace: .canvasFramePixels
        )
    }

    @objc(hitTestOSCAtMousePositionX:mousePositionY:activePart:atTime:)
    func hitTestOSC(atMousePositionX mousePositionX: Double, mousePositionY: Double, activePart: UnsafeMutablePointer<Int>?, at time: CMTime) {
        let paramAPI = parameterRetrievalAPI()
        let mouse = AUPoint(x: mousePositionX, y: mousePositionY)
        activePart?.pointee = UprightOSCPart.none.rawValue
        guard uprightEditMode(at: time, paramAPI: paramAPI) else {
            return
        }

        let correctionMode = uprightCorrectionMode(at: time, paramAPI: paramAPI)
        let controlMode = uprightControlMode(at: time, paramAPI: paramAPI)

        guard controlMode != .automatic else {
            return
        }

        if controlMode == .manual {
            let guides = manualGuides(at: time, paramAPI: paramAPI, correctionMode: correctionMode)
            for guide in guides {
                let start = canvasPoint(fromObjectPoint: guide.start)
                let end = canvasPoint(fromObjectPoint: guide.end)
                let handles = [
                    AUOSCHandle(point: start, part: guide.spec.startPart.rawValue),
                    AUOSCHandle(point: end, part: guide.spec.endPart.rawValue)
                ]
                for handle in handles {
                    let dx = mouse.x - handle.point.x
                    let dy = mouse.y - handle.point.y
                    if hypot(dx, dy) <= 12.0 {
                        activePart?.pointee = handle.part
                        return
                    }
                }

                if distance(from: mouse, toSegmentStart: start, end: end) <= 8.0 {
                    activePart?.pointee = guide.spec.linePart.rawValue
                    return
                }
            }
            return
        }

        let candidates = AnyUprightUprightCandidates.displayCandidates(
            from: uprightCandidateLines(at: time, paramAPI: paramAPI),
            controlMode: controlMode,
            correctionMode: correctionMode
        )
        for candidate in candidates {
            let start = canvasPoint(fromObjectPoint: candidate.start)
            let end = canvasPoint(fromObjectPoint: candidate.end)
            if distance(from: mouse, toSegmentStart: start, end: end) <= 8.0 {
                activePart?.pointee = candidate.spec.linePart
                return
            }
        }
    }

    @objc(mouseDownAtPositionX:positionY:activePart:modifiers:forceUpdate:atTime:)
    func mouseDown(atPositionX mousePositionX: Double, positionY mousePositionY: Double, activePart: Int, modifiers: FxModifierKeys, forceUpdate: UnsafeMutablePointer<ObjCBool>?, at time: CMTime) {
        let paramAPI = parameterRetrievalAPI()
        let correctionMode = uprightCorrectionMode(at: time, paramAPI: paramAPI)
        let controlMode = uprightControlMode(at: time, paramAPI: paramAPI)
        guard uprightEditMode(at: time, paramAPI: paramAPI),
              let settingAPI = parameterSettingAPI() else {
            forceUpdate?.pointee = false
            return
        }

        if controlMode == .manual,
           let part = UprightOSCPart(rawValue: activePart),
           let spec = guideSpec(forLinePart: part) {
            let guides = manualGuides(at: time, paramAPI: paramAPI, correctionMode: correctionMode)
            let current = guides.first { $0.spec.linePart == part }?.enabled ?? true
            let next = !current
            settingAPI.setBoolValue(next, toParameter: spec.enabled.rawValue, at: time)
            writeGuidedCorrection(
                from: guides.map { guide in
                    guard guide.spec.linePart == part else {
                        return guide
                    }
                    return UprightGuideLine(spec: guide.spec, enabled: next, orientation: guide.orientation, start: guide.start, end: guide.end)
                },
                correctionMode: correctionMode,
                settingAPI: settingAPI,
                time: time
            )
            forceUpdate?.pointee = true
            return
        }

        if controlMode == .semiAutomatic,
           let candidateIndex = AnyUprightUprightCandidates.candidateIndex(for: activePart) {
            let candidates = AnyUprightUprightCandidates.displayCandidates(
                from: uprightCandidateLines(at: time, paramAPI: paramAPI),
                controlMode: controlMode,
                correctionMode: correctionMode
            )
            if let candidate = candidates.first(where: { $0.spec.linePart == activePart }) {
                let selected = AnyUprightUprightCandidates.selectionValueAfterToggling(candidate, within: candidates, correctionMode: correctionMode)
                settingAPI.setBoolValue(selected, toParameter: AnyUprightUprightCandidates.specs[candidateIndex].selected, at: time)
                writeSelectedCandidateCorrection(
                    from: candidates.map { existing in
                        guard existing.spec.linePart == candidate.spec.linePart else {
                            return existing
                        }
                        return UprightCandidateLine(
                            spec: existing.spec,
                            selected: selected,
                            orientation: existing.orientation,
                            start: existing.start,
                            end: existing.end,
                            score: existing.score
                        )
                    },
                    correctionMode: correctionMode,
                    settingAPI: settingAPI,
                    time: time
                )
            }
        }
        forceUpdate?.pointee = true
    }

    @objc(mouseDraggedAtPositionX:positionY:activePart:modifiers:forceUpdate:atTime:)
    func mouseDragged(atPositionX mousePositionX: Double, positionY mousePositionY: Double, activePart: Int, modifiers: FxModifierKeys, forceUpdate: UnsafeMutablePointer<ObjCBool>?, at time: CMTime) {
        let paramAPI = parameterRetrievalAPI()
        let correctionMode = uprightCorrectionMode(at: time, paramAPI: paramAPI)
        guard uprightEditMode(at: time, paramAPI: paramAPI),
              uprightControlMode(at: time, paramAPI: paramAPI) == .manual else {
            forceUpdate?.pointee = false
            return
        }

        guard let part = UprightOSCPart(rawValue: activePart),
              let endpoint = endpointParameter(for: part),
              let settingAPI = parameterSettingAPI() else {
            forceUpdate?.pointee = false
            return
        }

        let objectPoint = objectPoint(fromCanvasPoint: AUPoint(x: mousePositionX, y: mousePositionY))
        settingAPI.setXValue(objectPoint.x, yValue: objectPoint.y, toParameter: endpoint.rawValue, at: time)
        let guides = manualGuides(at: time, paramAPI: paramAPI, correctionMode: correctionMode).map { guide in
            guard guide.spec.start == endpoint || guide.spec.end == endpoint else {
                return guide
            }

            if guide.spec.start == endpoint {
                return UprightGuideLine(spec: guide.spec, enabled: guide.enabled, orientation: guide.orientation, start: objectPoint, end: guide.end)
            }
            return UprightGuideLine(spec: guide.spec, enabled: guide.enabled, orientation: guide.orientation, start: guide.start, end: objectPoint)
        }
        writeGuidedCorrection(from: guides, correctionMode: correctionMode, settingAPI: settingAPI, time: time)
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

    private func guideStyle(_ guide: UprightGuideLine, activePart: Int) -> AUOSCOverlayStyle {
        var style = AUOSCOverlayStyle()
        if !guide.enabled {
            style.lineColor = disabledGuideColor()
            style.handleColor = disabledGuideColor()
        }
        if guide.spec.linePart.rawValue == activePart
            || guide.spec.startPart.rawValue == activePart
            || guide.spec.endPart.rawValue == activePart {
            style.lineColor = style.activeHandleColor
        }
        return style
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

    private func disabledGuideColor() -> SIMD4<Float> {
        SIMD4<Float>(0.45, 0.45, 0.45, 0.8)
    }

    private func manualGuides(at time: CMTime, paramAPI: FxParameterRetrievalAPI_v6?, correctionMode: UprightCorrectionMode) -> [UprightGuideLine] {
        uprightGuideLines(at: time, paramAPI: paramAPI, includeDisabled: true).filter { guide in
            switch guide.orientation {
            case .vertical:
                return correctionMode.includesVertical
            case .horizontal:
                return correctionMode.includesHorizontal
            }
        }
    }

    private func writeGuidedCorrection(from guides: [UprightGuideLine], correctionMode: UprightCorrectionMode, settingAPI: FxParameterSettingAPI_v5, time: CMTime) {
        let verticalLines = guides
            .filter { $0.enabled && $0.orientation == .vertical }
            .map { imageLine(from: $0, size: AUSize(width: 1.0, height: 1.0)) }
        let horizontalLines = guides
            .filter { $0.enabled && $0.orientation == .horizontal }
            .map { imageLine(from: $0, size: AUSize(width: 1.0, height: 1.0)) }
        writeUprightCorrection(
            verticalLines: verticalLines,
            horizontalLines: horizontalLines,
            correctionMode: correctionMode,
            settingAPI: settingAPI,
            time: time
        )
    }

    private func writeSelectedCandidateCorrection(from candidates: [UprightCandidateLine], correctionMode: UprightCorrectionMode, settingAPI: FxParameterSettingAPI_v5, time: CMTime) {
        let verticalLines = AnyUprightUprightCandidates.selectedImageLines(from: candidates, orientation: .vertical)
        let horizontalLines = AnyUprightUprightCandidates.selectedImageLines(from: candidates, orientation: .horizontal)
        writeUprightCorrection(
            verticalLines: verticalLines,
            horizontalLines: horizontalLines,
            correctionMode: correctionMode,
            settingAPI: settingAPI,
            time: time
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

    private func distance(from point: AUPoint, toSegmentStart start: AUPoint, end: AUPoint) -> Double {
        let vx = end.x - start.x
        let vy = end.y - start.y
        let lengthSquared = vx * vx + vy * vy
        guard lengthSquared > 0.0 else {
            return hypot(point.x - start.x, point.y - start.y)
        }

        let t = max(0.0, min(1.0, ((point.x - start.x) * vx + (point.y - start.y) * vy) / lengthSquared))
        let closest = AUPoint(x: start.x + t * vx, y: start.y + t * vy)
        return hypot(point.x - closest.x, point.y - closest.y)
    }
}
