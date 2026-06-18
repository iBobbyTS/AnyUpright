//
//  MetalDeviceCache.swift
//  AnyUpright
//
//  Created by iBobby on 2026-06-05.
//

import Foundation

let kMaxCommandQueues   = 5

final class MetalCommandQueueLease {
    let commandQueue: MTLCommandQueue

    private let poolLease: CommandQueuePool<AnyObject>.Lease
    private let returnLock = NSLock()
    private var returned = false

    fileprivate init(commandQueue: MTLCommandQueue, poolLease: CommandQueuePool<AnyObject>.Lease) {
        self.commandQueue = commandQueue
        self.poolLease = poolLease
    }

    func returnToCache() {
        returnLock.lock()
        guard !returned else {
            returnLock.unlock()
            return
        }
        returned = true
        returnLock.unlock()

        poolLease.returnToPool()
    }

    deinit {
        returnToCache()
    }
}

class MetalDeviceCacheItem: NSObject {
    let gpuDevice : MTLDevice
    let pipelineState : MTLRenderPipelineState
    let pixelFormat : MTLPixelFormat
    private let commandQueuePool: CommandQueuePool<AnyObject>
    
    init(with newDevice:MTLDevice, pixFormat:MTLPixelFormat) throws {
        gpuDevice = newDevice
        
        // Set up the command queue cache for each device
        var commandQueues = [AnyObject]()
        for _ in 0..<kMaxCommandQueues
        {
            if let commandQueue = gpuDevice.makeCommandQueue()
            {
                commandQueues.append(commandQueue as AnyObject)
            }
        }
        commandQueuePool = CommandQueuePool(resources: commandQueues)
        
        // Load all the shader files with a .metal file extension in the project
        let defaultLibrary = gpuDevice.makeDefaultLibrary()
        
        // Configure a pipeline descriptor that is used to create a pipeline state
        let pipelineStateDescriptor = MTLRenderPipelineDescriptor.init()
        pipelineStateDescriptor.label = "AnyUprightWarp"
        let vertexFunction = defaultLibrary?.makeFunction(name: "anyUprightWarpVertex")
        let fragmentFunction = defaultLibrary?.makeFunction(name: "anyUprightWarpFragment")
        pipelineStateDescriptor.vertexFunction = vertexFunction
        pipelineStateDescriptor.fragmentFunction = fragmentFunction
        pipelineStateDescriptor.colorAttachments [ 0 ].pixelFormat = pixFormat
        pixelFormat = pixFormat

        try pipelineState = gpuDevice.makeRenderPipelineState(descriptor: pipelineStateDescriptor)
    }
    
    func commandQueueLease() -> MetalCommandQueueLease? {
        guard let poolLease = commandQueuePool.checkout() else {
            return nil
        }

        guard let commandQueue = poolLease.resource as? MTLCommandQueue else {
            poolLease.returnToPool()
            return nil
        }

        return MetalCommandQueueLease(commandQueue: commandQueue, poolLease: poolLease)
    }
}

class MetalDeviceCache: NSObject {
    private var deviceCaches : [MetalDeviceCacheItem]
    private let deviceCachesLock = NSLock()
    static let deviceCache = MetalDeviceCache()
        
    override init() {
        let devices = MTLCopyAllDevices()
        
        deviceCaches = Array.init()
        for nextDevice in devices
        {
            do {
                let newCacheItem = try MetalDeviceCacheItem.init(with: nextDevice, pixFormat: MTLPixelFormat.rgba16Float)
                deviceCaches.append(newCacheItem)
            } catch {
                NSLog ("Unable to create device cache in AnyUpright.")
            }
        }
    }
    
    class func FxMTLPixelFormat(for imageTile:FxImageTile) -> MTLPixelFormat {
        var result = MTLPixelFormat.rgba16Float
        
        switch imageTile.ioSurface.pixelFormat {
        case kCVPixelFormatType_128RGBAFloat:
            result = MTLPixelFormat.rgba32Float
            
        case kCVPixelFormatType_32BGRA:
            result = MTLPixelFormat.bgra8Unorm
            
        default:
            NSLog("Got an unexpected pixel format in the IOSurface: 0x%08x", imageTile.ioSurface.pixelFormat)
        }
        return result
    }
    

    func device(with registryID:UInt64) -> MTLDevice? {
        deviceCachesLock.lock()
        defer { deviceCachesLock.unlock() }

        if let cacheItem = deviceCaches.first(where: { $0.gpuDevice.registryID == registryID }) {
            return cacheItem.gpuDevice
        }
        
        return nil
    }
    
    func pipelineState(with registryID:UInt64, pixelFormat:MTLPixelFormat) -> MTLRenderPipelineState? {
        cacheItem(with: registryID, pixelFormat: pixelFormat)?.pipelineState
    }
    
    func commandQueueLease(with registryID:UInt64, pixelFormat:MTLPixelFormat) -> MetalCommandQueueLease? {
        cacheItem(with: registryID, pixelFormat: pixelFormat)?.commandQueueLease()
    }

    private func cacheItem(with registryID: UInt64, pixelFormat: MTLPixelFormat) -> MetalDeviceCacheItem? {
        deviceCachesLock.lock()
        defer { deviceCachesLock.unlock() }

        if let cacheItem = deviceCaches.first(where: { $0.gpuDevice.registryID == registryID && $0.pixelFormat == pixelFormat }) {
            return cacheItem
        }

        guard let device = MTLCopyAllDevices().first(where: { $0.registryID == registryID }) else {
            return nil
        }

        do {
            let newCacheItem = try MetalDeviceCacheItem.init(with: device, pixFormat: pixelFormat)
            deviceCaches.append(newCacheItem)
            return newCacheItem
        } catch {
            NSLog ("Unable to create a new cache item with the desired pixel format")
            return nil
        }
    }
}
