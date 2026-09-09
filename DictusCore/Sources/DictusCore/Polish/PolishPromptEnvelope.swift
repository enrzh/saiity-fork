import Foundation

/// Shared user-turn framing for every cleanup backend.
///
/// Keeping this in DictusCore prevents the Apple Foundation Models path and the
/// local evaluation harness from silently measuring different prompts.
public enum PolishPromptEnvelope {
    public static func userTurn(raw: String) -> String {
        """
        Polish this text. Output only the polished version, nothing else.

        Input:
        \(raw)

        Polished output:
        """
    }
}
