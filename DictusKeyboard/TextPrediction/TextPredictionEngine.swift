// DictusKeyboard/TextPrediction/TextPredictionEngine.swift
// Core prediction logic: word completions, spell-checking, and accent suggestions.
import UIKit
import NaturalLanguage
import SyllivraKernel

/// Provides word completions, spell-checking, and accent suggestions for the keyboard.
///
/// WHY a class (not struct):
/// UITextChecker is a reference type (NSObject subclass) and maintains internal state
/// for its learned words dictionary. Using a class avoids copy-on-write issues and
/// ensures a single UITextChecker instance is reused throughout the keyboard session.
///
/// WHY UITextChecker:
/// Apple's built-in spell checker and word completion engine. It uses the system
/// dictionary which is already installed on every iOS device -- no additional data
/// download needed. We combine its completions with our FrequencyDictionary to
/// rank results by word frequency (most common words first).
class TextPredictionEngine {

    /// Shared instance — engines are heavy (~3 MiB FrequencyDictionary + AOSP trie mmap).
    /// Per-controller instances were leaking via SwiftUI @ObservedObject zombies that
    /// survive their owning KeyboardViewController.deinit (KeyboardRootView struct held
    /// alive by KeyboardState.shared.objectWillChange subscription). Sharing the heavy
    /// resources means the leak no longer multiplies memory per app-switch cycle.
    static let shared = TextPredictionEngine(bundle: Bundle(for: AOSPTrieBridge.self))

    private let textChecker = UITextChecker()
    private var frequencyDict = FrequencyDictionary()
    private let aospTrieEngine = AOSPTrieEngine()
    private let dictionaryBundle: Bundle
    /// Exact acceptance only; extra n-grams and frequency tables are not loaded.
    /// Accessed on the existing prediction queue, including mapping and removal.
    private var acceptedWordTries: [String: AOSPTrieBridge] = [:]
    private(set) var enabledDictionaryLanguages: [String] = []
    private var acceptedWordsReady = false
    private var didInitializeDictionaries = false
    private var language: String = SupportedLanguage.active.rawValue
    private var selectedLanguage: String = SupportedLanguage.active.rawValue
    private var lastLanguageProbeText: String?
    private var lastDetectedLanguage: String?

    /// The active language's data profile, or nil if `language` is not a registered
    /// `SupportedLanguage`. Used to gate language-specific pipeline stages by
    /// reading profile data instead of hardcoded language string comparisons.
    private var profile: LanguageProfile? {
        SupportedLanguage(rawValue: language)?.profile
    }

    /// Whether this process has already reported that the prune was done in an
    /// earlier session. See `reportPruneAlreadyDone()`.
    private var hasReportedPruneAlreadyDone = false

    init(bundle: Bundle = .main) {
        dictionaryBundle = bundle
    }

    /// Only explicitly selected languages with a bundled dictionary are mapped.
    /// Empty spoken preferences do not implicitly enable the entire catalog.
    private func refreshAcceptedWordDictionaries() {
        let enabled = SpokenLanguagePreferences.normalized(
            [selectedLanguage] + SpokenLanguagePreferences.load(from: AppGroup.defaults))
            .filter { dictionaryBundle.path(forResource: "\($0)_spellcheck", ofType: "dict") != nil }
        guard enabled != enabledDictionaryLanguages else { return }
        enabledDictionaryLanguages = enabled
        acceptedWordTries = acceptedWordTries.filter { enabled.contains($0.key) }
        for code in enabled where acceptedWordTries[code] == nil {
            guard let path = dictionaryBundle.path(forResource: "\(code)_spellcheck", ofType: "dict") else { continue }
            let trie = AOSPTrieBridge()
            if trie.loadDictionary(atPath: path) { acceptedWordTries[code] = trie }
        }
        // A failed map must not allow correction while an enabled language's
        // valid words are unknown. Input remains available without correction.
        acceptedWordsReady = enabled.allSatisfy { acceptedWordTries[$0] != nil }
    }

    private func isAcceptedWord(_ word: String) -> Bool {
        let exact = word.lowercased().precomposedStringWithCanonicalMapping
        return acceptedWordTries.values.contains { $0.wordExists(exact) }
    }

    private func shouldPreserveSpelling(_ word: String) -> Bool {
        // Explicit vocabulary takes precedence; exact foreign words then block
        // every correction path, including language overrides and n-gram boosts.
        UserDictionary.shared.isLearned(word.lowercased()) || !acceptedWordsReady
            || aospTrieEngine.isLoading || isAcceptedWord(word)
    }

    /// A sentence needs different dictionaries when no one enabled dictionary
    /// contains all its recognized words. Shared words and unknown typos are
    /// neutral; this chooses no language for an individual token.
    private func hasMixedDictionaryWords(_ text: String) -> Bool {
        var common = Set(enabledDictionaryLanguages)
        guard common.count > 1 else { return false }
        for token in text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }) {
            let word = String(token).trimmingCharacters(in: .punctuationCharacters)
                .lowercased().precomposedStringWithCanonicalMapping
            let matches = Set(acceptedWordTries.compactMap { code, trie in trie.wordExists(word) ? code : nil })
            guard !matches.isEmpty else { continue }
            common.formIntersection(matches)
            if common.isEmpty { return true }
        }
        return false
    }

    /// Updates the active language for completions and spell-checking.
    /// Reloads the frequency dictionary for the new language.
    ///
    /// WHY reload on language change:
    /// We only keep one language's frequency data in memory at a time
    /// to stay within the keyboard extension's ~50MB memory budget.
    func setLanguage(_ lang: String) {
        guard language != lang else { return }
        language = lang
        loadDictionaries(for: lang)
    }

    /// Anchors a new host-field context without reloading the selected
    /// dictionary on every keystroke. Recent-text detection may temporarily
    /// refine `language`, but the selected language remains the fallback.
    func setSelectedLanguage(_ lang: String) {
        let selectionChanged = selectedLanguage != lang
        selectedLanguage = lang
        if selectionChanged {
            lastLanguageProbeText = nil
            lastDetectedLanguage = nil
        }
        refreshAcceptedWordDictionaries()
        if !didInitializeDictionaries {
            didInitializeDictionaries = true
            language = lang
            loadDictionaries(for: lang)
        } else if selectionChanged || !enabledDictionaryLanguages.contains(language) { setLanguage(lang) }
    }

    /// Clears sticky typed-language detection so an emptied field falls back
    /// to the selected keyboard language instead of the previous document's prior.
    func resetTypedLanguageDetection() {
        lastLanguageProbeText = nil
        lastDetectedLanguage = nil
        setLanguage(selectedLanguage)
    }

    /// Uses the most recent text when it is confidently identifiable. The
    /// active keyboard language remains the fallback for short or mixed input.
    func setLanguage(forRecentText text: String) {
        refreshAcceptedWordDictionaries()
        let recentText = String(text.suffix(240))
        // Empty / fully-deleted input must drop sticky detection so the next
        // document does not inherit the previous field's language prior.
        if recentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            resetTypedLanguageDetection()
            return
        }
        if PredictionLanguageSafety.shouldAbstain(for: recentText) || hasMixedDictionaryWords(recentText) {
            lastLanguageProbeText = recentText
            lastDetectedLanguage = nil
            setLanguage(selectedLanguage)
            return
        }
        // While the user is still extending the same word, keep the last
        // confident typed-language decision instead of re-probing every glyph.
        if let lastProbe = lastLanguageProbeText,
           lastProbe.count >= 8,
           recentText.hasPrefix(lastProbe),
           recentText.count > lastProbe.count,
           !recentText.dropFirst(lastProbe.count).contains(where: { $0.isWhitespace || $0.isNewline }) {
            setLanguage(lastDetectedLanguage ?? selectedLanguage)
            return
        }

        let detected = recentLanguageCode(for: recentText)
        lastLanguageProbeText = recentText
        lastDetectedLanguage = detected
        setLanguage(detected ?? selectedLanguage)
    }

    /// CJK text has no useful Latin spell-check path. Returning no correction
    /// is safer and cheaper than applying an English/German dictionary to it.
    /// True while the trie for the active language is still being mapped in.
    /// Space must not wait on that load.
    var dictionaryLoadInFlight: Bool { !didInitializeDictionaries || aospTrieEngine.isLoading }

    func shouldSkipTokenPrediction(for word: String) -> Bool {
        if TypingFact.shouldLeaveUntouched(word) || TypingFact.isOpenPrefix(word) {
            return true
        }
        return word.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x3040...0x30FF, 0x3400...0x4DBF, 0x4E00...0x9FFF,
                 0xAC00...0xD7AF, 0xF900...0xFAFF:
                return true
            default:
                return false
            }
        }
    }

    /// Long unsupported or ambiguous context must not silently use the active
    /// dictionary, which is commonly English. Short context is intentionally
    /// allowed to use the user's selected keyboard language.
    func shouldAbstainFromPrediction(for text: String) -> Bool {
        let recentText = String(text.suffix(240))
        guard recentText.count >= 24,
              recentText.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count >= 4 else {
            return false
        }
        if PredictionLanguageSafety.shouldAbstain(for: recentText) { return true }
        if enabledDictionaryLanguages.count > 1 && acceptedWordTries[selectedLanguage] != nil { return false }
        return recentLanguageCode(for: recentText) == nil
    }

    /// Post-dictation offers require a confident supported language rather
    /// than the selected keyboard language as a fallback.
    func canOfferLocalContinuation(for text: String) -> Bool {
        recentLanguageCode(for: String(text.suffix(240))) != nil
    }

    private func recentLanguageCode(for recentText: String) -> String? {
        // A short clause must not replace the selected correction language.
        let wordCount = recentText.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
        guard recentText.count >= 24,
              wordCount >= 4,
              !PredictionLanguageSafety.shouldAbstain(for: recentText),
              !hasMixedDictionaryWords(recentText) else {
            return nil
        }
        let recognizer = NLLanguageRecognizer()
        recognizer.languageConstraints = SpokenLanguagePreferences.normalized(
            [selectedLanguage] + SpokenLanguagePreferences.load(from: AppGroup.defaults))
            .map(NLLanguage.init(rawValue:))
        recognizer.processString(recentText)
        let hypotheses = recognizer.languageHypotheses(withMaximum: 3)
            .sorted { $0.value > $1.value }
        guard let top = hypotheses.first else {
            return nil
        }
        let secondProbability = hypotheses.dropFirst().first?.value ?? 0
        let confidenceFloor: Double = wordCount >= 4 ? 0.55 : 0.62
        let leadFloor: Double = wordCount >= 4 ? 0.08 : 0.12
        guard top.value >= confidenceFloor,
              top.value - secondProbability >= leadFloor,
              let language = Self.supportedLanguageCode(for: top.key.rawValue),
              enabledDictionaryLanguages.contains(language),
              UITextChecker.availableLanguages.contains(where: { $0.hasPrefix(language) }) else {
            return nil
        }
        return language
    }

    private static func supportedLanguageCode(for identifier: String) -> String? {
        // NaturalLanguage can return regional identifiers such as `pt-BR`.
        // Normalize to the base code and let the existing loader decide which
        // bundled resources exist. UITextChecker still provides useful local
        // completions for the other keyboard languages without a new download.
        let baseCode = identifier
            .lowercased()
            .split(separator: "-")
            .first
            .map(String.init) ?? identifier.lowercased()
        switch baseCode {
        case "de": return SupportedLanguage.german.rawValue
        case "en": return SupportedLanguage.english.rawValue
        case "es": return SupportedLanguage.spanish.rawValue
        case "fr": return SupportedLanguage.french.rawValue
        default:
            guard SupportedLanguage(rawValue: baseCode) != nil else { return nil }
            return baseCode
        }
    }

    /// Loads both dictionaries for `lang` and runs the work that can only happen
    /// once a dictionary is actually loaded.
    private func loadDictionaries(for lang: String) {
        // Verify language is available in UITextChecker
        let available = UITextChecker.availableLanguages
        if !available.contains(where: { $0.hasPrefix(lang) }) {
            print("[TextPredictionEngine] Warning: '\(lang)' not in available languages: \(available)")
        }
        frequencyDict.load(language: lang, bundle: dictionaryBundle)
        aospTrieEngine.load(language: lang, bundle: dictionaryBundle) { [weak self] _ in
            // The user dictionary's one-shot prune (#287). This is the first
            // moment in a cold session at which anything can ask the dictionary a
            // question, so it has to be one of the triggers — but it is not a
            // privileged one. A completion can belong to a load that has since
            // been superseded, and the trie it finds may be another language's
            // entirely; the gate below is what decides, not the fact of being
            // called from here.
            self?.pruneUserDictionaryIfPossible(trigger: "dictionary-loaded")
        }
    }

    /// Attempts the user dictionary's one-shot prune, and says so when it cannot.
    ///
    /// WHY there are several triggers and no privileged one (#287). Two triggers
    /// exist because neither is sufficient alone: the load completion is the only
    /// moment a cold session can ask the dictionary anything, and it is
    /// systematically starved once a session is warm — `viewWillAppear` issues a
    /// load on every keyboard appearance, each tearing the mmap down
    /// synchronously on the main thread before the previous completion, posted
    /// with `DispatchQueue.main.async`, gets to run. That starvation is why the
    /// prune never once ran on device. `viewWillAppear` therefore also attempts
    /// it *before* asking for the next load, while the previous dictionary is
    /// still mounted.
    ///
    /// Neither is trusted, and that is the point. `UserDictionaryPruneGate` holds
    /// the one precondition — the mounted dictionary is the active language's —
    /// so a trigger cannot be wrong, only early. Adding another is safe.
    ///
    /// Whenever the prune is still owed and cannot be done, a probe says why, so
    /// an export can never again be ambiguous between "never called", "called and
    /// declined", and "done long ago".
    func pruneUserDictionaryIfPossible(trigger: String) {
        let decision = UserDictionaryPruneGate.decide(
            alreadyPruned: UserDictionary.shared.hasPrunedTrieDuplicates,
            mountedLanguage: aospTrieEngine.mountedLanguage,
            activeLanguage: SupportedLanguage.active.rawValue
        )
        switch decision {
        case .run:
            UserDictionary.shared.pruneTrieDuplicatesIfNeeded(using: aospTrieEngine)
        case .alreadyDone:
            reportPruneAlreadyDone()
        case .notMounted, .languageMismatch:
            PersistentLog.log(.diagnosticProbe(
                component: "UserDictionaryPrune",
                instanceID: "",
                action: "skipped",
                details: "trigger=\(trigger) reason=\(decision.reason)"
            ))
        }
    }

    /// Says, once per keyboard process, that the prune has already been done.
    ///
    /// WHY this line has to exist. `userDictionaryPruned` is written once in the
    /// life of an install, and `PersistentLog` is a 1 MB file trimmed from the
    /// head — so an hour of ordinary use scrolls that line out of every later
    /// export. Without a standing statement, "this install was cleaned long ago"
    /// and "the prune is broken and never ran" are the same observation: silence.
    /// The third device pass on #287 was spent on exactly that ambiguity.
    ///
    /// WHY once per process and not once per call: `viewWillAppear` runs on every
    /// keyboard appearance, seventeen times in an hour of real use, and iOS keeps
    /// several controllers alive. One line per process is enough to date the
    /// state, and anything finer is the noise #255 was about.
    private func reportPruneAlreadyDone() {
        guard !hasReportedPruneAlreadyDone else { return }
        hasReportedPruneAlreadyDone = true
        PersistentLog.log(.diagnosticProbe(
            component: "UserDictionaryPrune",
            instanceID: "",
            action: "alreadyDone",
            details: "learnedCount=\(UserDictionary.shared.count)"
        ))
    }

    /// Whether `word` is genuinely new to the active language's dictionary —
    /// the gate the word-boundary learning site needs (#287 decision 2).
    ///
    /// WHY false while the dictionary is still loading: the answer would be
    /// "unknown" for every word typed in that window, and learning them all is
    /// exactly the pollution this gate exists to stop. AOSP LatinIME takes the
    /// same position for the same reason — it turns learning off entirely on a
    /// slow InputConnection, because a word it cannot vet is a word it should
    /// not keep. If we cannot ask, we do not learn.
    func isUnknownToDictionary(_ word: String) -> Bool {
        acceptedWordsReady && !dictionaryLoadInFlight && aospTrieEngine.isReady
            && !isAcceptedWord(word) && !aospTrieEngine.knowsWord(word)
    }

    /// Returns up to 3 word completions for a partial word, ranked by frequency.
    ///
    /// HOW IT WORKS:
    /// 1. UITextChecker.completions() returns all possible completions from the system dictionary
    /// 2. We select only the few highest-ranked completions using our frequency dictionary
    /// 3. LearnedWordCompletions gives one word the user taught us the first slot (#346)
    /// 4. We return only the top 3 to fill the suggestion bar's 3 slots
    ///
    /// WHY frequency-based ranking:
    /// UITextChecker returns completions in alphabetical order by default. Ranking by
    /// word frequency ensures "les" appears before "lesparre" when typing "le".
    ///
    /// WHY the learned set is read here on every keystroke, with no cache:
    /// it lives in memory, holds tens of entries since #287 stopped learning
    /// words the trie already knows, and this runs on the suggestion queue. A
    /// cache would only add an invalidation to get wrong — the other process
    /// writes to this dictionary too.
    func suggestions(for partialWord: String) -> [String] {
        suggestions(for: partialWord, limit: 3)
    }

    /// Ranked typed-prefix completions for the active keyboard language.
    /// `limit` widens the pool for next-letter priors without changing the
    /// three visible suggestion-bar slots (those still call `limit: 3`).
    func suggestions(for partialWord: String, limit: Int) -> [String] {
        guard !partialWord.isEmpty, limit > 0 else { return [] }

        let nsString = partialWord as NSString
        let range = NSRange(location: 0, length: nsString.length)

        // `?? []` and not an early return: a prefix the system checker has
        // nothing to say about is exactly the case a learned word exists for.
        let completions = textChecker.completions(
            forPartialWordRange: range,
            in: partialWord,
            language: language
        ) ?? []

        let learnedWords = UserDictionary.shared.learnedWordsByLastUsed
        // Keep one extra system candidate when a learned word will claim a slot
        // on the visible bar. Wider limits are for next-letter priors.
        let rankingLimit = max(limit, 3) + (LearnedWordCompletions.offer(
            for: partialWord,
            in: learnedWords
        ) == nil ? 0 : 1)
        let ranked = frequencyDict.rankedCompletions(completions, limit: rankingLimit)
        let merged = LearnedWordCompletions.merge(
            typedPrefix: partialWord,
            learnedWords: learnedWords,
            systemCompletions: ranked
        )
        return Array(merged.prefix(limit))
    }

    /// Returns the best correction and alternatives for a misspelled word.
    /// Returns nil if the word is correctly spelled or is a user-learned word.
    ///
    /// WHY two-pass lookup:
    /// Pass 1: Check UserDictionary first. Words the user has learned (via rejection
    /// or repetition) are always considered correct -- no trie lookup needed. This
    /// prevents the trie from "correcting" names, slang, or jargon the user has taught.
    /// Pass 2: Delegate to AOSPTrieEngine for proximity-weighted, accent-aware correction
    /// against the 100K+ word binary trie dictionary.
    ///
    /// WHY AOSPTrieEngine instead of SymSpell:
    /// The trie walks candidates during lookup with keyboard proximity scoring,
    /// supporting 100K+ words in ~0.4 MiB per language via mmap. SymSpell pre-generated
    /// all edit-distance deletes, using 15 MiB for just 10K words.
    /// - Parameter isAtSentenceStart: whether the word sits at a sentence start
    ///   in the host document (start-of-field, after newline or after .!?).
    ///   Drives the proper-noun guard (#199): mid-sentence capitalized unknown
    ///   words are preserved. Defaults to `true`, the conservative value —
    ///   callers without position info keep full correction behavior (only the
    ///   position-independent acronym rule applies).
    func spellCheck(
        _ word: String,
        isAtSentenceStart: Bool = true
    ) -> (correction: String, alternatives: [String])? {
        guard !word.isEmpty else { return nil }
        if TypingFact.shouldLeaveUntouched(word) || TypingFact.isOpenPrefix(word) {
            return nil
        }
        guard !shouldPreserveSpelling(word) else { return nil }

        // Active-language overrides may repair a spelling only after explicit
        // vocabulary and exact words from every enabled dictionary are protected.
        if let result = aospTrieEngine.languageOverride(for: word) {
            #if DEBUG
            AutocorrectDebugLog.autocorrectDecision(
                original: word, corrected: result.correction,
                branch: "language-override", prevWord: nil
            )
            #endif
            return result
        }

        // Apostrophe prefix fix: when the user types an apostrophe after an
        // invalid contraction prefix ("v'est"), correct the prefix via keyboard
        // proximity. Gated on the language having any contraction prefixes —
        // currently only French qualifies. Valid FR prefixes are {j,n,s,m,t,d,c,l,qu}.
        // Examples: "v'est" → "c'est", "b'est" → "c'est", "x'ai" → "j'ai".
        //
        // WHY before everything else:
        // Our downstream apostrophe split only validates the part AFTER the
        // apostrophe — "v'est" → checks "est" (valid) → returns nil (no correction).
        // We need to intercept wrong prefixes explicitly.
        if let profile = profile, !profile.contractionPrefixes.isEmpty,
           let corrected = correctApostrophePrefix(word) {
            #if DEBUG
            AutocorrectDebugLog.autocorrectDecision(
                original: word, corrected: corrected, branch: "apostrophe-prefix", prevWord: nil
            )
            #endif
            return (corrected, [])
        }

        // Two-pass lookup: user dictionary first (learned words are always "correct").
        // Extract the word part after any apostrophe for user dict check, matching
        // the same apostrophe handling that AOSPTrieEngine uses internally.
        let lowered = word.lowercased()
        let wordToCheck: String
        let apostrophePrefix: String?
        if let apoIndex = lowered.lastIndex(of: "'") {
            wordToCheck = String(lowered[lowered.index(after: apoIndex)...])
            apostrophePrefix = String(lowered[...apoIndex])
        } else {
            wordToCheck = lowered
            apostrophePrefix = nil
        }
        if UserDictionary.shared.isLearned(wordToCheck) {
            #if DEBUG
            AutocorrectDebugLog.autocorrectSkipped(word: word, reason: "user-learned")
            #endif
            return nil  // User-learned word: no correction needed
        }

        // Accent expansion runs BEFORE wordExists check.
        // "tres" may exist in the trie as a low-frequency word, but "très" is far
        // more common. The accent expansion uses frequency comparison to decide.
        // "deja" → "déjà", "apres" → "après", "tres" → "très"
        // The apostrophe prefix must be reassembled: wordToCheck is only the
        // part after the apostrophe, so "J'etais" checks "etais" → "étais" and
        // the correction is "j'" + "étais", not bare "étais".
        if let accented = aospTrieEngine.accentExpansion(wordToCheck) {
            let full = (apostrophePrefix ?? "") + accented
            let isCapitalized = word.first?.isUppercase == true
            let corrected = isCapitalized ? full.capitalized : full
            #if DEBUG
            AutocorrectDebugLog.autocorrectDecision(
                original: word, corrected: corrected, branch: "accent", prevWord: nil
            )
            #endif
            return (corrected, [])
        }

        // Valid word guard: if the word exists in the trie dictionary, it's correct.
        // This prevents aggressive corrections like "fais" → "vais".
        // Runs AFTER accent expansion so "tres" → "très" still works.
        if aospTrieEngine.wordExists(wordToCheck) {
            #if DEBUG
            AutocorrectDebugLog.autocorrectSkipped(word: word, reason: "already-valid")
            #endif
            return nil
        }

        // Contraction expansion: "Cest" → "C'est", "jai" → "j'ai"
        // Runs BEFORE the proper-noun guard: like accent expansion, it's a
        // high-confidence exact transformation (registered prefix + dictionary
        // suffix), so a capitalized "Cest" mid-sentence must correct to "C'est"
        // rather than be preserved as a pseudo-name (and worse, learned).
        if let expanded = aospTrieEngine.contractionExpansion(word) {
            let isCapitalized = word.first?.isUppercase == true
            let corrected = isCapitalized ? expanded.capitalized : expanded
            #if DEBUG
            AutocorrectDebugLog.autocorrectDecision(
                original: word, corrected: corrected, branch: "contraction", prevWord: nil
            )
            #endif
            return (corrected, [])
        }

        // Proper-noun guard (#199): only unknown words reach this point.
        // An unknown capitalized word mid-sentence ("vu Mathilde") or an
        // all-caps acronym ("SNCF") is most likely intentional — preserve it
        // instead of forcing the closest dictionary word. Runs AFTER the
        // high-confidence branches (languageOverride, UserDictionary, accent
        // and contraction expansion) but BEFORE the fuzzy ones (split, trie).
        // The preserved word is then learned via handleSpace's recordUsage path,
        // protecting future occurrences even at sentence start.
        if ProperNounGuard.isLikelyProperNoun(word: word, isAtSentenceStart: isAtSentenceStart) {
            #if DEBUG
            AutocorrectDebugLog.autocorrectSkipped(word: word, reason: "likely-proper-noun")
            #endif
            return nil
        }

        // Word splitting + single-word correction comparison.
        //
        // Strategy (informed by real user feedback + debug log analysis):
        //
        // 1. Split with bigram evidence (any strategy) → accept. The n-gram
        //    model confirms this is a real phrase pattern.
        //
        // 2. Split with boundary signal but NO bigram evidence → compare ED.
        //    Our Wikipedia corpus misses colloquial phrases like "pas mal"
        //    (bigram score 0) but the spacebar-neighbor key proves a missed
        //    space. Accept the split only when it fits the input noticeably
        //    better than the trie's single-word correction (split ED + 1 ≤
        //    single ED). This rejects "fonction agités" cases where single-
        //    word correction is at ED 0 or 1 but keeps "pas mal" cases
        //    where single-word "Pascal" is at ED 2 and split ED is 1.
        //
        // 3. No split → fall through to trie single-word correction.
        let evaluation = trySplitWithSignal(wordToCheck)
        let splitResult = evaluation.split
        let splitHasBoundary = evaluation.hasBoundarySignal
        let splitHasBigram = evaluation.hasBigramEvidence
        if let split = splitResult {
            let useSplit: Bool
            if splitHasBigram {
                useSplit = true  // bigram confirmed, accept
            } else if splitHasBoundary {
                // Boundary-only (no bigram): compare with single-word correction via ED
                if let single = aospTrieEngine.spellCheck(word) {
                    let splitJoined = split.replacingOccurrences(of: " ", with: "").lowercased()
                    let splitED = Self.editDistance(wordToCheck, splitJoined)
                    let singleLower = single.correction.lowercased()
                    let singleWordPart: String
                    if let idx = singleLower.lastIndex(of: "'") {
                        singleWordPart = String(singleLower[singleLower.index(after: idx)...])
                    } else {
                        singleWordPart = singleLower
                    }
                    let singleED = Self.editDistance(wordToCheck, singleWordPart)
                    // Accept split only if strictly better fit (split + 1 ≤ single).
                    // "pasnmal": split "pasmal" ED 1, single "pascal" ED 2 → 1+1=2 ≤ 2 ✓
                    // "fonctionnalités": split "fonctionagités" ED ~3, single ED 0/1 → reject ✓
                    useSplit = (splitED + 1) <= singleED
                } else {
                    useSplit = true  // no single-word alternative, accept split
                }
            } else {
                useSplit = false  // direct split rejected without bigram (prevented by trySplit)
            }

            if useSplit {
                let isCapitalized = word.first?.isUppercase == true
                let result = isCapitalized ? (split.prefix(1).uppercased() + split.dropFirst()) : split
                #if DEBUG
                AutocorrectDebugLog.autocorrectDecision(
                    original: word, corrected: result,
                    branch: splitHasBoundary ? "split-boundary" : "split-bigram",
                    prevWord: nil
                )
                #endif
                return (result, [])
            }
            #if DEBUG
            AutocorrectDebugLog.note("split \"\(split)\" rejected (ED comparison favored single-word)")
            #endif
        }

        // Pass 5: trie spell check (proximity-weighted, accent-aware)
        let trieResult = aospTrieEngine.spellCheck(word)
        #if DEBUG
        if let r = trieResult {
            let corrFreq = aospTrieEngine.wordFrequency(r.correction.lowercased())
            let altsWithFreq = r.alternatives.map { alt in
                (alt, aospTrieEngine.wordFrequency(alt.lowercased()))
            }
            AutocorrectDebugLog.trieCandidates(
                word: word, correction: r.correction,
                correctionFreq: corrFreq, alternatives: altsWithFreq
            )
            AutocorrectDebugLog.autocorrectDecision(
                original: word, corrected: r.correction, branch: "trie", prevWord: nil
            )
        } else {
            AutocorrectDebugLog.autocorrectSkipped(word: word, reason: "no-trie-candidate")
        }
        #endif
        return trieResult
    }

    /// Predict next words based on context (1-2 previous words).
    /// Falls back to top frequent words when no n-gram match exists.
    ///
    /// WHY fallback to frequency:
    /// When the user types a word not in the n-gram model (rare word, name, etc.),
    /// showing the most common words is better than an empty suggestion bar.
    /// These are the words most likely to follow any context.
    func predictNextWords(after words: [String], maxResults: Int = 3) -> [String] {
        let predictions = aospTrieEngine.predictNextWords(after: words, maxResults: maxResults)
        if predictions.isEmpty {
            return frequencyDict.topWords(count: maxResults)
        }
        return predictions
    }

    /// N-gram-only continuation candidates. Unlike ordinary typing prediction,
    /// post-dictation offers never fall back to generic frequent words.
    func localContinuationCandidates(after words: [String], maxResults: Int = 3) -> [String] {
        aospTrieEngine.predictNextWords(after: words, maxResults: maxResults)
    }

    /// Derives a bounded next-character distribution from the existing local
    /// completion dictionary. No network or model-backed prediction is involved.
    func nextCharacterProbabilities(for partialWord: String) -> NextCharacterProbabilities {
        nextCharacterProbabilities(for: partialWord, after: [], isAtSentenceStart: false)
    }

    func nextCharacterProbabilities(
        for partialWord: String,
        after previousWords: [String],
        isAtSentenceStart: Bool,
        recallTokens: [String] = []
    ) -> NextCharacterProbabilities {
        let prefix = partialWord.lowercased()
        guard !prefix.isEmpty, !TypingFact.isOpenPrefix(partialWord) else {
            return NextCharacterProbabilities([:])
        }

        var weights: [String: Double] = [:]
        for (letter, weight) in TypingFact.recallWeights(prefix: prefix, tokens: recallTokens) {
            weights[letter, default: 0] += weight
        }
        // Pull a wider completion list so next-letter priors reflect the active
        // typed-language dictionary, not only the top 3 bar suggestions.
        let completionCandidates = suggestions(for: partialWord, limit: 24)
        for (index, candidate) in completionCandidates.enumerated() {
            let lowered = candidate.lowercased()
            guard lowered.hasPrefix(prefix), lowered.count > prefix.count else { continue }
            let nextIndex = lowered.index(lowered.startIndex, offsetBy: prefix.count)
            let nextCharacter = String(lowered[nextIndex])
            guard nextCharacter.count == 1 else { continue }
            weights[nextCharacter, default: 0] += Double(12 - min(index, 11))
        }

        // Frequency-dictionary prefix fan-out catches letters the suggestion
        // bar ranked away but that are still common for this typed language.
        for (index, candidate) in frequencyDict.prefixCompletions(prefix: prefix, limit: 32).enumerated() {
            let lowered = candidate.lowercased()
            guard lowered.count > prefix.count else { continue }
            let nextIndex = lowered.index(lowered.startIndex, offsetBy: prefix.count)
            weights[String(lowered[nextIndex]), default: 0] += Double(6 - min(index / 4, 5))
        }

        // Add the existing local bigram/trigram signal when it knows the
        // preceding words. A sentence boundary deliberately resets that signal.
        // Fact tokens are context, not failed words, and an empty word-pair
        // table must not fall back to the most common words in the language.
        let contextualWords = TypingFact.contextWords(from: previousWords)
        let contextual = isAtSentenceStart
            ? []
            : localContinuationCandidates(after: contextualWords, maxResults: 12)
        for (index, candidate) in contextual.enumerated() {
            let lowered = candidate.lowercased()
            guard lowered.hasPrefix(prefix), lowered.count > prefix.count else { continue }
            let nextIndex = lowered.index(lowered.startIndex, offsetBy: prefix.count)
            weights[String(lowered[nextIndex]), default: 0] += Double(10 - min(index, 9))
        }
        return NextCharacterProbabilities(weights)
    }

    func nextCharacterProbabilities(
        after previousWords: [String],
        isAtSentenceStart: Bool
    ) -> NextCharacterProbabilities {
        // A new sentence has no word pair yet. The most common words in the
        // language ("the", "a", "I") are not a continuation the typist asked for,
        // so the seam stays on the static key until a real pair exists.
        guard !isAtSentenceStart else {
            return NextCharacterProbabilities([:])
        }
        let contextualWords = TypingFact.contextWords(from: previousWords)
        let candidates = localContinuationCandidates(after: contextualWords, maxResults: 8)
        guard !candidates.isEmpty else {
            return NextCharacterProbabilities([:])
        }
        let weights = candidates.enumerated().reduce(into: [String: Double]()) { result, item in
            guard let first = item.element.lowercased().first else { return }
            let weight = Double(8 - min(item.offset, 7))
            result[String(first), default: 0] += weight
        }
        return NextCharacterProbabilities(weights)
    }

    /// Best dictionary word for a sampled swipe path, or the sampled letters
    /// when no ranked candidate exists.
    func swipeWord(from path: String) -> String? {
        let sampled = SwipeTypingDecoder.sampledLetters(from: path)
        guard SwipeTypingDecoder.shouldCommit(path: sampled) else { return nil }
        if let best = frequencyDict.swipeCandidates(path: sampled, limit: 1).first {
            return best
        }
        if aospTrieEngine.wordExists(sampled) {
            return sampled
        }
        if let result = aospTrieEngine.spellCheck(sampled) {
            return result.correction
        }
        return sampled
    }

    /// Spell check with n-gram context boosting.
    /// Uses two strategies to find context-appropriate corrections:
    /// 1. Rerank existing spell corrections using bigram scores
    /// 2. Check if n-gram predictions are close to the typed word (prediction-based)
    ///
    /// Strategy 2 is the key insight: instead of asking "what are the corrections for sui?"
    /// and hoping "suis" appears, we ask "what does the n-gram model predict after je?"
    /// and check if any prediction (like "suis") is close to what was typed ("sui").
    func spellCheck(
        _ word: String,
        previousWord: String?,
        isAtSentenceStart: Bool = true
    ) -> (correction: String, alternatives: [String])? {
        // Protect exact enabled-language words before overrides and contextual
        // re-ranking, which otherwise bypass the ordinary spell-check guard.
        guard !shouldPreserveSpelling(word) else { return nil }
        // Language overrides are authoritative — return before the bigram
        // rerank can replace them. Concrete failure this prevents (#222):
        // "je lai" → override "l'ai", but the corpus tokenizes "j'ai" as ONE
        // token so bigram("ai" after "je") = 0, while bigram("lui" after "je")
        // is huge and "lui" sits at edit distance 1 of "lai" — the rerank
        // replaced the override with "lui" ("je lai fais" → "je lui fais").
        if let override = aospTrieEngine.languageOverride(for: word) {
            #if DEBUG
            AutocorrectDebugLog.autocorrectDecision(
                original: word, corrected: override.correction,
                branch: "language-override", prevWord: previousWord
            )
            #endif
            return override
        }

        let result = spellCheck(word, isAtSentenceStart: isAtSentenceStart)

        // If no previous word context or n-grams not loaded, return standard result
        guard let prev = previousWord, !prev.isEmpty, aospTrieEngine.ngramsLoaded else {
            return result
        }

        let lowered = word.lowercased()
        let wordToCheck: String
        let prefix: String?
        if let apoIdx = lowered.lastIndex(of: "'") {
            wordToCheck = String(lowered[lowered.index(after: apoIdx)...])
            prefix = String(lowered[...apoIdx])
        } else {
            wordToCheck = lowered
            prefix = nil
        }

        let prevLower = prev.lowercased()

        // Get n-gram predictions close to the typed word (edit distance exactly 1).
        // Only for words of 3+ characters — short words like "a", "à", "un" have too
        // many neighbors at distance 1-2, causing false corrections (e.g., "a" → "la").
        // Max distance 1 (not 2): distance 2 is too permissive even for longer words
        // (e.g., "suis" → "vais" at distance 2 would be a false correction).
        let closePredictions: [(String, UInt16)]
        if wordToCheck.count >= 3 {
            let predictions = aospTrieEngine.predictNextWords(after: [prevLower], maxResults: 8)
            closePredictions = predictions.compactMap { prediction in
                let dist = Self.editDistance(wordToCheck, prediction)
                guard dist == 1 else { return nil }
                let score = aospTrieEngine.bigramScore(for: prediction, after: prevLower)
                return score > 0 ? (prediction, score) : nil
            }
        } else {
            closePredictions = []
        }

        if let result = result {
            // Have base corrections — merge with close predictions and rerank
            var candidateSet: [String: UInt16] = [:]

            // Score existing corrections
            for candidate in [result.correction] + result.alternatives {
                let lowerCandidate = candidate.lowercased()
                let wordPart: String
                if let apoIdx = lowerCandidate.lastIndex(of: "'") {
                    wordPart = String(lowerCandidate[lowerCandidate.index(after: apoIdx)...])
                } else {
                    wordPart = lowerCandidate
                }
                candidateSet[candidate] = aospTrieEngine.bigramScore(for: wordPart, after: prevLower)
            }

            // Add close predictions (may introduce new candidates like "suis")
            let isCapitalized = word.first?.isUppercase == true
            for (prediction, score) in closePredictions {
                // `prefix ?? ""` reproduces the nil branch exactly: prepending the
                // empty string is the identity, which is what nil returned before.
                let full = (prefix ?? "") + prediction
                let display = isCapitalized ? full.capitalized : full
                if let existing = candidateSet[display] {
                    candidateSet[display] = max(existing, score)
                } else {
                    candidateSet[display] = score
                }
            }

            // CRITICAL: if no candidate has ANY bigram evidence (all scores = 0),
            // the rerank becomes a random pick based on Dictionary iteration order.
            // This corrupted good trie corrections like "main" → "mais" with no
            // real justification. In this case, keep the trie's original result.
            let hasAnyBigramEvidence = candidateSet.values.contains { $0 > 0 }
            guard hasAnyBigramEvidence else {
                #if DEBUG
                AutocorrectDebugLog.note(
                    "bigram-rerank skipped (no evidence) for \"\(word)\" prev=\"\(prev)\", keeping \"\(result.correction)\""
                )
                #endif
                return result
            }

            // CRITICAL: the rerank must not pick a candidate that's FARTHER from
            // the typed input than the original trie winner. Example from debug
            // logs: pejx → trie chose "peux" (ED 1), but bigram("veux" after "tu")
            // = 49828 while bigram("peux" after "tu") = 0 (data gap, our corpus
            // lacks common colloquial phrases). Rerank promoted "veux" (ED 2)
            // over "peux" (ED 1), forcing the user to undo.
            //
            // Fix: filter candidates to those at ED ≤ original winner's ED. The
            // rerank may still reorder within this set, but can never move to a
            // less-proximal candidate. Prevents bigram data gaps from overriding
            // the trie's proximity scoring.
            let originalWordPart: String = {
                let ol = result.correction.lowercased()
                if let idx = ol.lastIndex(of: "'") {
                    return String(ol[ol.index(after: idx)...])
                } else {
                    return ol
                }
            }()
            let originalED = Self.editDistance(wordToCheck, originalWordPart)

            let eligible = candidateSet.filter { candidate, _ in
                let cl = candidate.lowercased()
                let cWordPart: String
                if let idx = cl.lastIndex(of: "'") {
                    cWordPart = String(cl[cl.index(after: idx)...])
                } else {
                    cWordPart = cl
                }
                return Self.editDistance(wordToCheck, cWordPart) <= originalED
            }
            // Safety: if filter removed everything (shouldn't happen — original is always eligible),
            // fall back to full set.
            let candidates = eligible.isEmpty ? candidateSet : eligible

            let reranked = candidates.sorted { $0.value > $1.value }
            let newCorrection = reranked[0].key
            let newAlternatives = reranked.dropFirst().map { $0.key }
            #if DEBUG
            if newCorrection != result.correction {
                let beforeScore = candidateSet[result.correction] ?? 0
                let afterScore = reranked[0].value
                AutocorrectDebugLog.bigramRerank(
                    word: word, prevWord: prev,
                    before: (result.correction, beforeScore),
                    after: (newCorrection, afterScore)
                )
            }
            #endif
            return (newCorrection, Array(newAlternatives.prefix(2)))
        }

        // Word is valid (spellCheck returned nil) — do not override with n-gram
        // predictions. This prevents "je fais" → "je vais" when "fais" is valid.
        return nil
    }

    /// Levenshtein edit distance between two strings. O(n*m) but strings are
    /// short (< 20 chars) so this is sub-microsecond.
    private static func editDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var dp = Array(0...b.count)
        for i in 1...a.count {
            var prev = dp[0]
            dp[0] = i
            for j in 1...b.count {
                let temp = dp[j]
                if a[i - 1] == b[j - 1] {
                    dp[j] = prev
                } else {
                    dp[j] = min(prev, dp[j], dp[j - 1]) + 1
                }
                prev = temp
            }
        }
        return dp[b.count]
    }

    // MARK: - Word Splitting

    /// Keys adjacent to the spacebar on each keyboard layout.
    /// When the user presses one of these instead of space, two words get fused.
    /// On AZERTY: bottom row is W-X-C-V-B-N — only N (rightmost, next to space/comma)
    /// and B are truly adjacent to the spacebar. V was previously included but is
    /// 3 keys from space, causing false splits like "calvier" → "cal hier".
    /// On QWERTY: bottom row is Z-X-C-V-B-N-M — M is rightmost (next to space),
    /// N and B are close enough to count.
    /// QWERTZ shares the QWERTY set: its bottom row is Y-X-C-V-B-N-M, so the three
    /// keys adjacent to the spacebar are the same ones (#151).
    private static let azertySpacebarNeighbors: Set<Character> = ["n", "b", ","]
    private static let qwertySpacebarNeighbors: Set<Character> = ["n", "b", "m"]

    /// Short French words (2 chars) that are allowed to appear as split parts.
    /// Standard split requires ≥3 chars per part to avoid noise like "ho ne",
    /// but French has many 2-char pronouns/articles/connectives that commonly
    /// start missed-space compounds (e.g., "tuboeux" should split as "tu peux",
    /// "jepense" as "je pense"). This allowlist restricts the 2-char relaxation
    /// to words that are structurally plausible as a left/right split half.
    private static let shortSplitAllowlist: Set<String> = [
        "je", "tu", "il", "on", "me", "te", "se", "ne",
        "le", "la", "un", "du", "au", "en",
        "et", "ou", "ni", "si", "ça", "où", "ce"
    ]

    /// Whether a split part is long enough or belongs to the short-word allowlist.
    private static func isValidSplitPart(_ part: String) -> Bool {
        return part.count >= 3 || (part.count == 2 && shortSplitAllowlist.contains(part))
    }

    // MARK: - Apostrophe Prefix Correction

    /// Valid single-char contraction prefixes in French.
    /// "qu'" is handled separately since it's 2 chars.
    private static let validFrenchApostrophePrefixes: Set<Character> =
        ["j", "n", "s", "m", "t", "d", "c", "l"]

    /// Proximity groups for AZERTY — each key maps to the valid apostrophe prefix
    /// it likely substitutes when typed by mistake. Built from AZERTY bottom/middle
    /// row adjacency:
    /// - V is next to C → v'est → c'est
    /// - B is next to N → b'est → n'est (less common but possible)
    /// - G, H are next to J → g'ai/h'ai → j'ai
    private static let azertyApostrophePrefixFix: [Character: Character] = [
        "v": "c",  // v'est → c'est
        "x": "c",  // x'est → c'est (x is left of c on AZERTY)
        "f": "d",  // f'est → d'est (not a real contraction, skip?)
        "g": "j",  // g'ai → j'ai (g is left of h which is left of j)
        "h": "j",  // h'ai → j'ai
        "k": "j",  // k'ai → j'ai
        "b": "n",  // b'est → n'est
        "y": "t",  // y'es → t'es (adjacent on AZERTY top row)
        "r": "t",  // r'es → t'es
        "u": "t"  // u'es → t'es
    ]

    /// Correct a word with invalid apostrophe prefix via keyboard proximity.
    /// "v'est" → "c'est", "b'a" → "n'a", etc.
    /// Returns nil if no fix applies.
    private func correctApostrophePrefix(_ word: String) -> String? {
        let lower = word.lowercased()
        guard let apoIdx = lower.firstIndex(of: "'") else { return nil }

        // Only 1-char prefix is handled here (qu' is 2-char and handled elsewhere).
        let prefixDistance = lower.distance(from: lower.startIndex, to: apoIdx)
        guard prefixDistance == 1 else { return nil }

        let prefixChar = lower[lower.startIndex]
        let suffix = String(lower[lower.index(after: apoIdx)...])
        guard !suffix.isEmpty else { return nil }

        // Prefix is already valid — let the normal pipeline handle it.
        if Self.validFrenchApostrophePrefixes.contains(prefixChar) {
            return nil
        }

        // Look up the proximity fix for this prefix character.
        guard let fixedPrefix = Self.azertyApostrophePrefixFix[prefixChar] else {
            return nil
        }

        // Verify the suffix is a real word (avoids correcting random typos like
        // "v'azxy" where the suffix is garbage).
        guard aospTrieEngine.wordExists(suffix) else { return nil }

        // Reassemble with the corrected prefix and original casing.
        let isCapitalized = word.first?.isUppercase == true
        let corrected = "\(fixedPrefix)'\(suffix)"
        return isCapitalized ? (corrected.prefix(1).uppercased() + corrected.dropFirst()) : corrected
    }

    /// The winning split plus the evidence backing it.
    ///
    /// WHY a struct and not a tuple: three labelled members is one past what the
    /// project lints for, and a named type also stops the caller destructuring
    /// three same-shaped values positionally.
    private struct SplitEvaluation {
        /// The winning "left right" split, or nil when nothing qualified.
        let split: String?
        /// The split used a spacebar-neighbor char — strong physical evidence.
        let hasBoundarySignal: Bool
        /// The pair (left, right) has a bigram score > 0 — linguistic evidence.
        let hasBigramEvidence: Bool
    }

    /// A boundary-split candidate while the loop below is still looking for the
    /// best one. Same reason as SplitEvaluation for being a struct.
    private struct BoundaryCandidate {
        let split: String
        let score: UInt32
        let hasBigram: Bool
    }

    /// Wrapper around trySplit that returns the winning split plus flags
    /// describing the evidence backing it. Caller decides whether to accept.
    ///
    /// Evidence sources:
    /// - boundarySignal: split used a spacebar-neighbor char — strong physical evidence
    /// - bigramEvidence: pair (left, right) has bigram score > 0 — linguistic evidence
    ///
    /// Rules for returning a candidate:
    /// - Direct split (no boundary): REQUIRES bigram. Prevents "honnête lent".
    /// - Boundary split: allowed WITHOUT bigram (our n-gram corpus misses
    ///   colloquial phrases like "pas mal"). Caller applies an ED comparison
    ///   with the single-word correction to decide.
    ///
    /// Boundary splits with bigram evidence win over those without.
    private func trySplitWithSignal(_ word: String) -> SplitEvaluation {
        let chars = Array(word)
        // Minimum absolute part length 2; each part must also pass isValidSplitPart
        // which requires either ≥3 chars or membership in the short-word allowlist.
        // This lets "tu peux" split from "tuboeux" while still blocking "ho ne"
        // from "honne" (since "ho" is not allowlisted).
        let minPartLength = 2
        guard chars.count >= 4 else {
            return SplitEvaluation(split: nil, hasBoundarySignal: false, hasBigramEvidence: false)
        }

        let spacebarNeighbors = LayoutType.active == .azerty
            ? Self.azertySpacebarNeighbors
            : Self.qwertySpacebarNeighbors

        var bestBoundary: BoundaryCandidate?
        var bestBigram: (split: String, score: UInt32)?

        /// Score a candidate pair. Returns (score, hasBigram).
        /// Candidates with bigram get a large bonus (1000×bigram), making them
        /// strictly win over non-bigram candidates at the same freq product.
        func scorePair(left: String, right: String) -> (UInt32, Bool) {
            let bigram = aospTrieEngine.bigramScore(for: right, after: left)
            let freqProduct = UInt32(aospTrieEngine.wordFrequency(left))
                            * UInt32(aospTrieEngine.wordFrequency(right))
            if bigram > 0 {
                return (freqProduct + UInt32(bigram) * 1000, true)
            } else {
                return (freqProduct, false)
            }
        }

        /// True when `score` should replace the current best, including the case
        /// where there is no current best yet.
        /// WHY not the shorter `score > (current ?? 0)`: a first candidate scoring
        /// zero must still beat "no candidate at all", and that shorthand would
        /// silently drop it.
        func improves(_ score: UInt32, over current: UInt32?) -> Bool {
            guard let current else { return true }
            return score > current
        }

        for splitPos in minPartLength...(chars.count - minPartLength) {
            let left = String(chars[0..<splitPos])
            let right = String(chars[splitPos...])

            // Both parts must meet the length/allowlist requirement.
            guard Self.isValidSplitPart(left) else { continue }

            let leftExists = aospTrieEngine.wordExists(left)
            let rightExists = aospTrieEngine.wordExists(right)

            // Boundary-char removal at spacebar neighbor (bigram OPTIONAL)
            if splitPos < chars.count, spacebarNeighbors.contains(chars[splitPos]) {
                let rightAfter = String(chars[(splitPos + 1)...])
                if Self.isValidSplitPart(rightAfter) {
                    // Case A: both halves valid as-is
                    if leftExists && aospTrieEngine.wordExists(rightAfter) {
                        let (s, hasBi) = scorePair(left: left, right: rightAfter)
                        if improves(s, over: bestBoundary?.score) {
                            bestBoundary = BoundaryCandidate(
                                split: "\(left) \(rightAfter)", score: s, hasBigram: hasBi
                            )
                        }
                    }
                    // Case B: right half needs spell correction (min 3 chars to avoid
                    // correcting short garbage into arbitrary words).
                    if leftExists && !aospTrieEngine.wordExists(rightAfter) && rightAfter.count >= 3,
                       let c = aospTrieEngine.spellCheck(rightAfter) {
                        let (s, hasBi) = scorePair(left: left, right: c.correction)
                        if improves(s, over: bestBoundary?.score) {
                            bestBoundary = BoundaryCandidate(
                                split: "\(left) \(c.correction)", score: s, hasBigram: hasBi
                            )
                        }
                    }
                }
            }

            // Direct split — REQUIRES bigram evidence (no boundary signal to fall back on)
            guard Self.isValidSplitPart(right) else { continue }
            if leftExists && rightExists {
                let (s, hasBi) = scorePair(left: left, right: right)
                if hasBi, improves(s, over: bestBigram?.score) {
                    bestBigram = ("\(left) \(right)", s)
                }
            }
        }

        // Priority: boundary > direct bigram (boundary has stronger physical signal)
        let winner: String?
        let hasBoundary: Bool
        let hasBigramEv: Bool
        if let b = bestBoundary {
            winner = b.split
            hasBoundary = true
            hasBigramEv = b.hasBigram
        } else if let bg = bestBigram {
            winner = bg.split
            hasBoundary = false
            hasBigramEv = true
        } else {
            winner = nil
            hasBoundary = false
            hasBigramEv = false
        }

        #if DEBUG
        if winner != nil {
            AutocorrectDebugLog.splitEvaluation(
                word: word, boundaryBest: bestBoundary?.split,
                bigramBest: bestBigram?.split, winner: winner
            )
        }
        #endif
        return SplitEvaluation(
            split: winner, hasBoundarySignal: hasBoundary, hasBigramEvidence: hasBigramEv
        )
    }

}
