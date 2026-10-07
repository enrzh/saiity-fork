// DictusKeyboard/TextPrediction/SuggestionState.swift
// Observable state for the suggestion bar UI, bridging TextPredictionEngine to SwiftUI.
import UIKit
import DictusCore

/// The current mode of the suggestion bar.
///
/// WHY an enum:
/// The suggestion bar displays different content depending on context:
/// - idle: empty bar (user just typed a space or field is empty)
/// - completions: showing word completions for partial input
/// - corrections: showing spell corrections for a complete misspelled word
/// The UI layer uses this to style the bar differently per mode.
enum SuggestionMode {
    case idle
    case completions
    case corrections
    case predictions      // After space: showing n-gram predicted next words
    case undoAvailable    // After autocorrect: showing undo option for previous correction
}

/// Tracks the last autocorrection so the user can undo it.
///
/// WHY:
/// Autocorrect can be wrong. iOS convention is that tapping the suggestion bar
/// after an autocorrection undoes it. We store the original + corrected word
/// and whether a space was auto-inserted, so undo can restore exact state.
struct AutocorrectState {
    let originalWord: String
    let correctedWord: String
    let insertedSpace: Bool
}

/// A correction that is still close enough to the caret to learn an explicit
/// user override. This stays in memory only; the final word is persisted through
/// UserDictionary after a stable boundary is observed.
private struct PendingAutocorrection {
    let originalWord: String
    let correctedWord: String
    let prefixContext: String
    let expectedContext: String
    let afterContext: String
}

/// Observable suggestion state for SwiftUI binding.
///
/// WHY ObservableObject:
/// The suggestion bar is a SwiftUI view that needs to reactively update when
/// suggestions change. @Published properties trigger SwiftUI re-renders
/// automatically when the engine produces new suggestions.
///
/// WHY a separate class from TextPredictionEngine:
/// Separation of concerns: TextPredictionEngine is pure logic (testable without UI),
/// SuggestionState is the UI-facing adapter that holds @Published state and
/// handles UITextDocumentProxy interaction.
class SuggestionState: ObservableObject {

    /// Process-wide shared instance.
    /// Per-controller instances were being retained by SwiftUI's @ObservedObject backing
    /// store past their owning KeyboardViewController.deinit (#134). Sharing makes the
    /// leak no-op since all observers point to the same instance — only one keyboard
    /// is visible at a time.
    static let shared = SuggestionState()

    @Published var suggestions: [String] = []
    @Published var mode: SuggestionMode = .idle
    @Published var currentWord: String = ""

    /// Latest bounded next-character distribution for invisible letter routing.
    /// It is intentionally separate from `suggestions`: this never changes the
    /// suggestion lane or creates visible prediction UI.
    @Published private(set) var adaptiveTouchPrediction: NextCharacterProbabilities?

    /// Tracks an autocorrection that can be undone by tapping the suggestion bar.
    /// Set when autocorrect fires on space, cleared on next space or undo tap.
    @Published var pendingUndo: AutocorrectState?

    /// Words the user has rejected autocorrection for (undo'd).
    /// After undo, the same word should not be re-corrected on the next space.
    /// Cleared when the user starts typing a new word.
    var rejectedWords: Set<String> = []

    /// Policy derived from the host field's input traits (#200).
    /// Refreshed on the main thread by DictusKeyboardBridge/KeyboardViewController
    /// whenever the field can have changed (appearance, text/selection change,
    /// each keystroke). Cached here because updateAsync/updatePredictions run on
    /// a background queue and cannot read UITextDocumentProxy themselves.
    var hostPolicy: HostFieldPolicy = .allowed

    /// Shared engine — heavy resources (frequency dict, trie) are process-wide singletons
    /// to avoid the per-controller leak documented in #134.
    private let engine = TextPredictionEngine.shared
    private init() {}

    /// Serial background queue for suggestion computation.
    /// WHY serial: Ensures suggestion computations don't race each other.
    /// WHY .userInitiated: Suggestions are user-facing but not blocking the touch pipeline.
    private let suggestionQueue = DispatchQueue(
        label: "de.aiity.saiity.suggestions",
        qos: .userInitiated
    )

    /// Current in-flight suggestion work. Cancelled when a new keystroke arrives.
    /// WHY DispatchWorkItem: Thread-safe cancellation built into GCD.
    /// Without coalescing, rapid typing queues 6-10 suggestion computations per second,
    /// all running to completion. With coalescing, only the latest keystroke runs.
    private var currentSuggestionWork: DispatchWorkItem?
    private var suggestionRequestGate = SuggestionRequestGate()
    private struct SpaceCommit {
        let word: String
        // Nil is a completed "no correction needed" result, not a cache miss.
        let correction: String?
        let contextKey: String
        let selectedLanguage: String
        let spokenLanguages: [String]
    }

    private var pendingAutocorrection: PendingAutocorrection?
    /// Correction prepared on the suggestion queue for the word currently
    /// being typed. Space reads it instead of waiting on a dictionary load.
    private var spaceCommit: SpaceCommit?
    private var suppressNextAutocorrectionBoundary = false
    private var adaptiveTouchWork: DispatchWorkItem?
    private var adaptiveTouchRequestGate = SuggestionRequestGate()
    private var lastAutocorrectEnabled = AppGroup.defaults.object(forKey: SharedKeys.autocorrectEnabled) as? Bool ?? true
    private var lastSpokenLanguages = SpokenLanguagePreferences.load(from: AppGroup.defaults)
    private struct AdaptiveContext: Equatable {
        let text: String
        let policy: HostFieldPolicy
        let autocorrect: Bool
        let language: String
        let spokenLanguages: [String]
        let rejected: Set<String>
    }
    private var lastAdaptiveContext: AdaptiveContext?

    /// Whether autocorrect is enabled (reads from App Group shared preferences).
    var autocorrectEnabled: Bool {
        AppGroup.defaults.object(forKey: SharedKeys.autocorrectEnabled) as? Bool ?? true
    }

    /// Applies autocorrect on space and inserts the space. Does not populate the
    /// accessory lane — this keyboard does not show word suggestions in the bar.
    func handleSpace(proxy: UITextDocumentProxy) {
        hostPolicy = HostInputTraits.policy(for: proxy)
        let context = proxy.documentContextBeforeInput ?? ""
        reconcilePendingAutocorrection(context: context, boundary: true)

        if context.isEmpty {
            proxy.insertText(" ")
            clear()
            noteTypedCharacter(" ")
            return
        }

        if let last = context.last, last.isWhitespace || last.isNewline {
            proxy.insertText(" ")
            clear(resetLanguage: false)
            noteTypedCharacter(" ")
            return
        }

        let word = extractLastWord(from: context)
        var corrected = false
        var canLearn = !autocorrectEnabled || !hostPolicy.autocorrectAllowed
            || engine.shouldSkipTokenPrediction(for: word)
        if let expansion = SnippetStore.expansion(for: word, from: AppGroup.defaults) {
            for _ in word { proxy.deleteBackward() }
            proxy.insertText(expansion)
            proxy.insertText(" ")
            rejectedWords.removeAll()
            pendingUndo = nil
            clear(resetLanguage: false)
            noteTypedCharacter(" ")
            HapticFeedback.playInputClick()
            return
        }
        if hostPolicy.autocorrectAllowed,
           autocorrectEnabled,
           !word.isEmpty,
           !word.unicodeScalars.contains(where: { CharacterSet.decimalDigits.contains($0) }),
           !engine.shouldSkipTokenPrediction(for: word),
           !rejectedWords.contains(word.lowercased()) {
            let contextKey = String(context.suffix(240))
            let prepared = spaceCommit
            let snapshotMatches = prepared?.word.caseInsensitiveCompare(word) == .orderedSame
                && prepared?.contextKey == contextKey
                && prepared?.selectedLanguage == SupportedLanguage.active.rawValue
                && prepared?.spokenLanguages == SpokenLanguagePreferences.load(from: AppGroup.defaults)
            let correction: String?
            if let prepared, snapshotMatches {
                canLearn = true
                correction = prepared.correction.flatMap { TypingCommit.accepts(typed: word, correction: $0) ? $0 : nil }
            } else {
                // A missed background result preserves the typed word. Never
                // wait for dictionary loading or a prediction backlog on Space.
                correction = nil
            }
            if let correction {
                corrected = true
                let prefix = prefixBeforeWord(in: context, word: word)
                let pending = PendingAutocorrection(
                    originalWord: word,
                    correctedWord: correction,
                    prefixContext: prefix,
                    expectedContext: prefix + correction + " ",
                    afterContext: proxy.documentContextAfterInput ?? ""
                )
                for _ in word { proxy.deleteBackward() }
                proxy.insertText(correction)
                pendingAutocorrection = pending
                suppressNextAutocorrectionBoundary = true
            }
        } else {
            pendingUndo = nil
        }

        // Learning does not require a supported autocorrection language or an
        // enabled corrector. Sensitive/token fields keep their existing policy.
        let learningWord = context.split(whereSeparator: \.isWhitespace).last.map(String.init)?
            .trimmingCharacters(in: .punctuationCharacters) ?? ""
        if !corrected, canLearn, hostPolicy.suggestionsAllowed, isSafeUserOverride(learningWord) {
            DispatchQueue.main.async { _ = UserDictionary.shared.recordUsage(learningWord) }
        }

        proxy.insertText(" ")
        rejectedWords.removeAll()
        pendingUndo = nil
        // A space ends the word. It does not end the sentence language.
        clear(resetLanguage: false)
        noteTypedCharacter(" ")
    }

    /// Drop a stale hit bias immediately; the contextual replacement is computed
    /// off the main thread by updateAdaptiveTouchPrediction.
    func noteTypedCharacter(_ _: String) {
        lastAdaptiveContext = nil
        adaptiveTouchWork?.cancel()
        _ = adaptiveTouchRequestGate.begin()
        if adaptiveTouchPrediction != nil {
            adaptiveTouchPrediction = nil
        }
    }

    /// Updates suggestions based on the current text input state.
    ///
    /// Called on every keystroke from the keyboard view.
    ///
    /// HOW IT WORKS:
    /// 1. Extract the last partial word from the text before the cursor
    /// 2. Check spell correction engine (same engine that fires on space)
    /// 3. If correction found: show [original | **correction** | alternative] (standard mobile layout)
    /// 4. If no correction: show UITextChecker completions
    /// 5. If no partial word (after space/newline), go idle
    ///
    /// WHY show correction in bar:
    /// The bar must preview what space will do. Standard iOS keyboard behavior:
    /// center slot (bold) = what gets auto-applied on space. If the bar shows
    /// completions but space applies a different correction, that's confusing.
    func update(proxy: UITextDocumentProxy) {
        // Host field traits gate (#200): search/URL/email fields get no suggestions.
        hostPolicy = HostInputTraits.policy(for: proxy)
        guard hostPolicy.suggestionsAllowed else {
            clear()
            return
        }

        guard let context = proxy.documentContextBeforeInput, !context.isEmpty else {
            clear()
            return
        }

        // Only the proxy read and policy check stay synchronous. The whole
        // prediction pipeline, including language detection and dictionary loads,
        // runs through the coalescing background path.
        updateAsync(context: context)
    }

    /// Async suggestion update: takes pre-read context string (read on main thread),
    /// then dispatches computation to background. Cancels previous in-flight work.
    ///
    /// WHY a separate method from update(proxy:):
    /// update(proxy:) reads UITextDocumentProxy directly and runs synchronously on main.
    /// updateAsync takes a pre-read context string so the heavy computation
    /// (extractLastWord + engine lookups) runs on a background queue.
    /// The synchronous update() is still used by delete/undo paths where fresh proxy
    /// context is needed immediately.
    func updateAsync(context: String?) {
        // Host field traits gate (#200): reads the cached policy — this method
        // dispatches to a background queue and cannot touch the proxy itself.
        guard hostPolicy.suggestionsAllowed else {
            clear()
            return
        }

        guard let context = context, !context.isEmpty else {
            clear()
            return
        }

        // If text ends with whitespace, show next-word predictions. Undo stays
        // until the next non-space edit so the previous correction can still
        // be reversed from the accessory lane.
        if let lastChar = context.last, lastChar.isWhitespace || lastChar.isNewline {
            if mode != .undoAvailable {
                updatePredictions(context: context)
            }
            return
        }

        let requestToken = beginSuggestionRequest()

        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }

            // Detection may have refined the previous request to another
            // language. Re-anchor every new context to the selected keyboard
            // language before allowing a confident refinement.
            self.engine.setSelectedLanguage(SupportedLanguage.active.rawValue)

            guard !self.engine.shouldAbstainFromPrediction(for: context) else {
                DispatchQueue.main.async { [weak self] in self?.clear() }
                return
            }
            self.engine.setLanguage(forRecentText: context)

            let partial = self.extractLastWord(from: context)
            guard !partial.isEmpty else {
                DispatchQueue.main.async { [weak self] in
                    guard let self,
                          self.suggestionRequestGate.isCurrent(requestToken) else { return }
                    self.clear()
                }
                return
            }

            if self.engine.shouldSkipTokenPrediction(for: partial) {
                DispatchQueue.main.async { [weak self] in
                    guard let self,
                          self.suggestionRequestGate.isCurrent(requestToken) else { return }
                    self.clear()
                }
                return
            }

            // Guard: skip spell correction for tokens containing digits (#74)
            let containsDigit = partial.unicodeScalars.contains {
                CharacterSet.decimalDigits.contains($0)
            }
            if containsDigit {
                let completions = self.engine.suggestions(for: partial)
                DispatchQueue.main.async { [weak self] in
                    guard let self = self,
                          self.suggestionRequestGate.isCurrent(requestToken) else { return }
                    self.currentWord = partial
                    self.suggestions = completions.isEmpty ? [] : completions
                    self.mode = completions.isEmpty ? .idle : .completions
                }
                return
            }

            // Extract previous word for n-gram context boosting
            let previousWord = self.extractPreviousWord(from: context, currentWord: partial)

            // Check spell correction first (mirrors what handleSpace will do)
            let spellResult: (correction: String, alternatives: [String])?
            if self.autocorrectEnabled,
               !self.rejectedWords.contains(partial.lowercased()) {
                spellResult = self.engine.spellCheck(
                    partial,
                    previousWord: previousWord,
                    isAtSentenceStart: ProperNounGuard.isAtSentenceStart(context: context, word: partial)
                )
            } else {
                spellResult = nil
            }

            // Compute completions as fallback
            let completions = self.engine.suggestions(for: partial)

            // Snapshot the learned set here rather than in the main-thread block
            // below: it is the same background queue `suggestions(for:)` already
            // reads it on, and the corrections row must be built from the same
            // view of the dictionary the completions were.
            let learnedWords = UserDictionary.shared.learnedWordsByLastUsed

            // Publish on main thread (required for @Published)
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                // Cancellation cannot identify stale work once a newer item has
                // replaced currentSuggestionWork. Check the captured generation.
                guard self.suggestionRequestGate.isCurrent(requestToken) else { return }

                self.currentWord = partial

                // Undo available: show original word as first slot, fill remaining with completions
                if let undo = self.pendingUndo {
                    var undoSuggestions = [undo.originalWord]
                    undoSuggestions.append(contentsOf: completions.prefix(2))
                    self.suggestions = undoSuggestions
                    self.mode = .undoAvailable
                } else if let result = spellResult,
                   result.correction.lowercased() != partial.lowercased() {
                    // Spell correction (standard mobile layout), third slot to a
                    // learned word when one extends the typed prefix (#346).
                    // Same function as the sync path so the two agree.
                    self.suggestions = LearnedWordCompletions.correctionsRow(
                        typedWord: partial,
                        correction: result.correction,
                        alternative: result.alternatives.first,
                        learnedWords: learnedWords
                    )
                    self.mode = .corrections
                } else if !completions.isEmpty {
                    self.suggestions = completions
                    self.mode = .completions
                } else {
                    self.suggestions = []
                    self.mode = .idle
                }
            }
        }

        currentSuggestionWork = work
        suggestionQueue.async(execute: work)
    }

    /// Refreshes the invisible next-character cache from a live context snapshot.
    /// The owning controller must call this on the main thread after document edits
    /// and caret/field changes; stale workers cannot publish after a newer request.
    func updateAdaptiveTouchPrediction(context: String?, policy: HostFieldPolicy? = nil) {
        if let policy {
            hostPolicy = policy
        }
        let selectedLanguage = SupportedLanguage.active.rawValue
        let snapshot = AdaptiveContext(text: context ?? "", policy: hostPolicy,
            autocorrect: autocorrectEnabled, language: selectedLanguage,
            spokenLanguages: SpokenLanguagePreferences.load(from: AppGroup.defaults), rejected: rejectedWords)
        guard snapshot != lastAdaptiveContext else { return }
        lastAdaptiveContext = snapshot
        adaptiveTouchWork?.cancel()
        let requestToken = adaptiveTouchRequestGate.begin()
        spaceCommit = nil

        guard hostPolicy.suggestionsAllowed else {
            // URL, email, search, and the other protected fields must not keep
            // a prior computed in the previous field.
            adaptiveTouchPrediction = nil
            return
        }
        guard let inputContext = context, !inputContext.isEmpty else {
            // The host may withhold context; no guess is safer than an old field's bias.
            if adaptiveTouchPrediction != nil { adaptiveTouchPrediction = nil }
            return
        }

        let last = inputContext.last
        let isBoundary = last?.isWhitespace == true || last?.isNewline == true
        let sentenceContext = contextSinceSentenceBoundary(inputContext)
        let allWords = extractLastWords(from: sentenceContext, count: 3)
        let previousWords = isBoundary ? allWords : Array(allWords.dropLast())
        let partial = isBoundary ? "" : extractLastWord(from: inputContext)
        let atSentenceStart = isBoundary
            ? isAtSentenceStartAfterBoundary(inputContext)
            : isAtSentenceStart(context: inputContext, word: partial)
        guard isBoundary || !partial.isEmpty else { return }

        let rejected = !partial.isEmpty && rejectedWords.contains(partial.lowercased())
        if adaptiveTouchPrediction != nil { adaptiveTouchPrediction = nil }

        let allowsAutocorrect = hostPolicy.autocorrectAllowed && autocorrectEnabled
        weak var cancellableWork: DispatchWorkItem?
        let work = DispatchWorkItem { [weak self] in
            guard let self, let work = cancellableWork, !work.isCancelled else { return }
            guard snapshot.spokenLanguages == SpokenLanguagePreferences.load(from: AppGroup.defaults) else { return }
            // The keyboard language can stay fixed while spoken-language
            // membership changes in the app. Exact acceptance follows both.
            self.engine.setSelectedLanguage(selectedLanguage)
            // A completed word is the cheap, stable language boundary. This
            // live path previously never called typed-language detection.
            if isBoundary { self.engine.setLanguage(forRecentText: inputContext) }
            let abstains = self.engine.shouldAbstainFromPrediction(for: inputContext)
            guard !work.isCancelled else { return }
            // Prepare Space first. Adaptive hit refinement must not hold up
            // the correction a fast typist is about to commit.
            let commit = abstains ? nil : self.preparedSpaceCommit(
                partial: partial, context: inputContext, previousWord: previousWords.last,
                isAtSentenceStart: atSentenceStart, isBoundary: isBoundary,
                allowsAutocorrect: allowsAutocorrect, rejected: rejected,
                selectedLanguage: selectedLanguage, spokenLanguages: snapshot.spokenLanguages)
            self.publishSpaceCommit(commit, token: requestToken)
            guard !work.isCancelled else { return }
            let probabilities = rejected || abstains
                ? NextCharacterProbabilities([:])
                : isBoundary
                    ? self.engine.nextCharacterProbabilities(
                        after: previousWords, isAtSentenceStart: atSentenceStart)
                    : self.engine.nextCharacterProbabilities(
                        for: partial, after: previousWords, isAtSentenceStart: atSentenceStart)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.adaptiveTouchRequestGate.isCurrent(requestToken),
                      self.hostPolicy.suggestionsAllowed else { return }
                self.adaptiveTouchPrediction = probabilities.isEmpty ? nil : probabilities
                self.adaptiveTouchWork = nil
            }
        }
        cancellableWork = work
        adaptiveTouchWork = work
        suggestionQueue.async(execute: work)
    }

    private func preparedSpaceCommit(
        partial: String,
        context: String,
        previousWord: String?,
        isAtSentenceStart: Bool,
        isBoundary: Bool,
        allowsAutocorrect: Bool,
        rejected: Bool,
        selectedLanguage: String,
        spokenLanguages: [String]
    ) -> SpaceCommit? {
        guard allowsAutocorrect, !isBoundary, !partial.isEmpty,
              !engine.dictionaryLoadInFlight,
              !engine.shouldSkipTokenPrediction(for: partial),
              !rejected else { return nil }
        let result = engine.spellCheck(
            partial,
            previousWord: previousWord,
            isAtSentenceStart: isAtSentenceStart
        )
        return SpaceCommit(
            word: partial,
            correction: result.flatMap { TypingCommit.accepts(typed: partial, correction: $0.correction) ? $0.correction : nil },
            contextKey: String(context.suffix(240)),
            selectedLanguage: selectedLanguage,
            spokenLanguages: spokenLanguages
        )
    }

    private func publishSpaceCommit(_ commit: SpaceCommit?, token: SuggestionRequestGate.Token) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.adaptiveTouchRequestGate.isCurrent(token) else { return }
            self.spaceCommit = commit
        }
    }

    /// Drops only the invisible routing cache, leaving the suggestion lane intact.
    func clearAdaptiveTouchPrediction() {
        lastAdaptiveContext = nil
        adaptiveTouchWork?.cancel()
        adaptiveTouchWork = nil
        _ = adaptiveTouchRequestGate.begin()
        adaptiveTouchPrediction = nil
    }

    /// Delegates spell-checking to the engine.
    /// Returns the best correction and alternatives for a misspelled word, or nil if correct.
    func performSpellCheck(_ word: String) -> (correction: String, alternatives: [String])? {
        suggestionQueue.sync { engine.spellCheck(word) }
    }

    /// Spell check with optional previous word context for n-gram boosting.
    /// When previousWord is provided, correction candidates are reranked by bigram frequency.
    /// isAtSentenceStart drives the proper-noun guard (#199); defaults to true
    /// (conservative — corrections stay enabled for callers without position info).
    func performSpellCheck(
        _ word: String,
        previousWord: String?,
        isAtSentenceStart: Bool = true
    ) -> (correction: String, alternatives: [String])? {
        suggestionQueue.sync {
            engine.spellCheck(word, previousWord: previousWord, isAtSentenceStart: isAtSentenceStart)
        }
    }

    /// Resets the suggestion state to idle.
    func clear(resetLanguage: Bool = true) {
        _ = beginSuggestionRequest()
        spaceCommit = nil
        clearAdaptiveTouchPrediction()
        suggestions = []
        mode = .idle
        currentWord = ""
        // Fully deleted input: drop sticky typed-language so plates/priors
        // return to the selected keyboard language. A space is not that.
        guard resetLanguage else { return }
        suggestionQueue.async { [weak self] in
            self?.engine.resetTypedLanguageDetection()
        }
    }

    /// Re-read preference-backed behavior after the app changes a setting while
    /// the keyboard extension is cached.
    func refreshPreferences() {
        let enabled = autocorrectEnabled
        let spoken = SpokenLanguagePreferences.load(from: AppGroup.defaults)
        if spoken != lastSpokenLanguages {
            lastSpokenLanguages = spoken
            spaceCommit = nil
            clearAdaptiveTouchPrediction()
            suggestionQueue.async { [weak self] in
                self?.engine.setSelectedLanguage(SupportedLanguage.active.rawValue)
            }
        }
        guard enabled != lastAutocorrectEnabled else { return }
        lastAutocorrectEnabled = enabled
        spaceCommit = nil
        clearAdaptiveTouchPrediction()
        guard !enabled else { return }
        pendingUndo = nil
        pendingAutocorrection = nil
        suppressNextAutocorrectionBoundary = false
        if mode == .corrections || mode == .undoAvailable {
            suggestions = []
            mode = .idle
            currentWord = ""
        }
    }

    func refreshVocabulary() {
        UserDictionary.shared.reload()
        spaceCommit = nil
        clearAdaptiveTouchPrediction()
    }

    /// The keyboard gets selection callbacks for both its own insertions and a
    /// user's caret movement. Text edits are reconciled by
    /// `reconcilePendingAutocorrection(proxy:)`; this callback only invalidates
    /// a pending correction when the caret moved away from the original trailing
    /// context. That distinction keeps a normal backspace-and-retype override
    /// learnable while still failing closed for a genuine caret move.
    func noteSelectionChanged(proxy: UITextDocumentProxy) {
        guard let pending = pendingAutocorrection else { return }
        guard let after = proxy.documentContextAfterInput else {
            pendingAutocorrection = nil
            return
        }
        guard after == pending.afterContext else {
            pendingAutocorrection = nil
            return
        }
    }

    /// Reconciles an edit reported by the host after text insertion. This is
    /// intentionally separate from `handleSpace`, which evaluates the pending
    /// word before it inserts the new boundary itself.
    func reconcilePendingAutocorrection(proxy: UITextDocumentProxy) {
        let context = proxy.documentContextBeforeInput ?? ""
        let boundary = context.last.map {
            $0.isWhitespace || $0.isNewline || $0.unicodeScalars.allSatisfy {
                CharacterSet.punctuationCharacters.contains($0)
            }
        } ?? false
        reconcilePendingAutocorrection(context: context, boundary: boundary)
    }

    /// Learns only a final word that replaced the applied correction at the same
    /// caret. A changed word is accepted on a word/punctuation boundary; edits
    /// without a boundary remain pending until the next one.
    private func reconcilePendingAutocorrection(
        context: String,
        boundary: Bool
    ) {
        guard let pending = pendingAutocorrection else { return }

        if context == pending.expectedContext {
            if boundary, suppressNextAutocorrectionBoundary {
                suppressNextAutocorrectionBoundary = false
                return
            }
            if boundary { pendingAutocorrection = nil }
            return
        }

        suppressNextAutocorrectionBoundary = false

        guard let wordRange = lastWordRange(in: context),
              context[..<wordRange.lowerBound].hasSuffix(pending.prefixContext) else {
            pendingAutocorrection = nil
            return
        }
        guard boundary else { return }

        let word = String(context[wordRange])
        if word.caseInsensitiveCompare(pending.correctedWord) == .orderedSame {
            pendingAutocorrection = nil
            return
        }
        if isSafeUserOverride(word), word.caseInsensitiveCompare(pending.originalWord) != .orderedSame {
            _ = UserDictionary.shared.learn(word)
        }
        pendingAutocorrection = nil
    }

    private func isSafeUserOverride(_ word: String) -> Bool {
        guard word.count > 1, word.count <= DictationVocabulary.maxTermCharacters else { return false }
        var hasLetter = false
        for scalar in word.unicodeScalars {
            if CharacterSet.letters.contains(scalar) {
                hasLetter = true
                continue
            }
            if CharacterSet.nonBaseCharacters.contains(scalar) || scalar == "'" || scalar == "’" || scalar == "-" {
                continue
            }
            return false
        }
        return hasLetter
    }

    private func prefixBeforeWord(in context: String, word: String) -> String {
        guard let range = context.range(of: word, options: .backwards) else { return context }
        return String(context[..<range.lowerBound])
    }

    private func lastWordRange(in text: String) -> Range<String.Index>? {
        guard !text.isEmpty else { return nil }
        var result: Range<String.Index>?
        text.enumerateSubstrings(
            in: text.startIndex..<text.endIndex,
            options: [.byWords, .reverse]
        ) { _, range, _, stop in
            result = range
            stop = true
        }
        return result
    }

    /// Applies a visible suggestion directly to the host field.
    /// The proxy is supplied by the current keyboard controller so this shared
    /// state never retains a controller or a text document proxy.
    func acceptSuggestion(at index: Int, proxy: UITextDocumentProxy) {
        guard suggestions.indices.contains(index) else { return }
        let suggestion = suggestions[index]

        if mode == .undoAvailable, index == 0, let undo = pendingUndo {
            let count = undo.correctedWord.count + (undo.insertedSpace ? 1 : 0)
            for _ in 0..<count { proxy.deleteBackward() }
            proxy.insertText(undo.originalWord)
            rejectedWords.insert(undo.originalWord.lowercased())
            pendingUndo = nil
            clear()
            return
        }

        if mode == .predictions {
            proxy.insertText(suggestion)
        } else {
            for _ in currentWord { proxy.deleteBackward() }
            proxy.insertText(suggestion)
        }
        clear()
    }

    /// Updates the prediction engine's language.
    func setLanguage(_ lang: String) {
        suggestionQueue.async { [weak self] in
            guard let self else { return }
            self.engine.setSelectedLanguage(lang)
        }
    }

    /// Whether the active language's dictionary does not know this word (#287).
    /// The word-boundary learning site asks before recording anything.
    func isUnknownToDictionary(_ word: String) -> Bool {
        suggestionQueue.sync { engine.isUnknownToDictionary(word) }
    }

    /// Attempts the user dictionary's one-shot prune (#287). Call from a moment
    /// with a dictionary already mounted and no load pending — see the engine.
    func pruneUserDictionaryIfPossible(trigger: String) {
        suggestionQueue.sync { engine.pruneUserDictionaryIfPossible(trigger: trigger) }
    }

    // MARK: - N-gram Predictions

    /// Updates suggestion bar with n-gram predicted next words.
    /// Called after space insertion (handleSpace) and after prediction tap (chaining).
    ///
    /// WHY a separate method from update/updateAsync:
    /// Predictions use a different data path: instead of extracting the current partial
    /// word and running spell check, we extract the last 1-2 complete words and query
    /// the n-gram engine. The result is displayed in .predictions mode, not .corrections.
    func updatePredictions(context: String?) {
        let requestToken = beginSuggestionRequest()
        // Host field traits gate (#200): no next-word predictions in search/URL fields.
        guard hostPolicy.suggestionsAllowed else {
            clear()
            return
        }

        guard let context = context, !context.isEmpty else {
            clear()
            return
        }

        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }

            // Keep the n-gram path consistent with partial-word suggestions:
            // a previous field's detected language must not become this field's
            // silent default.
            self.engine.setSelectedLanguage(SupportedLanguage.active.rawValue)

            guard !self.engine.shouldAbstainFromPrediction(for: context) else {
                DispatchQueue.main.async { [weak self] in self?.clear() }
                return
            }
            self.engine.setLanguage(forRecentText: context)

            // Extract last 1-2 complete words from context
            let words = self.extractLastWords(from: context, count: 2)
            guard !words.isEmpty else {
                DispatchQueue.main.async { [weak self] in
                    guard let self,
                          self.suggestionRequestGate.isCurrent(requestToken) else { return }
                    self.clear()
                }
                return
            }

            let predictions = self.engine.predictNextWords(after: words)
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                guard self.suggestionRequestGate.isCurrent(requestToken) else { return }

                if let undo = self.pendingUndo {
                    var undoSuggestions = [undo.originalWord]
                    undoSuggestions.append(contentsOf: predictions.prefix(2))
                    self.suggestions = undoSuggestions
                    self.mode = .undoAvailable
                } else if predictions.isEmpty {
                    self.suggestions = []
                    self.mode = .idle
                } else {
                    self.suggestions = Array(predictions.prefix(3))
                    self.mode = .predictions
                }
            }
        }

        currentSuggestionWork = work
        suggestionQueue.async(execute: work)
    }

    /// Extracts the last N complete words from text context.
    /// Used for n-gram context: "Je suis en " -> ["suis", "en"]
    ///
    /// WHY not reuse extractLastWord: that returns the partial word being typed
    /// (before cursor, no trailing space). For predictions, we need the complete
    /// words before the space -- the n-gram engine looks up what comes AFTER these words.
    private func extractLastWords(from text: String, count: Int) -> [String] {
        var words: [String] = []
        text.enumerateSubstrings(in: text.startIndex..., options: .byWords) { substring, _, _, _ in
            if let word = substring {
                words.append(word)
            }
        }
        let start = max(0, words.count - count)
        return Array(words[start...])
    }

    private func isAtSentenceStartAfterBoundary(_ context: String) -> Bool {
        // Keep a trailing newline visible as a sentence boundary while
        // ignoring ordinary spaces typed after punctuation.
        let trimmed = context.trimmingCharacters(in: .whitespaces)
        guard let last = trimmed.last else { return true }
        return last == "." || last == "!" || last == "?" || last.isNewline
    }

    private func contextSinceSentenceBoundary(_ text: String) -> String {
        guard let boundary = text.lastIndex(where: {
            $0 == "." || $0 == "!" || $0 == "?" || $0 == "\n"
        }) else {
            return text
        }
        return String(text[text.index(after: boundary)...])
    }

    // MARK: - Private

    @discardableResult
    private func beginSuggestionRequest() -> SuggestionRequestGate.Token {
        currentSuggestionWork?.cancel()
        currentSuggestionWork = nil
        return suggestionRequestGate.begin()
    }

    /// Extract the word before the current partial word in the text context.
    /// "Je sui" with currentWord "sui" returns "Je".
    /// "J'ai un prblm" with currentWord "prblm" returns "un".
    ///
    /// WHY not just split on spaces: Swift's enumerateSubstrings handles
    /// Unicode word boundaries correctly (apostrophes, hyphens, etc.).
    private func extractPreviousWord(from text: String, currentWord: String) -> String? {
        var words: [String] = []
        text.enumerateSubstrings(in: text.startIndex..., options: .byWords) { substring, _, _, _ in
            if let word = substring {
                words.append(word)
            }
        }
        // The last word should be currentWord; the one before it is previousWord
        guard words.count >= 2, words.last?.lowercased() == currentWord.lowercased() else {
            return nil
        }
        return words[words.count - 2]
    }

    /// Extracts the last word from a text context string.
    ///
    /// WHY manual extraction:
    /// We use Swift's built-in word boundary detection via enumerateSubstrings
    /// to correctly handle Unicode, apostrophes in French (l'homme), and
    /// other edge cases. This is more reliable than splitting on spaces.
    private func isAtSentenceStart(context: String, word: String) -> Bool {
        guard let range = context.range(of: word, options: .backwards) else { return true }
        let prefix = context[..<range.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prefix.isEmpty else { return true }
        guard let last = prefix.last else { return true }
        return last == "." || last == "!" || last == "?" || last == "\n"
    }

    private func extractLastWord(from text: String) -> String {
        var lastWord = ""
        text.enumerateSubstrings(in: text.startIndex..., options: .byWords) { substring, _, _, _ in
            if let word = substring {
                lastWord = word
            }
        }
        return lastWord
    }
}
