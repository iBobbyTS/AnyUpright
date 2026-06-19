//
//  AnyUprightQuadOSCParameterWriter.swift
//  AnyUpright
//

import Foundation
import AppKit
import CoreImage
import IOSurface
import Vision

extension AnyUprightQuadManualOSCPlugIn {
    func setSourceQuad(_ quad: AUQuad, size: AUSize, settingAPI: FxParameterSettingAPI_v5, time: CMTime) {
        let offsets = AnyUprightGeometry.sourceQuadOffsets(forSourceQuad: quad, size: size)
        writeSourceCorner(.topLeft, percent: offsets.topLeftPercent, settingAPI: settingAPI, time: time)
        writeSourceCorner(.topRight, percent: offsets.topRightPercent, settingAPI: settingAPI, time: time)
        writeSourceCorner(.bottomRight, percent: offsets.bottomRightPercent, settingAPI: settingAPI, time: time)
        writeSourceCorner(.bottomLeft, percent: offsets.bottomLeftPercent, settingAPI: settingAPI, time: time)
        debugLog(
            String(
                format: "set-source-quad tl=(%.2f,%.2f) tr=(%.2f,%.2f) br=(%.2f,%.2f) bl=(%.2f,%.2f)",
                quad.topLeft.x,
                quad.topLeft.y,
                quad.topRight.x,
                quad.topRight.y,
                quad.bottomRight.x,
                quad.bottomRight.y,
                quad.bottomLeft.x,
                quad.bottomLeft.y
            )
        )
    }

    func setCorner(_ point: AUPoint, part: QuadOSCPart, mode: AUQuadTransformMode, offsets: AUCornerOffsets, size: AUSize, settingAPI: FxParameterSettingAPI_v5, time: CMTime) {
        guard let ids = parameterIDs(forCornerPart: part) else {
            return
        }

        switch mode {
        case .outputCorners:
            let pixels = AnyUprightGeometry.cornerPixelOffset(
                forObjectPoint: point,
                corner: ids.corner,
                offsets: offsets,
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

        case .sourceQuad:
            let percent = AnyUprightGeometry.sourceCornerPercentOffset(forObjectPoint: point, corner: ids.corner)
            debugLog(
                String(
                    format: "set-corner part=%d mode=source object=(%.5f,%.5f) writePercent=(%.5f,%.5f)",
                    part.rawValue,
                    point.x,
                    point.y,
                    percent.x,
                    percent.y
                )
            )
            settingAPI.setFloatValue(percent.x, toParameter: ids.percentX.rawValue, at: time)
            settingAPI.setFloatValue(percent.y, toParameter: ids.percentY.rawValue, at: time)
            settingAPI.setFloatValue(0.0, toParameter: ids.pixelX.rawValue, at: time)
            settingAPI.setFloatValue(0.0, toParameter: ids.pixelY.rawValue, at: time)
        }
    }

    func translateCorners(from state: AnyUprightParameterState, pixelDelta: AUPoint, corners: [AUQuadCorner], mode: AUQuadTransformMode, size: AUSize, settingAPI: FxParameterSettingAPI_v5, time: CMTime) {
        let offsets = quadCornerOffsets(from: state)

        if mode == .sourceQuad {
            let percentDelta = AUPoint(
                x: pixelDelta.x / max(size.width, 1.0),
                y: pixelDelta.y / max(size.height, 1.0)
            )
            debugLog(
                String(
                    format: "translate-corners mode=source corners=%@ pixelDelta=(%.2f,%.2f) percentDelta=(%.5f,%.5f)",
                    corners.map { "\($0)" }.joined(separator: ","),
                    pixelDelta.x,
                    pixelDelta.y,
                    percentDelta.x,
                    percentDelta.y
                )
            )
            for corner in corners {
                let ids = parameterIDs(for: corner)
                let percent = percentOffset(for: corner, in: offsets)
                settingAPI.setFloatValue(percent.x + percentDelta.x, toParameter: ids.percentX.rawValue, at: time)
                settingAPI.setFloatValue(percent.y + percentDelta.y, toParameter: ids.percentY.rawValue, at: time)
                settingAPI.setFloatValue(0.0, toParameter: ids.pixelX.rawValue, at: time)
                settingAPI.setFloatValue(0.0, toParameter: ids.pixelY.rawValue, at: time)
            }
            return
        }

        for corner in corners {
            let ids = parameterIDs(for: corner)
            let pixels = pixelOffset(for: corner, in: offsets)
            debugLog(
                String(
                    format: "translate-corner mode=output corner=%@ pixelBase=(%.2f,%.2f) pixelDelta=(%.2f,%.2f)",
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

    func parameterIDs(forCornerPart part: QuadOSCPart) -> (corner: AUQuadCorner, percentX: QuadParam, percentY: QuadParam, pixelX: QuadParam, pixelY: QuadParam)? {
        switch part {
        case .topLeft:
            return (.topLeft, .topLeftPercentX, .topLeftPercentY, .topLeftPixelX, .topLeftPixelY)
        case .topRight:
            return (.topRight, .topRightPercentX, .topRightPercentY, .topRightPixelX, .topRightPixelY)
        case .bottomRight:
            return (.bottomRight, .bottomRightPercentX, .bottomRightPercentY, .bottomRightPixelX, .bottomRightPixelY)
        case .bottomLeft:
            return (.bottomLeft, .bottomLeftPercentX, .bottomLeftPercentY, .bottomLeftPixelX, .bottomLeftPixelY)
        default:
            return nil
        }
    }

    func parameterIDs(for corner: AUQuadCorner) -> (percentX: QuadParam, percentY: QuadParam, pixelX: QuadParam, pixelY: QuadParam) {
        switch corner {
        case .topLeft:
            return (.topLeftPercentX, .topLeftPercentY, .topLeftPixelX, .topLeftPixelY)
        case .topRight:
            return (.topRightPercentX, .topRightPercentY, .topRightPixelX, .topRightPixelY)
        case .bottomRight:
            return (.bottomRightPercentX, .bottomRightPercentY, .bottomRightPixelX, .bottomRightPixelY)
        case .bottomLeft:
            return (.bottomLeftPercentX, .bottomLeftPercentY, .bottomLeftPixelX, .bottomLeftPixelY)
        }
    }

    private func writeSourceCorner(_ corner: AUQuadCorner, percent: AUPoint, settingAPI: FxParameterSettingAPI_v5, time: CMTime) {
        let ids = parameterIDs(for: corner)
        settingAPI.setFloatValue(percent.x, toParameter: ids.percentX.rawValue, at: time)
        settingAPI.setFloatValue(percent.y, toParameter: ids.percentY.rawValue, at: time)
        settingAPI.setFloatValue(0.0, toParameter: ids.pixelX.rawValue, at: time)
        settingAPI.setFloatValue(0.0, toParameter: ids.pixelY.rawValue, at: time)
    }

    func percentOffset(for corner: AUQuadCorner, in offsets: AUCornerOffsets) -> AUPoint {
        switch corner {
        case .topLeft:
            return offsets.topLeftPercent
        case .topRight:
            return offsets.topRightPercent
        case .bottomRight:
            return offsets.bottomRightPercent
        case .bottomLeft:
            return offsets.bottomLeftPercent
        }
    }

    func pixelOffset(for corner: AUQuadCorner, in offsets: AUCornerOffsets) -> AUPoint {
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
