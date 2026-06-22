//
//  AnyUprightQuadOSCControls.swift
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
    private var dragState: QuadOSCDragState?
    private var hoverPart: QuadOSCPart = .none
    private var detectionSelection = AUQuadDetectionSelectionState()
    var debugDrawSequence = 0

    required init?(apiManager: PROAPIAccessing) {
        super.init(apiManager: apiManager)
    }

    var fixedQuadMode: AUQuadTransformMode {
        .innerStretch
    }

    @objc(drawingCoordinates)
    func drawingCoordinates() -> FxDrawingCoordinates {
        return FxDrawingCoordinates(kFxDrawingCoordinates_CANVAS)
    }

    @objc(drawOSCWithWidth:height:activePart:destinationImage:atTime:)
    func drawOSC(withWidth width: Int, height: Int, activePart: Int, destinationImage: FxImageTile, at time: CMTime) {
        let paramAPI = parameterRetrievalAPI()
        let state = quadParameterState(at: time, paramAPI: paramAPI, fixedMode: fixedQuadMode)
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
        let chooseFromDetections = quadChooseFromDetections(at: time, paramAPI: paramAPI)
        if chooseFromDetections {
            setHoverPart(.none, forceUpdate: nil)
        } else {
            clearDetectionSelection(forceUpdate: nil)
        }
        let displayPart = chooseFromDetections ? QuadOSCPart.none : currentDisplayPart(hostActivePart: activePart)
        let debugSequence = nextDebugDrawSequence()
        debugCanvasMetrics(label: "draw-source-entry seq=\(debugSequence) part=\(displayPart.rawValue) host=\(activePart)", width: width, height: height, destinationImage: destinationImage, quad: quad, canvasFrame: canvasFrame)
        let handles = [
            AUOSCHandle(point: quad[0], part: QuadOSCPart.topLeft.rawValue),
            AUOSCHandle(point: quad[1], part: QuadOSCPart.topRight.rawValue),
            AUOSCHandle(point: quad[2], part: QuadOSCPart.bottomRight.rawValue),
            AUOSCHandle(point: quad[3], part: QuadOSCPart.bottomLeft.rawValue)
        ]
        debugInnerStretchDrawMapping(
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

        let detectedEdges = quadInnerStretchDetectionEdges(at: time, paramAPI: paramAPI)
        let detectedCorners = quadInnerStretchDetectionCorners(at: time, paramAPI: paramAPI)
        let detectionThreshold = quadDetectionScoreThreshold(at: time, paramAPI: paramAPI)
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
            detectionSegments + innerStretchOverlaySegments(for: displayPart, quad: quad),
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
        let state = quadParameterState(at: time, paramAPI: paramAPI, fixedMode: fixedQuadMode)
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
        if mode == .innerStretch, quadChooseFromDetections(at: time, paramAPI: paramAPI) {
            let threshold = quadDetectionScoreThreshold(at: time, paramAPI: paramAPI)
            let edges = quadInnerStretchDetectionEdges(at: time, paramAPI: paramAPI)
            let corners = quadInnerStretchDetectionCorners(at: time, paramAPI: paramAPI)
            let selection = pruneDetectionSelection(edges: edges, corners: corners, threshold: threshold, forceUpdate: nil)
            let hit = hitTestDetectionPrimitive(
                forEventPoint: eventPoint,
                edges: edges,
                corners: corners,
                threshold: threshold,
                selection: selection,
                canvasFrame: canvasFrame,
                rawCanvasQuad: geometry.rawCanvasQuad,
                preferredMode: nil
            )
            activePart?.pointee = hit.map { detectionPartID(for: $0.primitive) } ?? QuadOSCPart.none.rawValue
            return
        }
        let hit = hitTestPart(
            forEventPoint: eventPoint,
            handles: geometry.handles,
            quad: geometry.quad,
            rawCanvasHandles: geometry.rawCanvasHandles,
            rawCanvasQuad: geometry.rawCanvasQuad,
            useRawCanvasHitLayer: geometry.usesRawCanvasHitLayer,
            canvasFrame: canvasFrame,
            rawCanvasHitPadding: innerStretchRawCanvasHitPadding,
            preferredMode: nil
        )
        let part = hit?.part.rawValue ?? QuadOSCPart.none.rawValue
        activePart?.pointee = part
    }

    @objc(mouseDownAtPositionX:positionY:activePart:modifiers:forceUpdate:atTime:)
    func mouseDown(atPositionX mousePositionX: Double, positionY mousePositionY: Double, activePart: Int, modifiers: FxModifierKeys, forceUpdate: UnsafeMutablePointer<ObjCBool>?, at time: CMTime) {
        setHoverPart(.none, forceUpdate: nil)
        let paramAPI = parameterRetrievalAPI()
        let state = quadParameterState(at: time, paramAPI: paramAPI, fixedMode: fixedQuadMode)
        let mode = quadMode(from: state)
        let size = objectPixelSizeForOSC()
        let geometry = hitGeometry(from: state, size: size, mode: mode)
        let canvasFrame = objectCanvasFrame()
        let eventPoint = AUPoint(x: mousePositionX, y: mousePositionY)
        if shouldEnableQuadOSCControls(from: state, mode: mode),
           mode == .innerStretch,
           quadChooseFromDetections(at: time, paramAPI: paramAPI) {
            setDragState(nil)
            let threshold = quadDetectionScoreThreshold(at: time, paramAPI: paramAPI)
            let edges = quadInnerStretchDetectionEdges(at: time, paramAPI: paramAPI)
            let corners = quadInnerStretchDetectionCorners(at: time, paramAPI: paramAPI)
            let selection = pruneDetectionSelection(edges: edges, corners: corners, threshold: threshold, forceUpdate: nil)
            guard let hit = hitTestDetectionPrimitive(
                forEventPoint: eventPoint,
                edges: edges,
                corners: corners,
                threshold: threshold,
                selection: selection,
                canvasFrame: canvasFrame,
                rawCanvasQuad: geometry.rawCanvasQuad,
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
            quad: geometry.quad,
            rawCanvasHandles: geometry.rawCanvasHandles,
            rawCanvasQuad: geometry.rawCanvasQuad,
            useRawCanvasHitLayer: geometry.usesRawCanvasHitLayer,
            canvasFrame: canvasFrame,
            rawCanvasHitPadding: innerStretchRawCanvasHitPadding,
            preferredMode: nil
        )
        let resolvedCanvasPoint = resolvedEvent?.resolution
            ?? resolvedCanvasPoint(
                fromEventPoint: eventPoint,
                canvasFrame: canvasFrame,
                rawCanvasQuad: geometry.rawCanvasQuad,
                rawCanvasHitPadding: innerStretchRawCanvasHitPadding,
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
        let paramAPI = parameterRetrievalAPI()
        let state = quadParameterState(at: time, paramAPI: paramAPI, fixedMode: fixedQuadMode)
        let mode = quadMode(from: state)
        if mode == .innerStretch, quadChooseFromDetections(at: time, paramAPI: paramAPI) {
            setDragState(nil)
            forceUpdate?.pointee = false
            return
        }
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

    private func currentDetectionSelection() -> AUQuadDetectionSelectionState {
        detectionSelectionLock.lock()
        let selection = detectionSelection
        detectionSelectionLock.unlock()
        return selection
    }

    private func setDetectionSelection(_ selection: AUQuadDetectionSelectionState, forceUpdate: UnsafeMutablePointer<ObjCBool>?) {
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

    private func setDetectionHover(_ primitive: AUQuadDetectionPrimitiveID?, forceUpdate: UnsafeMutablePointer<ObjCBool>?) {
        var selection = currentDetectionSelection()
        guard selection.hover != primitive else {
            return
        }

        selection.hover = primitive
        setDetectionSelection(selection, forceUpdate: forceUpdate)
    }

    private func isChoosingDetections(at time: CMTime) -> Bool {
        let paramAPI = parameterRetrievalAPI()
        let state = quadParameterState(at: time, paramAPI: paramAPI, fixedMode: fixedQuadMode)
        let mode = quadMode(from: state)
        return mode == .innerStretch
            && shouldEnableQuadOSCControls(from: state, mode: mode)
            && quadChooseFromDetections(at: time, paramAPI: paramAPI)
    }

    private func pruneDetectionSelection(
        edges: [QuadInnerStretchDetectionEdge],
        corners: [QuadInnerStretchDetectionCorner],
        threshold: Double,
        forceUpdate: UnsafeMutablePointer<ObjCBool>?
    ) -> AUQuadDetectionSelectionState {
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
    private func updateDetectionHover(forEventPoint eventPoint: AUPoint, at time: CMTime, forceUpdate: UnsafeMutablePointer<ObjCBool>?) -> AUQuadDetectionPrimitiveID? {
        let paramAPI = parameterRetrievalAPI()
        let state = quadParameterState(at: time, paramAPI: paramAPI, fixedMode: fixedQuadMode)
        let mode = quadMode(from: state)
        guard mode == .innerStretch,
              shouldEnableQuadOSCControls(from: state, mode: mode),
              quadChooseFromDetections(at: time, paramAPI: paramAPI) else {
            clearDetectionSelection(forceUpdate: forceUpdate)
            return nil
        }

        let size = objectPixelSizeForOSC()
        let geometry = hitGeometry(from: state, size: size, mode: mode)
        let threshold = quadDetectionScoreThreshold(at: time, paramAPI: paramAPI)
        let edges = quadInnerStretchDetectionEdges(at: time, paramAPI: paramAPI)
        let corners = quadInnerStretchDetectionCorners(at: time, paramAPI: paramAPI)
        let selection = pruneDetectionSelection(edges: edges, corners: corners, threshold: threshold, forceUpdate: forceUpdate)
        let hit = hitTestDetectionPrimitive(
            forEventPoint: eventPoint,
            edges: edges,
            corners: corners,
            threshold: threshold,
            selection: selection,
            canvasFrame: objectCanvasFrame(),
            rawCanvasQuad: geometry.rawCanvasQuad,
            preferredMode: currentDragState()?.eventCoordinateMode
        )
        setDetectionHover(hit?.primitive, forceUpdate: forceUpdate)
        return hit?.primitive
    }

    private func hitTestDetectionPrimitive(
        forEventPoint eventPoint: AUPoint,
        edges: [QuadInnerStretchDetectionEdge],
        corners: [QuadInnerStretchDetectionCorner],
        threshold: Double,
        selection: AUQuadDetectionSelectionState,
        canvasFrame: [AUPoint],
        rawCanvasQuad: [AUPoint],
        preferredMode: QuadOSCEventCoordinateMode?
    ) -> (primitive: AUQuadDetectionPrimitiveID, resolution: QuadOSCEventResolution)? {
        let resolutions = eventResolutions(
            fromEventPoint: eventPoint,
            canvasFrame: canvasFrame,
            rawCanvasQuad: rawCanvasQuad,
            rawCanvasHitPadding: innerStretchRawCanvasHitPadding,
            preferredMode: preferredMode
        )
        let clampedThreshold = min(1.0, max(0.0, threshold))
        var closestCorner: (primitive: AUQuadDetectionPrimitiveID, resolution: QuadOSCEventResolution, distance: Double)?

        for resolution in resolutions {
            for corner in corners where corner.score >= clampedThreshold && selection.shouldShowCorner(index: corner.index) {
                let point = sourceDetectionCanvasPoint(from: corner.point)
                let distance = hypot(resolution.canvasPoint.x - point.x, resolution.canvasPoint.y - point.y)
                guard distance <= detectionCornerHitRadius else {
                    continue
                }

                let primitive = AUQuadDetectionPrimitiveID(kind: .corner, index: corner.index)
                if closestCorner == nil || distance < closestCorner!.distance {
                    closestCorner = (primitive, resolution, distance)
                }
            }
        }

        if let closestCorner {
            return (closestCorner.primitive, closestCorner.resolution)
        }

        var closestEdge: (primitive: AUQuadDetectionPrimitiveID, resolution: QuadOSCEventResolution, distance: Double)?
        for resolution in resolutions {
            for edge in edges where edge.score >= clampedThreshold && selection.shouldShowEdge(index: edge.index) {
                let line = sourceDetectionCanvasLine(from: edge.line)
                let distance = distance(from: resolution.canvasPoint, toSegmentStart: line.start, end: line.end)
                guard distance <= detectionEdgeHitRadius else {
                    continue
                }

                let primitive = AUQuadDetectionPrimitiveID(kind: .edge, index: edge.index)
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
        _ primitive: AUQuadDetectionPrimitiveID,
        edges: [QuadInnerStretchDetectionEdge],
        corners: [QuadInnerStretchDetectionCorner],
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
                  let quad = AnyUprightGeometry.imageQuad(fromNormalizedObjectPoints: points, size: size) else {
                forceUpdate?.pointee = true
                return
            }

            setInnerStretch(quad, size: size, settingAPI: settingAPI, time: time)
            settingAPI.setBoolValue(false, toParameter: QuadParam.chooseFromDetections.rawValue, at: time)
            clearDetectionSelection(forceUpdate: forceUpdate)
            forceUpdate?.pointee = true
            return
        }

        if selection.selectedEdgeIndexes.count == 4 {
            let lines = selection.selectedEdgeIndexes.sorted().compactMap { index in
                edges.first(where: { $0.index == index })?.line
            }
            guard lines.count == 4,
                  let quad = AnyUprightGeometry.imageQuad(fromNormalizedObjectLines: lines, size: size) else {
                forceUpdate?.pointee = true
                return
            }

            setInnerStretch(quad, size: size, settingAPI: settingAPI, time: time)
            settingAPI.setBoolValue(false, toParameter: QuadParam.chooseFromDetections.rawValue, at: time)
            clearDetectionSelection(forceUpdate: forceUpdate)
            forceUpdate?.pointee = true
        }
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
            rawCanvasHitPadding: innerStretchRawCanvasHitPadding,
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

    private func innerStretchOverlaySegments(for part: QuadOSCPart, quad: [AUPoint]) -> [AUOSCStyledSegment] {
        guard quad.count == 4 else {
            return []
        }

        var baseStyle = innerStretchOverlayStyle()
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

    private func sourceDetectionOverlaySegments(
        edges: [QuadInnerStretchDetectionEdge],
        corners: [QuadInnerStretchDetectionCorner],
        threshold: Double,
        selection: AUQuadDetectionSelectionState
    ) -> [AUOSCStyledSegment] {
        let clampedThreshold = min(1.0, max(0.0, threshold))
        var segments: [AUOSCStyledSegment] = []

        for edge in edges where edge.score >= clampedThreshold && selection.shouldShowEdge(index: edge.index) {
            let primitive = AUQuadDetectionPrimitiveID(kind: .edge, index: edge.index)
            let edgeStyle = sourceDetectionOverlayStyle(lineThickness: selection.isActive(primitive) ? 3.5 : 2.5, isActive: selection.isActive(primitive))
            segments.append(AUOSCStyledSegment(
                start: sourceDetectionCanvasPoint(from: edge.line.start),
                end: sourceDetectionCanvasPoint(from: edge.line.end),
                style: edgeStyle
            ))
        }

        for corner in corners where corner.score >= clampedThreshold && selection.shouldShowCorner(index: corner.index) {
            let primitive = AUQuadDetectionPrimitiveID(kind: .corner, index: corner.index)
            let crossStyle = sourceDetectionOverlayStyle(lineThickness: selection.isActive(primitive) ? 2.75 : 2.0, isActive: selection.isActive(primitive))
            appendDetectionCornerCross(
                at: sourceDetectionCanvasPoint(from: corner.point),
                style: crossStyle,
                to: &segments
            )
        }

        return segments
    }

    private func detectionPartID(for primitive: AUQuadDetectionPrimitiveID) -> Int {
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
    override var fixedQuadMode: AUQuadTransformMode {
        .outputCorners
    }
}
