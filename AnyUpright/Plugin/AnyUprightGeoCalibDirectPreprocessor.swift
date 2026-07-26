//
//  AnyUprightGeoCalibDirectPreprocessor.swift
//  AnyUpright
//

import Foundation
import Metal

enum AUGeoCalibDirectImagePreprocessor {
    static func preprocessFrame(
        _ frame: FxImageTile,
        targetShortSide: Int = 320,
        edgeDivisibleBy: Int = 32,
        targetInputShape: [Int]? = nil,
        deviceCache: MetalDeviceCache = MetalDeviceCache.deviceCache
    ) throws -> AUGeoCalibPreprocessedImage {
        guard frame.ioSurface != nil else {
            throw AUGeoCalibHorizonDetectorError.invalidImage("analysis frame has no IOSurface")
        }

        let bounds = frame.imagePixelBounds
        let sourceWidth = max(1, Int(bounds.right - bounds.left))
        let sourceHeight = max(1, Int(bounds.top - bounds.bottom))
        let target: (width: Int, height: Int)
        if let targetInputShape {
            let validated = try AUGeoCalibInputShapeSpec.validateInputShape(targetInputShape)
            target = (width: validated.cropWidth, height: validated.cropHeight)
        } else {
            let geometry = try AUGeoCalibPreprocessGeometry(
                sourceWidth: sourceWidth,
                sourceHeight: sourceHeight,
                targetShortSide: targetShortSide,
                edgeDivisibleBy: edgeDivisibleBy
            )
            target = (width: geometry.cropWidth, height: geometry.cropHeight)
        }

        guard let device = deviceCache.analysisDevice(preferredRegistryID: frame.deviceRegistryID),
              let sourceTexture = frame.metalTexture(for: device) else {
            throw AUGeoCalibHorizonDetectorError.invalidImage("unable to create Metal texture for analysis frame")
        }
        let pixelFormat = MetalDeviceCache.FxMTLPixelFormat(for: frame)
        let commandQueueLease = deviceCache.commandQueueLease(with: device.registryID, pixelFormat: pixelFormat)
        let commandQueue = commandQueueLease?.commandQueue ?? device.makeCommandQueue()
        defer { commandQueueLease?.returnToCache() }
        guard let commandQueue else {
            throw AUGeoCalibHorizonDetectorError.invalidImage("unable to create Metal command queue")
        }

        let resamplingGeometry = try AUImageResamplingGeometry(
            sourceWidth: sourceWidth,
            sourceHeight: sourceHeight,
            targetWidth: target.width,
            targetHeight: target.height,
            layout: .aspectFillCenterCrop
        )
        let tensor: AUImageResampledTensor
        do {
            tensor = try AUAppleSiliconImageResampler.resample(
                sourceTexture: sourceTexture,
                sourceWidth: sourceWidth,
                sourceHeight: sourceHeight,
                targetWidth: target.width,
                targetHeight: target.height,
                layout: .aspectFillCenterCrop,
                channels: .rgb,
                commandQueue: commandQueue
            )
        } catch {
            throw AUGeoCalibHorizonDetectorError.invalidImage(String(describing: error))
        }

        return AUGeoCalibPreprocessedImage(
            inputRGBNCHW: tensor.values,
            inputShape: tensor.shape,
            scales: SIMD2<Float>(
                Float(resamplingGeometry.resizedWidth) / Float(sourceWidth),
                Float(resamplingGeometry.resizedHeight) / Float(sourceHeight)
            )
        )
    }
}
