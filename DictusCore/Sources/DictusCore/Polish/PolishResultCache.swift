import Foundation

/// In-memory bounded cache for identical cleanup requests.
///
/// The cache deliberately does not persist user text. It only removes repeated
/// local-model work while the current app process is alive.
public struct PolishResultCache: Sendable {
    public struct Key: Hashable, Sendable {
        public let raw: String
        public let engine: String
        public let target: String?
        public let spanAware: Bool
        public let regionSignature: String?
        public let writingStyle: String

        public init(raw: String,
                    engine: String,
                    target: String?,
                    spanAware: Bool,
                    regionSignature: String? = nil,
                    writingStyle: String = WritingStyle.defaultStyle.rawValue) {
            self.raw = raw
            self.engine = engine
            self.target = target
            self.spanAware = spanAware
            self.regionSignature = regionSignature
            self.writingStyle = writingStyle
        }
    }

    private let capacity: Int
    private var values: [Key: String] = [:]
    private var order: [Key] = []

    public init(capacity: Int = 12) {
        self.capacity = max(1, capacity)
    }

    public mutating func value(for key: Key) -> String? {
        guard let value = values[key] else { return nil }
        touch(key)
        return value
    }

    public mutating func insert(_ value: String, for key: Key) {
        values[key] = value
        touch(key)
        while order.count > capacity {
            let evicted = order.removeFirst()
            values.removeValue(forKey: evicted)
        }
    }

    public mutating func removeAll() {
        values.removeAll(keepingCapacity: true)
        order.removeAll(keepingCapacity: true)
    }

    private mutating func touch(_ key: Key) {
        order.removeAll { $0 == key }
        order.append(key)
    }
}
