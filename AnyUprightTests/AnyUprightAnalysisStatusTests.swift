import Foundation
import simd

private enum AnalysisStatusTestFailure: Error, CustomStringConvertible {
    case failed(String)

    var description: String {
        switch self {
        case .failed(let message): return message
        }
    }
}

@main
struct AnyUprightAnalysisStatusTests {
    static func main() throws {
        try testMessages()
        try testTransientStatusExpires()
        try testNewTransientStatusSupersedesOldExpiration()
        try testTransientStatusOutlivesCallingOwner()
        try testFullTileLayout()
        try testPartialTileClipping()
        try testNoIntersectionAndInvalidDimensions()
        print("AnyUprightAnalysisStatusTests passed")
    }

    private static func testMessages() throws {
        try require(AUAnalysisDisplayStatusParameter.id >= 1, "status parameter ID lower bound")
        try require(AUAnalysisDisplayStatusParameter.id <= 9998, "status parameter ID upper bound")
        try require(AUAnalysisDisplayStatus.none.message == nil, "none must not render text")
        try require(AUAnalysisDisplayStatus.modelLoading.message == "Loading model", "model loading fallback message")
        try require(AUAnalysisDisplayStatus.analyzingFrame.message == "Analyzing frame", "analyzing fallback message")
        try require(AUAnalysisDisplayStatus.keyframesSet.message == "Keyframes set", "keyframes set fallback message")
        try require(AUAnalysisDisplayStatus.keyframesSet.preferredTransientDuration == 2.0, "keyframes set duration")
        try require(
            AUAnalysisDisplayStatus.keyframesRemoved.message == "Keyframes removed\nIf the clip already has keyframes, dragging creates a keyframe at the current frame. You do not need to click this button again.",
            "keyframes removed fallback message"
        )
        try require(AUAnalysisDisplayStatus.keyframesRemoved.preferredTransientDuration == 6.0, "keyframes removed duration")
        try require(AUAnalysisDisplayStatus.allCases.count == 5, "status cases")
    }

    private static func testTransientStatusExpires() throws {
        let queue = DispatchQueue(label: "AnyUprightAnalysisStatusTests.expiration")
        let controller = AUTransientDisplayStatusController(queue: queue)
        let lock = NSLock()
        var statuses: [AUAnalysisDisplayStatus] = []
        controller.show(
            .keyframesSet,
            duration: 0.02,
            applyInitial: { status in
                lock.lock()
                statuses.append(status)
                lock.unlock()
            },
            clear: {
                lock.lock()
                statuses.append(.none)
                lock.unlock()
            }
        )
        Thread.sleep(forTimeInterval: 0.08)
        lock.lock()
        let captured = statuses
        lock.unlock()
        try require(captured == [.keyframesSet, .none], "transient status must clear after its duration")
    }

    private static func testNewTransientStatusSupersedesOldExpiration() throws {
        let queue = DispatchQueue(label: "AnyUprightAnalysisStatusTests.generation")
        let controller = AUTransientDisplayStatusController(queue: queue)
        let lock = NSLock()
        var statuses: [AUAnalysisDisplayStatus] = []
        let record: (AUAnalysisDisplayStatus) -> Void = { status in
            lock.lock()
            statuses.append(status)
            lock.unlock()
        }
        controller.show(
            .keyframesSet,
            duration: 0.02,
            applyInitial: record,
            clear: { record(.none) }
        )
        Thread.sleep(forTimeInterval: 0.01)
        controller.show(
            .keyframesRemoved,
            duration: 0.06,
            applyInitial: record,
            clear: { record(.none) }
        )
        Thread.sleep(forTimeInterval: 0.03)
        lock.lock()
        let beforeLatestExpiration = statuses
        lock.unlock()
        try require(
            beforeLatestExpiration == [.keyframesSet, .keyframesRemoved],
            "an old timer must not clear a newer status"
        )
        Thread.sleep(forTimeInterval: 0.06)
        lock.lock()
        let afterLatestExpiration = statuses
        lock.unlock()
        try require(
            afterLatestExpiration == [.keyframesSet, .keyframesRemoved, .none],
            "the newest timer must clear the current status"
        )
    }

    private static func testTransientStatusOutlivesCallingOwner() throws {
        let queue = DispatchQueue(label: "AnyUprightAnalysisStatusTests.owner-lifetime")
        let lock = NSLock()
        var statuses: [AUAnalysisDisplayStatus] = []
        var controller: AUTransientDisplayStatusController? = AUTransientDisplayStatusController(queue: queue)
        controller?.show(
            .keyframesSet,
            duration: 0.02,
            applyInitial: { status in
                lock.lock()
                statuses.append(status)
                lock.unlock()
            },
            clear: {
                lock.lock()
                statuses.append(.none)
                lock.unlock()
            }
        )
        controller = nil

        Thread.sleep(forTimeInterval: 0.08)
        lock.lock()
        let captured = statuses
        lock.unlock()
        try require(
            captured == [.keyframesSet, .none],
            "a pending clear must survive release of the calling owner"
        )
    }

    private static func testFullTileLayout() throws {
        let image = rect(0, 0, 1920, 1080)
        let quad = try requireQuad(AUAnalysisStatusOverlayLayout.quad(
            imageRect: image,
            tileRect: image,
            cardWidth: 200,
            cardHeight: 80
        ))
        try require(quad.positions == [
            SIMD2<Float>(100, -40),
            SIMD2<Float>(-100, -40),
            SIMD2<Float>(100, 40),
            SIMD2<Float>(-100, 40),
        ], "full tile positions")
        try require(quad.textureCoordinates == [
            SIMD2<Float>(1, 0),
            SIMD2<Float>(0, 0),
            SIMD2<Float>(1, 1),
            SIMD2<Float>(0, 1),
        ], "full tile texture coordinates")
    }

    private static func testPartialTileClipping() throws {
        let image = rect(0, 0, 1920, 1080)
        let left = try requireQuad(AUAnalysisStatusOverlayLayout.quad(
            imageRect: image,
            tileRect: rect(0, 0, 900, 1080),
            cardWidth: 200,
            cardHeight: 80
        ))
        try require(left.positions == [
            SIMD2<Float>(450, -40),
            SIMD2<Float>(410, -40),
            SIMD2<Float>(450, 40),
            SIMD2<Float>(410, 40),
        ], "left tile positions")
        try require(approximatelyEqual(left.textureCoordinates[0].x, 0.2), "left tile u clipping")
        try require(left.textureCoordinates[1].x == 0, "left tile starts at u=0")

        let top = try requireQuad(AUAnalysisStatusOverlayLayout.quad(
            imageRect: image,
            tileRect: rect(0, 540, 1920, 1080),
            cardWidth: 200,
            cardHeight: 80
        ))
        try require(approximatelyEqual(top.textureCoordinates[0].y, 0.5), "top tile lower flipped-v clipping")
        try require(top.textureCoordinates[2].y == 1, "top tile ends at flipped v=1")
    }

    private static func testNoIntersectionAndInvalidDimensions() throws {
        let image = rect(0, 0, 1920, 1080)
        try require(AUAnalysisStatusOverlayLayout.quad(
            imageRect: image,
            tileRect: rect(0, 0, 800, 1080),
            cardWidth: 200,
            cardHeight: 80
        ) == nil, "non-intersecting tile")
        try require(AUAnalysisStatusOverlayLayout.quad(
            imageRect: rect(0, 0, 0, 1080),
            tileRect: image,
            cardWidth: 200,
            cardHeight: 80
        ) == nil, "empty image")
        try require(AUAnalysisStatusOverlayLayout.quad(
            imageRect: image,
            tileRect: image,
            cardWidth: 0,
            cardHeight: 80
        ) == nil, "empty card")
    }

    private static func rect(_ left: Double, _ bottom: Double, _ right: Double, _ top: Double) -> AUAnalysisStatusRect {
        AUAnalysisStatusRect(left: left, bottom: bottom, right: right, top: top)
    }

    private static func requireQuad(_ quad: AUAnalysisStatusOverlayQuad?) throws -> AUAnalysisStatusOverlayQuad {
        guard let quad else {
            throw AnalysisStatusTestFailure.failed("expected overlay quad")
        }
        return quad
    }

    private static func approximatelyEqual(_ lhs: Float, _ rhs: Float) -> Bool {
        abs(lhs - rhs) < 0.000_001
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw AnalysisStatusTestFailure.failed(message) }
    }
}
