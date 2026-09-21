import Foundation

/// Thread-safe, bounded cache for the invisible next-key probability map.
/// The keyboard touches it from its serial prediction queue and clears it from
/// the UI path, so the lock keeps invalidation cheap and deterministic.
public final class NextCharacterPredictionCache: @unchecked Sendable {
    private let lock = NSLock()
    private let capacity: Int
    private var values: [String: NextCharacterProbabilities] = [:]
    private var order: [String] = []

    public init(capacity: Int = 24) {
        self.capacity = max(1, capacity)
    }

    public func value(for key: String) -> NextCharacterProbabilities? {
        lock.lock()
        defer { lock.unlock() }
        guard let value = values[key] else { return nil }
        touch(key)
        return value
    }

    public func insert(_ value: NextCharacterProbabilities, for key: String) {
        lock.lock()
        values[key] = value
        touch(key)
        while order.count > capacity {
            let evicted = order.removeFirst()
            values.removeValue(forKey: evicted)
        }
        lock.unlock()
    }

    public func removeAll() {
        lock.lock()
        values.removeAll(keepingCapacity: true)
        order.removeAll(keepingCapacity: true)
        lock.unlock()
    }

    private func touch(_ key: String) {
        order.removeAll { $0 == key }
        order.append(key)
    }
}
