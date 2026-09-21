import Foundation

/// Shared user-turn framing for every cleanup backend.
///
/// Keeping this in DictusCore prevents the Apple Foundation Models path and the
/// local evaluation harness from silently measuring different prompts.
public enum PolishPromptEnvelope {
    public static func userTurn(raw: String) -> String {
        userTurn(raw: raw, style: .balanced)
    }

    public static func userTurn(raw: String, style: WritingStyle) -> String {
        """
        Edit the dictated transcript below conservatively. Output only the edited
        transcript, with no explanation, label, preamble, or quotation marks.

        Preserve the transcript's original language, meaning, tone, names,
        numbers, dates, URLs, email addresses, technical terms, and uncertainty.
        Restore grammar required by that language (German statement order after
        dropping so grundsätzlich, um before Uhr, conjugating dich dafür einladen).
        Remove clear fillers (uh, um, like as hesitation, yeah as stalling, so basically
        or so grundsätzlich as a restart), ASR non-speech labels such as (coughing) or
        (snow crunching), accidental repetitions, false starts, restated duplicates of the
        same message, and the superseded part of an explicit self-correction — including
        numeric or time corrections such as 2am, oh sorry, it's 4am → 4am. Never
        summarize, translate, embellish, answer the transcript, or replace wording with
        synonyms merely for style.

        Apply explicit spoken punctuation and layout commands. Preserve intentional
        paragraphs and line breaks. Create bullet points only when the speaker
        clearly says a bullet/list command or unmistakably dictates a list, with one
        item per line. Do not turn an ordinary mention of a bullet, line, or period
        into formatting.

        Writing style: \(style.promptInstruction)
        This preference never authorizes translation, summarization, omission of facts,
        or replacing clear wording merely because another phrasing sounds nicer.

        <DICTATION_TRANSCRIPT>
        \(raw)
        </DICTATION_TRANSCRIPT>
        """
    }
}
