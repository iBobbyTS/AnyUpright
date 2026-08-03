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
    case keyframesSet = 3
    case keyframesRemoved = 4

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
        case .keyframesSet:
            return localizedMessage(
                key: "AnyUpright::Keyframes Set",
                fallback: "已设置关键帧"
            )
        case .keyframesRemoved:
            return localizedMessage(
                key: "AnyUpright::Keyframes Removed",
                fallback: "已删除关键帧\n如果片段上已经有关键帧，拖动本身就会在当前帧创建新的关键帧，不需要重复点击本按钮"
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

final class AUTransientDisplayStatusController {
    static let defaultDuration: TimeInterval = 3.0
    private static let defaultQueue = DispatchQueue.main

    private let lock = NSLock()
    private let queue: DispatchQueue
    private var generation: UInt64 = 0
    private var pendingClear: DispatchWorkItem?

    init(queue: DispatchQueue = defaultQueue) {
        self.queue = queue
        AUTransientDisplayStatusDiagnostics.log("controller-init controller=\(ObjectIdentifier(self))")
    }

    deinit {
        lock.lock()
        let finalGeneration = generation
        let hadPendingClear = pendingClear != nil
        pendingClear?.cancel()
        pendingClear = nil
        lock.unlock()
        AUTransientDisplayStatusDiagnostics.log(
            "controller-deinit controller=\(ObjectIdentifier(self)) generation=\(finalGeneration) pending=\(hadPendingClear ? 1 : 0)"
        )
    }

    func show(
        _ status: AUAnalysisDisplayStatus,
        duration: TimeInterval = defaultDuration,
        traceID: String = UUID().uuidString,
        applyInitial: (AUAnalysisDisplayStatus) -> Void,
        clear: @escaping () -> Void
    ) {
        precondition(status != .none)

        lock.lock()
        generation &+= 1
        let scheduledGeneration = generation
        let replacedPendingClear = pendingClear != nil
        pendingClear?.cancel()
        let scheduledAt = AUMonotonicClock.nowNanos()
        let workItem = DispatchWorkItem { [self] in
            let elapsed = AUMonotonicClock.elapsedMilliseconds(since: scheduledAt)
            AUTransientDisplayStatusDiagnostics.log(
                "timer-fired trace=\(traceID) controller=\(ObjectIdentifier(self)) generation=\(scheduledGeneration) elapsedMs=\(String(format: "%.3f", elapsed))"
            )
            guard claimExpiration(generation: scheduledGeneration, traceID: traceID) else {
                return
            }
            AUTransientDisplayStatusDiagnostics.log(
                "timer-apply-clear trace=\(traceID) controller=\(ObjectIdentifier(self)) generation=\(scheduledGeneration)"
            )
            clear()
            AUTransientDisplayStatusDiagnostics.log(
                "timer-apply-clear-returned trace=\(traceID) controller=\(ObjectIdentifier(self)) generation=\(scheduledGeneration)"
            )
        }
        pendingClear = workItem
        lock.unlock()

        AUTransientDisplayStatusDiagnostics.log(
            "show trace=\(traceID) controller=\(ObjectIdentifier(self)) generation=\(scheduledGeneration) status=\(status.rawValue) duration=\(String(format: "%.3f", duration)) replacedPending=\(replacedPendingClear ? 1 : 0)"
        )
        applyInitial(status)
        AUTransientDisplayStatusDiagnostics.log(
            "show-initial-apply-returned trace=\(traceID) controller=\(ObjectIdentifier(self)) generation=\(scheduledGeneration) status=\(status.rawValue)"
        )
        queue.asyncAfter(deadline: .now() + max(0.0, duration), execute: workItem)
        AUTransientDisplayStatusDiagnostics.log(
            "timer-scheduled trace=\(traceID) controller=\(ObjectIdentifier(self)) generation=\(scheduledGeneration)"
        )
    }

    private func claimExpiration(generation expectedGeneration: UInt64, traceID: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard generation == expectedGeneration else {
            AUTransientDisplayStatusDiagnostics.log(
                "timer-rejected trace=\(traceID) controller=\(ObjectIdentifier(self)) expectedGeneration=\(expectedGeneration) actualGeneration=\(generation)"
            )
            return false
        }
        pendingClear = nil
        AUTransientDisplayStatusDiagnostics.log(
            "timer-claimed trace=\(traceID) controller=\(ObjectIdentifier(self)) generation=\(expectedGeneration)"
        )
        return true
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
        // Motion composes the OSC IOSurface across the Y-up Canvas boundary.
        // Flip only the text texture UVs; the Canvas-space quad stays unchanged.
        let vBottom = Float((visible.bottom - card.bottom) / card.height)
        let vTop = Float((visible.top - card.bottom) / card.height)

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
