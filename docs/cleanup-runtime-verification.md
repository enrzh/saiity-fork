# Cleanup runtime verification — 2026-09-12

Scope: cleanup only; no ASR catalog, DictationCoordinator, keyboard, release, or dependency changes.

## Inventory

- Apple Foundation Models: system-provided model, stateless per-call sessions with prewarming and a 4096-token context guard. No downloadable variant selector.
- Ollama: the first valid custom cleanup registration selects an OpenAI-compatible `/v1/chat/completions` endpoint and model name. Existing options are temperature 0, non-streaming responses, `reasoning_effort: none`, and `enable_thinking: false`. This is an HTTP backend, not an embedded iPhone inference runtime.
- Passthrough: deterministic cleanup fallback, no model weights.
- No bundled compact cleanup catalog or cleanup-specific model manager was found. Shared `ModelInfo.swift` was not edited.

The existing research report `docs/research/268-second-llm-backend.md` records historical tests of Gemma 3 1B/4B, Llama 3.2 3B, Qwen 3.5 0.8B and Qwen 3 1.7B. Its addendum leaves Qwen 3 1.7B as a candidate, not a device-validated replacement. Those historical results are not current measurements. No compact entries were added: this run could not verify installed artifacts and live runtime behavior.

## Changes

- Already-cancelled pipeline calls skip preprocessing and inference; URLSession cancellation is classified as cancellation rather than engine failure.
- Auto cleanup avoids a redundant whitespace normalization pass. Its fallback no longer decodes original input as model output, preserving paragraph breaks and nested list indentation.
- Ollama uses the existing URLSession request/resource timeout options with a 30-second budget instead of 300 seconds. This is an interactive fallback policy, not a measured inference speedup; a slow cold model may now fall back sooner.
- App and HTTP harness share response parsing. Explicit non-stop finish reasons, unfinished leading reasoning blocks, and reasoning-only responses fail closed. Legacy servers without `finish_reason` remain supported, so truncation cannot be detected reliably on those servers.
- The Auto prompt, mixed-language wording, sampling options, and language guardrails remain unchanged. No claim is made that heuristic guardrails prove semantic preservation in arbitrary LLM output.

## Verification

From `DictusCore`, using `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`:

```sh
swift test --scratch-path /tmp/dictus-cleanup-eval-build --filter 'Polish|OllamaHTTPContractTests|VerbalPunctuation'
swift run --scratch-path /tmp/dictus-cleanup-eval-build polish-harness eval Sources/polish-harness/fixtures/auto.json
swift run --scratch-path /tmp/dictus-cleanup-eval-build polish-harness eval Sources/polish-harness/fixtures/cleanup-preservation.json
```

The focused suite passed 191 tests with zero failures. Core and harness compiled on macOS 27. Live Apple FM eval stopped with `modelNotReady`. No Ollama executable was found on PATH or in standard installation locations, and no local listener was present on port 11434. No server was started and no weights were downloaded.

New fixtures cover mixed languages, names, negation, numbers, and numbered lists. Timeout/cancellation tests assert preservation of the mixed-language structured fallback. Fixture expectations score final output and may pass on fallback: an eval pass alone must never be reported as successful model inference.

The harness parsed the new fixtures, but its `prompt` command rejects Auto-mode fixtures (it only prints per-language prompts). Live evaluation of these fixtures remains pending model availability.

No before/after inference latency or iPhone memory benchmark was possible. The app target was not built or device-tested; the timeout tests simulate URL errors rather than waiting on a real stalled server. Existing package warnings concern an unhandled harness README and async NSLock usage in context-budget tests.

## Files changed

- `DictusApp/Polish/PolishCoordinator.swift`
- `DictusCore/Sources/DictusCore/Polish/OllamaHTTPContract.swift`
- `DictusCore/Sources/DictusCore/Polish/PolishPipeline.swift`
- `DictusCore/Sources/DictusCore/Polish/PolishPostpass.swift`
- `DictusCore/Sources/polish-harness/LocalHTTPPolishEngine.swift`
- `DictusCore/Sources/polish-harness/fixtures/cleanup-preservation.json` (new)
- `DictusCore/Tests/DictusCoreTests/OllamaHTTPContractTests.swift`
- `DictusCore/Tests/DictusCoreTests/Polish/PolishCancellationRegressionTests.swift` (new)
- `docs/cleanup-runtime-verification.md` (this report, new)
