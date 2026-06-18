import Foundation

final class CommandQueuePool<Resource: AnyObject> {
    final class Lease {
        let resource: Resource

        private let pool: CommandQueuePool<Resource>
        private let returnLock = NSLock()
        private var returned = false

        fileprivate init(resource: Resource, pool: CommandQueuePool<Resource>) {
            self.resource = resource
            self.pool = pool
        }

        func returnToPool() {
            returnLock.lock()
            guard !returned else {
                returnLock.unlock()
                return
            }
            returned = true
            returnLock.unlock()

            pool.returnResource(resource)
        }

        deinit {
            returnToPool()
        }
    }

    private struct Slot {
        let resource: Resource
        var inUse: Bool
    }

    private let lock = NSLock()
    private var slots: [Slot]

    init(resources: [Resource]) {
        slots = resources.map { Slot(resource: $0, inUse: false) }
    }

    var capacity: Int {
        lock.lock()
        defer { lock.unlock() }

        return slots.count
    }

    var availableCount: Int {
        lock.lock()
        defer { lock.unlock() }

        return slots.filter { !$0.inUse }.count
    }

    func checkout() -> Lease? {
        lock.lock()
        defer { lock.unlock() }

        guard let slotIndex = slots.firstIndex(where: { !$0.inUse }) else {
            return nil
        }

        slots[slotIndex].inUse = true
        return Lease(resource: slots[slotIndex].resource, pool: self)
    }

    func contains(_ resource: Resource) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        return slots.contains { $0.resource === resource }
    }

    private func returnResource(_ resource: Resource) {
        lock.lock()
        defer { lock.unlock() }

        guard let slotIndex = slots.firstIndex(where: { $0.resource === resource }) else {
            return
        }

        slots[slotIndex].inUse = false
    }
}
