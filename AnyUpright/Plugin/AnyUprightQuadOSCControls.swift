//
//  AnyUprightQuadOSCControls.swift
//  AnyUpright
//

import Foundation
import AppKit
import CoreImage
import IOSurface
import Vision

@objc(AnyUprightQuadManualOSCPlugIn)
class AnyUprightQuadManualOSCPlugIn: AnyUprightOSCPlugIn, FxOnScreenControl_v4 {
    private struct SharedSurfaceState {
        static let lock = NSLock()
        static var surfaceSize = AUSize(width: 1.0, height: 1.0)
        static var outputSize = AUSize(width: 1920.0, height: 1080.0)
    }

    private let overlayRenderer = AnyUprightOSCOverlayRenderer()
    private let sourceQuadRawCanvasHitPadding = 24.0
    private let dragStateLock = NSLock()
    private let hoverStateLock = NSLock()
    private var dragState: QuadOSCDragState?
    private var hoverPart: QuadOSCPart = .none
    var debugDrawSequence = 0

    required init?(apiManager: PROAPIAccessing) {
        super.init(apiManager: apiManager)
    }

    var fixedQuadMode: AUQuadTransformMode {
        .sourceQuad
    }

    @objc(drawingCoordinates)
    func drawingCoordinates() -> FxDrawingCoordinates {
        return FxDrawingCoordinates(kFxDrawingCoordinates_CANVAS)
    }

    @objc(drawOSCWithWidth:height:activePart:destinationImage:atTime:)
    func drawOSC(withWidth width: Int, height: Int, activePart: Int, destinationImage: FxImageTile, at time: CMTime) {
        let state = quadParameterState(at: time, paramAPI: parameterRetrievalAPI(), fixedMode: fixedQuadMode)
        let mode = quadMode(from: state)
        guard shouldEnableQuadOSCControls(from: state, mode: mode) else {
            overlayRenderer.clear(destinationImage: destinationImage)
            return
        }

        updateLastSurfaceSize(from: destinationImage, fallback: AUSize(width: Double(width), height: Double(height)))
        let outputSize = AUSize(width: max(1.0, Double(width)), height: max(1.0, Double(height)))
        if mode == .outputCorners {
            renderOutputCornersOSC(from: state, outputSize: outputSize, destinationImage: destinationImage)
            return
        }

        let objectSize = objectPixelSizeForOSC(defaultSize: outputSize)
        let geometry = hitGeometry(from: state, size: objectSize, mode: mode)
        let quad = geometry.rawCanvasQuad
        let canvasFrame = objectCanvasFrame()
        let displayPart = currentDisplayPart(hostActivePart: activePart)
        let debugSequence = nextDebugDrawSequence()
        debugCanvasMetrics(label: "draw-source-entry seq=\(debugSequence) part=\(displayPart.rawValue) host=\(activePart)", width: width, height: height, destinationImage: destinationImage, quad: quad, canvasFrame: canvasFrame)
        let handles = [
            AUOSCHandle(point: quad[0], part: QuadOSCPart.topLeft.rawValue),
            AUOSCHandle(point: quad[1], part: QuadOSCPart.topRight.rawValue),
            AUOSCHandle(point: quad[2], part: QuadOSCPart.bottomRight.rawValue),
            AUOSCHandle(point: quad[3], part: QuadOSCPart.bottomLeft.rawValue)
        ]
        debugSourceQuadDrawMapping(
            sequence: debugSequence,
            width: width,
            height: height,
            destinationImage: destinationImage,
            outputSize: outputSize,
            objectSize: objectSize,
            quad: quad,
            objectCanvasQuad: geometry.quad,
            canvasFrame: canvasFrame
        )

        overlayRenderer.renderStyledSegments(
            sourceQuadOverlaySegments(for: displayPart, quad: quad),
            handles: handles,
            activePart: displayPart.rawValue,
            destinationImage: destinationImage,
            destinationSize: outputSize,
            canvasFrame: canvasFrame,
            coordinateSpace: .canvasFramePixels,
            handleStyle: sourceQuadOverlayStyle(),
            debugLog: { [weak self] message in
                self?.debugLog("draw-source seq=\(debugSequence) \(message)")
            }
        )
    }

    @objc(hitTestOSCAtMousePositionX:mousePositionY:activePart:atTime:)
    func hitTestOSC(atMousePositionX mousePositionX: Double, mousePositionY: Double, activePart: UnsafeMutablePointer<Int>?, at time: CMTime) {
        let state = quadParameterState(at: time, paramAPI: parameterRetrievalAPI(), fixedMode: fixedQuadMode)
        let mode = quadMode(from: state)
        guard shouldEnableQuadOSCControls(from: state, mode: mode) else {
            activePart?.pointee = QuadOSCPart.none.rawValue
            return
        }

        let size = objectPixelSizeForOSC()
        let geometry = hitGeometry(from: state, size: size, mode: mode)
        let canvasFrame = objectCanvasFrame()
        let eventPoint = AUPoint(x: mousePositionX, y: mousePositionY)
        debugCanvasMetrics(label: "hit", eventPoint: eventPoint, quad: geometry.rawCanvasQuad, canvasFrame: canvasFrame)
        let hit = hitTestPart(
            forEventPoint: eventPoint,
            handles: geometry.handles,
            quad: geometry.quad,
            rawCanvasHandles: geometry.rawCanvasHandles,
            rawCanvasQuad: geometry.rawCanvasQuad,
            useRawCanvasHitLayer: geometry.usesRawCanvasHitLayer,
            canvasFrame: canvasFrame,
            rawCanvasHitPadding: sourceQuadRawCanvasHitPadding,
            preferredMode: nil
        )
        let part = hit?.part.rawValue ?? QuadOSCPart.none.rawValue
        activePart?.pointee = part
    }

    @objc(mouseDownAtPositionX:positionY:activePart:modifiers:forceUpdate:atTime:)
    func mouseDown(atPositionX mousePositionX: Double, positionY mousePositionY: Double, activePart: Int, modifiers: FxModifierKeys, forceUpdate: UnsafeMutablePointer<ObjCBool>?, at time: CMTime) {
        setHoverPart(.none, forceUpdate: nil)
        let state = quadParameterState(at: time, paramAPI: parameterRetrievalAPI(), fixedMode: fixedQuadMode)
        let mode = quadMode(from: state)
        let size = objectPixelSizeForOSC()
        let geometry = hitGeometry(from: state, size: size, mode: mode)
        let canvasFrame = objectCanvasFrame()
        let eventPoint = AUPoint(x: mousePositionX, y: mousePositionY)
        let resolvedEvent = hitTestPart(
            forEventPoint: eventPoint,
            handles: geometry.handles,
            quad: geometry.quad,
            rawCanvasHandles: geometry.rawCanvasHandles,
            rawCanvasQuad: geometry.rawCanvasQuad,
            useRawCanvasHitLayer: geometry.usesRawCanvasHitLayer,
            canvasFrame: canvasFrame,
            rawCanvasHitPadding: sourceQuadRawCanvasHitPadding,
            preferredMode: nil
        )
        let resolvedCanvasPoint = resolvedEvent?.resolution
            ?? resolvedCanvasPoint(
                fromEventPoint: eventPoint,
                canvasFrame: canvasFrame,
                rawCanvasQuad: geometry.rawCanvasQuad,
                rawCanvasHitPadding: sourceQuadRawCanvasHitPadding,
                preferredMode: nil
            )

        let resolvedPartRaw = resolveOSCDragPart(
            hostActivePart: activePart,
            localHitPart: resolvedEvent?.part.rawValue,
            nonePart: QuadOSCPart.none.rawValue
        )
        let resolvedPart = resolvedPartRaw.flatMap(QuadOSCPart.init(rawValue:))
        debugOSCEventResolution(
            label: "mouse-down",
            eventPoint: eventPoint,
            resolved: resolvedCanvasPoint,
            part: resolvedPart,
            mode: mode,
            size: size
        )
        guard shouldEnableQuadOSCControls(from: state, mode: mode),
              let resolvedPart else {
            setDragState(nil)
            forceUpdate?.pointee = false
            return
        }

        setDragState(QuadOSCDragState(part: resolvedPart, lastCanvasPoint: resolvedCanvasPoint.canvasPoint, eventCoordinateMode: resolvedCanvasPoint.coordinateMode))
        forceUpdate?.pointee = true
    }

    @objc(mouseDraggedAtPositionX:positionY:activePart:modifiers:forceUpdate:atTime:)
    func mouseDragged(atPositionX mousePositionX: Double, positionY mousePositionY: Double, activePart: Int, modifiers: FxModifierKeys, forceUpdate: UnsafeMutablePointer<ObjCBool>?, at time: CMTime) {
        let state = quadParameterState(at: time, paramAPI: parameterRetrievalAPI(), fixedMode: fixedQuadMode)
        let mode = quadMode(from: state)
        let storedState = currentDragState()
        let part = validDragPart(from: activePart) ?? storedState?.part

        guard shouldEnableQuadOSCControls(from: state, mode: mode),
              let part,
              let settingAPI = parameterSettingAPI() else {
            forceUpdate?.pointee = false
            return
        }

        let size = objectPixelSizeForOSC()
        let geometry = hitGeometry(from: state, size: size, mode: mode)
        let eventPoint = AUPoint(x: mousePositionX, y: mousePositionY)
        let resolved = resolvedCanvasPoint(
            fromEventPoint: eventPoint,
            canvasFrame: objectCanvasFrame(),
            rawCanvasQuad: geometry.rawCanvasQuad,
            rawCanvasHitPadding: sourceQuadRawCanvasHitPadding,
            preferredMode: storedState?.eventCoordinateMode
        )
        let canvasPoint = resolved.canvasPoint
        let draggedObjectPoint = dragObjectPoint(from: resolved, mode: mode, sourceSize: size)
        debugOSCEventResolution(
            label: "mouse-drag",
            eventPoint: eventPoint,
            resolved: resolved,
            part: part,
            mode: mode,
            size: size
        )
        if part == .quad, let previousCanvasPoint = storedState?.lastCanvasPoint {
            let previousResolution = QuadOSCEventResolution(canvasPoint: previousCanvasPoint, coordinateMode: storedState?.eventCoordinateMode ?? resolved.coordinateMode)
            let previousDragPoint = dragObjectPoint(from: previousResolution, mode: mode, sourceSize: size)
            let pixelDelta = AUPoint(
                x: (draggedObjectPoint.x - previousDragPoint.x) * size.width,
                y: (draggedObjectPoint.y - previousDragPoint.y) * size.height
            )
            debugOSCDragDelta(label: "mouse-drag-quad", previous: previousResolution, current: resolved, previousObject: previousDragPoint, currentObject: draggedObjectPoint, pixelDelta: pixelDelta, size: size)
            translateCorners(
                from: state,
                pixelDelta: pixelDelta,
                corners: [.topLeft, .topRight, .bottomRight, .bottomLeft],
                mode: mode,
                size: size,
                settingAPI: settingAPI,
                time: time
            )
            setDragState(QuadOSCDragState(part: part, lastCanvasPoint: canvasPoint, eventCoordinateMode: storedState?.eventCoordinateMode ?? resolved.coordinateMode))
            forceUpdate?.pointee = true
            return
        }

        if let edgeCorners = corners(forEdgePart: part), let previousCanvasPoint = storedState?.lastCanvasPoint {
            let previousResolution = QuadOSCEventResolution(canvasPoint: previousCanvasPoint, coordinateMode: storedState?.eventCoordinateMode ?? resolved.coordinateMode)
            let previousDragPoint = dragObjectPoint(from: previousResolution, mode: mode, sourceSize: size)
            let pixelDelta = AUPoint(
                x: (draggedObjectPoint.x - previousDragPoint.x) * size.width,
                y: (draggedObjectPoint.y - previousDragPoint.y) * size.height
            )
            debugOSCDragDelta(label: "mouse-drag-edge", previous: previousResolution, current: resolved, previousObject: previousDragPoint, currentObject: draggedObjectPoint, pixelDelta: pixelDelta, size: size)
            translateCorners(
                from: state,
                pixelDelta: pixelDelta,
                corners: edgeCorners,
                mode: mode,
                size: size,
                settingAPI: settingAPI,
                time: time
            )
            setDragState(QuadOSCDragState(part: part, lastCanvasPoint: canvasPoint, eventCoordinateMode: storedState?.eventCoordinateMode ?? resolved.coordinateMode))
            forceUpdate?.pointee = true
            return
        }

        setDragState(QuadOSCDragState(part: part, lastCanvasPoint: canvasPoint, eventCoordinateMode: storedState?.eventCoordinateMode ?? resolved.coordinateMode))
        setCorner(draggedObjectPoint, part: part, mode: mode, offsets: quadCornerOffsets(from: state), size: size, settingAPI: settingAPI, time: time)
        forceUpdate?.pointee = true
    }

    @objc(mouseUpAtPositionX:positionY:activePart:modifiers:forceUpdate:atTime:)
    func mouseUp(atPositionX mousePositionX: Double, positionY mousePositionY: Double, activePart: Int, modifiers: FxModifierKeys, forceUpdate: UnsafeMutablePointer<ObjCBool>?, at time: CMTime) {
        setDragState(nil)
        let eventPoint = AUPoint(x: mousePositionX, y: mousePositionY)
        updateHoverPart(forEventPoint: eventPoint, at: time, forceUpdate: forceUpdate)
        forceUpdate?.pointee = true
    }

    @objc(mouseEnteredAtPositionX:positionY:modifiers:forceUpdate:atTime:)
    func mouseEntered(atPositionX mousePositionX: Double, positionY mousePositionY: Double, modifiers: FxModifierKeys, forceUpdate: UnsafeMutablePointer<ObjCBool>?, at time: CMTime) {
        let eventPoint = AUPoint(x: mousePositionX, y: mousePositionY)
        updateHoverPart(forEventPoint: eventPoint, at: time, forceUpdate: forceUpdate)
    }

    @objc(mouseMovedAtPositionX:positionY:activePart:modifiers:forceUpdate:atTime:)
    func mouseMoved(atPositionX mousePositionX: Double, positionY mousePositionY: Double, activePart: Int, modifiers: FxModifierKeys, forceUpdate: UnsafeMutablePointer<ObjCBool>?, at time: CMTime) {
        let eventPoint = AUPoint(x: mousePositionX, y: mousePositionY)
        let hoverPart = updateHoverPart(forEventPoint: eventPoint, at: time, forceUpdate: forceUpdate)
        if hoverPart != .none || validDragPart(from: activePart) != nil {
            setCursor(NSCursor.pointingHand)
        } else {
            setCursor(NSCursor.arrow)
        }
    }

    @objc(mouseExitedAtPositionX:positionY:modifiers:forceUpdate:atTime:)
    func mouseExited(atPositionX mousePositionX: Double, positionY mousePositionY: Double, modifiers: FxModifierKeys, forceUpdate: UnsafeMutablePointer<ObjCBool>?, at time: CMTime) {
        setCursor(NSCursor.arrow)
        setHoverPart(.none, forceUpdate: forceUpdate)
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


    private func renderOutputCornersOSC(from state: AnyUprightParameterState, outputSize: AUSize, destinationImage: FxImageTile) {
        let objectPoints = quadObjectPoints(from: state, size: objectPixelSizeForOSC(defaultSize: outputSize), mode: .outputCorners)
        let canvasPoints = quadCanvasPoints(from: objectPoints)
        let handles = [
            AUOSCHandle(point: canvasPoints.topLeft, part: QuadOSCPart.topLeft.rawValue),
            AUOSCHandle(point: canvasPoints.topRight, part: QuadOSCPart.topRight.rawValue),
            AUOSCHandle(point: canvasPoints.bottomRight, part: QuadOSCPart.bottomRight.rawValue),
            AUOSCHandle(point: canvasPoints.bottomLeft, part: QuadOSCPart.bottomLeft.rawValue)
        ]
        let displayPart = currentDisplayPart()
        overlayRenderer.renderQuad(
            points: [canvasPoints.topLeft, canvasPoints.topRight, canvasPoints.bottomRight, canvasPoints.bottomLeft],
            handles: handles,
            activePart: displayPart.rawValue,
            destinationImage: destinationImage,
            destinationSize: outputSize,
            canvasFrame: objectCanvasFrame(),
            coordinateSpace: .pixels
        )
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

    private func currentHoverPart() -> QuadOSCPart {
        hoverStateLock.lock()
        let part = hoverPart
        hoverStateLock.unlock()
        return part
    }

    private func currentDisplayPart(hostActivePart: Int = QuadOSCPart.none.rawValue) -> QuadOSCPart {
        let hoverPart = currentHoverPart()
        let rawDisplayPart = resolveOSCDisplayPart(
            hostActivePart: hostActivePart,
            hoverPart: hoverPart.rawValue,
            dragPart: currentDragState()?.part.rawValue,
            nonePart: QuadOSCPart.none.rawValue
        )
        return QuadOSCPart(rawValue: rawDisplayPart) ?? .none
    }

    private func updateLastSurfaceSize(from image: FxImageTile, fallback: AUSize) {
        let width = Double(image.ioSurface.map { IOSurfaceGetWidth($0) } ?? Int(max(1.0, fallback.width)))
        let height = Double(image.ioSurface.map { IOSurfaceGetHeight($0) } ?? Int(max(1.0, fallback.height)))

        SharedSurfaceState.lock.lock()
        SharedSurfaceState.surfaceSize = AUSize(width: max(1.0, width), height: max(1.0, height))
        SharedSurfaceState.outputSize = AUSize(width: max(1.0, fallback.width), height: max(1.0, fallback.height))
        SharedSurfaceState.lock.unlock()
    }

    func currentSurfaceSize() -> AUSize {
        SharedSurfaceState.lock.lock()
        let size = SharedSurfaceState.surfaceSize
        SharedSurfaceState.lock.unlock()
        return size
    }

    @discardableResult
    private func updateHoverPart(forEventPoint eventPoint: AUPoint, at time: CMTime, forceUpdate: UnsafeMutablePointer<ObjCBool>?) -> QuadOSCPart {
        let state = quadParameterState(at: time, paramAPI: parameterRetrievalAPI(), fixedMode: fixedQuadMode)
        let mode = quadMode(from: state)
        guard shouldEnableQuadOSCControls(from: state, mode: mode) else {
            setHoverPart(.none, forceUpdate: forceUpdate)
            return .none
        }

        let size = objectPixelSizeForOSC()
        let geometry = hitGeometry(from: state, size: size, mode: mode)
        let canvasFrame = objectCanvasFrame()
        debugCanvasMetrics(label: "hover", eventPoint: eventPoint, quad: geometry.rawCanvasQuad, canvasFrame: canvasFrame)
        let hit = hitTestPart(
            forEventPoint: eventPoint,
            handles: geometry.handles,
            quad: geometry.quad,
            rawCanvasHandles: geometry.rawCanvasHandles,
            rawCanvasQuad: geometry.rawCanvasQuad,
            useRawCanvasHitLayer: geometry.usesRawCanvasHitLayer,
            canvasFrame: canvasFrame,
            rawCanvasHitPadding: sourceQuadRawCanvasHitPadding,
            preferredMode: currentDragState()?.eventCoordinateMode
        )
        let part = hit?.part ?? .none
        setHoverPart(part, forceUpdate: forceUpdate)
        return part
    }

    private func setHoverPart(_ part: QuadOSCPart, forceUpdate: UnsafeMutablePointer<ObjCBool>?) {
        hoverStateLock.lock()
        let changed = hoverPart != part
        hoverPart = part
        hoverStateLock.unlock()
        forceUpdate?.pointee = ObjCBool(changed)
    }

    private func sourceQuadOverlayStyle() -> AUOSCOverlayStyle {
        var style = AUOSCOverlayStyle()
        style.lineColor = SIMD4<Float>(1.0, 1.0, 1.0, 1.0)
        style.shadowColor = SIMD4<Float>(0.0, 0.0, 0.0, 0.72)
        style.handleColor = SIMD4<Float>(0.0, 0.55, 1.0, 1.0)
        style.activeHandleColor = SIMD4<Float>(1.0, 0.85, 0.0, 1.0)
        style.lineThickness = 3.0
        style.handleRadius = 15.0
        style.handleShape = .circle
        return style
    }

    private func hoverOverlayStyle() -> AUOSCOverlayStyle {
        var style = AUOSCOverlayStyle()
        style.lineColor = SIMD4<Float>(1.0, 0.85, 0.0, 1.0)
        style.shadowColor = SIMD4<Float>(0.0, 0.0, 0.0, 0.72)
        style.handleColor = SIMD4<Float>(1.0, 0.85, 0.0, 1.0)
        style.activeHandleColor = SIMD4<Float>(1.0, 0.85, 0.0, 1.0)
        style.lineThickness = 4.0
        style.handleRadius = 15.0
        style.handleShape = .circle
        return style
    }

    private func sourceQuadOverlaySegments(for part: QuadOSCPart, quad: [AUPoint]) -> [AUOSCStyledSegment] {
        guard quad.count == 4 else {
            return []
        }

        var baseStyle = sourceQuadOverlayStyle()
        baseStyle.handleRadius = 0.0
        let top = AUOSCStyledSegment(start: quad[0], end: quad[1], style: baseStyle)
        let right = AUOSCStyledSegment(start: quad[1], end: quad[2], style: baseStyle)
        let bottom = AUOSCStyledSegment(start: quad[3], end: quad[2], style: baseStyle)
        let left = AUOSCStyledSegment(start: quad[0], end: quad[3], style: baseStyle)
        let base = [top, right, bottom, left]

        var hoverStyle = hoverOverlayStyle()
        hoverStyle.handleRadius = 0.0
        let hoverTop = AUOSCStyledSegment(start: quad[0], end: quad[1], style: hoverStyle)
        let hoverRight = AUOSCStyledSegment(start: quad[1], end: quad[2], style: hoverStyle)
        let hoverBottom = AUOSCStyledSegment(start: quad[3], end: quad[2], style: hoverStyle)
        let hoverLeft = AUOSCStyledSegment(start: quad[0], end: quad[3], style: hoverStyle)

        switch part {
        case .quad:
            return base + [hoverTop, hoverRight, hoverBottom, hoverLeft]
        case .topEdge:
            return base + [hoverTop]
        case .rightEdge:
            return base + [hoverRight]
        case .bottomEdge:
            return base + [hoverBottom]
        case .leftEdge:
            return base + [hoverLeft]
        default:
            return base
        }
    }

}

@objc(AnyUprightQuadOutputCornersOSCPlugIn)
class AnyUprightQuadOutputCornersOSCPlugIn: AnyUprightQuadManualOSCPlugIn {
    override var fixedQuadMode: AUQuadTransformMode {
        .outputCorners
    }
}
