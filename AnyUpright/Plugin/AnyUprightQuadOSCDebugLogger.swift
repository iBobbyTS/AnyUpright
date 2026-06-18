//
//  AnyUprightQuadOSCDebugLogger.swift
//  AnyUpright
//

import Foundation
import AppKit
import CoreImage
import IOSurface
import Vision

extension AnyUprightQuadManualOSCPlugIn {
    func debugLog(_ message: String) {
        let flagPath = "/tmp/AnyUprightQuadOSC.debug"
        guard FileManager.default.fileExists(atPath: flagPath) else {
            return
        }

        let logPath = "/tmp/AnyUprightQuadOSC.log"
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

    func debugOSCEventResolution(
        label: String,
        eventPoint: AUPoint,
        resolved: QuadOSCEventResolution,
        part: QuadOSCPart?,
        mode: AUQuadTransformMode,
        size: AUSize
    ) {
        guard FileManager.default.fileExists(atPath: "/tmp/AnyUprightQuadOSC.debug") else {
            return
        }

        let objectPoint = objectPoint(fromCanvasPoint: resolved.canvasPoint)
        let dragPoint = sourceQuadDragPoint(from: objectPoint, mode: mode, coordinateMode: resolved.coordinateMode)
        let partDescription = part.map { "\($0.rawValue)" } ?? "nil"
        debugLog(
            String(
                format: "%@ event=(%.2f,%.2f) resolved=(%.2f,%.2f) eventMode=%@ part=%@ object=(%.5f,%.5f) dragObject=(%.5f,%.5f) objectPx=(%.2f,%.2f) dragPx=(%.2f,%.2f)",
                label,
                eventPoint.x,
                eventPoint.y,
                resolved.canvasPoint.x,
                resolved.canvasPoint.y,
                resolved.coordinateMode.description,
                partDescription,
                objectPoint.x,
                objectPoint.y,
                dragPoint.x,
                dragPoint.y,
                objectPoint.x * size.width,
                objectPoint.y * size.height,
                dragPoint.x * size.width,
                dragPoint.y * size.height
            )
        )
    }

    func debugOSCDragDelta(
        label: String,
        previous: QuadOSCEventResolution,
        current: QuadOSCEventResolution,
        previousObject: AUPoint,
        currentObject: AUPoint,
        pixelDelta: AUPoint,
        size: AUSize
    ) {
        guard FileManager.default.fileExists(atPath: "/tmp/AnyUprightQuadOSC.debug") else {
            return
        }

        let percentDelta = AUPoint(
            x: pixelDelta.x / max(size.width, 1.0),
            y: pixelDelta.y / max(size.height, 1.0)
        )
        debugLog(
            String(
                format: "%@ prev=(%.2f,%.2f %@) curr=(%.2f,%.2f %@) prevObj=(%.5f,%.5f) currObj=(%.5f,%.5f) pixelDelta=(%.2f,%.2f) percentDelta=(%.5f,%.5f)",
                label,
                previous.canvasPoint.x,
                previous.canvasPoint.y,
                previous.coordinateMode.description,
                current.canvasPoint.x,
                current.canvasPoint.y,
                current.coordinateMode.description,
                previousObject.x,
                previousObject.y,
                currentObject.x,
                currentObject.y,
                pixelDelta.x,
                pixelDelta.y,
                percentDelta.x,
                percentDelta.y
            )
        )
    }

    func debugDescription(of points: [AUPoint]) -> String {
        points.map { point in
            String(format: "(%.1f,%.1f)", point.x, point.y)
        }
        .joined(separator: " ")
    }

    func debugDescription(of rect: FxRect) -> String {
        String(format: "(%.1f,%.1f,%.1f,%.1f)", Double(rect.left), Double(rect.bottom), Double(rect.right), Double(rect.top))
    }

    func nextDebugDrawSequence() -> Int {
        guard FileManager.default.fileExists(atPath: "/tmp/AnyUprightQuadOSC.debug") else {
            return 0
        }

        debugDrawSequence += 1
        return debugDrawSequence
    }

    func debugBoundsDescription(of points: [AUPoint]) -> String {
        guard let bounds = coordinateFrame(from: points) else {
            return "nil"
        }

        return String(
            format: "min=(%.2f,%.2f) max=(%.2f,%.2f) size=(%.2f,%.2f) center=(%.2f,%.2f)",
            bounds.minX,
            bounds.minY,
            bounds.maxX,
            bounds.maxY,
            bounds.width,
            bounds.height,
            bounds.center.x,
            bounds.center.y
        )
    }

    func coordinateFrame(from points: [AUPoint]) -> (minX: Double, minY: Double, maxX: Double, maxY: Double, width: Double, height: Double, center: AUPoint)? {
        guard let minX = points.map(\.x).min(),
              let maxX = points.map(\.x).max(),
              let minY = points.map(\.y).min(),
              let maxY = points.map(\.y).max() else {
            return nil
        }

        let width = max(1.0, maxX - minX)
        let height = max(1.0, maxY - minY)
        return (
            minX: minX,
            minY: minY,
            maxX: maxX,
            maxY: maxY,
            width: width,
            height: height,
            center: AUPoint(x: (minX + maxX) / 2.0, y: (minY + maxY) / 2.0)
        )
    }

    func debugSurfaceSize(from destinationImage: FxImageTile, fallback: AUSize) -> AUSize {
        AUSize(
            width: Double(destinationImage.ioSurface.map { IOSurfaceGetWidth($0) } ?? Int(max(1.0, fallback.width))),
            height: Double(destinationImage.ioSurface.map { IOSurfaceGetHeight($0) } ?? Int(max(1.0, fallback.height)))
        )
    }

    func debugSourceQuadDrawMapping(
        sequence: Int,
        width: Int,
        height: Int,
        destinationImage: FxImageTile,
        outputSize: AUSize,
        objectSize: AUSize,
        quad: [AUPoint],
        objectCanvasQuad: [AUPoint],
        canvasFrame: [AUPoint]
    ) {
        guard FileManager.default.fileExists(atPath: "/tmp/AnyUprightQuadOSC.debug") else {
            return
        }

        let surfaceSize = debugSurfaceSize(from: destinationImage, fallback: AUSize(width: Double(width), height: Double(height)))
        let frameBounds = coordinateFrame(from: canvasFrame)
        let frameCenter = frameBounds?.center ?? AUPoint(x: 0.0, y: 0.0)
        let surfaceCenter = AUPoint(x: surfaceSize.width / 2.0, y: surfaceSize.height / 2.0)
        let frameToSurfaceDelta = AUPoint(x: frameCenter.x - surfaceCenter.x, y: frameCenter.y - surfaceCenter.y)
        let frameScale = AUPoint(
            x: surfaceSize.width / max(frameBounds?.width ?? 1.0, 1.0),
            y: surfaceSize.height / max(frameBounds?.height ?? 1.0, 1.0)
        )

        let pointRows = quad.enumerated().map { index, point -> String in
            let normalizedInFrame = AUPoint(
                x: (point.x - (frameBounds?.minX ?? 0.0)) / max(frameBounds?.width ?? 1.0, 1.0),
                y: (point.y - (frameBounds?.minY ?? 0.0)) / max(frameBounds?.height ?? 1.0, 1.0)
            )
            let direct = point
            let centerRelative = AUPoint(
                x: point.x - frameToSurfaceDelta.x,
                y: point.y - frameToSurfaceDelta.y
            )
            let surfaceDirect = oscSurfacePixel(
                fromHostCanvasPixel: point,
                surfaceSize: surfaceSize
            )
            let fitted = AUPoint(
                x: normalizedInFrame.x * surfaceSize.width,
                y: normalizedInFrame.y * surfaceSize.height
            )
            return String(
                format: "p%d canvas=(%.2f,%.2f) norm=(%.4f,%.4f) direct=(%.2f,%.2f) centerRel=(%.2f,%.2f) surfaceDirect=(%.2f,%.2f) frameFit=(%.2f,%.2f)",
                index,
                point.x,
                point.y,
                normalizedInFrame.x,
                normalizedInFrame.y,
                direct.x,
                direct.y,
                centerRelative.x,
                centerRelative.y,
                surfaceDirect.x,
                surfaceDirect.y,
                fitted.x,
                fitted.y
            )
        }.joined(separator: " | ")

        debugCanvasMetrics(label: "draw-source seq=\(sequence)", width: width, height: height, destinationImage: destinationImage, quad: quad, canvasFrame: canvasFrame)
        debugLog(
            String(
                format: "draw-source seq=%d output=(%.2f,%.2f) surface=(%.2f,%.2f) frameBounds=%@ quadBounds=%@ objectQuad=%@ frameCenter=(%.2f,%.2f) surfaceCenter=(%.2f,%.2f) frameToSurfaceDelta=(%.2f,%.2f) surfacePerFrame=(%.6f,%.6f)",
                sequence,
                outputSize.width,
                outputSize.height,
                surfaceSize.width,
                surfaceSize.height,
                debugBoundsDescription(of: canvasFrame),
                debugBoundsDescription(of: quad),
                debugDescription(of: objectCanvasQuad),
                frameCenter.x,
                frameCenter.y,
                surfaceCenter.x,
                surfaceCenter.y,
                frameToSurfaceDelta.x,
                frameToSurfaceDelta.y,
                frameScale.x,
                frameScale.y
            )
        )
        debugLog(
            String(
                format: "draw-source seq=%d objectSize=(%.2f,%.2f) outputSize=(%.2f,%.2f) surfaceSize=(%.2f,%.2f)",
                sequence,
                objectSize.width,
                objectSize.height,
                outputSize.width,
                outputSize.height,
                surfaceSize.width,
                surfaceSize.height
            )
        )
        debugLog("draw-source seq=\(sequence) point-map \(pointRows)")
    }

    func debugCanvasMetrics(label: String, width: Int? = nil, height: Int? = nil, destinationImage: FxImageTile? = nil, eventPoint: AUPoint? = nil, quad: [AUPoint]? = nil, canvasFrame: [AUPoint]? = nil) {
        guard FileManager.default.fileExists(atPath: "/tmp/AnyUprightQuadOSC.debug") else {
            return
        }

        let oscAPI = _apiManager.api(for: FxOnScreenControlAPI_v4.self) as? FxOnScreenControlAPI_v4
        let zoom = oscAPI?.canvasZoom() ?? -1.0
        let backingScale = oscAPI?.backingScaleFactor() ?? -1.0
        let objectBounds = oscAPI?.objectBounds() ?? .zero
        let surfaceDescription: String
        if let destinationImage {
            let surfaceWidth = destinationImage.ioSurface.map { IOSurfaceGetWidth($0) } ?? -1
            let surfaceHeight = destinationImage.ioSurface.map { IOSurfaceGetHeight($0) } ?? -1
            surfaceDescription = "\(surfaceWidth)x\(surfaceHeight) image=\(debugDescription(of: destinationImage.imagePixelBounds)) tile=\(debugDescription(of: destinationImage.tilePixelBounds))"
        } else {
            let surfaceSize = currentSurfaceSize()
            surfaceDescription = String(format: "%.1fx%.1f", surfaceSize.width, surfaceSize.height)
        }
        let eventDescription = eventPoint.map { String(format: " event=(%.1f,%.1f)", $0.x, $0.y) } ?? ""
        let frameDescription = canvasFrame.map { " frame=\(debugDescription(of: $0))" } ?? ""
        let quadDescription = quad.map { " quad=\(debugDescription(of: $0))" } ?? ""
        let sizeDescription = width.flatMap { widthValue in height.map { " wh=\(widthValue)x\($0)" } } ?? ""
        let boundsDescription = String(format: " objectBounds=(%.1f,%.1f,%.1f,%.1f)", objectBounds.origin.x, objectBounds.origin.y, objectBounds.size.width, objectBounds.size.height)

        debugLog("\(label)\(sizeDescription) surface=\(surfaceDescription) zoom=\(zoom) backing=\(backingScale)\(boundsDescription)\(eventDescription)\(frameDescription)\(quadDescription)")
    }
}
