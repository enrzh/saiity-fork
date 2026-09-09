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
        case .english, .spanish, .german:
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
        out = normalizeCleanupWhitespace(out)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !out.isEmpty else { return leadingNewlines + trailingNewlines }
        if let language {
            out = removeKnownFillers(out)
            out = removeImmediateStutters(out)
            out = resolveDateCorrection(out)
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

    private static func removeKnownFillers(_ text: String) -> String {
        var out = text.replacingOccurrences(
            of: #"(?i)(^|[ \t,(])(?:uh+|um+|euh+|äh+|ähm+|öhm+|hmm+|hum+|eeh|eh+|erm+|mmm+)(?=($|[ \t,!?;:.]))(?:[ \t]*[,;:])?[ \t]*"#,
            with: "$1",
            options: [.regularExpression]
        )
        out = out.replacingOccurrences(
            of: #"(^|[ \t,(])呃(?=($|[ \t,!?;:.\p{Han}]))(?:[ \t]*[,;:])?[ \t]*"#,
            with: "$1",
            options: [.regularExpression]
        )

        // Discourse words are removed only when punctuation marks them as a
        // parenthetical filler at the beginning of a sentence.
        let discourse = #"(?:like|well|you know|basically|enfin|voilà|tu vois|tu sais|also|na ja|sozusagen|pues|este|o sea)"#
        return out.replacingOccurrences(
            of: "(?i)^(?:" + discourse + ")[ \\t]*[,;:][ \\t]*",
            with: "",
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
        text.replacingOccurrences(
            of: #"(?i)^(.+?)[ \t]+(?:monday|tuesday|wednesday|thursday|friday|saturday|sunday|lundi|mardi|mercredi|jeudi|vendredi|samedi|dimanche|montag|dienstag|mittwoch|donnerstag|freitag|samstag|sonntag|(?:el[ \t]+)?(?:lunes|martes|miércoles|jueves|viernes|sábado|domingo)),[ \t]*(?:actually|rather|i mean|enfin|plutôt|je veux dire|eigentlich|besser gesagt|ich meine|mejor|más bien|quiero decir|en realidad)[ \t]+(monday|tuesday|wednesday|thursday|friday|saturday|sunday|lundi|mardi|mercredi|jeudi|vendredi|samedi|dimanche|montag|dienstag|mittwoch|donnerstag|freitag|samstag|sonntag|(?:el[ \t]+)?(?:lunes|martes|miércoles|jueves|viernes|sábado|domingo))$"#,
            with: "$1 $2",
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
