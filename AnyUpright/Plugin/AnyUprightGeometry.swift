//
//  AnyUprightGeometry.swift
//  AnyUpright
//

import Foundation
import simd

struct AUPoint: Equatable {
    var x: Double
    var y: Double
}

struct AUSize: Equatable {
    var width: Double
    var height: Double
}

struct AUQuad: Equatable {
    var topLeft: AUPoint
    var topRight: AUPoint
    var bottomRight: AUPoint
    var bottomLeft: AUPoint

    static func fullFrame(_ size: AUSize) -> AUQuad {
        AUQuad(
            topLeft: AUPoint(x: 0.0, y: 0.0),
            topRight: AUPoint(x: size.width, y: 0.0),
            bottomRight: AUPoint(x: size.width, y: size.height),
            bottomLeft: AUPoint(x: 0.0, y: size.height)
        )
    }
}

struct AUCornerOffsets {
    var topLeftPercent: AUPoint = AUPoint(x: 0.0, y: 0.0)
    var topRightPercent: AUPoint = AUPoint(x: 0.0, y: 0.0)
    var bottomRightPercent: AUPoint = AUPoint(x: 0.0, y: 0.0)
    var bottomLeftPercent: AUPoint = AUPoint(x: 0.0, y: 0.0)

    var topLeftPixels: AUPoint = AUPoint(x: 0.0, y: 0.0)
    var topRightPixels: AUPoint = AUPoint(x: 0.0, y: 0.0)
    var bottomRightPixels: AUPoint = AUPoint(x: 0.0, y: 0.0)
    var bottomLeftPixels: AUPoint = AUPoint(x: 0.0, y: 0.0)
}

enum AnyUprightGeometry {
    static func quad(from offsets: AUCornerOffsets, size: AUSize) -> AUQuad {
        func apply(_ base: AUPoint, percent: AUPoint, pixels: AUPoint) -> AUPoint {
            AUPoint(
                x: base.x + percent.x * size.width + pixels.x,
                y: base.y - percent.y * size.height - pixels.y
            )
        }

        let frame = AUQuad.fullFrame(size)
        return AUQuad(
            topLeft: apply(frame.topLeft, percent: offsets.topLeftPercent, pixels: offsets.topLeftPixels),
            topRight: apply(frame.topRight, percent: offsets.topRightPercent, pixels: offsets.topRightPixels),
            bottomRight: apply(frame.bottomRight, percent: offsets.bottomRightPercent, pixels: offsets.bottomRightPixels),
            bottomLeft: apply(frame.bottomLeft, percent: offsets.bottomLeftPercent, pixels: offsets.bottomLeftPixels)
        )
    }

    static func uprightQuad(vertical: Double, horizontal: Double, size: AUSize) -> AUQuad {
        let maxInset = min(size.width, size.height) * 0.25
        let verticalInset = abs(vertical) * maxInset
        let horizontalInset = abs(horizontal) * maxInset

        var quad = AUQuad.fullFrame(size)

        if vertical > 0.0 {
            quad.topLeft.x += verticalInset
            quad.topRight.x -= verticalInset
        } else if vertical < 0.0 {
            quad.bottomLeft.x += verticalInset
            quad.bottomRight.x -= verticalInset
        }

        if horizontal > 0.0 {
            quad.topRight.y += horizontalInset
            quad.bottomRight.y -= horizontalInset
        } else if horizontal < 0.0 {
            quad.topLeft.y += horizontalInset
            quad.bottomLeft.y -= horizontalInset
        }

        return quad
    }

    static func rotationScaleToFill(angleRadians: Double, size: AUSize) -> Double {
        let center = AUPoint(x: size.width / 2.0, y: size.height / 2.0)
        let corners = [
            AUPoint(x: 0.0, y: 0.0),
            AUPoint(x: size.width, y: 0.0),
            AUPoint(x: size.width, y: size.height),
            AUPoint(x: 0.0, y: size.height)
        ]

        let c = cos(-angleRadians)
        let s = sin(-angleRadians)
        var scale = 1.0

        for corner in corners {
            let dx = corner.x - center.x
            let dy = corner.y - center.y
            let rotatedX = c * dx - s * dy
            let rotatedY = s * dx + c * dy
            if size.width > 0.0 {
                scale = max(scale, abs(rotatedX) / (size.width / 2.0))
            }
            if size.height > 0.0 {
                scale = max(scale, abs(rotatedY) / (size.height / 2.0))
            }
        }

        return scale
    }

    static func rotationOutputToSource(angleRadians: Double, fillFrame: Bool, size: AUSize) -> simd_float3x3 {
        let scale = fillFrame ? rotationScaleToFill(angleRadians: angleRadians, size: size) : 1.0
        let center = AUPoint(x: size.width / 2.0, y: size.height / 2.0)
        let c = cos(-angleRadians) / scale
        let s = sin(-angleRadians) / scale

        let a = c
        let b = -s
        let d = s
        let e = c
        let tx = center.x - a * center.x - b * center.y
        let ty = center.y - d * center.x - e * center.y

        return matrix(a, b, tx, d, e, ty, 0.0, 0.0, 1.0)
    }

    static func homography(from output: AUQuad, to source: AUQuad) -> simd_float3x3 {
        let pairs = [
            (output.topLeft, source.topLeft),
            (output.topRight, source.topRight),
            (output.bottomRight, source.bottomRight),
            (output.bottomLeft, source.bottomLeft)
        ]

        var equations = Array(repeating: Array(repeating: 0.0, count: 9), count: 8)
        for (index, pair) in pairs.enumerated() {
            let x = pair.0.x
            let y = pair.0.y
            let u = pair.1.x
            let v = pair.1.y
            let row = index * 2

            equations[row][0] = x
            equations[row][1] = y
            equations[row][2] = 1.0
            equations[row][6] = -u * x
            equations[row][7] = -u * y
            equations[row][8] = u

            equations[row + 1][3] = x
            equations[row + 1][4] = y
            equations[row + 1][5] = 1.0
            equations[row + 1][6] = -v * x
            equations[row + 1][7] = -v * y
            equations[row + 1][8] = v
        }

        guard let solution = solve(equations) else {
            return matrix(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0)
        }

        return matrix(
            solution[0], solution[1], solution[2],
            solution[3], solution[4], solution[5],
            solution[6], solution[7], 1.0
        )
    }

    static func multiply(_ lhs: simd_float3x3, _ rhs: simd_float3x3) -> simd_float3x3 {
        lhs * rhs
    }

    private static func matrix(_ a: Double, _ b: Double, _ c: Double,
                               _ d: Double, _ e: Double, _ f: Double,
                               _ g: Double, _ h: Double, _ i: Double) -> simd_float3x3 {
        simd_float3x3(columns: (
            SIMD3<Float>(Float(a), Float(d), Float(g)),
            SIMD3<Float>(Float(b), Float(e), Float(h)),
            SIMD3<Float>(Float(c), Float(f), Float(i))
        ))
    }

    private static func solve(_ augmented: [[Double]]) -> [Double]? {
        var matrix = augmented
        let rowCount = 8
        let columnCount = 8

        for pivotColumn in 0..<columnCount {
            var pivotRow = pivotColumn
            var pivotValue = abs(matrix[pivotRow][pivotColumn])

            for row in (pivotColumn + 1)..<rowCount {
                let value = abs(matrix[row][pivotColumn])
                if value > pivotValue {
                    pivotValue = value
                    pivotRow = row
                }
            }

            if pivotValue < 0.000000001 {
                return nil
            }

            if pivotRow != pivotColumn {
                matrix.swapAt(pivotRow, pivotColumn)
            }

            let pivot = matrix[pivotColumn][pivotColumn]
            for column in pivotColumn...columnCount {
                matrix[pivotColumn][column] /= pivot
            }

            for row in 0..<rowCount where row != pivotColumn {
                let factor = matrix[row][pivotColumn]
                if factor == 0.0 {
                    continue
                }
                for column in pivotColumn...columnCount {
                    matrix[row][column] -= factor * matrix[pivotColumn][column]
                }
            }
        }

        return matrix.map { $0[columnCount] }
    }
}
