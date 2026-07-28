//
//  AnyUprightOuterStretchOSCPreviewGeometry.swift
//  AnyUpright
//

import Foundation

struct AUOuterStretchOSCPreviewLayout {
    static let maximumTextureDimension = 1600

    let physicalBounds: AUOutputCoordinateBounds
    let textureWidth: Int
    let textureHeight: Int
    let objectFrame: [AUPoint]

    static func make(corners: AUStretchCorners, outputSize: AUSize) -> AUOuterStretchOSCPreviewLayout? {
        let width = max(1.0, outputSize.width)
        let height = max(1.0, outputSize.height)
        let cornerPoints = [corners.topLeft, corners.topRight, corners.bottomRight, corners.bottomLeft]
        let extendsOutsideCanvas = cornerPoints.contains {
            $0.x < 0.0 || $0.x > width || $0.y < 0.0 || $0.y > height
        }
        guard extendsOutsideCanvas else {
            return nil
        }

        let unclampedMinX = min(0.0, cornerPoints.map(\.x).min() ?? 0.0)
        let unclampedMinY = min(0.0, cornerPoints.map(\.y).min() ?? 0.0)
        let unclampedMaxX = max(width, cornerPoints.map(\.x).max() ?? width)
        let unclampedMaxY = max(height, cornerPoints.map(\.y).max() ?? height)
        let minX = max(-width, unclampedMinX)
        let minY = max(-height, unclampedMinY)
        let maxX = min(width * 2.0, unclampedMaxX)
        let maxY = min(height * 2.0, unclampedMaxY)
        let previewWidth = max(1.0, maxX - minX)
        let previewHeight = max(1.0, maxY - minY)
        let scale = min(1.0, Double(maximumTextureDimension) / max(previewWidth, previewHeight))

        return AUOuterStretchOSCPreviewLayout(
            physicalBounds: AUOutputCoordinateBounds(left: minX, right: maxX, top: minY, bottom: maxY),
            textureWidth: max(1, Int(ceil(previewWidth * scale))),
            textureHeight: max(1, Int(ceil(previewHeight * scale))),
            objectFrame: [
                AUPoint(x: minX / width, y: 1.0 - minY / height),
                AUPoint(x: maxX / width, y: 1.0 - minY / height),
                AUPoint(x: maxX / width, y: 1.0 - maxY / height),
                AUPoint(x: minX / width, y: 1.0 - maxY / height)
            ]
        )
    }
}
