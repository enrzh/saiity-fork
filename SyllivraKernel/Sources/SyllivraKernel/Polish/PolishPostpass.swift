// SyllivraKernel/Sources/SyllivraKernel/Polish/PolishPostpass.swift
import Foundation

/// Code-level corrections applied AFTER the polish engine returns.
///
/// Round 4 round-1 testing showed Apple Foundation Models has two
/// behavioural floors we cannot prompt-tune past:
///
/// 1. Raw `\n` characters in the input get "naturalised" into `, ` + capital
///    on output. The model interprets a newline as a sentence-boundary cue
///    and rewrites the boundary in prose form, no matter how the prompt
///    spells out "preserve newlines".
///
/// 2. The model never inserts the U+00A0 NO-BREAK SPACE before `?`, `!`,
///    `;`, `:` even when the rule line says so and the examples literally
///    contain NBSP bytes. ASCII space and NBSP are indistinguishable to
///    its sampling.
///
/// Both are deterministic transformations — handling them in code is more
/// reliable than coaxing the model. The pre-engine `encodeForEngine` step
/// hides newlines behind a multi-char ASCII marker that survives the
/// round-trip; the post-engine `decodeFromEngine` step restores the
/// newlines and applies the French typographic spacing. `cleanupFloor` adds a
/// conservative language-neutral fallback when the model is unavailable or
/// rejected.
public enum PolishPostpass {

    /// String the engine sees in place of `\n`. Apple FM treats this as
    /// opaque text and passes it through unaltered (round-1 testing).
    /// The marker is intentionally verbose so user speech won't accidentally
    /// transcribe to the same bytes.
    public static let newlineMarker = "<<NL>>"

    /// Encode `\n` characters as the engine-safe marker. Run on the pre-pass
    /// output before handing the string to Apple FM.
    public static func encodeForEngine(_ text: String) -> String {
        text.replacingOccurrences(of: "\n", with: newlineMarker)
    }

    /// Language-agnostic half of the decode: restores newlines from markers
    /// and collapses stray blank lines. This is the ONLY post-pass applied in
    /// Auto-detect mode (#239) — the language typography below is per-language
    /// and would mangle unknown scripts (e.g. CJK full-width punctuation).
    public static func decodeNewlines(_ polished: String) -> String {
        var out = polished
        // Two adjacent markers are an intentional paragraph break from the
        // input. Protect that distinction while collapsing raw newlines the
        // model may have added around a marker.
        let paragraphToken = "\u{E000}"
        out = out.replacingOccurrences(
            of: #"(?:<<NL>>){2,}"#,
            with: paragraphToken,
            options: [.regularExpression]
        )
        out = out.replacingOccurrences(of: newlineMarker, with: "\n")
        out = out.replacingOccurrences(
            of: #"[ \t]*\n+[ \t]*(\u{E000})"#,
            with: "$1",
            options: [.regularExpression]
        )
        out = out.replacingOccurrences(
            of: #"(\u{E000})[ \t]*\n+"#,
            with: "$1",
            options: [.regularExpression]
        )

        // Collapse stray newlines (language-agnostic). Each "retour à la ligne"
        // encodes to exactly one marker, but the model adds its OWN paragraph
        // breaks around the marker when the text looks structured (a meeting
        // recap, an enumeration). After decode those stack into `\n\n\n\n`.
        // Reduce raw runs of whitespace-separated newlines to a single `\n`, and
        // trim the spaces hugging each break. Explicit paragraph markers are
        // restored after this normalization, so intentional blank lines survive.
        out = out.replacingOccurrences(
            of: #"[ \t]*\n(?:[ \t]*\n)*[ \t]*"#,
            with: "\n",
            options: [.regularExpression]
        )
        return out.replacingOccurrences(of: paragraphToken, with: "\n\n")
    }

    /// Run on the engine's output. Restores newlines from markers and
    /// applies language-specific typography Apple FM is unreliable about.
    public static func decodeFromEngine(_ polished: String,
                                        language: SupportedLanguage) -> String {
        var out = decodeNewlines(polished)

        switch language {
        case .french:
            // NBSP before ? ! ; :. Pattern matches ONE ASCII space (U+0020)
            // immediately preceding the mark; any existing NBSP (U+00A0)
            // stays untouched. `[ ]` is the literal space character class
            // — avoids `\s` which would also match `\n` and `\t`.
            out = out.replacingOccurrences(
                of: #"[ ]([?!;:])"#,
                with: "\u{00A0}$1",
                options: [.regularExpression]
            )
            // Restore the accent on a sentence-initial capital `A` — Apple FM
            // drops accents on capitals just like it drops the NBSP. Narrow on
            // purpose: a standalone `A` at a sentence start (string start, after
            // a newline, or after `. ! ? :`) followed by a lowercase word is
            // almost always the preposition `À` (À très vite / bientôt / plus
            // tard). If the next word is uppercase (acronym, proper noun) or it
            // is `A.` (abbreviation), the pattern does not match and we leave it.
            out = out.replacingOccurrences(
                of: #"(^|\n|[.!?:]\s+)A(\s+\p{Ll})"#,
                with: "$1À$2",
                options: [.regularExpression]
            )
        case .english, .spanish, .german,
             .italian, .portuguese, .dutch, .polish, .swedish, .danish, .finnish, .czech:
            break
        }
        return out
    }

    /// Explicit unhandled languages get neutral cleanup. In Auto, lexical rules
    /// require a confident monolingual reading; unknown text stays unchanged.
    public static func cleanupFloor(_ text: String,
                                    language: SupportedLanguage? = .english) -> String {
        // shortcut: code-marked text stays verbatim; parse literal spans only if mixed prose/code needs cleanup.
        guard !text.contains("`") else { return text }
        let leadingNewlines = String(text.prefix { $0 == "\n" })
        let trailingNewlines = String(text.reversed().prefix { $0 == "\n" }.reversed())
        var out = String(text
            .dropFirst(leadingNewlines.count)
            .dropLast(trailingNewlines.count))
        out = removeNonSpeechEventLabels(out)
        out = normalizeCleanupWhitespace(out)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !out.isEmpty else { return leadingNewlines + trailingNewlines }
        let handled: Set<SupportedLanguage> = [.english, .french, .german, .spanish]
        let evidence = SpeechLanguageEvidence.analyze(text: out, detectedLanguage: nil)
        let inferredCode = evidence.validatedLanguageCode
        let inferred = inferredCode.flatMap(SupportedLanguage.init(rawValue:))
        let uncertain = evidence.isMixedScript || evidence.hasLanguageSwitch
            || language.map { !handled.contains($0) } == true
        let lexicalLanguage = uncertain ? nil : inferredCode == nil ? language : inferred
        if let lexicalLanguage, [.english, .french, .german, .spanish].contains(lexicalLanguage) {
            out = removeHesitationFillers(out, language: lexicalLanguage)
            if lexicalLanguage == .english {
                out = removeSpokenRestartFillers(out)
                out = removeEnglishUmFillers(out)
                out = removeFillerLike(out)
                out = normalizeClockTimes(out)
                out = resolveNumberCorrection(out)
                out = collapseRestatedClauses(out)
                out = repairEnglishIndefiniteArticle(out)
            }
            out = resolveDateCorrection(out, language: lexicalLanguage)
        }
        // Short Auto fragments lack enough context for lexical stutter removal.
        if let lexicalLanguage, language != nil
            || (handled.contains(lexicalLanguage) && evidence.meaningfulCharacterCount >= 16) {
            out = removeImmediateStutters(out)
        }
        if language != nil, let lexicalLanguage {
            out = removeDiscourseFillers(out, language: lexicalLanguage)
            if lexicalLanguage == .english { out = resolveProperNameCorrection(out) }
            // Apply this again to engine output. The pre-pass normally
            // converted commands before the LLM call, but a backend can echo
            // them verbatim.
            out = VerbalPunctuationPrepass.apply(out, language: lexicalLanguage)
        }
        out = normalizeCleanupWhitespace(out)
        out = out.replacingOccurrences(
            of: #"[ \t]+([,.;:!?，。；：！？])"#, with: "$1", options: [.regularExpression]
        )
        out = out.trimmingCharacters(in: .whitespaces)
        out = capitalizeLineStarts(out)
        return leadingNewlines + out + trailingNewlines
    }

    /// Grammar-only floor after cleanup or translation. Idempotent: it does not
    /// invent facts. Language-specific spoken grammar belongs on the model path.
    public static func grammarFloor(_ text: String,
                                    language: SupportedLanguage? = nil) -> String {
        cleanupFloor(text, language: language)
    }

    /// Whisper and similar models emit stage directions instead of speech:
    /// `(singing)`, `[kiss]`, `[BLANK_AUDIO]`, `(snow crunching)`, `♪`. Strip
    /// those labels without touching ordinary parentheticals such as
    /// `(see attached)` or `(2024)`.
    public static func removeNonSpeechEventLabels(_ text: String) -> String {
        var out = stripVocabularyNoiseMarkers(text)
        out = out.replacingOccurrences(
            of: #"(?i)\[(?:BLANK[_ ]AUDIO|NO[_ ]SPEECH|SILENCE|MUSIC|APPLAUSE|INAUDIBLE)\]"#,
            with: "",
            options: [.regularExpression]
        )
        out = out.replacingOccurrences(
            of: #"(^|[ \t])[♪♫]+(?=$|[ \t,.;:!?])"#,
            with: "$1",
            options: [.regularExpression]
        )
        return normalizeCleanupWhitespace(out)
            .trimmingCharacters(in: .whitespaces)
    }

    /// whisper-guard / Parrot rule: a short `(...)` / `[...]` / `*...*` span
    /// is a non-speech marker when it is 1–4 words, ≤40 inner characters, and
    /// the last word is a known noise token (or every word is noise/modifier).
    /// Last-word dominance keeps `(music director)` and `(see attached)`.
    private static func stripVocabularyNoiseMarkers(_ text: String) -> String {
        let pattern = #"(?i)[ \t]*(?:\(([^\)]{1,40})\)|\[([^\]]{1,40})\]|\*([^*]{1,40})\*)[~*]{0,3}[.,;:!?]*"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return text }
        let mutable = NSMutableString(string: text)
        for match in matches.reversed() {
            let innerRange: NSRange
            if match.range(at: 1).location != NSNotFound {
                innerRange = match.range(at: 1)
            } else if match.range(at: 2).location != NSNotFound {
                innerRange = match.range(at: 2)
            } else {
                innerRange = match.range(at: 3)
            }
            guard innerRange.location != NSNotFound,
                  isNonSpeechNoiseInner(ns.substring(with: innerRange)) else { continue }
            mutable.deleteCharacters(in: match.range)
        }
        return String(mutable)
    }

    private static let nonSpeechExactInners: Set<String> = [
        "blank audio",
        "clears throat",
        "clearing throat",
        "speaking foreign language",
        "speaking in foreign language",
    ]

    private static let nonSpeechModifiers: Set<String> = [
        "soft", "loud", "faint", "distant", "background", "heavy", "light",
        "quiet", "ambient", "low", "high", "slight", "sudden", "long", "short",
        "audience",
    ]

    /// Last-word allowlist from whisper-guard, plus environmental actions
    /// Whisper labels on outdoor/noisy audio (`(snow crunching)`).
    private static let nonSpeechNoiseWords: Set<String> = [
        "singing", "laugh", "laughs", "laughing", "laughter", "chuckle", "chuckles",
        "giggle", "giggles", "music", "applause", "clapping", "clap", "cough",
        "coughs", "coughing", "kiss", "kisses", "kissing", "inaudible", "silence",
        "humming", "whistle", "whistling", "sigh", "sighs", "sighing", "breathing",
        "moaning", "screaming", "crying", "cheering", "explosion", "gunshot",
        "doorbell", "audience", "growling", "sobbing", "sneezing", "gasping", "whispering",
        "mumbling", "snoring", "yelling", "weeping", "noise", "crosstalk",
        "typing", "static", "beep", "ringing", "crunching", "rustling",
        "footsteps", "knocking", "tapping", "clicking", "barking", "honking",
        "creaking", "rattling", "buzzing", "dripping", "sniffling", "slamming",
        "popping", "thunder", "chatter", "applaus", "gelächter", "geräusch",
        "stille", "musik", "musique", "musica", "música", "muzyka", "risas",
        "rires", "rire", "śmiech", "aplausos", "applausi", "oklaski", "ruido",
        "silencio", "cisza",
    ]

    private static func isNonSpeechNoiseInner(_ inner: String) -> Bool {
        let trimmed = inner.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 40 else { return false }
        if trimmed.allSatisfy({ $0.isNumber || $0 == ":" || $0.isWhitespace }) {
            return false
        }
        let normalized = trimmed
            .lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
        if nonSpeechExactInners.contains(normalized) { return true }
        let words = normalized
            .split(whereSeparator: { $0.isWhitespace })
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }
            .filter { !$0.isEmpty }
        guard (1...4).contains(words.count), let last = words.last else { return false }
        if nonSpeechNoiseWords.contains(last) { return true }
        return words.contains(where: { nonSpeechNoiseWords.contains($0) })
            && words.allSatisfy { nonSpeechNoiseWords.contains($0) || nonSpeechModifiers.contains($0) }
    }

    private static func normalizeCleanupWhitespace(_ text: String) -> String {
        var out = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        // Normalize each line independently so indentation and list markers
        // survive cleanup. A global whitespace collapse turns nested bullets
        // into plain prose, which is a formatting loss rather than polish.
        out = out.components(separatedBy: "\n").map { line in
            let indentation = String(line.prefix { $0 == " " || $0 == "\t" })
            let content = String(line.dropFirst(indentation.count))
                .replacingOccurrences(of: #"[ \t]+"#, with: " ", options: [.regularExpression])
                .replacingOccurrences(of: #"[ \t]+$"#, with: "", options: [.regularExpression])
            return indentation + content
        }.joined(separator: "\n")
        return out.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: [.regularExpression])
    }

    private static func removeHesitationFillers(_ text: String, language: SupportedLanguage) -> String {
        let fillers: String
        switch language {
        case .english: fillers = "uh+|hmm+|erm+|mmm+"
        case .french: fillers = "euh+|hum+|hmm+"
        case .german: fillers = "äh+|ähm+|öhm+|hmm+"
        case .spanish: fillers = "eh+|hmm+"
        default: return text
        }
        return text.replacingOccurrences(
            of: #"(?i)(^|[ \t,(])(?:"# + fillers + #")(?=($|[ \t,!?;:.]))(?:[ \t]*[,;:])?[ \t]*"#,
            with: "$1",
            options: [.regularExpression]
        )
    }

    /// `um` is an English hesitation and a German/Portuguese function word.
    /// Only strip it when the language is known to be English.
    private static func removeEnglishUmFillers(_ text: String) -> String {
        text.replacingOccurrences(
            of: #"(?i)(^|[ \t,(])um+(?=($|[ \t,!?;:.]))(?:[ \t]*[,;:])?[ \t]*"#,
            with: "$1",
            options: [.regularExpression]
        )
    }

    private static func removeDiscourseFillers(_ text: String, language: SupportedLanguage) -> String {
        // Discourse words are removed only when punctuation marks them as a
        // parenthetical filler at the beginning of a sentence.
        let discourse: String
        switch language {
        case .english: discourse = "like|well|you know|basically"
        case .french: discourse = "enfin|voilà|tu vois|tu sais"
        case .german: discourse = "also|na ja|sozusagen"
        case .spanish: discourse = "pues|este|o sea"
        default: return text
        }
        return text.replacingOccurrences(
            of: "(?i)^(?:" + discourse + ")[ \\t]*[,;:][ \\t]*",
            with: "",
            options: [.regularExpression]
        )
    }

    private static func removeSpokenRestartFillers(_ text: String) -> String {
        var out = text.replacingOccurrences(
            of: #"(?i)[ \t]*(?:um+|uh+)\s*,\s*(?:yeah|yes)[.!?]?[ \t]*"#,
            with: ". ",
            options: [.regularExpression]
        )
        out = out.replacingOccurrences(
            of: #"(?i)(?:^|[.!?]\s+)(?:yeah|yes)[.!][ \t]+"#,
            with: "",
            options: [.regularExpression]
        )
        out = out.replacingOccurrences(
            of: #"(?i)([.!?])[ \t]+so\s+basically[ \t]+"#,
            with: "$1 ",
            options: [.regularExpression]
        )
        out = out.replacingOccurrences(
            of: #"(?i)(?:^|[ \t]+)so\s+basically[ \t]+"#,
            with: " ",
            options: [.regularExpression]
        )
        return out
    }

    private static func removeFillerLike(_ text: String) -> String {
        text.replacingOccurrences(
            of: #"(?i)\b(got|get|have|had|need|needed|want|wanted|see|saw|make|made)\s+like\s+"#,
            with: "$1 ",
            options: [.regularExpression]
        )
    }

    private static func normalizeClockTimes(_ text: String) -> String {
        let out = text.replacingOccurrences(
            of: #"(?i)(\d{1,2}(?::\d{2})?)\s*a\.?\s*m\.?\b"#,
            with: "$1am",
            options: [.regularExpression]
        )
        return out.replacingOccurrences(
            of: #"(?i)(\d{1,2}(?::\d{2})?)\s*p\.?\s*m\.?\b"#,
            with: "$1pm",
            options: [.regularExpression]
        )
    }

    private static let clockTime = #"\d{1,2}(?::\d{2})?(?:am|pm)"#
    private static let spokenCorrection = #"(?:oh\s+)?(?:sorry|actually|i mean|wait(?:\s*,?\s*no)?|rather)"#

    private static func resolveNumberCorrection(_ text: String) -> String {
        // Simple adjacent values or clock times only; complex numbers, lists, dates, codes and URLs stay intact.
        let value = #"(?<![\p{L}\p{N}_:/+−.,-])(?:"# + clockTime
            + #"|\p{N}+(?:[.,]\p{N}+)?)(?![\p{L}\p{N}_:/+−-]|[.,]\p{N})"#
        return text.replacingOccurrences(
            of: "(?i)(" + value + #")[ \t]*[,.]?[ \t]*"# + spokenCorrection
                + #"[,.]?[ \t]*(?:it'?s[ \t]+)?("# + value + ")",
            with: "$2",
            options: [.regularExpression]
        )
    }

    private static func removeImmediateStutters(_ text: String) -> String {
        // Only grammatical false starts: repeated content words may be emphasis.
        let pattern = #"(?i)\b(i|we|he|she|they|the|a|an|je|tu|que|le|la|les|ich|wir|der|die|das|de|el|los|las|yo)(?:[ \t]+\1\b)+"#
        return text.replacingOccurrences(of: pattern, with: "$1", options: [.regularExpression])
    }

    private static func resolveDateCorrection(_ text: String, language: SupportedLanguage) -> String {
        let weekday: String
        let correction: String
        switch language {
        case .english:
            weekday = "monday|tuesday|wednesday|thursday|friday|saturday|sunday"
            correction = "actually|rather|i mean"
        case .french:
            weekday = "lundi|mardi|mercredi|jeudi|vendredi|samedi|dimanche"
            correction = "enfin|plutôt|je veux dire"
        case .german:
            weekday = "montag|dienstag|mittwoch|donnerstag|freitag|samstag|sonntag"
            correction = "eigentlich|besser gesagt|ich meine"
        case .spanish:
            weekday = #"(?:el[ \t]+)?(?:lunes|martes|miércoles|jueves|viernes|sábado|domingo)"#
            correction = "mejor|más bien|quiero decir|en realidad"
        default: return text
        }
        return text.replacingOccurrences(
            of: "(?i)(?:" + weekday + #")[ \t]*,[ \t]*(?:"# + correction + #")[ \t]+("# + weekday + ")",
            with: "$1",
            options: [.regularExpression]
        )
    }

    private static func collapseRestatedClauses(_ text: String) -> String {
        let pattern = #"(?i)\b((?:I(?:'ve)? got|I have) an? [\p{L}'’-]+) at ("# + clockTime + #")([.!?])?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        guard matches.count >= 2 else { return text }

        var removal = IndexSet()
        for index in 1..<matches.count {
            let previous = matches[index - 1]
            let current = matches[index]
            let previousTime = ns.substring(with: previous.range(at: 2)).lowercased()
            let currentTime = ns.substring(with: current.range(at: 2)).lowercased()
            let previousEvent = ns.substring(with: previous.range(at: 1)).lowercased()
            let currentEvent = ns.substring(with: current.range(at: 1)).lowercased()
            guard previousTime == currentTime, previousEvent == currentEvent else { continue }
            let gapLocation = previous.range.upperBound
            let gapLength = current.range.location - gapLocation
            guard gapLength >= 0 else { continue }
            let gap = ns.substring(with: NSRange(location: gapLocation, length: gapLength))
            let leftover = gap.trimmingCharacters(in: .whitespacesAndNewlines)
            guard leftover.isEmpty || leftover.allSatisfy({ ".,!?".contains($0) }) else { continue }
            var removalStart = gapLocation
            for character in gap {
                if character == "." || character == "!" || character == "?" {
                    removalStart += 1
                    break
                }
                guard character.isWhitespace else { break }
                removalStart += 1
            }
            guard removalStart < current.range.upperBound else { continue }
            removal.insert(integersIn: removalStart..<current.range.upperBound)
        }
        guard !removal.isEmpty else { return text }
        let mutable = NSMutableString(string: text)
        for range in removal.rangeView.reversed() {
            mutable.deleteCharacters(in: NSRange(range))
        }
        return String(mutable)
    }

    private static func repairEnglishIndefiniteArticle(_ text: String) -> String {
        text.replacingOccurrences(
            of: #"(?i)\ba ([aeiou])"#,
            with: "an $1",
            options: [.regularExpression]
        )
    }

    private static func resolveProperNameCorrection(_ text: String) -> String {
        text.replacingOccurrences(
            of: #"\b([A-Z][\p{L}'’-]*)[ \t]*,[ \t]*(?:actually|I mean|rather)[ \t]+([A-Z][\p{L}'’-]*)\b"#,
            with: "$2",
            options: [.regularExpression]
        )
    }

    private static func capitalizeLineStarts(_ text: String) -> String {
        text.components(separatedBy: "\n").map { line in
            let prefix: String
            let content: String
            if let match = line.range(of: #"^[ \t]*(?:[-*•]|[0-9]+[.)])[ \t]+"#, options: .regularExpression) {
                prefix = String(line[match])
                content = String(line[match.upperBound...])
            } else {
                prefix = ""
                content = line
            }
            guard let first = content.first, first.isLetter, first.isLowercase else { return line }
            return prefix + String(first).uppercased() + content.dropFirst()
        }.joined(separator: "\n")
    }

}
