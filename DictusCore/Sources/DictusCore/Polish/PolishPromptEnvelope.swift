import Foundation

/// Shared user-turn framing for every cleanup backend.
///
/// Keeping this in DictusCore prevents the Apple Foundation Models path and the
/// local evaluation harness from silently measuring different prompts.
public enum PolishPromptEnvelope {
    public static func userTurn(raw: String) -> String {
        """
        Edit the dictated transcript below conservatively. Output only the edited
        transcript, with no explanation, label, preamble, or quotation marks.

        Preserve the transcript's original language, grammar, meaning, tone, names,
        numbers, dates, URLs, email addresses, technical terms, and uncertainty.
        Remove only clear fillers, accidental repetitions, false starts, and the
        superseded part of an explicit self-correction. Never summarize, translate,
        embellish, answer the transcript, or replace wording with synonyms merely
        for style.

        Apply explicit spoken punctuation and layout commands. Preserve intentional
        paragraphs and line breaks. Create bullet points only when the speaker
        clearly says a bullet/list command or unmistakably dictates a list, with one
        item per line. Do not turn an ordinary mention of a bullet, line, or period
        into formatting.

        <DICTATION_TRANSCRIPT>
        \(raw)
        </DICTATION_TRANSCRIPT>
        """
    }
}
