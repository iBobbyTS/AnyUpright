//
//  AnyUprightUprightV2Geometry.swift
//  AnyUpright
//

import Foundation

struct AUUprightV2Matrix3: Equatable {
    var values: [Double]

    init(_ values: [Double]) {
        precondition(values.count == 9)
        self.values = values
    }

    static let identity = AUUprightV2Matrix3([
        1, 0, 0,
        0, 1, 0,
        0, 0, 1,
    ])

    subscript(row: Int, column: Int) -> Double {
        get { values[row * 3 + column] }
        set { values[row * 3 + column] = newValue }
    }

    var determinant: Double {
        self[0, 0] * (self[1, 1] * self[2, 2] - self[1, 2] * self[2, 1])
            - self[0, 1] * (self[1, 0] * self[2, 2] - self[1, 2] * self[2, 0])
            + self[0, 2] * (self[1, 0] * self[2, 1] - self[1, 1] * self[2, 0])
    }

    var transposed: AUUprightV2Matrix3 {
        AUUprightV2Matrix3([
            self[0, 0], self[1, 0], self[2, 0],
            self[0, 1], self[1, 1], self[2, 1],
            self[0, 2], self[1, 2], self[2, 2],
        ])
    }

    func inverted() throws -> AUUprightV2Matrix3 {
        let determinant = determinant
        guard determinant.isFinite, abs(determinant) > 1e-12 else {
            throw AUUprightV2GeometryError.singularMatrix
        }
        let inverse = 1.0 / determinant
        return AUUprightV2Matrix3([
            (self[1, 1] * self[2, 2] - self[1, 2] * self[2, 1]) * inverse,
            (self[0, 2] * self[2, 1] - self[0, 1] * self[2, 2]) * inverse,
            (self[0, 1] * self[1, 2] - self[0, 2] * self[1, 1]) * inverse,
            (self[1, 2] * self[2, 0] - self[1, 0] * self[2, 2]) * inverse,
            (self[0, 0] * self[2, 2] - self[0, 2] * self[2, 0]) * inverse,
            (self[0, 2] * self[1, 0] - self[0, 0] * self[1, 2]) * inverse,
            (self[1, 0] * self[2, 1] - self[1, 1] * self[2, 0]) * inverse,
            (self[0, 1] * self[2, 0] - self[0, 0] * self[2, 1]) * inverse,
            (self[0, 0] * self[1, 1] - self[0, 1] * self[1, 0]) * inverse,
        ])
    }

    static func * (lhs: AUUprightV2Matrix3, rhs: AUUprightV2Matrix3) -> AUUprightV2Matrix3 {
        var result = Array(repeating: 0.0, count: 9)
        for row in 0..<3 {
            for column in 0..<3 {
                result[row * 3 + column] = (0..<3).reduce(0.0) {
                    $0 + lhs[row, $1] * rhs[$1, column]
                }
            }
        }
        return AUUprightV2Matrix3(result)
    }

    static func * (lhs: AUUprightV2Matrix3, rhs: SIMD3<Double>) -> SIMD3<Double> {
        SIMD3(
            lhs[0, 0] * rhs.x + lhs[0, 1] * rhs.y + lhs[0, 2] * rhs.z,
            lhs[1, 0] * rhs.x + lhs[1, 1] * rhs.y + lhs[1, 2] * rhs.z,
            lhs[2, 0] * rhs.x + lhs[2, 1] * rhs.y + lhs[2, 2] * rhs.z
        )
    }
}

enum AUUprightV2GeometryError: Error {
    case degenerateValue
    case singularMatrix
    case nonFiniteMatrix
}

enum AnyUprightUprightV2Geometry {
    static let epsilon = 1e-12

    static func dot(_ first: SIMD3<Double>, _ second: SIMD3<Double>) -> Double {
        first.x * second.x + first.y * second.y + first.z * second.z
    }

    static func dot(_ first: SIMD2<Double>, _ second: SIMD2<Double>) -> Double {
        first.x * second.x + first.y * second.y
    }

    static func cross(_ first: SIMD3<Double>, _ second: SIMD3<Double>) -> SIMD3<Double> {
        SIMD3(
            first.y * second.z - first.z * second.y,
            first.z * second.x - first.x * second.z,
            first.x * second.y - first.y * second.x
        )
    }

    static func norm(_ value: SIMD3<Double>) -> Double {
        sqrt(dot(value, value))
    }

    static func norm(_ value: SIMD2<Double>) -> Double {
        sqrt(dot(value, value))
    }

    static func normalized(_ value: SIMD3<Double>) throws -> SIMD3<Double> {
        let length = norm(value)
        guard length.isFinite, length > epsilon else {
            throw AUUprightV2GeometryError.degenerateValue
        }
        return value / length
    }

    static func normalized(_ value: SIMD2<Double>) throws -> SIMD2<Double> {
        let length = norm(value)
        guard length.isFinite, length > epsilon else {
            throw AUUprightV2GeometryError.degenerateValue
        }
        return value / length
    }

    static func canonicalLine(
        start: AUPoint,
        end: AUPoint
    ) throws -> SIMD3<Double> {
        var line = cross(
            SIMD3(start.x, start.y, 1.0),
            SIMD3(end.x, end.y, 1.0)
        )
        let length = hypot(line.x, line.y)
        guard length > epsilon else {
            throw AUUprightV2GeometryError.degenerateValue
        }
        line /= length
        if line.x < 0.0 || (abs(line.x) <= epsilon && line.y < 0.0) {
            line = -line
        }
        return line
    }

    static func lineDirection(_ line: SIMD3<Double>) throws -> SIMD2<Double> {
        try normalized(SIMD2(-line.y, line.x))
    }

    static func undirectedAngle(
        _ first: SIMD3<Double>,
        _ second: SIMD3<Double>
    ) throws -> Double {
        acos(min(1.0, max(-1.0, abs(dot(try normalized(first), try normalized(second))))))
    }

    static func undirectedAngle(
        _ first: SIMD2<Double>,
        _ second: SIMD2<Double>
    ) throws -> Double {
        acos(min(1.0, max(-1.0, abs(dot(try normalized(first), try normalized(second))))))
    }

    static func intervalOverlapRatio(
        firstStart: AUPoint,
        firstEnd: AUPoint,
        secondStart: AUPoint,
        secondEnd: AUPoint
    ) throws -> Double {
        let direction = try normalized(SIMD2(firstEnd.x - firstStart.x, firstEnd.y - firstStart.y))
        let first = [
            dot(SIMD2(firstStart.x, firstStart.y), direction),
            dot(SIMD2(firstEnd.x, firstEnd.y), direction),
        ].sorted()
        let second = [
            dot(SIMD2(secondStart.x, secondStart.y), direction),
            dot(SIMD2(secondEnd.x, secondEnd.y), direction),
        ].sorted()
        let overlap = max(0.0, min(first[1], second[1]) - max(first[0], second[0]))
        return overlap / max(epsilon, min(first[1] - first[0], second[1] - second[0]))
    }

    static func cameraIntrinsics(
        width: Int,
        height: Int,
        verticalFOV: Double,
        aspectScale: Double = 1.0
    ) -> AUUprightV2Matrix3 {
        let fov = min(150.0 * .pi / 180.0, max(10.0 * .pi / 180.0, verticalFOV))
        let fy = (Double(height) * 0.5) / tan(fov * 0.5)
        let fx = fy * aspectScale
        return AUUprightV2Matrix3([
            fx, 0, (Double(width) - 1.0) * 0.5,
            0, fy, (Double(height) - 1.0) * 0.5,
            0, 0, 1,
        ])
    }

    static func fovFromFocal(height: Int, focal: Double) -> Double {
        2.0 * atan((Double(height) * 0.5) / max(epsilon, focal))
    }

    static func vpToRay(
        _ point: SIMD3<Double>,
        intrinsics: AUUprightV2Matrix3
    ) throws -> SIMD3<Double> {
        try normalized(try intrinsics.inverted() * point)
    }

    static func canonicalRay(_ value: SIMD3<Double>) throws -> SIMD3<Double> {
        var ray = try normalized(value)
        if ray.z < 0.0 || (abs(ray.z) < epsilon && ray.y < 0.0) {
            ray = -ray
        }
        return ray
    }

    static func rotation(axis rawAxis: SIMD3<Double>, angle: Double) throws -> AUUprightV2Matrix3 {
        let axis = try normalized(rawAxis)
        let cosine = cos(angle)
        let sine = sin(angle)
        let oneMinusCosine = 1.0 - cosine
        let x = axis.x
        let y = axis.y
        let z = axis.z
        return AUUprightV2Matrix3([
            cosine + x * x * oneMinusCosine,
            x * y * oneMinusCosine - z * sine,
            x * z * oneMinusCosine + y * sine,
            y * x * oneMinusCosine + z * sine,
            cosine + y * y * oneMinusCosine,
            y * z * oneMinusCosine - x * sine,
            z * x * oneMinusCosine - y * sine,
            z * y * oneMinusCosine + x * sine,
            cosine + z * z * oneMinusCosine,
        ])
    }

    static func rotationAligning(
        _ rawFirst: SIMD3<Double>,
        target rawTarget: SIMD3<Double>,
        strength: Double
    ) throws -> AUUprightV2Matrix3 {
        let first = try normalized(rawFirst)
        let target = try normalized(rawTarget)
        let crossed = cross(first, target)
        let sine = norm(crossed)
        let cosine = min(1.0, max(-1.0, dot(first, target)))
        let boundedStrength = min(1.0, max(0.0, strength))
        if sine <= epsilon {
            if cosine > 0.0 || boundedStrength == 0.0 {
                return .identity
            }
            var axis = cross(first, SIMD3(1, 0, 0))
            if norm(axis) <= epsilon {
                axis = cross(first, SIMD3(0, 1, 0))
            }
            return try rotation(axis: axis, angle: .pi * boundedStrength)
        }
        return try rotation(
            axis: crossed / sine,
            angle: atan2(sine, cosine) * boundedStrength
        )
    }

    static func correctionRotation(
        verticalRay: SIMD3<Double>,
        horizontalRay: SIMD3<Double>?,
        verticalStrength: Double,
        horizontalStrength: Double
    ) throws -> AUUprightV2Matrix3 {
        var vertical = try normalized(verticalRay)
        if vertical.y < 0.0 {
            vertical = -vertical
        }
        let verticalRotation = try rotationAligning(
            vertical,
            target: SIMD3(0, 1, 0),
            strength: verticalStrength
        )
        guard var horizontal = horizontalRay, horizontalStrength > 0.0 else {
            return verticalRotation
        }
        horizontal = try normalized(horizontal)
        horizontal -= vertical * dot(horizontal, vertical)
        horizontal = try normalized(horizontal)
        var afterVertical = try normalized(verticalRotation * horizontal)
        if afterVertical.x < 0.0 {
            afterVertical = -afterVertical
        }
        let yaw = atan2(afterVertical.z, afterVertical.x)
        let yawRotation = try rotation(
            axis: SIMD3(0, 1, 0),
            angle: yaw * horizontalStrength
        )
        return yawRotation * verticalRotation
    }

    static func sourceToOutputHomography(
        width: Int,
        height: Int,
        sourceIntrinsics: AUUprightV2Matrix3,
        correction: AUUprightV2Matrix3,
        focalScale: Double,
        aspect: Double
    ) throws -> AUUprightV2Matrix3 {
        var target = sourceIntrinsics
        target[0, 0] *= focalScale * aspect
        target[1, 1] *= focalScale / max(epsilon, aspect)
        return try normalizedHomography(target * correction * sourceIntrinsics.inverted())
    }

    static func normalizedHomography(
        _ matrix: AUUprightV2Matrix3
    ) throws -> AUUprightV2Matrix3 {
        guard matrix.values.allSatisfy(\.isFinite), abs(matrix.determinant) > 1e-10 else {
            throw AUUprightV2GeometryError.nonFiniteMatrix
        }
        var scale = matrix[2, 2]
        if abs(scale) <= epsilon {
            scale = pow(abs(matrix.determinant), 1.0 / 3.0)
        }
        guard scale.isFinite, abs(scale) > epsilon else {
            throw AUUprightV2GeometryError.nonFiniteMatrix
        }
        return AUUprightV2Matrix3(matrix.values.map { $0 / scale })
    }

    static func transformedPoint(
        _ point: AUPoint,
        by matrix: AUUprightV2Matrix3
    ) -> AUPoint? {
        let result = matrix * SIMD3(point.x, point.y, 1.0)
        guard abs(result.z) > epsilon else {
            return nil
        }
        let transformed = AUPoint(x: result.x / result.z, y: result.y / result.z)
        return transformed.x.isFinite && transformed.y.isFinite ? transformed : nil
    }

    static func frameAndCropHomography(
        _ sourceToOutput: AUUprightV2Matrix3,
        width: Int,
        height: Int,
        maximumScale: Double
    ) throws -> (matrix: AUUprightV2Matrix3, cropScale: Double) {
        let center = AUPoint(
            x: (Double(width) - 1.0) * 0.5,
            y: (Double(height) - 1.0) * 0.5
        )
        guard let mappedCenter = transformedPoint(center, by: sourceToOutput) else {
            throw AUUprightV2GeometryError.nonFiniteMatrix
        }
        var translation = AUUprightV2Matrix3.identity
        translation[0, 2] = center.x - mappedCenter.x
        translation[1, 2] = center.y - mappedCenter.y
        let centered = translation * sourceToOutput
        let corners = imageCorners(width: width, height: height)

        func zoomed(_ scale: Double) -> AUUprightV2Matrix3 {
            AUUprightV2Matrix3([
                scale, 0, center.x * (1.0 - scale),
                0, scale, center.y * (1.0 - scale),
                0, 0, 1,
            ]) * centered
        }

        func covers(_ scale: Double) -> Bool {
            let points = corners.compactMap { transformedPoint($0, by: zoomed(scale)) }
            return points.count == corners.count && convexContains(polygon: points, points: corners)
        }

        if covers(1.0) {
            return (try normalizedHomography(zoomed(1.0)), 1.0)
        }
        if !covers(maximumScale) {
            return (try normalizedHomography(zoomed(maximumScale)), maximumScale + 0.001)
        }
        var low = 1.0
        var high = maximumScale
        for _ in 0..<32 {
            let middle = (low + high) * 0.5
            if covers(middle) {
                high = middle
            } else {
                low = middle
            }
        }
        return (try normalizedHomography(zoomed(high)), high)
    }

    static func transformedLines(
        _ lines: [SIMD3<Double>],
        by sourceToOutput: AUUprightV2Matrix3
    ) throws -> [SIMD3<Double>?] {
        let transform = try sourceToOutput.inverted().transposed
        return lines.map { line in
            var result = transform * line
            let length = hypot(result.x, result.y)
            guard length > epsilon else {
                return nil
            }
            result /= length
            return result
        }
    }

    static func axisResidual(_ line: SIMD3<Double>) -> Double {
        let angle = atan2(abs(line.x), abs(-line.y))
        return min(angle, abs(.pi * 0.5 - angle))
    }

    static func jacobianStatistics(
        _ matrix: AUUprightV2Matrix3,
        width: Int,
        height: Int,
        gridSize: Int = 9
    ) -> (condition: Double, areaSpread: Double) {
        var conditions: [Double] = []
        var areas: [Double] = []
        for row in 0..<gridSize {
            let y = Double(row) * (Double(height) - 1.0) / Double(gridSize - 1)
            for column in 0..<gridSize {
                let x = Double(column) * (Double(width) - 1.0) / Double(gridSize - 1)
                let denominator = matrix[2, 0] * x + matrix[2, 1] * y + matrix[2, 2]
                guard abs(denominator) > epsilon,
                      let output = transformedPoint(AUPoint(x: x, y: y), by: matrix) else {
                    return (.infinity, .infinity)
                }
                let j00 = (matrix[0, 0] - matrix[2, 0] * output.x) / denominator
                let j01 = (matrix[0, 1] - matrix[2, 1] * output.x) / denominator
                let j10 = (matrix[1, 0] - matrix[2, 0] * output.y) / denominator
                let j11 = (matrix[1, 1] - matrix[2, 1] * output.y) / denominator
                let a = j00 * j00 + j10 * j10
                let b = j00 * j01 + j10 * j11
                let d = j01 * j01 + j11 * j11
                let trace = a + d
                let discriminant = sqrt(max(0.0, (a - d) * (a - d) + 4.0 * b * b))
                let maximum = sqrt(max(0.0, (trace + discriminant) * 0.5))
                let minimum = sqrt(max(0.0, (trace - discriminant) * 0.5))
                guard minimum > epsilon else {
                    return (.infinity, .infinity)
                }
                conditions.append(log(max(1.0, maximum / minimum)))
                let area = abs(j00 * j11 - j01 * j10)
                if area > epsilon {
                    areas.append(area)
                }
            }
        }
        guard !areas.isEmpty else {
            return (.infinity, .infinity)
        }
        return (
            percentile(conditions, 0.95),
            log(percentile(areas, 0.95) / percentile(areas, 0.05))
        )
    }

    static func normalizedGridDisplacement(
        _ matrix: AUUprightV2Matrix3,
        width: Int,
        height: Int,
        gridSize: Int = 5
    ) -> Double {
        var sum = 0.0
        var count = 0
        for row in 0..<gridSize {
            let y = Double(row) * (Double(height) - 1.0) / Double(gridSize - 1)
            for column in 0..<gridSize {
                let x = Double(column) * (Double(width) - 1.0) / Double(gridSize - 1)
                guard let output = transformedPoint(AUPoint(x: x, y: y), by: matrix) else {
                    return .infinity
                }
                sum += hypot(output.x - x, output.y - y)
                count += 1
            }
        }
        return sum / Double(max(1, count)) / hypot(Double(width), Double(height))
    }

    static func smallestEigenvector(
        of input: AUUprightV2Matrix3
    ) throws -> SIMD3<Double> {
        var matrix = input
        var vectors = AUUprightV2Matrix3.identity
        for _ in 0..<32 {
            let candidates = [
                (abs(matrix[0, 1]), 0, 1),
                (abs(matrix[0, 2]), 0, 2),
                (abs(matrix[1, 2]), 1, 2),
            ]
            guard let largest = candidates.max(by: { $0.0 < $1.0 }), largest.0 > 1e-14 else {
                break
            }
            let p = largest.1
            let q = largest.2
            let angle = 0.5 * atan2(2.0 * matrix[p, q], matrix[q, q] - matrix[p, p])
            let cosine = cos(angle)
            let sine = sin(angle)
            var rotation = AUUprightV2Matrix3.identity
            rotation[p, p] = cosine
            rotation[q, q] = cosine
            rotation[p, q] = sine
            rotation[q, p] = -sine
            matrix = rotation.transposed * matrix * rotation
            vectors = vectors * rotation
        }
        let diagonal = [matrix[0, 0], matrix[1, 1], matrix[2, 2]]
        guard let index = diagonal.indices.min(by: { diagonal[$0] < diagonal[$1] }) else {
            throw AUUprightV2GeometryError.degenerateValue
        }
        return try normalized(SIMD3(vectors[0, index], vectors[1, index], vectors[2, index]))
    }

    private static func imageCorners(width: Int, height: Int) -> [AUPoint] {
        [
            AUPoint(x: 0, y: 0),
            AUPoint(x: Double(width) - 1.0, y: 0),
            AUPoint(x: Double(width) - 1.0, y: Double(height) - 1.0),
            AUPoint(x: 0, y: Double(height) - 1.0),
        ]
    }

    private static func convexContains(
        polygon: [AUPoint],
        points: [AUPoint]
    ) -> Bool {
        var signs: [Double] = []
        for index in polygon.indices {
            let first = polygon[index]
            let second = polygon[(index + 1) % polygon.count]
            let edgeX = second.x - first.x
            let edgeY = second.y - first.y
            signs.append(contentsOf: points.map {
                edgeX * ($0.y - first.y) - edgeY * ($0.x - first.x)
            })
        }
        return signs.allSatisfy { $0 >= -1e-7 } || signs.allSatisfy { $0 <= 1e-7 }
    }

    private static func percentile(_ values: [Double], _ fraction: Double) -> Double {
        let ordered = values.sorted()
        guard ordered.count > 1 else {
            return ordered.first ?? .infinity
        }
        let position = Double(ordered.count - 1) * fraction
        let lower = Int(floor(position))
        let upper = Int(ceil(position))
        let weight = position - Double(lower)
        return ordered[lower] * (1.0 - weight) + ordered[upper] * weight
    }
}
