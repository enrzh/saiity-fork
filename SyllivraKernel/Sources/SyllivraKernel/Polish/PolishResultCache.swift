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
        public let modelIdentifier: String
        public let transcriptionMode: String
        public let outputMode: String
        public let keyboardLanguage: String
        public let promptRevision: String

        public init(raw: String,
                    engine: String,
                    target: String?,
                    spanAware: Bool,
                    regionSignature: String? = nil,
                    writingStyle: String = WritingStyle.defaultStyle.rawValue,
                    modelIdentifier: String = "",
                    transcriptionMode: String = "",
                    outputMode: String = "",
                    keyboardLanguage: String = "",
                    promptRevision: String = DictationCleanupPrompt.revision + "\n" + PolishGlossary.promptBlock) {
            self.raw = raw
            self.engine = engine
            self.target = target
            self.spanAware = spanAware
            self.regionSignature = regionSignature
            self.writingStyle = writingStyle
            self.modelIdentifier = modelIdentifier
            self.transcriptionMode = transcriptionMode
            self.outputMode = outputMode
            self.keyboardLanguage = keyboardLanguage
            self.promptRevision = promptRevision
        }
    }

    /// Duration-gated cleanup must not share a cached model result with a
    /// short clip, and a skipped or cancelled call must not be stored as success.
    public enum Admission {
        public static func isEligible(recordingDuration: TimeInterval, minimumDuration: TimeInterval) -> Bool {
            recordingDuration >= minimumDuration
        }

        /// `succeeded` means the model finished with a usable result. Starting
        /// the engine and then returning the deterministic fallback is not success.
        public static func shouldStore(eligible: Bool, succeeded: Bool, cancelled: Bool) -> Bool {
            eligible && succeeded && !cancelled
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
