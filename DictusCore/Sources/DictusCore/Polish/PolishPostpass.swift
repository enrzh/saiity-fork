// DictusCore/Sources/DictusCore/Polish/PolishPostpass.swift
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

    /// `language` enables the legacy known-language lexical rules. Pass `nil`
    /// when the input language is unknown; only language-neutral cleanup runs.
    public static func cleanupFloor(_ text: String,
                                    language: SupportedLanguage? = .english) -> String {
        let leadingNewlines = String(text.prefix { $0 == "\n" })
        let trailingNewlines = String(text.reversed().prefix { $0 == "\n" }.reversed())
        var out = String(text
            .dropFirst(leadingNewlines.count)
            .dropLast(trailingNewlines.count))
        out = removeNonSpeechEventLabels(out)
        out = normalizeCleanupWhitespace(out)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !out.isEmpty else { return leadingNewlines + trailingNewlines }
        // Spoken cleanup is language-neutral enough to run in Auto / mixed
        // mode (`language == nil`). The product always uses that path, and
        // prompt-only cleanup never runs there.
        out = removeSpokenRestartFillers(out)
        out = removeHesitationFillers(out)
        out = removeFillerLike(out)
        out = normalizeClockTimes(out)
        out = resolveTimeCorrection(out)
        out = resolveDateCorrection(out)
        out = collapseRestatedClauses(out)
        out = repairEnglishIndefiniteArticle(out)
        if let language {
            if language == .english {
                out = removeEnglishUmFillers(out)
            }
            out = removeDiscourseFillers(out)
            out = removeImmediateStutters(out)
            out = resolveProperNameCorrection(out)
            // Apply this again to engine output. The pre-pass normally
            // converted commands before the LLM call, but a backend can echo
            // them verbatim.
            out = VerbalPunctuationPrepass.apply(out, language: language)
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
            of: #"\[(?:[A-Z][A-Z0-9 _-]{1,24})\]"#,
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

    private static func removeHesitationFillers(_ text: String) -> String {
        let out = text.replacingOccurrences(
            of: #"(?i)(^|[ \t,(])(?:uh+|euh+|äh+|ähm+|öhm+|hmm+|hum+|eeh|eh+|erm+|mmm+)(?=($|[ \t,!?;:.]))(?:[ \t]*[,;:])?[ \t]*"#,
            with: "$1",
            options: [.regularExpression]
        )
        return out.replacingOccurrences(
            of: #"(^|[ \t,(])呃(?=($|[ \t,!?;:.\p{Han}]))(?:[ \t]*[,;:])?[ \t]*"#,
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

    private static func removeDiscourseFillers(_ text: String) -> String {
        // Discourse words are removed only when punctuation marks them as a
        // parenthetical filler at the beginning of a sentence.
        let discourse = #"(?:like|well|you know|basically|enfin|voilà|tu vois|tu sais|also|na ja|sozusagen|pues|este|o sea)"#
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

    private static func resolveTimeCorrection(_ text: String) -> String {
        text.replacingOccurrences(
            of: "(?i)(" + clockTime + #")\s*[,.]?\s*"# + spokenCorrection + #"[,.]?\s*(?:it'?s\s+)?("# + clockTime + ")",
            with: "$2",
            options: [.regularExpression]
        )
    }

    private static func removeImmediateStutters(_ text: String) -> String {
        let meaningfulRepetitions = #"very|really|so|too|quite|much|many|more|less|again|bien|très"#
        let pattern = "(?i)\\b(?!(?:" + meaningfulRepetitions + ")\\b)([\\p{L}\\p{N}][\\p{L}\\p{N}'’-]*)[ \\t]+\\1\\b"
        var out = text
        while true {
            let cleaned = out.replacingOccurrences(of: pattern, with: "$1", options: [.regularExpression])
            guard cleaned != out else { return out }
            out = cleaned
        }
    }

    private static func resolveDateCorrection(_ text: String) -> String {
        let weekday = #"(?:monday|tuesday|wednesday|thursday|friday|saturday|sunday|lundi|mardi|mercredi|jeudi|vendredi|samedi|dimanche|montag|dienstag|mittwoch|donnerstag|freitag|samstag|sonntag|(?:el[ \t]+)?(?:lunes|martes|miércoles|jueves|viernes|sábado|domingo))"#
        return text.replacingOccurrences(
            of: "(?i)" + weekday + #"[ \t]*,[ \t]*(?:actually|rather|i mean|enfin|plutôt|je veux dire|eigentlich|besser gesagt|ich meine|mejor|más bien|quiero decir|en realidad)[ \t]+("# + weekday + ")",
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
            guard previousTime == currentTime else { continue }
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
