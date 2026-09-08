import Foundation

/// The active ASR capability snapshot used by the keyboard language control.
public struct ASRCapability: Equatable, Sendable {
    public let supportsAutomaticInputLanguage: Bool
    public let sourceLanguage: SupportedLanguage?

    public init(supportsAutomaticInputLanguage: Bool, sourceLanguage: SupportedLanguage?) {
        self.supportsAutomaticInputLanguage = supportsAutomaticInputLanguage
        self.sourceLanguage = sourceLanguage
    }

    public var displaySourceCode: String {
        supportsAutomaticInputLanguage ? "AUTO" : (sourceLanguage?.shortCode ?? "--")
    }

    /// Resolve the display capability from the active model and one captured
    /// transcription policy. Unknown model metadata fails closed.
    public static func forModelIdentifier(
        _ identifier: String?,
        mode: TranscriptionLanguageMode,
        keyboardLanguage: SupportedLanguage
    ) -> Self {
        guard let model = identifier.flatMap(ModelInfo.forIdentifier) else {
            return Self(supportsAutomaticInputLanguage: false, sourceLanguage: nil)
        }

        switch model.languageSupport.coverage {
        case .whisperMultilingual:
            switch mode {
            case .autoDetect:
                return Self(supportsAutomaticInputLanguage: true, sourceLanguage: nil)
            case .followKeyboard:
                return Self(supportsAutomaticInputLanguage: false, sourceLanguage: keyboardLanguage)
            case .explicit(let language):
                return Self(supportsAutomaticInputLanguage: false, sourceLanguage: language)
            }
        case .parakeetEuropean:
            // FluidAudio currently ignores the source-language parameter. Do not
            // present the keyboard choice as a resolved runtime source.
            return Self(supportsAutomaticInputLanguage: false, sourceLanguage: nil)
        }
    }
}

/// Translation readiness is supplied by the translation runtime, independently
/// of the active ASR model.
public enum TranslationTargetStatus: String, Equatable, Sendable {
    case installedReady
    case supportedNeedsDownload
    case unavailable
}

public struct TranslationTargetReadiness: Equatable, Sendable {
    public let source: String
    public let installedTargets: Set<String>
    public let supportedTargets: Set<String>

    public init(source: String, targets: Set<String>) {
        self.source = source
        self.installedTargets = targets
        self.supportedTargets = targets
    }

    public init(source: String, installedTargets: Set<String>, supportedTargets: Set<String>) {
        self.source = source
        self.installedTargets = installedTargets
        self.supportedTargets = supportedTargets
    }

    /// Backward-compatible name for the previously installed-only payload.
    public var targets: Set<String> { installedTargets }

    public static let appGroupKey = SharedKeys.translationReadiness

    public func persist(to defaults: UserDefaults = AppGroup.defaults) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.appGroupKey)
        defaults.synchronize()
    }

    public static func load(from defaults: UserDefaults = AppGroup.defaults) -> Self? {
        guard let data = defaults.data(forKey: Self.appGroupKey) else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }

    public func selectableTargets(for sourceLanguage: SupportedLanguage?) -> [SupportedLanguage] {
        guard matches(sourceLanguage) else { return [] }
        let available = installedTargets.union(supportedTargets)
        return SupportedLanguage.allCases.filter { available.contains($0.rawValue) }
    }

    public func readyTargets(for sourceLanguage: SupportedLanguage?) -> [SupportedLanguage] {
        guard matches(sourceLanguage) else { return [] }
        return SupportedLanguage.allCases.filter { installedTargets.contains($0.rawValue) }
    }

    public func status(
        for target: SupportedLanguage,
        sourceLanguage: SupportedLanguage?
    ) -> TranslationTargetStatus {
        guard matches(sourceLanguage) else { return .unavailable }
        if installedTargets.contains(target.rawValue) { return .installedReady }
        if supportedTargets.contains(target.rawValue) { return .supportedNeedsDownload }
        return .unavailable
    }

    public func menuLabel(
        for target: SupportedLanguage,
        sourceLanguage: SupportedLanguage?
    ) -> String {
        switch status(for: target, sourceLanguage: sourceLanguage) {
        case .installedReady:
            return "Translate to \(target.displayName)"
        case .supportedNeedsDownload:
            return "Translate to \(target.displayName) (Download required)"
        case .unavailable:
            return "Translate to \(target.displayName) (Unavailable)"
        }
    }

    public func accessibilityLabel(
        for target: SupportedLanguage,
        sourceLanguage: SupportedLanguage?
    ) -> String {
        switch status(for: target, sourceLanguage: sourceLanguage) {
        case .installedReady:
            return "Translate to \(target.displayName)"
        case .supportedNeedsDownload:
            return "Translate to \(target.displayName), download required"
        case .unavailable:
            return "Translate to \(target.displayName), unavailable"
        }
    }

    private func matches(_ sourceLanguage: SupportedLanguage?) -> Bool {
        if source == "auto" {
            return sourceLanguage == nil
        }
        return sourceLanguage?.rawValue == source
    }
}

extension TranslationTargetReadiness: Codable {}

public enum TranslationFallbackReason: String, Equatable, Sendable {
    case unavailable
    case emptyResponse
    case mismatchedClient
    case cancelled
}

public enum TranslationOutcome: Equatable, Sendable {
    case translated(String)
    case fallbackOriginal(String, reason: TranslationFallbackReason)

    public static func fallback(_ original: String, reason: TranslationFallbackReason) -> Self {
        .fallbackOriginal(original, reason: reason)
    }

    public static func resolved(
        original: String,
        translated: String?,
        clientIdentifierMatches: Bool
    ) -> Self {
        guard clientIdentifierMatches else {
            return .fallbackOriginal(original, reason: .mismatchedClient)
        }
        guard let translated, !translated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .fallbackOriginal(original, reason: .emptyResponse)
        }
        return .translated(translated)
    }

    public var resolvedText: String {
        switch self {
        case .translated(let text), .fallbackOriginal(let text, _): return text
        }
    }
}

public enum DictationFinalizationStep: String, Sendable {
    case authoritativeTranscript
    case translation
    case ready
    case publish
    case insertionAcknowledged

    public static func isValid(_ steps: [Self]) -> Bool {
        steps == [.authoritativeTranscript, .translation, .ready, .publish, .insertionAcknowledged]
    }
}

/// The small, testable decision the App owner makes before publishing a result.
/// Translation fallback is still a successful user-visible result, while a request
/// whose identity no longer matches the active session is silently dropped.
public struct DictationFinalizationDecision: Equatable, Sendable {
    public let finalText: String?
    public let steps: [DictationFinalizationStep]
    public let errorMessage: String?

    public var shouldPublish: Bool {
        finalText != nil && DictationFinalizationStep.isValid(steps)
    }

    public static func make(
        transcript: String,
        outcome: TranslationOutcome,
        request: DictationLanguageRequest,
        currentRequest: DictationLanguageRequest
    ) -> Self {
        guard !transcript.isEmpty,
              !outcome.resolvedText.isEmpty,
              let currentSessionID = currentRequest.sessionID,
              let currentClientIdentifier = currentRequest.clientIdentifier,
              request.matches(
                sessionID: currentSessionID,
                generation: currentRequest.generation ?? 0,
                clientIdentifier: currentClientIdentifier
              ) else {
            return Self(finalText: nil, steps: [], errorMessage: nil)
        }

        return Self(
            finalText: outcome.resolvedText,
            steps: [
                .authoritativeTranscript,
                .translation,
                .ready,
                .publish,
                .insertionAcknowledged
            ],
            errorMessage: nil
        )
    }
}

/// Models the one-shot completion gate used by cancellation continuations.
/// A second cancellation is a no-op instead of a double resume.
public struct DictationCancellationContinuation: Equatable, Sendable {
    public private(set) var resumeCount = 0

    public init() {}

    @discardableResult
    public mutating func resume() -> Bool {
        guard resumeCount == 0 else { return false }
        resumeCount = 1
        return true
    }
}

/// The cross-process request captured by the app for one dictation.
public struct DictationLanguageRequest: Codable, Equatable, Sendable {
    public let mode: TranscriptionLanguageMode
    public let translationTarget: SupportedLanguage?
    public let sessionID: String?
    public let generation: Int?
    public let clientIdentifier: String?
    public let resolvedSourceLanguage: SupportedLanguage?

    public static let appGroupKey = SharedKeys.dictationLanguageRequest

    public init(
        mode: TranscriptionLanguageMode,
        translationTarget: SupportedLanguage?,
        sessionID: String? = nil,
        generation: Int? = nil,
        clientIdentifier: String? = nil,
        resolvedSourceLanguage: SupportedLanguage? = nil
    ) {
        self.mode = mode
        self.translationTarget = translationTarget
        self.sessionID = sessionID
        self.generation = generation
        self.clientIdentifier = clientIdentifier
        self.resolvedSourceLanguage = resolvedSourceLanguage
    }

    public func persist(to defaults: UserDefaults = AppGroup.defaults) {
        guard hasValidRequestShape else { return }
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.appGroupKey)
        Self.legacyKeys.forEach { defaults.removeObject(forKey: $0) }
        defaults.synchronize()
    }

    public static func load(from defaults: UserDefaults = AppGroup.defaults) -> Self {
        if defaults.object(forKey: Self.appGroupKey) != nil {
            guard let data = defaults.data(forKey: Self.appGroupKey),
                  let request = try? JSONDecoder().decode(Self.self, from: data) else {
                return Self(mode: .followKeyboard, translationTarget: nil)
            }
            return request.hasValidRequestShape ? request : Self(mode: .followKeyboard, translationTarget: nil)
        }

        return loadLegacy(from: defaults)
    }

    public var isBound: Bool {
        hasValidRequestShape && sessionID != nil && generation != nil && clientIdentifier != nil
    }

    /// Request generations belong to the keyboard process, not the app's local
    /// cancellation counter. Compare the full transport identity independently.
    public func hasSameIdentity(as other: Self) -> Bool {
        isBound && other.isBound && sessionID == other.sessionID
            && generation == other.generation && clientIdentifier == other.clientIdentifier
    }

    /// Return the mode to use when starting a new dictation.
    ///
    /// Transcription is always Auto-detect. The argument remains in the API so
    /// callers from the previous setting-based design stay source-compatible.
    public func modeForNextDictation(defaultingTo _: TranscriptionLanguageMode) -> TranscriptionLanguageMode {
        .autoDetect
    }

    public func unbound() -> Self {
        Self(mode: mode, translationTarget: translationTarget)
    }

    public func bound(sessionID: String, generation: Int, clientIdentifier: String) -> Self {
        Self(
            mode: mode,
            translationTarget: translationTarget,
            sessionID: sessionID,
            generation: generation,
            clientIdentifier: clientIdentifier,
            resolvedSourceLanguage: resolvedSourceLanguage
        )
    }

    public func withResolvedSourceLanguage(_ sourceLanguage: SupportedLanguage?) -> Self {
        Self(
            mode: mode,
            translationTarget: translationTarget,
            sessionID: sessionID,
            generation: generation,
            clientIdentifier: clientIdentifier,
            resolvedSourceLanguage: sourceLanguage
        )
    }

    public func matches(sessionID: String, generation: Int, clientIdentifier: String) -> Bool {
        isBound
            && self.sessionID == sessionID
            && self.generation == generation
            && self.clientIdentifier == clientIdentifier
    }

    private var hasValidBindingShape: Bool {
        let present = [sessionID != nil, generation != nil, clientIdentifier != nil]
        return present.allSatisfy { $0 } || present.allSatisfy { !$0 }
    }

    private static let legacyKeys = [
        appGroupKey + ".mode",
        appGroupKey + ".target",
        appGroupKey + ".sessionID",
        appGroupKey + ".generation",
        appGroupKey + ".clientIdentifier",
        appGroupKey + ".source"
    ]

    private static func loadLegacy(from defaults: UserDefaults) -> Self {
        let modeKey = appGroupKey + ".mode"
        let targetKey = appGroupKey + ".target"
        let sessionKey = appGroupKey + ".sessionID"
        let generationKey = appGroupKey + ".generation"
        let clientKey = appGroupKey + ".clientIdentifier"
        let sourceKey = appGroupKey + ".source"
        let anyLegacyValue = legacyKeys.contains { defaults.object(forKey: $0) != nil }
        guard anyLegacyValue else {
            return Self(
                mode: TranscriptionLanguageMode(
                    storedValue: defaults.string(forKey: SharedKeys.transcriptionLanguage)
                ),
                translationTarget: nil
            )
        }
        guard defaults.object(forKey: modeKey) != nil,
              let modeValue = defaults.string(forKey: modeKey) else {
            return Self(mode: .followKeyboard, translationTarget: nil)
        }

        let target: SupportedLanguage?
        if let value = defaults.object(forKey: targetKey) {
            guard let raw = value as? String, let language = SupportedLanguage(rawValue: raw) else {
                return Self(mode: .followKeyboard, translationTarget: nil)
            }
            target = language
        } else {
            target = nil
        }

        let sessionID = defaults.object(forKey: sessionKey).flatMap { $0 as? String }
        let generation = defaults.object(forKey: generationKey).flatMap { $0 as? Int }
        let clientIdentifier = defaults.object(forKey: clientKey).flatMap { $0 as? String }
        let source: SupportedLanguage?
        if let value = defaults.object(forKey: sourceKey) {
            guard let raw = value as? String, let language = SupportedLanguage(rawValue: raw) else {
                return Self(mode: .followKeyboard, translationTarget: nil)
            }
            source = language
        } else {
            source = nil
        }
        guard defaults.object(forKey: sessionKey) == nil || sessionID != nil,
              defaults.object(forKey: generationKey) == nil || generation != nil,
              defaults.object(forKey: clientKey) == nil || clientIdentifier != nil,
              defaults.object(forKey: sourceKey) == nil || source != nil else {
            return Self(mode: .followKeyboard, translationTarget: nil)
        }

        let request = Self(
            mode: TranscriptionLanguageMode(storedValue: modeValue),
            translationTarget: target,
            sessionID: sessionID,
            generation: generation,
            clientIdentifier: clientIdentifier,
            resolvedSourceLanguage: source
        )
        return request.hasValidRequestShape ? request : Self(mode: .followKeyboard, translationTarget: nil)
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case mode
        case translationTarget
        case sessionID
        case generation
        case clientIdentifier
        case resolvedSourceLanguage
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(1, forKey: .schemaVersion)
        try container.encode(mode.storedValue, forKey: .mode)
        try container.encodeIfPresent(translationTarget, forKey: .translationTarget)
        try container.encodeIfPresent(sessionID, forKey: .sessionID)
        try container.encodeIfPresent(generation, forKey: .generation)
        try container.encodeIfPresent(clientIdentifier, forKey: .clientIdentifier)
        try container.encodeIfPresent(resolvedSourceLanguage, forKey: .resolvedSourceLanguage)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(Int.self, forKey: .schemaVersion) == 1 else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion,
                in: container,
                debugDescription: "Unsupported dictation request schema"
            )
        }
        mode = TranscriptionLanguageMode(
            storedValue: try container.decode(String.self, forKey: .mode)
        )
        translationTarget = try container.decodeIfPresent(SupportedLanguage.self, forKey: .translationTarget)
        sessionID = try container.decodeIfPresent(String.self, forKey: .sessionID)
        generation = try container.decodeIfPresent(Int.self, forKey: .generation)
        clientIdentifier = try container.decodeIfPresent(String.self, forKey: .clientIdentifier)
        resolvedSourceLanguage = try container.decodeIfPresent(SupportedLanguage.self, forKey: .resolvedSourceLanguage)
    }

    private var hasValidRequestShape: Bool {
        hasValidBindingShape && (mode != .autoDetect || resolvedSourceLanguage == nil)
    }
}
