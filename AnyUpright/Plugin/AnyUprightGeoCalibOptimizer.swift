//
//  AnyUprightGeoCalibOptimizer.swift
//  AnyUpright
//

import Foundation

enum AUGeoCalibOptimizerError: Error, CustomStringConvertible {
    case invalidInput(String)
    case unsupportedConfiguration(String)

    var description: String {
        switch self {
        case .invalidInput(let message):
            return "Invalid GeoCalib optimizer input: \(message)"
        case .unsupportedConfiguration(let message):
            return "Unsupported GeoCalib optimizer configuration: \(message)"
        }
    }
}

struct AUGeoCalibOptimizerConfiguration {
    var cameraModel = "pinhole"
    var numSteps = 30
    var lambda = 0.1
    var useSphericalManifold = true
    var useLogFocal = true
    var upLossScale = 1e-2
    var latitudeLossScale = 1e-2
}

struct AUGeoCalibDenseFields {
    var width: Int
    var height: Int
    var upFieldNCHW: [Float]
    var upConfidenceNCHW: [Float]
    var latitudeFieldNCHW: [Float]
    var latitudeConfidenceNCHW: [Float]
    var scales: SIMD2<Float>

    var pixelCount: Int {
        width * height
    }
}

struct AUGeoCalibOptimizerResult {
    var cameraData: [Float]
    var gravityData: [Float]
    var rollRadians: Double
    var pitchRadians: Double
    var verticalFOVRadians: Double
    var stopAt: Int
    var initialCost: Double
    var finalCost: Double
    var initialUpCost: Double
    var initialLatitudeCost: Double
    var finalUpCost: Double
    var finalLatitudeCost: Double
    var rollUncertaintyRadians: Double
    var pitchUncertaintyRadians: Double
    var gravityUncertainty: Double
    var focalUncertainty: Double
    var verticalFOVUncertaintyRadians: Double
    var covariance: [Float]
}

enum AUGeoCalibOptimizer {
    static func optimize(
        fields: AUGeoCalibDenseFields,
        configuration: AUGeoCalibOptimizerConfiguration = AUGeoCalibOptimizerConfiguration()
    ) throws -> AUGeoCalibOptimizerResult {
        try validate(fields)
        guard configuration.cameraModel == "pinhole" else {
            throw AUGeoCalibOptimizerError.unsupportedConfiguration("only pinhole is currently supported")
        }

        var camera = initialCamera(fields: fields)
        var gravity = AUOptimizerGravity.fromRollPitch(roll: 0, pitch: 0)
        var damping = configuration.lambda
        var stopAt = configuration.numSteps
        var initialCost = 0.0
        var initialUpCost = 0.0
        var initialLatitudeCost = 0.0
        var previousCost = 0.0

        for step in 0..<configuration.numSteps {
            let system = accumulateSystem(
                camera: camera,
                gravity: gravity,
                fields: fields,
                configuration: configuration,
                asRollPitchFocal: false,
                includeJacobians: true
            )
            if step == 0 {
                initialUpCost = system.costs.up
                initialLatitudeCost = system.costs.latitude
                initialCost = system.costs.total
                previousCost = system.costs.total
            }

            let delta = solveDampedSystem(
                gradient: system.gradient,
                hessian: system.hessian,
                lambda: damping
            )
            camera.updateFocal(delta: delta[2], asLog: configuration.useLogFocal)
            gravity.update(
                delta0: delta[0],
                delta1: delta[1],
                spherical: configuration.useSphericalManifold
            )

            let newCosts = accumulateSystem(
                camera: camera,
                gravity: gravity,
                fields: fields,
                configuration: configuration,
                asRollPitchFocal: false,
                includeJacobians: false
            ).costs
            damping = min(max(damping * (newCosts.total > previousCost ? 10 : 0.1), 1e-6), 1e2)
            if closeEnough(newCosts.total, previousCost) {
                stopAt = min(step + 1, stopAt)
                break
            }
            previousCost = newCosts.total
        }

        let finalSystem = accumulateSystem(
            camera: camera,
            gravity: gravity,
            fields: fields,
            configuration: configuration,
            asRollPitchFocal: false,
            includeJacobians: false
        )
        let uncertaintySystem = accumulateSystem(
            camera: camera,
            gravity: gravity,
            fields: fields,
            configuration: configuration,
            asRollPitchFocal: true,
            includeJacobians: true
        )
        let covariance = inverse3x3(uncertaintySystem.hessian) ?? Array(repeating: 0, count: 9)
        let rollVariance = max(covariance[0], 0)
        let pitchVariance = max(covariance[4], 0)
        let gravityTrace = covariance[0] + covariance[4]
        let gravityDetPart = sqrt(
            (covariance[0] - covariance[4]) * (covariance[0] - covariance[4]) +
            4 * covariance[1] * covariance[3]
        )
        let gravityVariance = max((gravityTrace + gravityDetPart) / 2, 0)
        let focalVariance = max(covariance[8], 0)
        let jFOV = jFocalToFOV(focal: camera.fy, height: camera.height)
        let verticalFOVVariance = jFOV * jFOV * focalVariance

        return AUGeoCalibOptimizerResult(
            cameraData: camera.data,
            gravityData: gravity.data,
            rollRadians: gravity.roll,
            pitchRadians: gravity.pitch,
            verticalFOVRadians: focalToFOV(focal: camera.fy, height: camera.height),
            stopAt: stopAt,
            initialCost: initialCost,
            finalCost: finalSystem.costs.total,
            initialUpCost: initialUpCost,
            initialLatitudeCost: initialLatitudeCost,
            finalUpCost: finalSystem.costs.up,
            finalLatitudeCost: finalSystem.costs.latitude,
            rollUncertaintyRadians: sqrt(rollVariance),
            pitchUncertaintyRadians: sqrt(pitchVariance),
            gravityUncertainty: sqrt(gravityVariance),
            focalUncertainty: sqrt(focalVariance) / 2,
            verticalFOVUncertaintyRadians: sqrt(verticalFOVVariance / 2),
            covariance: covariance.map(Float.init)
        )
    }

    private static func validate(_ fields: AUGeoCalibDenseFields) throws {
        guard fields.width > 0, fields.height > 0 else {
            throw AUGeoCalibOptimizerError.invalidInput("width and height must be positive")
        }
        let pixels = fields.width * fields.height
        guard fields.upFieldNCHW.count == 2 * pixels else {
            throw AUGeoCalibOptimizerError.invalidInput("up_field must be [1, 2, H, W]")
        }
        guard fields.upConfidenceNCHW.count == pixels,
              fields.latitudeFieldNCHW.count == pixels,
              fields.latitudeConfidenceNCHW.count == pixels else {
            throw AUGeoCalibOptimizerError.invalidInput("confidence and latitude tensors must be [1, 1, H, W]")
        }
        guard fields.scales.x > 0, fields.scales.y > 0 else {
            throw AUGeoCalibOptimizerError.invalidInput("image scales must be positive")
        }
    }

    private static func initialCamera(fields: AUGeoCalibDenseFields) -> AUOptimizerCamera {
        let height = Double(fields.height)
        let width = Double(fields.width)
        let focal = 0.7 * max(height, width)
        let scaleX = Double(fields.scales.x)
        let scaleY = Double(fields.scales.y)
        return AUOptimizerCamera(
            width: width,
            height: height,
            fx: focal * scaleX / scaleY,
            fy: focal,
            cx: width / 2,
            cy: height / 2
        )
    }

    private static func accumulateSystem(
        camera: AUOptimizerCamera,
        gravity: AUOptimizerGravity,
        fields: AUGeoCalibDenseFields,
        configuration: AUGeoCalibOptimizerConfiguration,
        asRollPitchFocal: Bool,
        includeJacobians: Bool
    ) -> AUOptimizerSystem {
        let gravityJacobian = asRollPitchFocal ? jRollPitch(gravity) : sphericalJPlus(x0: gravity.x, x1: gravity.y, x2: gravity.z)
        let gravityJ00 = gravityJacobian[0][0]
        let gravityJ01 = gravityJacobian[0][1]
        let gravityJ10 = gravityJacobian[1][0]
        let gravityJ11 = gravityJacobian[1][1]
        let gravityJ20 = gravityJacobian[2][0]
        let gravityJ21 = gravityJacobian[2][1]
        let width = fields.width
        let height = fields.height
        let pixels = fields.pixelCount
        let upField = fields.upFieldNCHW
        let upConfidence = fields.upConfidenceNCHW
        let latitudeField = fields.latitudeFieldNCHW
        let latitudeConfidence = fields.latitudeConfidenceNCHW
        let focalScaleX = asRollPitchFocal || !configuration.useLogFocal ? 1 / camera.fx : 1
        let focalScaleY = asRollPitchFocal || !configuration.useLogFocal ? 1 / camera.fy : 1
        var accumulator = AUOptimizerAccumulator()
        var upCostSum = 0.0
        var latitudeCostSum = 0.0

        for yy in 0..<height {
            let y = Double(yy)
            let pixelRow = yy * width
            for xx in 0..<width {
                let x = Double(xx)
                let pixel = pixelRow + xx
                let uvx = (x - camera.cx) / camera.fx
                let uvy = (y - camera.cy) / camera.fy

                let projectedX = gravity.x - gravity.z * uvx
                let projectedY = gravity.y - gravity.z * uvy
                let projectedNorm = max(sqrt(projectedX * projectedX + projectedY * projectedY), 1e-30)
                let predictedUpX = projectedX / projectedNorm
                let predictedUpY = projectedY / projectedNorm
                let upResidualX = Double(upField[pixel]) - predictedUpX
                let upResidualY = Double(upField[pixels + pixel]) - predictedUpY
                let upSquared = upResidualX * upResidualX + upResidualY * upResidualY
                var upLoss = huberCostAndWeight(squaredResidual: upSquared, scale: configuration.upLossScale)
                let upConfidenceValue = Double(upConfidence[pixel])
                upLoss.cost *= upConfidenceValue
                upLoss.weight *= upConfidenceValue
                upCostSum += upLoss.cost

                let rayNorm = max(sqrt(uvx * uvx + uvy * uvy + 1), 1e-30)
                let invRayNorm = 1 / rayNorm
                let rayX = uvx * invRayNorm
                let rayY = uvy * invRayNorm
                let rayZ = invRayNorm
                let predictedLatitudeSin = rayX * gravity.x + rayY * gravity.y + rayZ * gravity.z
                let targetLatitudeSin = sin(Double(latitudeField[pixel]))
                let latitudeResidual = targetLatitudeSin - predictedLatitudeSin
                var latitudeLoss = huberCostAndWeight(
                    squaredResidual: latitudeResidual * latitudeResidual,
                    scale: configuration.latitudeLossScale
                )
                let latitudeConfidenceValue = Double(latitudeConfidence[pixel])
                latitudeLoss.cost *= latitudeConfidenceValue
                latitudeLoss.weight *= latitudeConfidenceValue
                latitudeCostSum += latitudeLoss.cost

                guard includeJacobians else {
                    continue
                }

                let invProjectedNorm = 1 / projectedNorm
                let invProjectedNorm3 = 1 / (projectedNorm * projectedNorm * projectedNorm)
                let normalizeJ00 = invProjectedNorm - projectedX * projectedX * invProjectedNorm3
                let normalizeJ01 = -projectedX * projectedY * invProjectedNorm3
                let normalizeJ10 = -projectedY * projectedX * invProjectedNorm3
                let normalizeJ11 = invProjectedNorm - projectedY * projectedY * invProjectedNorm3

                let projectedJ00 = gravityJ00 - uvx * gravityJ20
                let projectedJ01 = gravityJ01 - uvx * gravityJ21
                let projectedJ10 = gravityJ10 - uvy * gravityJ20
                let projectedJ11 = gravityJ11 - uvy * gravityJ21
                let upJ00 = normalizeJ00 * projectedJ00 + normalizeJ01 * projectedJ10
                let upJ01 = normalizeJ00 * projectedJ01 + normalizeJ01 * projectedJ11
                let upJ10 = normalizeJ10 * projectedJ00 + normalizeJ11 * projectedJ10
                let upJ11 = normalizeJ10 * projectedJ01 + normalizeJ11 * projectedJ11

                let focalJacobianX = -uvx * focalScaleX
                let focalJacobianY = -uvy * focalScaleY
                let projectionFocalJacobianX = -gravity.z * focalJacobianX
                let projectionFocalJacobianY = -gravity.z * focalJacobianY
                let upJ02 = normalizeJ00 * projectionFocalJacobianX + normalizeJ01 * projectionFocalJacobianY
                let upJ12 = normalizeJ10 * projectionFocalJacobianX + normalizeJ11 * projectionFocalJacobianY
                accumulator.addRow(
                    j0: upJ00,
                    j1: upJ01,
                    j2: upJ02,
                    residual: upResidualX,
                    weight: upLoss.weight
                )
                accumulator.addRow(
                    j0: upJ10,
                    j1: upJ11,
                    j2: upJ12,
                    residual: upResidualY,
                    weight: upLoss.weight
                )

                let invRayNorm3 = 1 / (rayNorm * rayNorm * rayNorm)
                let latitudeJ0 = rayX * gravityJ00 + rayY * gravityJ10 + rayZ * gravityJ20
                let latitudeJ1 = rayX * gravityJ01 + rayY * gravityJ11 + rayZ * gravityJ21
                let rayNormalizeJ00 = invRayNorm - uvx * uvx * invRayNorm3
                let rayNormalizeJ01 = -uvx * uvy * invRayNorm3
                let rayNormalizeJ10 = -uvy * uvx * invRayNorm3
                let rayNormalizeJ11 = invRayNorm - uvy * uvy * invRayNorm3
                let rayNormalizeJ20 = -uvx * invRayNorm3
                let rayNormalizeJ21 = -uvy * invRayNorm3
                let rayFocalJacobianX = rayNormalizeJ00 * focalJacobianX + rayNormalizeJ01 * focalJacobianY
                let rayFocalJacobianY = rayNormalizeJ10 * focalJacobianX + rayNormalizeJ11 * focalJacobianY
                let rayFocalJacobianZ = rayNormalizeJ20 * focalJacobianX + rayNormalizeJ21 * focalJacobianY
                let latitudeJ2 = rayFocalJacobianX * gravity.x + rayFocalJacobianY * gravity.y + rayFocalJacobianZ * gravity.z
                accumulator.addRow(
                    j0: latitudeJ0,
                    j1: latitudeJ1,
                    j2: latitudeJ2,
                    residual: latitudeResidual,
                    weight: latitudeLoss.weight
                )
            }
        }

        let pixelsAsDouble = Double(fields.pixelCount)
        return AUOptimizerSystem(
            costs: AUOptimizerCosts(up: upCostSum / pixelsAsDouble, latitude: latitudeCostSum / pixelsAsDouble),
            gradient: accumulator.gradient,
            hessian: accumulator.hessian
        )
    }
}

private struct AUOptimizerCamera {
    let width: Double
    let height: Double
    var fx: Double
    var fy: Double
    let cx: Double
    let cy: Double

    var data: [Float] {
        [Float(width), Float(height), Float(fx), Float(fy), Float(cx), Float(cy), 0, 0]
    }

    mutating func updateFocal(delta: Double, asLog: Bool) {
        let oldRatio = fx / fy
        let scale = asLog ? exp(delta) : 1
        var newFx = asLog ? fx * scale : fx + delta
        var newFy = asLog ? fy * scale : fy + delta
        let minF = fovToFocal(150 * Double.pi / 180, height: height)
        let maxF = fovToFocal(5 * Double.pi / 180, height: height)
        newFx = min(max(newFx, minF), maxF)
        newFy = min(max(newFy, minF), maxF)
        fy = newFy
        fx = newFy * oldRatio
    }
}

private struct AUOptimizerGravity {
    var x: Double
    var y: Double
    var z: Double

    init(x: Double, y: Double, z: Double) {
        let norm = max(sqrt(x * x + y * y + z * z), 1e-30)
        self.x = x / norm
        self.y = y / norm
        self.z = z / norm
    }

    static func fromRollPitch(roll: Double, pitch: Double) -> AUOptimizerGravity {
        let sr = sin(roll)
        let cr = cos(roll)
        let sp = sin(pitch)
        let cp = cos(pitch)
        return AUOptimizerGravity(x: -sr * cp, y: -cr * cp, z: sp)
    }

    var data: [Float] {
        [Float(x), Float(y), Float(z)]
    }

    var roll: Double {
        let denominator = sqrt(max(0, 1 - z * z)) + 1e-4
        let value = min(max(-x / denominator, -1), 1)
        let base = asin(value)
        let signX = x > 0 ? 1.0 : (x < 0 ? -1.0 : 0.0)
        let offset = -Double.pi * signX
        return y < 0 ? base : -base + offset
    }

    var pitch: Double {
        asin(min(max(z, -1), 1))
    }

    mutating func update(delta0: Double, delta1: Double, spherical: Bool) {
        if spherical {
            let updated = sphericalPlus(x: [x, y, z], delta: [delta0, delta1])
            self = AUOptimizerGravity(x: updated[0], y: updated[1], z: updated[2])
        } else {
            self = AUOptimizerGravity.fromRollPitch(roll: roll + delta0, pitch: pitch + delta1)
        }
    }
}

private struct AUOptimizerCosts {
    let up: Double
    let latitude: Double

    var total: Double {
        up + latitude
    }
}

private struct AUOptimizerSystem {
    let costs: AUOptimizerCosts
    let gradient: [Double]
    let hessian: [Double]
}

private struct AUOptimizerAccumulator {
    var gradient0 = 0.0
    var gradient1 = 0.0
    var gradient2 = 0.0
    var hessian00 = 0.0
    var hessian01 = 0.0
    var hessian02 = 0.0
    var hessian10 = 0.0
    var hessian11 = 0.0
    var hessian12 = 0.0
    var hessian20 = 0.0
    var hessian21 = 0.0
    var hessian22 = 0.0

    var gradient: [Double] {
        [gradient0, gradient1, gradient2]
    }

    var hessian: [Double] {
        [
            hessian00, hessian01, hessian02,
            hessian10, hessian11, hessian12,
            hessian20, hessian21, hessian22
        ]
    }

    @inline(__always)
    mutating func addRow(j0: Double, j1: Double, j2: Double, residual: Double, weight: Double) {
        let weightedResidual = weight * residual
        gradient0 += weightedResidual * j0
        gradient1 += weightedResidual * j1
        gradient2 += weightedResidual * j2

        let weightedJ0 = weight * j0
        let weightedJ1 = weight * j1
        let weightedJ2 = weight * j2
        hessian00 += weightedJ0 * j0
        hessian01 += weightedJ0 * j1
        hessian02 += weightedJ0 * j2
        hessian10 += weightedJ1 * j0
        hessian11 += weightedJ1 * j1
        hessian12 += weightedJ1 * j2
        hessian20 += weightedJ2 * j0
        hessian21 += weightedJ2 * j1
        hessian22 += weightedJ2 * j2
    }
}

private func fovToFocal(_ fov: Double, height: Double) -> Double {
    height / (2 * tan(fov / 2))
}

private func focalToFOV(focal: Double, height: Double) -> Double {
    2 * atan(height / (2 * focal))
}

private func jFocalToFOV(focal: Double, height: Double) -> Double {
    -4 * height / (4 * focal * focal + height * height)
}

private func closeEnough(_ first: Double, _ second: Double, absoluteTolerance: Double = 1e-8, relativeTolerance: Double = 1e-8) -> Bool {
    abs(first - second) <= absoluteTolerance + relativeTolerance * abs(second)
}

private func huberCostAndWeight(squaredResidual: Double, scale: Double) -> (cost: Double, weight: Double) {
    let scaled = squaredResidual / (scale * scale)
    if scaled <= 1 {
        return (squaredResidual, 1)
    }

    let root = sqrt(scaled + 1e-8)
    let weight = max(1.1920928955078125e-7, 1 / root)
    return ((2 * root - 1) * scale * scale, weight)
}

private func householderVector(_ x: [Double]) -> (v: [Double], beta: Double) {
    var sigma = x[0] * x[0] + x[1] * x[1]
    if sigma < 1e-7 {
        sigma += 1e-7
    }
    let xpiv = x[2]
    let norm = sqrt(sigma + xpiv * xpiv)
    let vpiv = xpiv < 0 ? xpiv - norm : -sigma / (xpiv + norm)
    let beta = 2 * vpiv * vpiv / (sigma + vpiv * vpiv)
    return ([x[0] / vpiv, x[1] / vpiv, 1], beta)
}

private func sphericalJPlus(_ x: [Double]) -> [[Double]] {
    let (v, beta) = householderVector(x)
    var h = Array(repeating: Array(repeating: 0.0, count: 2), count: 3)
    for row in 0..<3 {
        for column in 0..<2 {
            h[row][column] = (row == column ? 1 : 0) - beta * v[row] * v[column]
        }
    }
    return h
}

private func sphericalJPlus(x0: Double, x1: Double, x2: Double) -> [[Double]] {
    sphericalJPlus([x0, x1, x2])
}

private func sphericalPlus(x: [Double], delta: [Double]) -> [Double] {
    let nx = max(sqrt(x[0] * x[0] + x[1] * x[1] + x[2] * x[2]), 1e-30)
    let nd = sqrt(delta[0] * delta[0] + delta[1] * delta[1])
    let sinc = nd < 1e-7 ? 1 : sin(nd) / nd
    let expDelta = [sinc * delta[0], sinc * delta[1], cos(nd)]
    let (v, beta) = householderVector(x)
    let dot = v[0] * expDelta[0] + v[1] * expDelta[1] + v[2] * expDelta[2]
    let scale = beta * dot
    return [
        nx * (expDelta[0] - v[0] * scale),
        nx * (expDelta[1] - v[1] * scale),
        nx * (expDelta[2] - v[2] * scale)
    ]
}

private func jRollPitch(_ gravity: AUOptimizerGravity) -> [[Double]] {
    let roll = gravity.roll
    let pitch = gravity.pitch
    let cp = cos(pitch)
    let sp = sin(pitch)
    let cr = cos(roll)
    let sr = sin(roll)
    return [
        [-cr * cp, sr * sp],
        [sr * cp, cr * sp],
        [0, cp]
    ]
}

private func inverse3x3(_ m: [Double]) -> [Double]? {
    let a = m[0], b = m[1], c = m[2]
    let d = m[3], e = m[4], f = m[5]
    let g = m[6], h = m[7], i = m[8]
    let c00 = e * i - f * h
    let c01 = -(d * i - f * g)
    let c02 = d * h - e * g
    let c10 = -(b * i - c * h)
    let c11 = a * i - c * g
    let c12 = -(a * h - b * g)
    let c20 = b * f - c * e
    let c21 = -(a * f - c * d)
    let c22 = a * e - b * d
    let determinant = a * c00 + b * c01 + c * c02
    guard abs(determinant) > 1e-30 else {
        return nil
    }
    let invDeterminant = 1 / determinant
    return [
        c00 * invDeterminant, c10 * invDeterminant, c20 * invDeterminant,
        c01 * invDeterminant, c11 * invDeterminant, c21 * invDeterminant,
        c02 * invDeterminant, c12 * invDeterminant, c22 * invDeterminant
    ]
}

private func solveDampedSystem(gradient: [Double], hessian: [Double], lambda: Double) -> [Double] {
    var h = hessian
    for index in 0..<3 {
        let diagonalIndex = index * 3 + index
        h[diagonalIndex] += max(hessian[diagonalIndex] * lambda, 1e-6)
    }

    let a00 = h[0]
    guard a00 > 0 else { return [0, 0, 0] }
    let l00 = sqrt(a00)
    let l10 = h[3] / l00
    let l20 = h[6] / l00
    let a11 = h[4] - l10 * l10
    guard a11 > 0 else { return [0, 0, 0] }
    let l11 = sqrt(a11)
    let l21 = (h[7] - l20 * l10) / l11
    let a22 = h[8] - l20 * l20 - l21 * l21
    guard a22 > 0 else { return [0, 0, 0] }
    let l22 = sqrt(a22)

    let y0 = gradient[0] / l00
    let y1 = (gradient[1] - l10 * y0) / l11
    let y2 = (gradient[2] - l20 * y0 - l21 * y1) / l22

    let x2 = y2 / l22
    let x1 = (y1 - l21 * x2) / l11
    let x0 = (y0 - l10 * x1 - l20 * x2) / l00
    return [x0, x1, x2]
}
