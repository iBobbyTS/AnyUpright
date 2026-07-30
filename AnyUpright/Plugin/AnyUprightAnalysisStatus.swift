//
//  AnyUprightAnalysisStatus.swift
//  AnyUpright
//

import Foundation
import simd

private final class AUAnalysisStatusLocalizationToken {}

enum AUAnalysisDisplayStatusParameter {
    // FxPlug parameter IDs must be in the inclusive range 1...9998.
    static let id: UInt32 = 9997
}

enum AUAnalysisDisplayStatus: Int32, CaseIterable, Hashable {
    case none = 0
    case modelLoading = 1
    case analyzingFrame = 2

    var message: String? {
        switch self {
        case .none:
            return nil
        case .modelLoading:
            return localizedMessage(
                key: "AnyUpright::Analysis Model Loading",
                fallback: "模型加载中"
            )
        case .analyzingFrame:
            return localizedMessage(
                key: "AnyUpright::Analysis Frame Analyzing",
                fallback: "画面分析中"
            )
        }
    }

    private func localizedMessage(key: String, fallback: String) -> String {
        Bundle(for: AUAnalysisStatusLocalizationToken.self).localizedString(
            forKey: key,
            value: fallback,
            table: nil
        )
    }
}

struct AUAnalysisStatusRect: Equatable {
    var left: Double
    var bottom: Double
    var right: Double
    var top: Double

    var width: Double { max(0.0, right - left) }
    var height: Double { max(0.0, top - bottom) }

    func intersection(_ other: AUAnalysisStatusRect) -> AUAnalysisStatusRect? {
        let result = AUAnalysisStatusRect(
            left: max(left, other.left),
            bottom: max(bottom, other.bottom),
            right: min(right, other.right),
            top: min(top, other.top)
        )
        return result.width > 0.0 && result.height > 0.0 ? result : nil
    }
}

struct AUAnalysisStatusOverlayQuad: Equatable {
    var positions: [SIMD2<Float>]
    var textureCoordinates: [SIMD2<Float>]
}

enum AUAnalysisStatusOverlayLayout {
    static func quad(
        imageRect: AUAnalysisStatusRect,
        tileRect: AUAnalysisStatusRect,
        cardWidth: Double,
        cardHeight: Double
    ) -> AUAnalysisStatusOverlayQuad? {
        guard imageRect.width > 0.0,
              imageRect.height > 0.0,
              tileRect.width > 0.0,
              tileRect.height > 0.0,
              cardWidth > 0.0,
              cardHeight > 0.0 else {
            return nil
        }

        let centerX = (imageRect.left + imageRect.right) * 0.5
        let centerY = (imageRect.bottom + imageRect.top) * 0.5
        let card = AUAnalysisStatusRect(
            left: centerX - cardWidth * 0.5,
            bottom: centerY - cardHeight * 0.5,
            right: centerX + cardWidth * 0.5,
            top: centerY + cardHeight * 0.5
        )
        guard let visible = card.intersection(tileRect) else {
            return nil
        }

        let tileCenterX = (tileRect.left + tileRect.right) * 0.5
        let tileCenterY = (tileRect.bottom + tileRect.top) * 0.5
        let left = Float(visible.left - tileCenterX)
        let right = Float(visible.right - tileCenterX)
        let bottom = Float(visible.bottom - tileCenterY)
        let top = Float(visible.top - tileCenterY)

        let uLeft = Float((visible.left - card.left) / card.width)
        let uRight = Float((visible.right - card.left) / card.width)
        let vTop = Float((card.top - visible.top) / card.height)
        let vBottom = Float((card.top - visible.bottom) / card.height)

        return AUAnalysisStatusOverlayQuad(
            positions: [
                SIMD2<Float>(right, bottom),
                SIMD2<Float>(left, bottom),
                SIMD2<Float>(right, top),
                SIMD2<Float>(left, top),
            ],
            textureCoordinates: [
                SIMD2<Float>(uRight, vBottom),
                SIMD2<Float>(uLeft, vBottom),
                SIMD2<Float>(uRight, vTop),
                SIMD2<Float>(uLeft, vTop),
            ]
        )
    }
}
