//
//  AnyUprightStretchOSCControls.swift
//  AnyUpright
//

import Foundation
import AppKit
import CoreImage
import IOSurface
import Vision

@objc(AnyUprightInnerStretchOSCPlugIn)
class AnyUprightInnerStretchOSCPlugIn: AnyUprightOSCPlugIn, FxOnScreenControl_v4 {
    private struct SharedSurfaceState {
        static let lock = NSLock()
        static var surfaceSize = AUSize(width: 1.0, height: 1.0)
        static var outputSize = AUSize(width: 1920.0, height: 1080.0)
    }

    private let overlayRenderer = AnyUprightOSCOverlayRenderer()
    private let innerStretchRawCanvasHitPadding = 24.0
    private let detectionCornerHitRadius = 18.0
    private let detectionEdgeHitRadius = 14.0
    private let dragStateLock = NSLock()
    private let hoverStateLock = NSLock()
    private let detectionSelectionLock = NSLock()
    private var dragState: StretchOSCDragState?
    private var hoverPart: StretchOSCPart = .none
    private var detectionSelection = AUStretchDetectionSelectionState()
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
        let stretch = geometry.rawCanvasStretch
        let canvasFrame = objectCanvasFrame()
        let chooseFromDetections = stretchChooseFromDetections(at: time, paramAPI: paramAPI)
        if chooseFromDetections {
            setHoverPart(.none, forceUpdate: nil)
        } else {
            clearDetectionSelection(forceUpdate: nil)
        }
        let displayPart = chooseFromDetections ? StretchOSCPart.none : currentDisplayPart(hostActivePart: activePart)
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

        let detectedEdges = stretchInnerStretchDetectionEdges(at: time, paramAPI: paramAPI)
        let detectedCorners = stretchInnerStretchDetectionCorners(at: time, paramAPI: paramAPI)
        let detectionThreshold = stretchDetectionScoreThreshold(at: time, paramAPI: paramAPI)
        let detectionSegments: [AUOSCStyledSegment]
        if chooseFromDetections {
            let selection = pruneDetectionSelection(edges: detectedEdges, corners: detectedCorners, threshold: detectionThreshold, forceUpdate: nil)
            detectionSegments = sourceDetectionOverlaySegments(
                edges: detectedEdges,
                corners: detectedCorners,
                threshold: detectionThreshold,
                selection: selection
            )
        } else {
            detectionSegments = []
        }
        debugLog("draw-source seq=\(debugSequence) detection choose=\(chooseFromDetections) edges=\(detectedEdges.count) corners=\(detectedCorners.count) threshold=\(detectionThreshold) segments=\(detectionSegments.count)")
        overlayRenderer.renderStyledSegments(
            detectionSegments + innerStretchOverlaySegments(for: displayPart, stretch: stretch),
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
        debugCanvasMetrics(label: "hit", eventPoint: eventPoint, stretch: geometry.rawCanvasStretch, canvasFrame: canvasFrame)
        if mode == .innerStretch, stretchChooseFromDetections(at: time, paramAPI: paramAPI) {
            let threshold = stretchDetectionScoreThreshold(at: time, paramAPI: paramAPI)
            let edges = stretchInnerStretchDetectionEdges(at: time, paramAPI: paramAPI)
            let corners = stretchInnerStretchDetectionCorners(at: time, paramAPI: paramAPI)
            let selection = pruneDetectionSelection(edges: edges, corners: corners, threshold: threshold, forceUpdate: nil)
            let hit = hitTestDetectionPrimitive(
                forEventPoint: eventPoint,
                edges: edges,
                corners: corners,
                threshold: threshold,
                selection: selection,
                canvasFrame: canvasFrame,
                rawCanvasStretch: geometry.rawCanvasStretch,
                preferredMode: nil
            )
            activePart?.pointee = hit.map { detectionPartID(for: $0.primitive) } ?? StretchOSCPart.none.rawValue
            return
        }
        let hit = hitTestPart(
            forEventPoint: eventPoint,
            handles: geometry.handles,
            stretch: geometry.stretch,
            rawCanvasHandles: geometry.rawCanvasHandles,
            rawCanvasStretch: geometry.rawCanvasStretch,
            useRawCanvasHitLayer: geometry.usesRawCanvasHitLayer,
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
        if shouldEnableStretchOSCControls(from: state, mode: mode),
           mode == .innerStretch,
           stretchChooseFromDetections(at: time, paramAPI: paramAPI) {
            setDragState(nil)
            let threshold = stretchDetectionScoreThreshold(at: time, paramAPI: paramAPI)
            let edges = stretchInnerStretchDetectionEdges(at: time, paramAPI: paramAPI)
            let corners = stretchInnerStretchDetectionCorners(at: time, paramAPI: paramAPI)
            let selection = pruneDetectionSelection(edges: edges, corners: corners, threshold: threshold, forceUpdate: nil)
            guard let hit = hitTestDetectionPrimitive(
                forEventPoint: eventPoint,
                edges: edges,
                corners: corners,
                threshold: threshold,
                selection: selection,
                canvasFrame: canvasFrame,
                rawCanvasStretch: geometry.rawCanvasStretch,
                preferredMode: nil
            ) else {
                forceUpdate?.pointee = false
                return
            }

            toggleDetectionSelection(
                hit.primitive,
                edges: edges,
                corners: corners,
                size: size,
                time: time,
                forceUpdate: forceUpdate
            )
            return
        }
        let resolvedEvent = hitTestPart(
            forEventPoint: eventPoint,
            handles: geometry.handles,
            stretch: geometry.stretch,
            rawCanvasHandles: geometry.rawCanvasHandles,
            rawCanvasStretch: geometry.rawCanvasStretch,
            useRawCanvasHitLayer: geometry.usesRawCanvasHitLayer,
            canvasFrame: canvasFrame,
            rawCanvasHitPadding: innerStretchRawCanvasHitPadding,
            preferredMode: nil
        )
        let resolvedCanvasPoint = resolvedEvent?.resolution
            ?? resolvedCanvasPoint(
                fromEventPoint: eventPoint,
                canvasFrame: canvasFrame,
                rawCanvasStretch: geometry.rawCanvasStretch,
                rawCanvasHitPadding: innerStretchRawCanvasHitPadding,
                preferredMode: nil
            )

        let resolvedPartRaw = resolveOSCDragPart(
            hostActivePart: activePart,
            localHitPart: resolvedEvent?.part.rawValue,
            nonePart: StretchOSCPart.none.rawValue
        )
        let resolvedPart = resolvedPartRaw.flatMap(StretchOSCPart.init(rawValue:))
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
        if mode == .innerStretch, stretchChooseFromDetections(at: time, paramAPI: paramAPI) {
            setDragState(nil)
            forceUpdate?.pointee = false
            return
        }
        let storedState = currentDragState()
        let part = validDragPart(from: activePart) ?? storedState?.part

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
            rawCanvasStretch: geometry.rawCanvasStretch,
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
        if isChoosingDetections(at: time) {
            updateDetectionHover(forEventPoint: eventPoint, at: time, forceUpdate: forceUpdate)
            return
        }
        updateHoverPart(forEventPoint: eventPoint, at: time, forceUpdate: forceUpdate)
        forceUpdate?.pointee = true
    }

    @objc(mouseEnteredAtPositionX:positionY:modifiers:forceUpdate:atTime:)
    func mouseEntered(atPositionX mousePositionX: Double, positionY mousePositionY: Double, modifiers: FxModifierKeys, forceUpdate: UnsafeMutablePointer<ObjCBool>?, at time: CMTime) {
        let eventPoint = AUPoint(x: mousePositionX, y: mousePositionY)
        if isChoosingDetections(at: time) {
            updateDetectionHover(forEventPoint: eventPoint, at: time, forceUpdate: forceUpdate)
            return
        }
        updateHoverPart(forEventPoint: eventPoint, at: time, forceUpdate: forceUpdate)
    }

    @objc(mouseMovedAtPositionX:positionY:activePart:modifiers:forceUpdate:atTime:)
    func mouseMoved(atPositionX mousePositionX: Double, positionY mousePositionY: Double, activePart: Int, modifiers: FxModifierKeys, forceUpdate: UnsafeMutablePointer<ObjCBool>?, at time: CMTime) {
        let eventPoint = AUPoint(x: mousePositionX, y: mousePositionY)
        if isChoosingDetections(at: time) {
            let hover = updateDetectionHover(forEventPoint: eventPoint, at: time, forceUpdate: forceUpdate)
            setCursor(hover == nil ? NSCursor.arrow : NSCursor.pointingHand)
            return
        }
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
        setDetectionHover(nil, forceUpdate: forceUpdate)
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

    private func currentDetectionSelection() -> AUStretchDetectionSelectionState {
        detectionSelectionLock.lock()
        let selection = detectionSelection
        detectionSelectionLock.unlock()
        return selection
    }

    private func setDetectionSelection(_ selection: AUStretchDetectionSelectionState, forceUpdate: UnsafeMutablePointer<ObjCBool>?) {
        detectionSelectionLock.lock()
        let changed = detectionSelection != selection
        detectionSelection = selection
        detectionSelectionLock.unlock()
        if changed {
            forceUpdate?.pointee = true
        }
    }

    private func clearDetectionSelection(forceUpdate: UnsafeMutablePointer<ObjCBool>?) {
        var selection = currentDetectionSelection()
        guard !selection.isEmpty || selection.hover != nil else {
            return
        }

        selection.clear()
        setDetectionSelection(selection, forceUpdate: forceUpdate)
    }

    private func setDetectionHover(_ primitive: AUStretchDetectionPrimitiveID?, forceUpdate: UnsafeMutablePointer<ObjCBool>?) {
        var selection = currentDetectionSelection()
        guard selection.hover != primitive else {
            return
        }

        selection.hover = primitive
        setDetectionSelection(selection, forceUpdate: forceUpdate)
    }

    private func isChoosingDetections(at time: CMTime) -> Bool {
        let paramAPI = parameterRetrievalAPI()
        let state = stretchParameterState(at: time, paramAPI: paramAPI, fixedMode: fixedStretchMode)
        let mode = stretchMode(from: state)
        return mode == .innerStretch
            && shouldEnableStretchOSCControls(from: state, mode: mode)
            && stretchChooseFromDetections(at: time, paramAPI: paramAPI)
    }

    private func pruneDetectionSelection(
        edges: [InnerStretchDetectionEdge],
        corners: [InnerStretchDetectionCorner],
        threshold: Double,
        forceUpdate: UnsafeMutablePointer<ObjCBool>?
    ) -> AUStretchDetectionSelectionState {
        let clampedThreshold = min(1.0, max(0.0, threshold))
        let validEdgeIndexes = Set(edges.filter { $0.score >= clampedThreshold }.map(\.index))
        let validCornerIndexes = Set(corners.filter { $0.score >= clampedThreshold }.map(\.index))
        var selection = currentDetectionSelection()

        selection.selectedEdgeIndexes = selection.selectedEdgeIndexes.intersection(validEdgeIndexes)
        selection.selectedCornerIndexes = selection.selectedCornerIndexes.intersection(validCornerIndexes)
        if !selection.selectedCornerIndexes.isEmpty {
            selection.selectedEdgeIndexes.removeAll()
        } else if !selection.selectedEdgeIndexes.isEmpty {
            selection.selectedCornerIndexes.removeAll()
        }

        if let hover = selection.hover {
            switch hover.kind {
            case .corner where !validCornerIndexes.contains(hover.index):
                selection.hover = nil
            case .edge where !validEdgeIndexes.contains(hover.index):
                selection.hover = nil
            default:
                break
            }
        }

        setDetectionSelection(selection, forceUpdate: forceUpdate)
        return selection
    }

    @discardableResult
    private func updateDetectionHover(forEventPoint eventPoint: AUPoint, at time: CMTime, forceUpdate: UnsafeMutablePointer<ObjCBool>?) -> AUStretchDetectionPrimitiveID? {
        let paramAPI = parameterRetrievalAPI()
        let state = stretchParameterState(at: time, paramAPI: paramAPI, fixedMode: fixedStretchMode)
        let mode = stretchMode(from: state)
        guard mode == .innerStretch,
              shouldEnableStretchOSCControls(from: state, mode: mode),
              stretchChooseFromDetections(at: time, paramAPI: paramAPI) else {
            clearDetectionSelection(forceUpdate: forceUpdate)
            return nil
        }

        let size = objectPixelSizeForOSC()
        let geometry = hitGeometry(from: state, size: size, mode: mode)
        let threshold = stretchDetectionScoreThreshold(at: time, paramAPI: paramAPI)
        let edges = stretchInnerStretchDetectionEdges(at: time, paramAPI: paramAPI)
        let corners = stretchInnerStretchDetectionCorners(at: time, paramAPI: paramAPI)
        let selection = pruneDetectionSelection(edges: edges, corners: corners, threshold: threshold, forceUpdate: forceUpdate)
        let hit = hitTestDetectionPrimitive(
            forEventPoint: eventPoint,
            edges: edges,
            corners: corners,
            threshold: threshold,
            selection: selection,
            canvasFrame: objectCanvasFrame(),
            rawCanvasStretch: geometry.rawCanvasStretch,
            preferredMode: currentDragState()?.eventCoordinateMode
        )
        setDetectionHover(hit?.primitive, forceUpdate: forceUpdate)
        return hit?.primitive
    }

    private func hitTestDetectionPrimitive(
        forEventPoint eventPoint: AUPoint,
        edges: [InnerStretchDetectionEdge],
        corners: [InnerStretchDetectionCorner],
        threshold: Double,
        selection: AUStretchDetectionSelectionState,
        canvasFrame: [AUPoint],
        rawCanvasStretch: [AUPoint],
        preferredMode: StretchOSCEventCoordinateMode?
    ) -> (primitive: AUStretchDetectionPrimitiveID, resolution: StretchOSCEventResolution)? {
        let resolutions = eventResolutions(
            fromEventPoint: eventPoint,
            canvasFrame: canvasFrame,
            rawCanvasStretch: rawCanvasStretch,
            rawCanvasHitPadding: innerStretchRawCanvasHitPadding,
            preferredMode: preferredMode
        )
        let clampedThreshold = min(1.0, max(0.0, threshold))
        var closestCorner: (primitive: AUStretchDetectionPrimitiveID, resolution: StretchOSCEventResolution, distance: Double)?

        for resolution in resolutions {
            for corner in corners where corner.score >= clampedThreshold && selection.shouldShowCorner(index: corner.index) {
                let point = sourceDetectionCanvasPoint(from: corner.point)
                let distance = hypot(resolution.canvasPoint.x - point.x, resolution.canvasPoint.y - point.y)
                guard distance <= detectionCornerHitRadius else {
                    continue
                }

                let primitive = AUStretchDetectionPrimitiveID(kind: .corner, index: corner.index)
                if closestCorner == nil || distance < closestCorner!.distance {
                    closestCorner = (primitive, resolution, distance)
                }
            }
        }

        if let closestCorner {
            return (closestCorner.primitive, closestCorner.resolution)
        }

        var closestEdge: (primitive: AUStretchDetectionPrimitiveID, resolution: StretchOSCEventResolution, distance: Double)?
        for resolution in resolutions {
            for edge in edges where edge.score >= clampedThreshold && selection.shouldShowEdge(index: edge.index) {
                let line = sourceDetectionCanvasLine(from: edge.line)
                let distance = distance(from: resolution.canvasPoint, toSegmentStart: line.start, end: line.end)
                guard distance <= detectionEdgeHitRadius else {
                    continue
                }

                let primitive = AUStretchDetectionPrimitiveID(kind: .edge, index: edge.index)
                if closestEdge == nil || distance < closestEdge!.distance {
                    closestEdge = (primitive, resolution, distance)
                }
            }
        }

        if let closestEdge {
            return (closestEdge.primitive, closestEdge.resolution)
        }

        return nil
    }

    private func toggleDetectionSelection(
        _ primitive: AUStretchDetectionPrimitiveID,
        edges: [InnerStretchDetectionEdge],
        corners: [InnerStretchDetectionCorner],
        size: AUSize,
        time: CMTime,
        forceUpdate: UnsafeMutablePointer<ObjCBool>?
    ) {
        var selection = currentDetectionSelection()
        selection.toggle(primitive)
        selection.hover = primitive
        setDetectionSelection(selection, forceUpdate: forceUpdate)
        guard let settingAPI = parameterSettingAPI() else {
            forceUpdate?.pointee = true
            return
        }

        if selection.selectedCornerIndexes.count == 4 {
            let points = selection.selectedCornerIndexes.sorted().compactMap { index in
                corners.first(where: { $0.index == index })?.point
            }
            guard points.count == 4,
                  let stretch = AnyUprightGeometry.imageSelection(fromNormalizedObjectPoints: points, size: size) else {
                forceUpdate?.pointee = true
                return
            }

            setInnerStretch(stretch, size: size, settingAPI: settingAPI, time: time)
            settingAPI.setBoolValue(false, toParameter: StretchParam.chooseFromDetections.rawValue, at: time)
            clearDetectionSelection(forceUpdate: forceUpdate)
            forceUpdate?.pointee = true
            return
        }

        if selection.selectedEdgeIndexes.count == 4 {
            let lines = selection.selectedEdgeIndexes.sorted().compactMap { index in
                edges.first(where: { $0.index == index })?.line
            }
            guard lines.count == 4,
                  let stretch = AnyUprightGeometry.imageSelection(fromNormalizedObjectLines: lines, size: size) else {
                forceUpdate?.pointee = true
                return
            }

            setInnerStretch(stretch, size: size, settingAPI: settingAPI, time: time)
            settingAPI.setBoolValue(false, toParameter: StretchParam.chooseFromDetections.rawValue, at: time)
            clearDetectionSelection(forceUpdate: forceUpdate)
            forceUpdate?.pointee = true
        }
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
        debugCanvasMetrics(label: "hover", eventPoint: eventPoint, stretch: geometry.rawCanvasStretch, canvasFrame: canvasFrame)
        let hit = hitTestPart(
            forEventPoint: eventPoint,
            handles: geometry.handles,
            stretch: geometry.stretch,
            rawCanvasHandles: geometry.rawCanvasHandles,
            rawCanvasStretch: geometry.rawCanvasStretch,
            useRawCanvasHitLayer: geometry.usesRawCanvasHitLayer,
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

    private func sourceDetectionOverlayStyle(lineThickness: Double = 2.0, isActive: Bool = false) -> AUOSCOverlayStyle {
        var style = AUOSCOverlayStyle()
        style.lineColor = isActive
            ? SIMD4<Float>(1.0, 0.85, 0.0, 1.0)
            : SIMD4<Float>(0.15, 0.95, 0.35, 0.95)
        style.shadowColor = SIMD4<Float>(0.0, 0.0, 0.0, 0.72)
        style.lineThickness = lineThickness
        style.handleRadius = 0.0
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

    private func sourceDetectionOverlaySegments(
        edges: [InnerStretchDetectionEdge],
        corners: [InnerStretchDetectionCorner],
        threshold: Double,
        selection: AUStretchDetectionSelectionState
    ) -> [AUOSCStyledSegment] {
        let clampedThreshold = min(1.0, max(0.0, threshold))
        var segments: [AUOSCStyledSegment] = []

        for edge in edges where edge.score >= clampedThreshold && selection.shouldShowEdge(index: edge.index) {
            let primitive = AUStretchDetectionPrimitiveID(kind: .edge, index: edge.index)
            let edgeStyle = sourceDetectionOverlayStyle(lineThickness: selection.isActive(primitive) ? 3.5 : 2.5, isActive: selection.isActive(primitive))
            segments.append(AUOSCStyledSegment(
                start: sourceDetectionCanvasPoint(from: edge.line.start),
                end: sourceDetectionCanvasPoint(from: edge.line.end),
                style: edgeStyle
            ))
        }

        for corner in corners where corner.score >= clampedThreshold && selection.shouldShowCorner(index: corner.index) {
            let primitive = AUStretchDetectionPrimitiveID(kind: .corner, index: corner.index)
            let crossStyle = sourceDetectionOverlayStyle(lineThickness: selection.isActive(primitive) ? 2.75 : 2.0, isActive: selection.isActive(primitive))
            appendDetectionCornerCross(
                at: sourceDetectionCanvasPoint(from: corner.point),
                style: crossStyle,
                to: &segments
            )
        }

        return segments
    }

    private func detectionPartID(for primitive: AUStretchDetectionPrimitiveID) -> Int {
        switch primitive.kind {
        case .corner:
            return 1000 + primitive.index
        case .edge:
            return 2000 + primitive.index
        }
    }

    private func sourceDetectionCanvasPoint(from objectPoint: AUPoint) -> AUPoint {
        canvasPoint(fromObjectPoint: AnyUprightGeometry.verticallyFlippedObjectPoint(objectPoint))
    }

    private func sourceDetectionCanvasLine(from objectLine: AULineSegment) -> AULineSegment {
        AULineSegment(
            start: sourceDetectionCanvasPoint(from: objectLine.start),
            end: sourceDetectionCanvasPoint(from: objectLine.end)
        )
    }

    private func appendDetectionCornerCross(at point: AUPoint, style: AUOSCOverlayStyle, to segments: inout [AUOSCStyledSegment]) {
        let radius = 8.0
        segments.append(AUOSCStyledSegment(
            start: AUPoint(x: point.x - radius, y: point.y - radius),
            end: AUPoint(x: point.x + radius, y: point.y + radius),
            style: style
        ))
        segments.append(AUOSCStyledSegment(
            start: AUPoint(x: point.x - radius, y: point.y + radius),
            end: AUPoint(x: point.x + radius, y: point.y - radius),
            style: style
        ))
    }

}

@objc(AnyUprightOuterStretchOSCPlugIn)
class AnyUprightOuterStretchOSCPlugIn: AnyUprightInnerStretchOSCPlugIn {
    override var fixedStretchMode: AUStretchTransformMode {
        .outputCorners
    }
}
