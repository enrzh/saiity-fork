# Processing Prompt and Budget Implementation Plan

> Execute inline with `executing-plans`. Preserve the dirty checkout and prior work. Main owns serial tests, builds and model checks. Do not commit, push, upload or publish.

**Goal:** Make all production cleanup styles cheaper to prompt while preserving meaning, and tighten cancellation/time limits around cleanup and native translation.

**Architecture:** Keep the shared `DictationCleanupPrompt`, JSON `PolishPromptEnvelope`, existing backend owners and `PolishDeadline`. Cleanup remains a single constrained edit, with the style expressed once. Native translation uses its separate Apple API and shares one eight-second deadline across clauses; it does not inherit cleanup's no-translation contract.

**Tech Stack:** Existing Swift/Foundation, Foundation Models, MLX, URLSession and Translation. Token measurements use the existing first-party tokenizer and public pinned Qwen tokenizer fixture. No new production dependency, layer, model or download.

## Global constraints

- Work locally on `cursor/keyboard-surface-fixes-a66e`, HEAD `b696d880`; preserve all earlier processing, native-core, slimming and interaction changes.
- Keep iOS 17.0, 1.0.0 (242), App Group, model/language/style choices, source resources, recovery state and release artifacts.
- Preserve names, numbers, dates, units, negation, meaning, code/URLs, language switches, line breaks, lists, explicit vocabulary and unfinished thoughts. Do not lower existing output, structure, fact or language guardrails.
- Keep exact original translation fallback and generation/client identity checks. Never publish cancelled or stale output.
- Retain greedy/temperature-zero generation, transcript-sized output reserves, the 2,048-token ceiling, truncation rejection and single inference ownership.
- No room audio, private-transcript access, permissions changes, model downloads or remote inference during automated checks. Use fabricated text and public tokenizer resources.
- Phone installation remains the previously authorized same-bundle development update, after checks. Physical microphone/model/interaction QA remains separate.
- Dedicated simulator only, at most two booted; preserve the existing paused heartbeat and pending native interaction checks.

## Task 1: Compact the production contract

**Files:** `DictusCore/Sources/DictusCore/Polish/LocalCleanupModel.swift`, `DictusCore/Sources/DictusCore/Polish/PolishPromptEnvelope.swift`, `DictusCore/Sources/DictusCore/WritingStyle.swift`, existing prompt/vocabulary tests.

- [x] Save resolved prompts and exact pinned-tokenizer counts for all four styles and fabricated English, French, mixed-language, structured and instruction-like transcript inputs.
- [x] Keep one shared system contract: one edit pass; transcript is data; plain output only; preserve all facts/languages/structure; keep final explicit self-corrections; no invented completion, translation, summary, reasoning or wrapper.
- [x] Shorten style fragments to their actual tone differences. Retain the conservative concise rule and approved-vocabulary constraints. Keep a compact transformation example for small instruction models.
- [x] Use a short user-turn prefix followed by the unchanged JSON-encoded transcript. Bump the production prompt revision so the existing result cache cannot return results from the previous contract.
- [x] Verify adversarial JSON round-trip, style separation, exact glossary inclusion and prompt-size reduction. The old per-language templates are historical/evaluation entry points, not the production resolution path; preserve them.

## Task 2: Stop avoidable model and network work

**Files:** `DictusCore/Sources/DictusCore/Polish/PolishPipeline.swift`, `DictusCore/Sources/DictusCore/Polish/AppleFoundationModelsPolishEngine.swift`, `DictusCore/Sources/DictusCore/Polish/OllamaHTTPContract.swift`, existing cancellation/execution/HTTP tests.

- [x] Write failing checks that blank input and an expired deadline avoid context preparation/inference and preserve deterministic fallback.
- [x] Exit before prompt/context work for blank or expired input. Check cancellation at Apple backend entry and after token budgeting, before generation, and before returning a response. Existing shared execution ownership remains intact.
- [x] Align the HTTP resource timeout with the existing eight-second cleanup ceiling; retain zero-temperature/no-reasoning request options and incomplete-output rejection.
- [x] Verify cancellation, noncooperative-SDK ownership, context overflow, output caps/truncation, all styles and exact fact/language/structure fallback. Do not reduce token reserves without model quality evidence.

## Task 3: Bound native translation clauses

**File:** `DictusApp/DictationCoordinator.swift`; reuse `PolishDeadline`.

- [x] Create one `PolishDeadline()` before the native translation span loop. Check it before another clause, after availability lookup and after SDK output; expired work returns the complete original transcript.
- [x] Pass that deadline through `translationOutcome`, `translateWithHostLimited` and `translateWithInstalledSource`. The host timeout sleeps until the shared instant rather than restarting eight seconds for each clause.
- [x] Cancel the installed-source SDK session at the shared deadline and on parent cancellation. Cancel its timer when the call finishes. A cooperative SDK must release promptly; compilation cannot establish behavior of a stalled physical translation model.
- [x] Keep source/target validation, Simplified Chinese conversion, installed-pair detection, user-controlled downloads, exact original fallback and client/generation identities unchanged. Do not choose a lower-quality translation strategy without native-language evaluation.

## Task 4: Validate and hand off

- [x] Run focused red/green checks, then the full affected Core suite in Debug and Release once final source is stable.
- [x] Re-measure all prompts with the same pinned tokenizer. Count instructions and JSON envelope separately; token reduction does not prove semantic quality or phone latency.
- [x] Check Apple model availability without enabling settings or downloading assets. Use only fabricated text if a real local model is already available; otherwise record that limitation.
- [x] Build simulator and signed device targets serially; verify app/keyboard/widget signatures, versions, App Group and original resource hashes.
- [x] Update the authorized development phone installation and match its new bundle location/version to filtered inventory.
- [x] Record evidence, resource/quality trade-offs, SDK warnings and separate physical/model/translation gates. Keep all source changes uncommitted.

## Verified result

Implementation and local handoff are complete. See [the QA checkpoint](../../qa/2026-10-13-processing-prompts.md) for exact token measurements, Debug/Release results, signing/resource checks and the verified development installation. Short-input prompt tokens decrease by 23.4–26.1% across all styles without reducing output caps. Each configuration runs 1,990 tests with one existing skip and zero failures.

Apple's Mac model remains `modelNotReady`; actual model quality, translation pair availability, physical latency and noncooperative SDK behavior are separate pending gates. The eight-second translation deadline requests cancellation and rejects late output; availability lookup and an SDK ignoring cancellation can still delay return. No model download, microphone capture, commit, push, upload or publication occurred.

## Follow-up: typed-ready dictation

The user requests transcription like Typeless and Wispr Flow. Their official public pages describe filler/restart removal, final self-corrections, punctuation and list formatting. This follow-up targets that edited-text behavior with the existing local pipeline. It does not establish acoustic accuracy, real-model parity or a measured speed comparison with either product.

**Design:** Keep one constrained, typed-ready cleanup pass across all four styles. Add explicit English/French paragraph and bullet commands to the existing pre-pass. Reuse validated monolingual evidence for Auto hesitation/pronoun-stutter cleanup. Resolve only adjacent, explicitly corrected bare numbers or clock times; preserve dates, codes, URLs, units, negation, meaningful repetition and mixed/uncertain languages. Use one regex pass for immediate stutters. Retain the eight-second budgets, context/output limits, vocabulary, cancellation, original recovery and selected model/style settings.

**Files:** `PolishPostpass.swift`, `VerbalPunctuationPrepass.swift`, `LocalCleanupModel.swift`, `TypingFact.swift` and existing cleanup/prompt/pre-pass/fact tests and fixture. No production type, dependency or model is added. Main executes serially; existing user work and release boundaries remain. Local correction acceptance preserves unrelated earlier amounts/names.

- [x] Reproduce missing Auto cleanup, adjacent correction and English/French formatting with fabricated transcript regressions. Include literal code, dates, invoice codes, URLs, negation, language switches and emphasis.
- [x] Apply the smallest existing-owner fixes. Express ready-to-send edits and clear spoken lists in a compact prompt, retain the 240-token estimator ceiling, and bump its cache revision.
- [x] Verify complete-pipeline fallback, formatting, all styles and unchanged output limits; measure the same 28 pinned-tokenizer cases against `cleanup-v3`.
- [x] Run final Debug/Release Core suites and serial app builds; verify signatures, versions, App Group and source/bundle resources. Update the authorized development installation and confirm filtered inventory.
- [x] Record exact evidence and remaining real-model/physical quality gates in the QA checkpoint. Keep all source changes local and uncommitted.
