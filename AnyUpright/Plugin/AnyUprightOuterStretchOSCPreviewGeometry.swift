//
//  AnyUprightOuterStretchOSCPreviewGeometry.swift
//  AnyUpright
//

import Foundation

struct AUOuterStretchOSCPreviewVertexGeometry {
    let position: AUPoint
    let outputCoordinate: AUPoint
}

struct AUOSCTextureOverlayVertexGeometry {
    let position: AUPoint
    let textureCoordinate: AUPoint
}

struct AUOuterStretchOSCPreviewLayout {
    static let maximumTextureDimension = 1600

    let physicalBounds: AUOutputCoordinateBounds
    let textureWidth: Int
    let textureHeight: Int
    let objectFrame: [AUPoint]

    var offscreenVertices: [AUOuterStretchOSCPreviewVertexGeometry] {
        let halfWidth = Double(textureWidth) / 2.0
        let halfHeight = Double(textureHeight) / 2.0
        return [
            AUOuterStretchOSCPreviewVertexGeometry(
                position: AUPoint(x: halfWidth, y: -halfHeight),
                outputCoordinate: AUPoint(x: physicalBounds.right, y: physicalBounds.top)
            ),
            AUOuterStretchOSCPreviewVertexGeometry(
                position: AUPoint(x: -halfWidth, y: -halfHeight),
                outputCoordinate: AUPoint(x: physicalBounds.left, y: physicalBounds.top)
            ),
            AUOuterStretchOSCPreviewVertexGeometry(
                position: AUPoint(x: halfWidth, y: halfHeight),
                outputCoordinate: AUPoint(x: physicalBounds.right, y: physicalBounds.bottom)
            ),
            AUOuterStretchOSCPreviewVertexGeometry(
                position: AUPoint(x: -halfWidth, y: halfHeight),
                outputCoordinate: AUPoint(x: physicalBounds.left, y: physicalBounds.bottom)
            )
        ]
    }

    static func textureOverlayVertices(
        surfacePixels: [AUPoint],
        surfaceSize: AUSize
    ) -> [AUOSCTextureOverlayVertexGeometry] {
        guard surfacePixels.count == 4 else {
            return []
        }

        func vertex(_ index: Int, textureCoordinate: AUPoint) -> AUOSCTextureOverlayVertexGeometry {
            AUOSCTextureOverlayVertexGeometry(
                position: oscMetalCenteredPixel(
                    fromSurfacePixel: surfacePixels[index],
                    surfaceSize: surfaceSize
                ),
                textureCoordinate: textureCoordinate
            )
        }

        return [
            vertex(2, textureCoordinate: AUPoint(x: 1.0, y: 1.0)),
            vertex(3, textureCoordinate: AUPoint(x: 0.0, y: 1.0)),
            vertex(1, textureCoordinate: AUPoint(x: 1.0, y: 0.0)),
            vertex(0, textureCoordinate: AUPoint(x: 0.0, y: 0.0))
        ]
    }

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

        // Motion composes the returned OSC surface into FxPlug's Y-up object space.
        // These bounds are physical output pixels, so physical maxY is the visual top.
        return AUOuterStretchOSCPreviewLayout(
            physicalBounds: AUOutputCoordinateBounds(left: minX, right: maxX, top: minY, bottom: maxY),
            textureWidth: max(1, Int(ceil(previewWidth * scale))),
            textureHeight: max(1, Int(ceil(previewHeight * scale))),
            objectFrame: [
                AUPoint(x: minX / width, y: maxY / height),
                AUPoint(x: maxX / width, y: maxY / height),
                AUPoint(x: maxX / width, y: minY / height),
                AUPoint(x: minX / width, y: minY / height)
            ]
        )
    }
}

enum AUOuterStretchOSCPreviewRenderPolicy {
    // Keep the OSC preview on Motion's small interaction render path. The final
    // Warp output continues to use the host-provided render size.
    static let maximumSourceDimension = 512.0

    static func shouldEncode(outputSize: AUSize) -> Bool {
        let width = max(0.0, outputSize.width)
        let height = max(0.0, outputSize.height)
        return max(width, height) <= maximumSourceDimension
    }
}
