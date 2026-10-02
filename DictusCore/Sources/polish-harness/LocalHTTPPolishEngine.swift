// DictusCore/Sources/polish-harness/LocalHTTPPolishEngine.swift
//
// THROWAWAY — spike code for #268, not a step toward shipping anything.
//
// It exists to answer exactly one question the #268 plan pre-registered as
// measurable off-device: for a given candidate model at a given quantization,
// how good is the polished French output compared with Apple Foundation Models,
// judged by the SAME `PolishPipeline`, the same pre/post-passes, the same
// guardrails and the same fixtures?
//
// Output quality is a property of the weights and the prompt, so a Mac can
// answer it. Latency and memory on an iPhone are properties of the hardware, so
// a Mac cannot, and this file does not pretend otherwise: the `engineMs` the
// harness prints for this engine includes an HTTP round trip to a local server
// on an M4 Pro and is meaningless as a device figure.
//
// Lives in the `polish-harness` target only — macOS-only, excluded from every
// app target and from CI (`DictusCore/Package.swift`). Delete with the branch.

import Foundation
import DictusCore

/// A `PolishEngineProtocol` engine that forwards to an OpenAI-compatible
/// `POST /v1/chat/completions` endpoint on localhost (Ollama, llama-server,
/// LM Studio, vLLM — they all speak it).
///
/// The prompt framing deliberately mirrors `AppleFoundationModelsPolishEngine`:
/// the resolved per-`(mode, language)` instructions become the `system` message,
/// and the user message repeats the same Input/"Polished output:" scaffolding.
/// Anything else would compare two prompts rather than two models.
///
/// The availability annotation is not a Foundation Models dependency in spirit —
/// nothing here calls Apple's model — it is only because the shipping prompt set
/// is reached through `AppleFoundationModelsPolishEngine.instructions(for:language:)`,
/// which carries the gate. Reading the prompts through that one entry point is
/// what guarantees both engines are handed the same instructions.
@available(iOS 26.0, macOS 26.0, *)
struct LocalHTTPPolishEngine: PolishEngineProtocol {

    let identifier: String
    private let endpoint: URL
    private let model: String
    private let temperature: Double
    private let disableThinking: Bool
    private let session: URLSession

    init(baseURL: String,
         model: String,
         temperature: Double = 0.0,
         disableThinking: Bool = true,
         timeout: TimeInterval = OllamaHTTPContract.cleanupTimeout) {
        self.model = model
        self.temperature = temperature
        self.disableThinking = disableThinking
        self.identifier = "local:\(model)"
        guard let url = OllamaHTTPContract.endpoint(baseURL: baseURL) else {
            fatalError("LocalHTTPPolishEngine: malformed base URL \(baseURL)")
        }
        self.endpoint = url
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        self.session = URLSession(configuration: configuration)
    }

    /// Shared with the Apple FM engine so the harness cannot benchmark a
    /// different user-turn envelope.
    static func userTurn(raw: String) -> String {
        PolishPromptEnvelope.userTurn(raw: raw)
    }

    func polish(raw: String,
                targetLanguage: SupportedLanguage,
                mode: PolishMode) async throws -> String {
        try await polish(raw: raw, targetLanguage: targetLanguage, mode: mode, style: .balanced)
    }

    func polish(raw: String,
                targetLanguage: SupportedLanguage,
                mode: PolishMode,
                style: WritingStyle) async throws -> String {
        let resolved = PolishPromptEnvelope.resolve(raw: raw, style: style)
        let instructions = resolved.instructions
        let userPrompt = resolved.userTurn
        var body: [String: Any] = [
            "model": model,
            "temperature": temperature,
            "stream": false,
            "max_tokens": PolishContextBudget.outputLimit(for: raw),
            "messages": [
                ["role": "system", "content": instructions],
                ["role": "user", "content": userPrompt]
            ]
        ]
        // Reasoning-tuned checkpoints think before answering by default. Polish is
        // a rewrite, not a puzzle, and a real integration would switch that off —
        // measuring with it on reports a latency no shipped product would pay.
        //
        // Two keys, because they are not interchangeable. Measured against Ollama
        // Ollama 0.32.6 on 2026-08-13: `chat_template_kwargs` was
        // accepted and IGNORED (4594 characters of reasoning still generated),
        // while `reasoning_effort: "none"` actually suppressed it. The former stays
        // for servers that honour it (vLLM, llama-server); the latter is what makes
        // the numbers in this spike honest. Non-reasoning models ignore both.
        if disableThinking {
            body["reasoning_effort"] = "none"
            body["chat_template_kwargs"] = ["enable_thinking": false]
        }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        return try OllamaHTTPContract.responseText(
            data: data, statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0
        )
    }
}
