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
        return FxDrawingCoordinates(kFxDrawingCoordinates_OBJECT)
    }

    @objc(drawOSCWithWidth:height:activePart:destinationImage:atTime:)
    func drawOSC(withWidth width: Int, height: Int, activePart: Int, destinationImage: FxImageTile, at time: CMTime) {
        let paramAPI = parameterRetrievalAPI()
        let guides = uprightGuideLines(at: time, paramAPI: paramAPI)
        let chooseFromDetections = uprightChooseFromDetections(at: time, paramAPI: paramAPI)
        let candidateThreshold = uprightCandidateScoreThreshold(at: time, paramAPI: paramAPI)
        let candidates = AnyUprightUprightCandidates.displayCandidates(
            from: uprightCandidateLines(at: time, paramAPI: paramAPI),
            chooseFromDetections: chooseFromDetections,
            threshold: candidateThreshold
        )
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
        let chooseFromDetections = uprightChooseFromDetections(at: time, paramAPI: paramAPI)

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

        guard chooseFromDetections else {
            return
        }

        let candidateThreshold = uprightCandidateScoreThreshold(at: time, paramAPI: paramAPI)
        let candidates = AnyUprightUprightCandidates.displayCandidates(
            from: uprightCandidateLines(at: time, paramAPI: paramAPI),
            chooseFromDetections: true,
            threshold: candidateThreshold
        )
        for candidate in candidates {
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
            let paramAPI = parameterRetrievalAPI()
            let candidates = AnyUprightUprightCandidates.displayCandidates(
                from: uprightCandidateLines(at: time, paramAPI: paramAPI),
                chooseFromDetections: uprightChooseFromDetections(at: time, paramAPI: paramAPI),
                threshold: uprightCandidateScoreThreshold(at: time, paramAPI: paramAPI)
            )
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
