import Foundation
import NaturalLanguage

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
        keyboardLanguage: SupportedLanguage,
        outputMode: TranscriptionOutputMode? = nil
    ) -> Self {
        guard let model = identifier.flatMap(ModelInfo.forIdentifier) else {
            return Self(supportsAutomaticInputLanguage: false, sourceLanguage: nil)
        }
        let effectiveOutputMode = outputMode ?? (mode == .autoDetect ? .multilingual : .singleLanguage)

        switch model.languageSupport.coverage {
        case .whisperMultilingual:
            switch mode {
            case .autoDetect:
                return effectiveOutputMode == .multilingual
                    ? Self(supportsAutomaticInputLanguage: true, sourceLanguage: nil)
                    : Self(supportsAutomaticInputLanguage: false, sourceLanguage: keyboardLanguage)
            case .followKeyboard:
                return Self(supportsAutomaticInputLanguage: false, sourceLanguage: keyboardLanguage)
            case .explicit(let language):
                return Self(supportsAutomaticInputLanguage: false, sourceLanguage: language)
            }
        case .whisperEnglishOnly:
            // The `.en` Whisper checkpoints are intentionally pinned to
            // English: offering Auto or another selected language would make
            // the settings UI promise behavior the model cannot provide.
            return Self(supportsAutomaticInputLanguage: false, sourceLanguage: .english)
        }
    }
}

/// Translation readiness is supplied by the translation runtime, independently
/// of the active ASR model.
public enum TranslationTargetStatus: String, Equatable, Sendable {
    case checking
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

    public func selectableTargets(forSourceCode sourceCode: String?) -> [TranslationLanguage] {
        guard matches(sourceCode) else { return [] }
        let available = installedTargets.union(supportedTargets)
        return TranslationLanguage.allCases.filter { available.contains($0.rawValue) }
    }

    public func readyTargets(forSourceCode sourceCode: String?) -> [TranslationLanguage] {
        guard matches(sourceCode), source != "auto" else { return [] }
        return TranslationLanguage.allCases.filter { installedTargets.contains($0.rawValue) }
    }

    public func matchesSourceCode(_ sourceCode: String?) -> Bool {
        matches(sourceCode)
    }

    public func status(
        for target: TranslationLanguage,
        sourceCode: String?
    ) -> TranslationTargetStatus {
        guard matches(sourceCode) else { return .unavailable }
        if source == "auto" { return .checking }
        if installedTargets.contains(target.rawValue) { return .installedReady }
        if supportedTargets.contains(target.rawValue) { return .supportedNeedsDownload }
        return .unavailable
    }

    public func menuLabel(
        for target: TranslationLanguage,
        sourceCode: String?
    ) -> String {
        switch status(for: target, sourceCode: sourceCode) {
        case .checking:
            return "Translate to \(target.displayName) (Check after source recognition)"
        case .installedReady:
            return "Translate to \(target.displayName)"
        case .supportedNeedsDownload:
            return "Translate to \(target.displayName) (Download required)"
        case .unavailable:
            return "Translate to \(target.displayName) (Unavailable)"
        }
    }

    public func accessibilityLabel(
        for target: TranslationLanguage,
        sourceCode: String?
    ) -> String {
        switch status(for: target, sourceCode: sourceCode) {
        case .checking:
            return "Translate to \(target.displayName), check after source recognition"
        case .installedReady:
            return "Translate to \(target.displayName)"
        case .supportedNeedsDownload:
            return "Translate to \(target.displayName), download required"
        case .unavailable:
            return "Translate to \(target.displayName), unavailable"
        }
    }

    private func matches(_ sourceCode: String?) -> Bool {
        if source == "auto" {
            return sourceCode == nil
        }
        return sourceCode == source
    }
}

extension TranslationTargetReadiness: Codable {}

public enum TranslationFallbackReason: String, Equatable, Sendable {
    case unavailable
    case emptyResponse
    case mismatchedClient
    case cancelled
    case rejectedOutput
}

public enum TranslationOutcome: Equatable, Sendable {
    case original(String)
    case translated(String)
    case fallbackOriginal(String, reason: TranslationFallbackReason)

    public static func fallback(_ original: String, reason: TranslationFallbackReason) -> Self {
        .fallbackOriginal(original, reason: reason)
    }

    public static func resolved(
        original: String,
        translated: String?,
        clientIdentifierMatches: Bool,
        target: TranslationLanguage? = nil,
        source: String? = nil
    ) -> Self {
        guard clientIdentifierMatches else {
            return .fallbackOriginal(original, reason: .mismatchedClient)
        }
        guard let translated, !translated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .fallbackOriginal(original, reason: .emptyResponse)
        }
        guard preservesTranslationFacts(original, output: translated, source: source, target: target),
              target.map({ acceptsTargetText(translated, original: original, target: $0) }) ?? true else {
            return .fallbackOriginal(original, reason: .rejectedOutput)
        }
        return .translated(translated)
    }

    public var fallbackReason: TranslationFallbackReason? {
        if case .fallbackOriginal(_, let reason) = self { return reason }
        return nil
    }

    public func replacingText(_ text: String) -> Self {
        switch self {
        case .original: return .original(text)
        case .translated: return .translated(text)
        case .fallbackOriginal(_, let reason): return .fallback(text, reason: reason)
        }
    }

    public static func combined(original: String, clauses: [String], outcomes: [Self], target: TranslationLanguage) -> Self {
        guard clauses.count == outcomes.count, !clauses.isEmpty else { return .fallback(original, reason: .emptyResponse) }
        guard original == clauses.joined() else { return .fallback(original, reason: .rejectedOutput) }
        if let reason = outcomes.compactMap(\.fallbackReason).first { return .fallback(original, reason: reason) }
        for (clause, outcome) in zip(clauses, outcomes) where !clause.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if resolved(original: clause, translated: outcome.resolvedText, clientIdentifierMatches: true, target: target).fallbackReason != nil {
                return .fallback(original, reason: .rejectedOutput)
            }
        }
        let output = outcomes.map(\.resolvedText).joined()
        // Facts are validated per clause with its locale, not a mixed dominant vote.
        guard acceptsTargetText(output, original: original, target: target) else { return .fallback(original, reason: .rejectedOutput) }
        return .translated(output)
    }

    private static func matches(_ pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
            Range($0.range, in: text).map { String(text[$0]) }
        }
    }

    private static func acceptsTargetText(_ output: String, original: String, target: TranslationLanguage) -> Bool {
        guard target.satisfiesOutputScript(output) else { return false }
        let wanted = SpeechLanguageEvidence.baseCode(target.code)
        for span in PolishSpanDetector.translationSpans(in: output) {
            let value = span.text.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            guard value.contains(where: \.isLetter), !isPreservedNameOrIdentifier(value, original: original) else { continue }
            let readings = SpeechLanguageEvidence.hypotheses(in: value)
            if let reading = readings.max(by: { $0.value < $1.value }), reading.value >= 0.95, reading.key != wanted { return false }
            if let code = span.languageCode, SpeechLanguageEvidence.baseCode(code) != wanted { return false }
            let scripts = Set(value.unicodeScalars.compactMap(SpeechLanguageEvidence.script(for:)))
            if value.filter(\.isLetter).count >= 2 {
                if scripts.contains(.kana), wanted != "ja" { return false }
                if scripts.contains(.hangul), wanted != "ko" { return false }
                if scripts.contains(.han), !["zh", "ja", "ko"].contains(wanted) { return false }
            }
            if value.count < 24, scripts == [.latin], (readings[wanted] ?? 0) < 0.05,
               (readings.values.max() ?? 0) >= 0.6 { return false }
        }
        // A dominant target reading must not hide a retained grammatical word.
        for word in matches(#"[\p{L}\p{M}]+(?:[_0-9][\p{L}\p{M}\p{N}_]*)?"#, in: output) where word.count >= 4 {
            guard !isPreservedNameOrIdentifier(word, original: original) else { continue }
            let readings = SpeechLanguageEvidence.hypotheses(in: word)
            if let best = readings.max(by: { $0.value < $1.value }), best.value >= 0.98,
               best.key != wanted, (readings[wanted] ?? 0) < 0.01 { return false }
        }
        return true
    }

    private static func isPreservedNameOrIdentifier(_ value: String, original: String) -> Bool {
        if value.lowercased() == "ok" { return true }
        guard original.range(of: value, options: [.caseInsensitive, .widthInsensitive]) != nil else { return false }
        if value.range(of: #"^(?:[A-Z]{2,5}|[\p{L}][\p{L}\p{N}_./+\-]*[\p{N}_][\p{L}\p{N}_./+\-]*|[A-Za-z]*[a-z][A-Z][A-Za-z]*|https?://\S+|[^\s]+@[^\s]+)$"#,
                       options: .regularExpression) != nil { return true }
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = value
        var named = false, onlyNames = true
        tagger.enumerateTags(in: value.startIndex..<value.endIndex, unit: .word, scheme: .nameType,
                            options: [.omitWhitespace, .omitPunctuation, .joinNames]) { tag, _ in
            if let tag, [NLTag.personalName, .placeName, .organizationName].contains(tag) { named = true }
            else { onlyNames = false }
            return true
        }
        return named && onlyNames
    }

    private static func preservesTranslationFacts(_ original: String, output: String, source: String?, target: TranslationLanguage?) -> Bool {
        let sourceCode = source == "auto" ? nil : SpeechLanguageEvidence.sourceLanguage(in: original, hint: source)
        let outputCode = target?.code ?? SpeechLanguageEvidence.sourceLanguage(in: output)
        guard numericFacts(in: original, language: sourceCode) == numericFacts(in: output, language: outputCode) else { return false }
        // A multiset of numbers loses the order inside dates and clock times.
        let datesAndTimes = #"(?<!\p{N})(?:\p{Nd}{4}[-/]\p{Nd}{1,2}[-/]\p{Nd}{1,2}|\p{Nd}{1,2}[/-]\p{Nd}{1,2}[/-]\p{Nd}{2,4}|\p{Nd}{1,2}:\p{Nd}{2}(?::\p{Nd}{2})?)(?!\p{N})"#
        guard matches(datesAndTimes, in: original).map(normalizeDigits).sorted() == matches(datesAndTimes, in: output).map(normalizeDigits).sorted() else { return false }
        let negationSource = sourceCode ?? SpeechLanguageEvidence.hypotheses(in: original).max(by: { $0.value < $1.value }).flatMap { $0.value >= 0.95 ? $0.key : nil }
        if let negationSource, let outputCode,
           let inputNegations = negationCount(original, language: negationSource),
           let outputNegations = negationCount(output, language: outputCode), inputNegations != outputNegations { return false }
        let identifiers = #"(?<![\p{L}\p{N}_])(?:[A-Za-z][A-Za-z0-9]*[_0-9][A-Za-z0-9_/-]*|https?://[^\s]+|[^\s]+@[^\s]+)"#
        for identifier in matches(identifiers, in: original) {
            guard output.range(of: identifier) != nil else { return false }
        }
        let ratio = Double(output.count) / Double(max(original.count, 1))
        guard ratio >= 0.08, ratio <= 5 else { return false }
        let sourceClauses = PolishSpanDetector.translationSpans(in: original).filter { $0.text.contains(where: \.isLetter) }
        let outputClauses = PolishSpanDetector.translationSpans(in: output).filter { $0.text.contains(where: \.isLetter) }
        if sourceClauses.count > outputClauses.count, ratio < 0.75 { return false }
        let sourceWords = original.split(whereSeparator: \.isWhitespace).count
        if sourceWords >= 8, output.split(whereSeparator: \.isWhitespace).count < sourceWords / 2,
           Set(original.unicodeScalars.compactMap(SpeechLanguageEvidence.script(for:))) == [.latin],
           Set(output.unicodeScalars.compactMap(SpeechLanguageEvidence.script(for:))) == [.latin] { return false }
        return true
    }

    private static func normalizeDigits(_ text: String) -> String {
        text.map { $0.wholeNumberValue.map(String.init) ?? ($0 == "٫" ? "." : $0 == "٬" ? "," : String($0)) }.joined()
    }

    static func numericFacts(in text: String, language: String?) -> [String] {
        let locale = language.map { Locale(identifier: $0) }
        let currencyAliases = ["EUR": #"(?i)€|\b(?:EUR|euros?|евро|евра|يورو)\b|欧元|歐元|यूरो|ইউরো|یورو"#,
            "USD": #"(?i)\$|\b(?:USD|dollars?|dólares|доллар\p{L}*|دولار\p{L}*)\b|美元|डॉलर|ডলার|ڈالر"#,
            "GBP": #"(?i)£|\b(?:GBP|pounds?|livres?|libras)\b|英镑|英鎊"#,
            "JPY": #"(?i)\b(?:JPY|yen)\b|日元|日圓|円"#, "CNY": #"(?i)\bCNY\b|人民币|人民幣|(?<![日美欧歐])元"#]
        let numberPattern = #"(?<![A-Za-z\p{N}])[+\-−]?\p{Nd}+(?:[.,٫٬'’\u00a0\u202f]\p{Nd}+)*"#
        guard let regex = try? NSRegularExpression(pattern: numberPattern) else { return [] }
        var values = regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match -> String? in
            guard let range = Range(match.range, in: text) else { return nil }
            let raw = String(text[range])
            let before = String(text[..<range.lowerBound].suffix(16))
            let after = String(text[range.upperBound...].prefix(16))
            var currencies = currencyAliases.compactMap { code, pattern in
                !matches("(?:" + pattern + #")[ \t]*$"#, in: before).isEmpty
                    || !matches(#"^[ \t]*(?:"# + pattern + ")", in: after).isEmpty ? code : nil
            }
            let prefix = before.trimmingCharacters(in: .whitespacesAndNewlines)
            let suffix = after.trimmingCharacters(in: .whitespacesAndNewlines)
            let prefixCode = String(prefix.suffix(3)), suffixCode = String(suffix.prefix(3))
            for code in [prefixCode, suffixCode] where !currencyAliases.keys.contains(code) && Locale.commonISOCurrencyCodes.contains(code) {
                if (code == prefixCode && (prefix.count == 3 || prefix.dropLast(3).last?.isLetter == false))
                    || (code == suffixCode && (suffix.count == 3 || suffix.dropFirst(3).first?.isLetter == false)) {
                    currencies.append(code)
                }
            }
            let adjacentSymbols = [before.last, after.first].compactMap { $0 }.filter {
                $0.unicodeScalars.contains { $0.properties.generalCategory == .currencySymbol }
            }.map(String.init)
            if currencies.isEmpty { currencies = adjacentSymbols }
            let digits = normalizeDigits(raw.replacingOccurrences(of: "٬", with: "")).replacingOccurrences(of: "−", with: "-")
                .replacingOccurrences(of: #"['’\u00a0\u202f]"#, with: "", options: .regularExpression)
            var value = digits
            if value.contains("."), value.contains(",") {
                let decimal = value.lastIndex(where: { $0 == "." || $0 == "," })!
                value = value[..<decimal].replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: "")
                    + "." + value[value.index(after: decimal)...]
            } else if !raw.contains("٫"), let grouping = locale?.groupingSeparator,
                      grouping != locale?.decimalSeparator, value.contains(grouping) {
                value = value.replacingOccurrences(of: grouping, with: "")
            } else { value = value.replacingOccurrences(of: ",", with: ".") }
            let number = Decimal(string: value, locale: Locale(identifier: "en_US_POSIX")).map { NSDecimalNumber(decimal: $0).stringValue } ?? value
            return number + "|" + currencies.sorted().joined(separator: ",")
        }
        // With amounts, currency belongs to each value. Bare 元 in 元気 is a word.
        if values.isEmpty {
            for (code, pattern) in currencyAliases {
                let unambiguous = code == "CNY" ? #"(?i)\bCNY\b|人民币|人民幣"# : pattern
                values += matches(unambiguous, in: text).map { _ in "currency:" + code }
            }
        }
        return values.sorted()
    }

    private static func negationCount(_ text: String, language: String) -> Int? {
        let patterns = [
            "en": #"(?i)\b(?:not|never|no|cannot|without)\b|n't\b|n’t\b"#,
            "de": #"(?i)\b(?:nicht|nie|kein\p{L}*|ohne)\b"#, "fr": #"(?i)\b(?:pas|jamais|sans|aucun\p{L}*)\b"#,
            "es": #"(?i)\b(?:no|nunca|sin)\b"#, "pt": #"(?i)\b(?:não|nunca|sem)\b"#, "it": #"(?i)\b(?:non|mai|senza)\b"#,
            "ru": #"(?i)\b(?:не|нет|никогда|без)\b"#, "he": #"\b(?:לא|אין|בלי)\b"#,
            "ar": #"\b(?:لا|لم|لن|ليس|بدون)\b"#, "hi": #"नहीं|मत|बिना"#, "bn": #"না|নয়|নেই"#,
            "ja": #"ません|ない|ぬ"#, "zh": #"不|没|无|未"#, "id": #"(?i)\b(?:tidak|bukan|tanpa|jangan)\b"#,
            "ur": #"نہیں|مت|بغیر"#
        ]
        guard let pattern = patterns[SpeechLanguageEvidence.baseCode(language)] else { return nil }
        let probe = SpeechLanguageEvidence.baseCode(language) == "zh"
            ? text.applyingTransform(StringTransform(rawValue: "Hant-Hans"), reverse: false) ?? text : text
        return matches(pattern, in: probe).count
    }

    public var resolvedText: String {
        switch self {
        case .original(let text), .translated(let text), .fallbackOriginal(let text, _): return text
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
    public let translationTarget: TranslationLanguage?
    public let sessionID: String?
    public let generation: Int?
    public let clientIdentifier: String?
    public let resolvedSourceLanguage: SupportedLanguage?

    public static let appGroupKey = SharedKeys.dictationLanguageRequest

    public init(
        mode: TranscriptionLanguageMode,
        translationTarget: TranslationLanguage?,
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

        let target: TranslationLanguage?
        if let value = defaults.object(forKey: targetKey) {
            guard let raw = value as? String, let language = TranslationLanguage(rawValue: raw) else {
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
        translationTarget = try container.decodeIfPresent(TranslationLanguage.self, forKey: .translationTarget)
        sessionID = try container.decodeIfPresent(String.self, forKey: .sessionID)
        generation = try container.decodeIfPresent(Int.self, forKey: .generation)
        clientIdentifier = try container.decodeIfPresent(String.self, forKey: .clientIdentifier)
        resolvedSourceLanguage = try container.decodeIfPresent(SupportedLanguage.self, forKey: .resolvedSourceLanguage)
    }

    private var hasValidRequestShape: Bool {
        hasValidBindingShape && (mode != .autoDetect || resolvedSourceLanguage == nil)
    }
}
