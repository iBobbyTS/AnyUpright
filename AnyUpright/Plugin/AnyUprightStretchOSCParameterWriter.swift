//
//  AnyUprightStretchOSCParameterWriter.swift
//  AnyUpright
//

import Foundation
import AppKit
import CoreImage
import IOSurface
import Vision

extension AnyUprightInnerStretchOSCPlugIn {
    func setInnerStretch(_ stretch: AUStretchCorners, size: AUSize, settingAPI: FxParameterSettingAPI_v5, time: CMTime) {
        let offsets = AnyUprightGeometry.innerStretchOffsets(forInnerStretch: stretch, size: size)
        writeCorner(.topLeft, pixels: offsets.topLeftPixels, settingAPI: settingAPI, time: time)
        writeCorner(.topRight, pixels: offsets.topRightPixels, settingAPI: settingAPI, time: time)
        writeCorner(.bottomRight, pixels: offsets.bottomRightPixels, settingAPI: settingAPI, time: time)
        writeCorner(.bottomLeft, pixels: offsets.bottomLeftPixels, settingAPI: settingAPI, time: time)
        debugLog(
            String(
                format: "set-inner-stretch tl=(%.2f,%.2f) tr=(%.2f,%.2f) br=(%.2f,%.2f) bl=(%.2f,%.2f)",
                stretch.topLeft.x,
                stretch.topLeft.y,
                stretch.topRight.x,
                stretch.topRight.y,
                stretch.bottomRight.x,
                stretch.bottomRight.y,
                stretch.bottomLeft.x,
                stretch.bottomLeft.y
            )
        )
    }

    func setCorner(_ point: AUPoint, part: StretchOSCPart, mode: AUStretchTransformMode, size: AUSize, settingAPI: FxParameterSettingAPI_v5, time: CMTime) {
        guard let ids = parameterIDs(forCornerPart: part) else {
            return
        }

        switch mode {
        case .outputCorners:
            let pixels = AnyUprightGeometry.cornerPixelOffset(
                forObjectPoint: point,
                corner: ids.corner,
                size: size
            )
            debugLog(
                String(
                    format: "set-corner part=%d mode=output object=(%.5f,%.5f) writePixels=(%.2f,%.2f)",
                    part.rawValue,
                    point.x,
                    point.y,
                    pixels.x,
                    pixels.y
                )
            )
            settingAPI.setFloatValue(pixels.x, toParameter: ids.pixelX.rawValue, at: time)
            settingAPI.setFloatValue(pixels.y, toParameter: ids.pixelY.rawValue, at: time)

        case .innerStretch:
            let pixels = AnyUprightGeometry.sourceCornerPixelOffset(forObjectPoint: point, corner: ids.corner, size: size)
            debugLog(
                String(
                    format: "set-corner part=%d mode=source object=(%.5f,%.5f) writePixels=(%.2f,%.2f)",
                    part.rawValue,
                    point.x,
                    point.y,
                    pixels.x,
                    pixels.y
                )
            )
            settingAPI.setFloatValue(pixels.x, toParameter: ids.pixelX.rawValue, at: time)
            settingAPI.setFloatValue(pixels.y, toParameter: ids.pixelY.rawValue, at: time)
        }
    }

    func translateCorners(from state: AnyUprightParameterState, pixelDelta: AUPoint, corners: [AUStretchCorner], mode: AUStretchTransformMode, settingAPI: FxParameterSettingAPI_v5, time: CMTime) {
        let offsets = stretchCornerOffsets(from: state)

        for corner in corners {
            let ids = parameterIDs(for: corner)
            let pixels = pixelOffset(for: corner, in: offsets)
            debugLog(
                String(
                    format: "translate-corner mode=%@ corner=%@ pixelBase=(%.2f,%.2f) pixelDelta=(%.2f,%.2f)",
                    mode == .innerStretch ? "source" : "output",
                    "\(corner)",
                    pixels.x,
                    pixels.y,
                    pixelDelta.x,
                    pixelDelta.y
                )
            )
            settingAPI.setFloatValue(pixels.x + pixelDelta.x, toParameter: ids.pixelX.rawValue, at: time)
            settingAPI.setFloatValue(pixels.y + pixelDelta.y, toParameter: ids.pixelY.rawValue, at: time)
        }
    }

    func parameterIDs(forCornerPart part: StretchOSCPart) -> (corner: AUStretchCorner, pixelX: StretchParam, pixelY: StretchParam)? {
        switch part {
        case .topLeft:
            return (.topLeft, .topLeftPixelX, .topLeftPixelY)
        case .topRight:
            return (.topRight, .topRightPixelX, .topRightPixelY)
        case .bottomRight:
            return (.bottomRight, .bottomRightPixelX, .bottomRightPixelY)
        case .bottomLeft:
            return (.bottomLeft, .bottomLeftPixelX, .bottomLeftPixelY)
        default:
            return nil
        }
    }

    func parameterIDs(for corner: AUStretchCorner) -> (pixelX: StretchParam, pixelY: StretchParam) {
        switch corner {
        case .topLeft:
            return (.topLeftPixelX, .topLeftPixelY)
        case .topRight:
            return (.topRightPixelX, .topRightPixelY)
        case .bottomRight:
            return (.bottomRightPixelX, .bottomRightPixelY)
        case .bottomLeft:
            return (.bottomLeftPixelX, .bottomLeftPixelY)
        }
    }

    private func writeCorner(_ corner: AUStretchCorner, pixels: AUPoint, settingAPI: FxParameterSettingAPI_v5, time: CMTime) {
        let ids = parameterIDs(for: corner)
        settingAPI.setFloatValue(pixels.x, toParameter: ids.pixelX.rawValue, at: time)
        settingAPI.setFloatValue(pixels.y, toParameter: ids.pixelY.rawValue, at: time)
    }

    func pixelOffset(for corner: AUStretchCorner, in offsets: AUCornerOffsets) -> AUPoint {
        switch corner {
        case .topLeft:
            return offsets.topLeftPixels
        case .topRight:
            return offsets.topRightPixels
        case .bottomRight:
            return offsets.bottomRightPixels
        case .bottomLeft:
            return offsets.bottomLeftPixels
        }
    }
}
