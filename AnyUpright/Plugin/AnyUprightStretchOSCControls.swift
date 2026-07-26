//
//  AnyUprightStretchOSCControls.swift
//  AnyUpright
//

import Foundation
import AppKit
import IOSurface

@objc(AnyUprightInnerStretchOSCPlugIn)
class AnyUprightInnerStretchOSCPlugIn: AnyUprightOSCPlugIn, FxOnScreenControl_v4 {
    private struct SharedSurfaceState {
        static let lock = NSLock()
        static var surfaceSize = AUSize(width: 1.0, height: 1.0)
        static var outputSize = AUSize(width: 1920.0, height: 1080.0)
    }

    private let overlayRenderer = AnyUprightOSCOverlayRenderer()
    private let innerStretchRawCanvasHitPadding = 24.0
    private let dragStateLock = NSLock()
    private let hoverStateLock = NSLock()
    private var dragState: StretchOSCDragState?
    private var hoverPart: StretchOSCPart = .none
    var debugDrawSequence = 0

    required init?(apiManager: PROAPIAccessing) {
        super.init(apiManager: apiManager)
    }

    var fixedStretchMode: AUStretchTransformMode {
        .innerStretch
    }

    @objc(drawingCoordinates)
    func drawingCoordinates() -> FxDrawingCoordinates {
        return FxDrawingCoordinates(kFxDrawingCoordinates_CANVAS)
    }

    @objc(drawOSCWithWidth:height:activePart:destinationImage:atTime:)
    func drawOSC(withWidth width: Int, height: Int, activePart: Int, destinationImage: FxImageTile, at time: CMTime) {
        let paramAPI = parameterRetrievalAPI()
        let state = stretchParameterState(at: time, paramAPI: paramAPI, fixedMode: fixedStretchMode)
        let mode = stretchMode(from: state)
        guard shouldEnableStretchOSCControls(from: state, mode: mode) else {
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
        let stretch = geometry.stretch
        let canvasFrame = objectCanvasFrame()
        let displayPart = currentDisplayPart(hostActivePart: activePart)
        let debugSequence = nextDebugDrawSequence()
        debugCanvasMetrics(label: "draw-source-entry seq=\(debugSequence) part=\(displayPart.rawValue) host=\(activePart)", width: width, height: height, destinationImage: destinationImage, stretch: stretch, canvasFrame: canvasFrame)
        let handles = [
            AUOSCHandle(point: stretch[0], part: StretchOSCPart.topLeft.rawValue),
            AUOSCHandle(point: stretch[1], part: StretchOSCPart.topRight.rawValue),
            AUOSCHandle(point: stretch[2], part: StretchOSCPart.bottomRight.rawValue),
            AUOSCHandle(point: stretch[3], part: StretchOSCPart.bottomLeft.rawValue)
        ]
        debugInnerStretchDrawMapping(
            sequence: debugSequence,
            width: width,
            height: height,
            destinationImage: destinationImage,
            outputSize: outputSize,
            objectSize: objectSize,
            stretch: stretch,
            objectCanvasStretch: geometry.stretch,
            canvasFrame: canvasFrame
        )

        overlayRenderer.renderStyledSegments(
            innerStretchOverlaySegments(for: displayPart, stretch: stretch),
            handles: handles,
            activePart: displayPart.rawValue,
            destinationImage: destinationImage,
            destinationSize: outputSize,
            canvasFrame: canvasFrame,
            coordinateSpace: .canvasFramePixels,
            handleStyle: innerStretchOverlayStyle(),
            debugLog: { [weak self] message in
                self?.debugLog("draw-source seq=\(debugSequence) \(message)")
            }
        )
    }

    @objc(hitTestOSCAtMousePositionX:mousePositionY:activePart:atTime:)
    func hitTestOSC(atMousePositionX mousePositionX: Double, mousePositionY: Double, activePart: UnsafeMutablePointer<Int>?, at time: CMTime) {
        let paramAPI = parameterRetrievalAPI()
        let state = stretchParameterState(at: time, paramAPI: paramAPI, fixedMode: fixedStretchMode)
        let mode = stretchMode(from: state)
        guard shouldEnableStretchOSCControls(from: state, mode: mode) else {
            activePart?.pointee = StretchOSCPart.none.rawValue
            return
        }

        let size = objectPixelSizeForOSC()
        let geometry = hitGeometry(from: state, size: size, mode: mode)
        let canvasFrame = objectCanvasFrame()
        let eventPoint = AUPoint(x: mousePositionX, y: mousePositionY)
        debugCanvasMetrics(label: "hit", eventPoint: eventPoint, stretch: geometry.stretch, canvasFrame: canvasFrame)
        let hit = hitTestPart(
            forEventPoint: eventPoint,
            handles: geometry.handles,
            stretch: geometry.stretch,
            canvasFrame: canvasFrame,
            rawCanvasHitPadding: innerStretchRawCanvasHitPadding,
            preferredMode: nil
        )
        let part = hit?.part.rawValue ?? StretchOSCPart.none.rawValue
        activePart?.pointee = part
    }

    @objc(mouseDownAtPositionX:positionY:activePart:modifiers:forceUpdate:atTime:)
    func mouseDown(atPositionX mousePositionX: Double, positionY mousePositionY: Double, activePart: Int, modifiers: FxModifierKeys, forceUpdate: UnsafeMutablePointer<ObjCBool>?, at time: CMTime) {
        setHoverPart(.none, forceUpdate: nil)
        let paramAPI = parameterRetrievalAPI()
        let state = stretchParameterState(at: time, paramAPI: paramAPI, fixedMode: fixedStretchMode)
        let mode = stretchMode(from: state)
        let size = objectPixelSizeForOSC()
        let geometry = hitGeometry(from: state, size: size, mode: mode)
        let canvasFrame = objectCanvasFrame()
        let eventPoint = AUPoint(x: mousePositionX, y: mousePositionY)
        let resolvedEvent = hitTestPart(
            forEventPoint: eventPoint,
            handles: geometry.handles,
            stretch: geometry.stretch,
            canvasFrame: canvasFrame,
            rawCanvasHitPadding: innerStretchRawCanvasHitPadding,
            preferredMode: nil
        )
        let resolvedCanvasPoint = resolvedEvent?.resolution
            ?? resolvedCanvasPoint(
                fromEventPoint: eventPoint,
                canvasFrame: canvasFrame,
                visibleControlPoints: geometry.stretch,
                rawCanvasHitPadding: innerStretchRawCanvasHitPadding,
                preferredMode: nil
            )

        let resolvedPartRaw = resolveOSCDragPart(
            hostActivePart: activePart,
            localHitPart: resolvedEvent?.part.rawValue,
            nonePart: StretchOSCPart.none.rawValue
        )
        let resolvedPart = resolvedPartRaw.flatMap(StretchOSCPart.init(rawValue:))
        debugLog(
            "mouse-down-parts host=\(activePart) local=\(resolvedEvent?.part.rawValue.description ?? "nil") resolved=\(resolvedPart?.rawValue.description ?? "nil")"
        )
        debugOSCEventResolution(
            label: "mouse-down",
            eventPoint: eventPoint,
            resolved: resolvedCanvasPoint,
            part: resolvedPart,
            mode: mode,
            size: size
        )
        guard shouldEnableStretchOSCControls(from: state, mode: mode),
              let resolvedPart else {
            setDragState(nil)
            forceUpdate?.pointee = false
            return
        }

        setDragState(StretchOSCDragState(part: resolvedPart, lastCanvasPoint: resolvedCanvasPoint.canvasPoint, eventCoordinateMode: resolvedCanvasPoint.coordinateMode))
        forceUpdate?.pointee = true
    }

    @objc(mouseDraggedAtPositionX:positionY:activePart:modifiers:forceUpdate:atTime:)
    func mouseDragged(atPositionX mousePositionX: Double, positionY mousePositionY: Double, activePart: Int, modifiers: FxModifierKeys, forceUpdate: UnsafeMutablePointer<ObjCBool>?, at time: CMTime) {
        let paramAPI = parameterRetrievalAPI()
        let state = stretchParameterState(at: time, paramAPI: paramAPI, fixedMode: fixedStretchMode)
        let mode = stretchMode(from: state)
        let storedState = currentDragState()
        let hostPart = validDragPart(from: activePart)
        let part = hostPart ?? storedState?.part
        debugLog(
            "mouse-drag-parts host=\(activePart) validHost=\(hostPart?.rawValue.description ?? "nil") stored=\(storedState?.part.rawValue.description ?? "nil") selected=\(part?.rawValue.description ?? "nil")"
        )

        guard shouldEnableStretchOSCControls(from: state, mode: mode),
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
            visibleControlPoints: geometry.stretch,
            rawCanvasHitPadding: innerStretchRawCanvasHitPadding,
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
        if part == .stretch, let previousCanvasPoint = storedState?.lastCanvasPoint {
            let previousResolution = StretchOSCEventResolution(canvasPoint: previousCanvasPoint, coordinateMode: storedState?.eventCoordinateMode ?? resolved.coordinateMode)
            let previousDragPoint = dragObjectPoint(from: previousResolution, mode: mode, sourceSize: size)
            let pixelDelta = AUPoint(
                x: (draggedObjectPoint.x - previousDragPoint.x) * size.width,
                y: (draggedObjectPoint.y - previousDragPoint.y) * size.height
            )
            debugOSCDragDelta(label: "mouse-drag-stretch", previous: previousResolution, current: resolved, previousObject: previousDragPoint, currentObject: draggedObjectPoint, pixelDelta: pixelDelta, size: size)
            translateCorners(
                from: state,
                pixelDelta: pixelDelta,
                corners: [.topLeft, .topRight, .bottomRight, .bottomLeft],
                mode: mode,
                size: size,
                settingAPI: settingAPI,
                time: time
            )
            setDragState(StretchOSCDragState(part: part, lastCanvasPoint: canvasPoint, eventCoordinateMode: storedState?.eventCoordinateMode ?? resolved.coordinateMode))
            forceUpdate?.pointee = true
            return
        }

        if let edgeCorners = corners(forEdgePart: part), let previousCanvasPoint = storedState?.lastCanvasPoint {
            let previousResolution = StretchOSCEventResolution(canvasPoint: previousCanvasPoint, coordinateMode: storedState?.eventCoordinateMode ?? resolved.coordinateMode)
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
            setDragState(StretchOSCDragState(part: part, lastCanvasPoint: canvasPoint, eventCoordinateMode: storedState?.eventCoordinateMode ?? resolved.coordinateMode))
            forceUpdate?.pointee = true
            return
        }

        setDragState(StretchOSCDragState(part: part, lastCanvasPoint: canvasPoint, eventCoordinateMode: storedState?.eventCoordinateMode ?? resolved.coordinateMode))
        setCorner(draggedObjectPoint, part: part, mode: mode, offsets: stretchCornerOffsets(from: state), size: size, settingAPI: settingAPI, time: time)
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
        let objectPoints = stretchObjectPoints(from: state, size: objectPixelSizeForOSC(defaultSize: outputSize), mode: .outputCorners)
        let canvasPoints = stretchCanvasPoints(from: objectPoints)
        let handles = [
            AUOSCHandle(point: canvasPoints.topLeft, part: StretchOSCPart.topLeft.rawValue),
            AUOSCHandle(point: canvasPoints.topRight, part: StretchOSCPart.topRight.rawValue),
            AUOSCHandle(point: canvasPoints.bottomRight, part: StretchOSCPart.bottomRight.rawValue),
            AUOSCHandle(point: canvasPoints.bottomLeft, part: StretchOSCPart.bottomLeft.rawValue)
        ]
        let displayPart = currentDisplayPart()
        overlayRenderer.renderStretch(
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

    private func setDragState(_ state: StretchOSCDragState?) {
        dragStateLock.lock()
        dragState = state
        dragStateLock.unlock()
    }

    private func currentDragState() -> StretchOSCDragState? {
        dragStateLock.lock()
        let state = dragState
        dragStateLock.unlock()
        return state
    }

    private func currentHoverPart() -> StretchOSCPart {
        hoverStateLock.lock()
        let part = hoverPart
        hoverStateLock.unlock()
        return part
    }

    private func currentDisplayPart(hostActivePart: Int = StretchOSCPart.none.rawValue) -> StretchOSCPart {
        let hoverPart = currentHoverPart()
        let rawDisplayPart = resolveOSCDisplayPart(
            hostActivePart: hostActivePart,
            hoverPart: hoverPart.rawValue,
            dragPart: currentDragState()?.part.rawValue,
            nonePart: StretchOSCPart.none.rawValue
        )
        return StretchOSCPart(rawValue: rawDisplayPart) ?? .none
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
    private func updateHoverPart(forEventPoint eventPoint: AUPoint, at time: CMTime, forceUpdate: UnsafeMutablePointer<ObjCBool>?) -> StretchOSCPart {
        let state = stretchParameterState(at: time, paramAPI: parameterRetrievalAPI(), fixedMode: fixedStretchMode)
        let mode = stretchMode(from: state)
        guard shouldEnableStretchOSCControls(from: state, mode: mode) else {
            setHoverPart(.none, forceUpdate: forceUpdate)
            return .none
        }

        let size = objectPixelSizeForOSC()
        let geometry = hitGeometry(from: state, size: size, mode: mode)
        let canvasFrame = objectCanvasFrame()
        debugCanvasMetrics(label: "hover", eventPoint: eventPoint, stretch: geometry.stretch, canvasFrame: canvasFrame)
        let hit = hitTestPart(
            forEventPoint: eventPoint,
            handles: geometry.handles,
            stretch: geometry.stretch,
            canvasFrame: canvasFrame,
            rawCanvasHitPadding: innerStretchRawCanvasHitPadding,
            preferredMode: currentDragState()?.eventCoordinateMode
        )
        let part = hit?.part ?? .none
        setHoverPart(part, forceUpdate: forceUpdate)
        return part
    }

    private func setHoverPart(_ part: StretchOSCPart, forceUpdate: UnsafeMutablePointer<ObjCBool>?) {
        hoverStateLock.lock()
        let changed = hoverPart != part
        hoverPart = part
        hoverStateLock.unlock()
        forceUpdate?.pointee = ObjCBool(changed)
    }

    private func innerStretchOverlayStyle() -> AUOSCOverlayStyle {
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

    private func innerStretchOverlaySegments(for part: StretchOSCPart, stretch: [AUPoint]) -> [AUOSCStyledSegment] {
        guard stretch.count == 4 else {
            return []
        }

        var baseStyle = innerStretchOverlayStyle()
        baseStyle.handleRadius = 0.0
        let top = AUOSCStyledSegment(start: stretch[0], end: stretch[1], style: baseStyle)
        let right = AUOSCStyledSegment(start: stretch[1], end: stretch[2], style: baseStyle)
        let bottom = AUOSCStyledSegment(start: stretch[3], end: stretch[2], style: baseStyle)
        let left = AUOSCStyledSegment(start: stretch[0], end: stretch[3], style: baseStyle)
        let base = [top, right, bottom, left]

        var hoverStyle = hoverOverlayStyle()
        hoverStyle.handleRadius = 0.0
        let hoverTop = AUOSCStyledSegment(start: stretch[0], end: stretch[1], style: hoverStyle)
        let hoverRight = AUOSCStyledSegment(start: stretch[1], end: stretch[2], style: hoverStyle)
        let hoverBottom = AUOSCStyledSegment(start: stretch[3], end: stretch[2], style: hoverStyle)
        let hoverLeft = AUOSCStyledSegment(start: stretch[0], end: stretch[3], style: hoverStyle)

        switch part {
        case .stretch:
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

@objc(AnyUprightOuterStretchOSCPlugIn)
class AnyUprightOuterStretchOSCPlugIn: AnyUprightInnerStretchOSCPlugIn {
    override var fixedStretchMode: AUStretchTransformMode {
        .outputCorners
    }
}
