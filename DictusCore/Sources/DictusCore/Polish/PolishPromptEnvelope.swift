import Foundation

/// Shared user-turn framing for every cleanup backend.
///
/// Keeping this in DictusCore prevents the Apple Foundation Models path and the
/// local evaluation harness from silently measuring different prompts.
public enum PolishPromptEnvelope {
    public struct Request: Sendable {
        public let instructions: String
        public let userTurn: String

        public var combined: String { instructions + "\n\n" + userTurn }
    }

    public static func resolve(raw: String, style: WritingStyle = .balanced) -> Request {
        Request(instructions: DictationCleanupPrompt.instructions(style: style), userTurn: userTurn(raw: raw))
    }

    public static func userTurn(raw: String) -> String {
        userTurn(raw: raw, style: .balanced)
    }

    public static func userTurn(raw: String, style: WritingStyle) -> String {
        // JSON escaping keeps quotes, closing tags and literal line-break
        // markers inside the data payload. Guardrails remain the trust boundary.
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        let payload = (try? encoder.encode(raw)).flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""
        return "Edit this transcript, encoded as one JSON string. Return plain transcript text, not JSON:\n" + payload
    }
}
