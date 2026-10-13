#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

struct BoundedMap<Key: Hashable & Sendable, Value: Sendable>: Sendable {
    private var storage: [Key: Value] = [:]
    private var accessOrder: [Key: UInt64] = [:]
    private var nextAccess: UInt64 = 0

    let capacity: Int

    init(capacity: Int) {
        self.capacity = max(capacity, 1)
    }

    var count: Int {
        storage.count
    }

    func value(forKey key: Key) -> Value? {
        storage[key]
    }

    mutating func setValue(
        _ value: Value,
        forKey key: Key,
        evictingBy evictionSelector: (([Key: Value], [Key: UInt64]) -> Key?)? = nil
    ) {
        storage[key] = value
        touch(key)

        while storage.count > capacity {
            let victim = evictionSelector?(storage, accessOrder) ?? leastRecentlyUsedKey()
            guard let victim else { break }
            removeValue(forKey: victim)
        }
    }

    @discardableResult
    mutating func removeValue(forKey key: Key) -> Value? {
        accessOrder.removeValue(forKey: key)
        return storage.removeValue(forKey: key)
    }

    mutating func removeAll(where shouldRemove: (Key, Value) -> Bool) {
        let keysToRemove = storage.compactMap { key, value in
            shouldRemove(key, value) ? key : nil
        }
        for key in keysToRemove {
            removeValue(forKey: key)
        }
    }

    private mutating func touch(_ key: Key) {
        nextAccess &+= 1
        accessOrder[key] = nextAccess
    }

    private func leastRecentlyUsedKey() -> Key? {
        accessOrder.min { lhs, rhs in lhs.value < rhs.value }?.key
    }
}

extension TallyConfig {
    static let defaultPeerStateCapacity = 4096
    static let peerStateCapacityMultiplier = 4

    var boundedPeerStateCapacity: Int {
        guard let maxPeers else { return Self.defaultPeerStateCapacity }
        let boundedMaxPeers = max(maxPeers, 1)
        guard boundedMaxPeers <= Int.max / Self.peerStateCapacityMultiplier else {
            return Int.max
        }
        return boundedMaxPeers * Self.peerStateCapacityMultiplier
    }

    var outstandingChallengeCapacity: Int {
        boundedPeerStateCapacity
    }
}
