import Darwin
import Foundation
import Metal

private let stressQueueCount = 5

private func fail(_ message: String) -> Never {
    fputs("stress-metal-device-cache failed: \(message)\n", stderr)
    exit(1)
}

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fail(message)
    }
}

@main
enum StressMetalDeviceCache {
    static func main() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("skipped: no Metal device")
            return
        }

        let pixelFormat = MTLPixelFormat.bgra8Unorm
        var commandQueues = [AnyObject]()
        for _ in 0..<stressQueueCount {
            guard let commandQueue = device.makeCommandQueue() else {
                fail("device could not create all command queues")
            }
            commandQueues.append(commandQueue as AnyObject)
        }

        let pool = CommandQueuePool<AnyObject>(resources: commandQueues)
        let activeLock = NSLock()
        var activeIDs = Set<ObjectIdentifier>()
        var duplicateActiveLeaseCount = 0
        var checkoutFailureCount = 0

        DispatchQueue.concurrentPerform(iterations: stressQueueCount * 4) { workerIndex in
            guard let lease = checkoutEventually(from: pool) else {
                activeLock.lock()
                checkoutFailureCount += 1
                activeLock.unlock()
                return
            }

            let leaseID = ObjectIdentifier(lease.resource)
            activeLock.lock()
            if activeIDs.contains(leaseID) {
                duplicateActiveLeaseCount += 1
            }
            activeIDs.insert(leaseID)
            activeLock.unlock()

            Thread.sleep(forTimeInterval: 0.002 + Double(workerIndex % 5) * 0.0005)

            activeLock.lock()
            activeIDs.remove(leaseID)
            activeLock.unlock()

            lease.returnToPool()
        }

        expect(checkoutFailureCount == 0, "some workers could not checkout a command queue")
        expect(duplicateActiveLeaseCount == 0, "same command queue was leased to multiple active workers")

        var finalLeases = [CommandQueuePool<AnyObject>.Lease]()
        for _ in 0..<stressQueueCount {
            guard let lease = pool.checkout() else {
                fail("not all command queues were available after stress")
            }
            finalLeases.append(lease)
        }
        expect(pool.checkout() == nil, "pool issued more command queues than its capacity")
        finalLeases.forEach { $0.returnToPool() }
        expect(pool.availableCount == stressQueueCount, "final leases did not return to the pool")

        print("stress-metal-device-cache passed: \(stressQueueCount) queues, pixelFormat=\(pixelFormat.rawValue)")
    }

    private static func checkoutEventually(
        from pool: CommandQueuePool<AnyObject>,
        attempts: Int = 1_000
    ) -> CommandQueuePool<AnyObject>.Lease? {
        for _ in 0..<attempts {
            if let lease = pool.checkout() {
                return lease
            }
            Thread.sleep(forTimeInterval: 0.001)
        }
        return nil
    }
}
