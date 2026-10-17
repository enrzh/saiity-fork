import Foundation

/// Shared vocabulary keeps its installed word/count and timestamp formats.
public final class UserDictionary {
    public static let shared = UserDictionary()
    static let storageKey = "dictus.userDictionary"
    static let pendingKey = "dictus.userDictionary.pending"
    static let lastUsedKey = "dictus.userDictionary.lastUsed"
    static let prunedTrieDuplicatesKey = "dictus.userDictionary.prunedTrieDuplicates"
    public static let repetitionThreshold = 2
    public static let maxLearnedWords = 1000
    static let maxPendingWords = 500
    static let staleAfterDays = 300

    private let lock = NSRecursiveLock()
    private var words: [String: Int] = [:]
    private var usedAt: [String: Int] = [:]
    private var probation: [String: Int] = [:]

    private init() { reload() }

    public var count: Int { lock.withLock { words.count } }
    public var allLearnedWords: [String: Int] { lock.withLock { words } }
    public var learnedWordsByLastUsed: [String: Int] { lock.withLock { usedAt } }
    public var hasPrunedTrieDuplicates: Bool { AppGroup.defaults.bool(forKey: Self.prunedTrieDuplicatesKey) }

    public func isLearned(_ word: String) -> Bool {
        lock.withLock { words[word.lowercased()] != nil }
    }

    @discardableResult
    public func learn(_ word: String, allowSingleCharacter: Bool = false) -> Bool {
        lock.withLock {
            let key = word.lowercased()
            guard !key.isEmpty, allowSingleCharacter || key.count > 1 else { return false }
            let isNew = words[key] == nil
            let total = Self.increment(words[key] ?? 0)
            words[key] = total
            usedAt[key] = Self.stamp()
            let removedPending = probation.removeValue(forKey: key) != nil
            persistVocabulary()
            if removedPending { persistPending() }
            if isNew { logLearning(key, count: total) }
            return isNew
        }
    }

    @discardableResult
    public func recordUsage(_ word: String) -> Bool {
        lock.withLock {
            let key = word.lowercased()
            guard key.count > 1 else { return false }
            if let total = words[key] {
                words[key] = Self.increment(total)
                usedAt[key] = Self.stamp()
                persistVocabulary()
                return false
            }
            let total = Self.increment(probation[key] ?? 0)
            probation[key] = total
            if total < Self.repetitionThreshold {
                if probation.count > Self.maxPendingWords { probation.removeAll() }
                persistPending()
                return false
            }
            probation.removeValue(forKey: key)
            words[key] = total
            usedAt[key] = Self.stamp()
            persistVocabulary()
            persistPending()
            logLearning(key, count: total)
            return true
        }
    }

    public func forget(_ word: String) {
        lock.withLock {
            let key = word.lowercased()
            words.removeValue(forKey: key)
            usedAt.removeValue(forKey: key)
            probation.removeValue(forKey: key)
            persistVocabulary()
            persistPending()
        }
    }

    public func resetAll() {
        lock.withLock {
            let removed = Array(words.keys)
            words.removeAll()
            usedAt.removeAll()
            probation.removeAll()
            writeVocabulary()
            persistPending()
            AppGroup.defaults.removeObject(forKey: Self.prunedTrieDuplicatesKey)
            PersistentLog.log(.userDictionaryReset(clearedCount: removed.count))
            #if DEBUG
            AutocorrectDebugLog.userDictionaryReset(words: removed)
            #endif
        }
    }

    public func reload() {
        lock.withLock {
            let defaults = AppGroup.defaults
            defaults.synchronize()
            words = Self.integers(for: Self.storageKey, in: defaults)
            usedAt = Self.integers(for: Self.lastUsedKey, in: defaults)
            probation = Self.integers(for: Self.pendingKey, in: defaults)

            // A malformed entry must not discard the user's other valid vocabulary.
            for (key, values) in [(Self.storageKey, words), (Self.pendingKey, probation)] {
                if let stored = defaults.dictionary(forKey: key), stored.count != values.count {
                    defaults.set(values, forKey: key)
                }
            }

            let missing = words.keys.filter { usedAt[$0] == nil }
            let orphaned = usedAt.keys.filter { words[$0] == nil }
            if !missing.isEmpty || !orphaned.isEmpty {
                let now = Self.stamp()
                for key in missing { usedAt[key] = now }
                for key in orphaned { usedAt.removeValue(forKey: key) }
                defaults.set(usedAt, forKey: Self.lastUsedKey)
                PersistentLog.log(.userDictionaryMigrated(stamped: missing.count, droppedStamps: orphaned.count,
                                                         learnedCount: words.count))
                #if DEBUG
                AutocorrectDebugLog.userDictionaryMigrated(words: missing)
                #endif
            }

            let cutoff = Self.stamp() - Self.staleAfterDays * 86_400
            let expired = words.keys.filter { (usedAt[$0] ?? 0) <= cutoff }
            if !expired.isEmpty {
                for key in expired {
                    words.removeValue(forKey: key)
                    usedAt.removeValue(forKey: key)
                }
                writeVocabulary()
                PersistentLog.log(.userDictionaryStaleDiscarded(removed: expired.count, learnedCount: words.count,
                                                               days: Self.staleAfterDays))
                #if DEBUG
                AutocorrectDebugLog.userDictionaryStaleDiscarded(words: expired)
                #endif
            }
        }
    }

    @discardableResult
    public func pruneTrieDuplicatesIfNeeded(using provider: FrequencyProvider) -> Int {
        lock.withLock {
            guard provider.isReady, !hasPrunedTrieDuplicates else { return 0 }
            let duplicates = words.keys.filter { provider.knowsWord($0) }
            for key in duplicates {
                words.removeValue(forKey: key)
                usedAt.removeValue(forKey: key)
            }
            probation = probation.filter { !provider.knowsWord($0.key) }
            writeVocabulary()
            persistPending()
            AppGroup.defaults.set(true, forKey: Self.prunedTrieDuplicatesKey)
            PersistentLog.log(.userDictionaryPruned(removed: duplicates.count, learnedCount: words.count))
            #if DEBUG
            AutocorrectDebugLog.userDictionaryPruned(words: duplicates)
            #endif
            return duplicates.count
        }
    }

    private static func integers(for key: String, in defaults: UserDefaults) -> [String: Int] {
        defaults.dictionary(forKey: key)?.compactMapValues { $0 as? Int } ?? [:]
    }

    private static func increment(_ value: Int) -> Int { value == Int.max ? value : value + 1 }
    private static func stamp() -> Int { Int(Date().timeIntervalSince1970) }

    private func evictsBefore(_ first: String, _ second: String) -> Bool {
        let firstUse = usedAt[first] ?? 0, secondUse = usedAt[second] ?? 0
        if firstUse != secondUse { return firstUse < secondUse }
        let firstCount = words[first] ?? 0, secondCount = words[second] ?? 0
        if firstCount != secondCount { return firstCount > secondCount }
        return first < second
    }

    private func persistVocabulary() {
        let overflow = words.count - Self.maxLearnedWords
        if overflow > 0 {
            let evicted: [String]
            if overflow == 1, let oldest = words.keys.min(by: evictsBefore) {
                evicted = [oldest]
            } else {
                evicted = Array(words.keys.sorted(by: evictsBefore).prefix(overflow))
            }
            for key in evicted {
                words.removeValue(forKey: key)
                usedAt.removeValue(forKey: key)
            }
            PersistentLog.log(.userDictionaryEvicted(removed: evicted.count, learnedCount: words.count,
                                                    cap: Self.maxLearnedWords))
            #if DEBUG
            AutocorrectDebugLog.userDictionaryEvicted(words: evicted)
            #endif
        }
        writeVocabulary()
    }

    private func writeVocabulary() {
        let defaults = AppGroup.defaults
        defaults.set(words, forKey: Self.storageKey)
        defaults.set(usedAt, forKey: Self.lastUsedKey)
    }

    private func persistPending() { AppGroup.defaults.set(probation, forKey: Self.pendingKey) }

    private func logLearning(_ word: String, count: Int) {
        PersistentLog.log(.userDictionaryWordLearned(learnedCount: words.count))
        #if DEBUG
        AutocorrectDebugLog.userDictionaryLearned(word: word, usageCount: count, learnedCount: words.count)
        #endif
    }
}
