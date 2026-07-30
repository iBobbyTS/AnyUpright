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
        try testFullTileLayout()
        try testPartialTileClipping()
        try testNoIntersectionAndInvalidDimensions()
        print("AnyUprightAnalysisStatusTests passed")
    }

    private static func testMessages() throws {
        try require(AUAnalysisDisplayStatusParameter.id >= 1, "status parameter ID lower bound")
        try require(AUAnalysisDisplayStatusParameter.id <= 9998, "status parameter ID upper bound")
        try require(AUAnalysisDisplayStatus.none.message == nil, "none must not render text")
        try require(AUAnalysisDisplayStatus.modelLoading.message == "模型加载中", "model loading message")
        try require(AUAnalysisDisplayStatus.analyzingFrame.message == "画面分析中", "analyzing message")
        try require(AUAnalysisDisplayStatus.allCases.count == 3, "status cases")
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
            SIMD2<Float>(1, 1),
            SIMD2<Float>(0, 1),
            SIMD2<Float>(1, 0),
            SIMD2<Float>(0, 0),
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
        try require(approximatelyEqual(top.textureCoordinates[0].y, 0.5), "top tile lower v clipping")
        try require(top.textureCoordinates[2].y == 0, "top tile starts at v=0")
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
