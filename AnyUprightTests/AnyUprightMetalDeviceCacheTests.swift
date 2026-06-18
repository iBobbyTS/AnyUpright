import Darwin
import Foundation

private final class FakeCommandQueue: NSObject {}

private struct TestFailure: Error, CustomStringConvertible {
    let description: String
}

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() {
        throw TestFailure(description: message)
    }
}

@main
enum AnyUprightMetalDeviceCacheTests {
    static func main() {
        do {
            try testCheckoutExclusivity()
            try testReturnIsIdempotent()
            try testLeaseDeinitReturnsResource()
            try testConcurrentCheckoutDoesNotDuplicateActiveResource()
            print("AnyUprightMetalDeviceCacheTests passed")
        } catch {
            fputs("AnyUprightMetalDeviceCacheTests failed: \(error)\n", stderr)
            exit(1)
        }
    }

    private static func testCheckoutExclusivity() throws {
        let queueA = FakeCommandQueue()
        let queueB = FakeCommandQueue()
        let pool = CommandQueuePool(resources: [queueA, queueB])

        guard let leaseA = pool.checkout(),
              let leaseB = pool.checkout() else {
            throw TestFailure(description: "expected both queue slots to be checked out")
        }

        try expect(leaseA.resource !== leaseB.resource, "pool issued the same queue to two active leases")
        try expect(pool.checkout() == nil, "pool issued more leases than available queue slots")

        leaseA.returnToPool()
        guard let leaseC = pool.checkout() else {
            throw TestFailure(description: "returned queue slot was not reusable")
        }
        try expect(pool.contains(leaseC.resource), "reused lease came from outside the pool")

        leaseB.returnToPool()
        leaseC.returnToPool()
    }

    private static func testReturnIsIdempotent() throws {
        let queue = FakeCommandQueue()
        let pool = CommandQueuePool(resources: [queue])

        guard let lease = pool.checkout() else {
            throw TestFailure(description: "expected one queue lease")
        }

        lease.returnToPool()
        lease.returnToPool()

        try expect(pool.availableCount == 1, "double return changed pool availability")
        guard let nextLease = pool.checkout() else {
            throw TestFailure(description: "queue was unavailable after idempotent return")
        }
        try expect(nextLease.resource === queue, "pool returned an unexpected queue")
        nextLease.returnToPool()
    }

    private static func testLeaseDeinitReturnsResource() throws {
        let queue = FakeCommandQueue()
        let pool = CommandQueuePool(resources: [queue])

        do {
            guard let lease = pool.checkout() else {
                throw TestFailure(description: "expected one queue lease")
            }
            try expect(lease.resource === queue, "pool returned an unexpected queue")
            try expect(pool.availableCount == 0, "checked out queue still appeared available")
        }

        try expect(pool.availableCount == 1, "lease deinit did not return queue to pool")
        guard let lease = pool.checkout() else {
            throw TestFailure(description: "queue was unavailable after lease deinit")
        }
        try expect(lease.resource === queue, "pool returned an unexpected queue after deinit")
        lease.returnToPool()
    }

    private static func testConcurrentCheckoutDoesNotDuplicateActiveResource() throws {
        let queues = (0..<5).map { _ in FakeCommandQueue() }
        let pool = CommandQueuePool(resources: queues)
        let activeLock = NSLock()
        var activeIDs = Set<ObjectIdentifier>()
        var duplicateActiveLeaseCount = 0
        var checkoutFailureCount = 0

        DispatchQueue.concurrentPerform(iterations: queues.count * 12) { _ in
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

            Thread.sleep(forTimeInterval: 0.002)

            activeLock.lock()
            activeIDs.remove(leaseID)
            activeLock.unlock()

            lease.returnToPool()
        }

        try expect(checkoutFailureCount == 0, "concurrent workers failed to checkout a queue")
        try expect(duplicateActiveLeaseCount == 0, "same queue was active in multiple leases")
        try expect(pool.availableCount == queues.count, "not all queues returned after concurrent test")
    }

    private static func checkoutEventually<Resource: AnyObject>(
        from pool: CommandQueuePool<Resource>,
        attempts: Int = 1_000
    ) -> CommandQueuePool<Resource>.Lease? {
        for _ in 0..<attempts {
            if let lease = pool.checkout() {
                return lease
            }
            Thread.sleep(forTimeInterval: 0.001)
        }
        return nil
    }
}
