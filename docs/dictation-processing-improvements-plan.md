> Archived scope. Current product decisions are in `PRD.md` and
> `docs/product-quality-plan.md`; runtime/keyboard evidence is in their current
> plans. Historical instructions below about excluding Qwen, removing the
> suggestion bar or removing the Settings model entry are superseded. Preserve
> this document as evidence; do not execute its old implementation prompt.

# Dictation and Processing Improvements Plan

Status: implemented for the non-Qwen scope. The full DictusCore suite and the
Release app build pass; physical-device ASR quality validation remains pending.

## Scope

Improve the existing local dictation pipeline from microphone input to final text:

`capture -> segment -> transcribe -> merge -> clean up -> deliver`

The current WhisperKit/Parakeet architecture, sequential inference, mixed-language default, cancellation, generation guards, and protected-span cleanup remain the baseline.

Qwen is explicitly out of scope. No cloud service, account, API key, mandatory model download, or manual language-switch control is added.

## Non-negotiable behavior

- Auto mode preserves every spoken language and script in place.
- ASR output remains the authoritative transcript until an explicitly chosen translation mode runs.
- Cleanup may improve punctuation and grammar, but may not silently translate, invent, or delete content.
- Names, numbers, dates, currencies, units, URLs, email addresses, code, negation, and quoted text are protected.
- Prediction is advisory only. It never replaces existing text or inserts automatically.
- All model inference stays local, sequential, cancellable, and bounded by the existing memory and timeout policy.

## Phase 1: Measure the real bottlenecks

Create one repeatable, consented evaluation set covering:

- English, German, Spanish, Portuguese, French, Russian, Arabic, Hindi, Mandarin, and Japanese.
- English-only, German-only, CJK-only, mixed-language switches, switches separated by silence, and forced hard cuts.
- Short utterances, long single-language recordings, names, dates, numbers, URLs, punctuation commands, lists, negation, self-correction, noise, clipping, and silence.

Record only structured metadata by default: audio hash, device/OS, model revision, region boundaries, detected language, confidence, load time, decode time, cleanup time, memory, cancellation, and final outcome.

Score WER/CER per language, script preservation, protected-span preservation, overlap duplication, dropped audio, empty output, warm latency, cold latency, and peak memory. Keep failed cases as first-class results.

Deliverable: a captured-run report that compares the current implementation against every later change without requiring model weights in unit tests.

## Phase 2: Improve capture quality before changing models

- Verify the actual sample rate, channel mix-down, gain, clipping, silence, and interruption state at the point where audio enters segmentation.
- Add a cheap audio-quality score for silence, clipping, and very low energy.
- Apply gain correction only to quiet speech when the noise floor supports it; never amplify a noisy recording blindly.
- Preserve one backing audio buffer and pass slices/ranges to segmentation and decode where practical.
- Release region buffers immediately after each sequential decode.
- Record exact sample ranges for every region so missing or repeated audio is diagnosable.

Acceptance: no dropped samples, no accidental full-recording copies, stable output on repeated captures, and no quality regression on clean speech.

## Phase 3: Make segmentation adaptive

Keep VAD-first segmentation, but make its decisions explicit and observable:

- Start with the existing 300-500 ms meaningful-silence boundary, 150-250 ms context, tiny-region merge, small forced-cut overlap, and roughly 8-12 second maximum.
- Adapt silence and minimum-region thresholds to measured speech energy and recording noise instead of using one threshold for every device.
- Avoid splitting a long, clean, single-language recording just because a fixed timer elapsed when a safe speech boundary is available.
- Use the hard maximum only when necessary, and keep overlap at the forced boundary.
- Avoid decoding isolated regions that are too short to contain reliable language evidence; merge them with a neighbor.

Acceptance: region decisions are deterministic from the same audio and policy, every sample belongs to at least one region, and forced cuts do not create repeated boundary words.

## Phase 4: Make model selection and loading reliable

- Maintain one warm engine per dictation session and never initialize WhisperKit or Parakeet per region.
- Add a model capability manifest containing supported scripts/languages, engine type, minimum OS, estimated memory tier, and load state.
- Do not show a model as selectable until its local files are complete, compatible, and loadable on the current device.
- In Auto mode, prefer a locally installed multilingual WhisperKit model for code-switching and CJK. Use Parakeet only for its verified language coverage.
- If the selected local model fails to load, perform one deterministic fallback to an installed compatible model, log the reason, and keep the failed model from immediately retrying in a loop.
- Warm the tokenizer/decoder and any safe Core ML resources before recording ends, without competing model initialization.

Acceptance: a model-load failure produces a useful recovery path, no infinite retry, no extra mandatory download, and warm inference remains sequential.

## Phase 5: Improve per-region decoding and language evidence

- Keep Whisper Auto decoding in transcription mode with independent language detection per region.
- Store detected language, confidence, script evidence, timestamps when available, region duration, decode latency, and fallback reason.
- Combine ASR language evidence with script evidence and neighboring regions; do not let one low-confidence region relabel the entire recording.
- Treat short or ambiguous regions as unknown and preserve their raw text rather than forcing English.
- Keep Parakeet output tagged with its actual language limits so it cannot be presented as universal multilingual support.
- Check cancellation before and after every region decode and before publishing any result.

Acceptance: English -> German -> English, Latin -> Chinese -> Latin, silence-separated switches, and short mixed spans remain in their spoken languages.

## Phase 6: Strengthen transcript merging

- Keep region transcripts and their sample ranges until final delivery and diagnostics are complete.
- Merge only boundary material supported by overlap timing and token/character agreement.
- Preserve a legitimate repeated word when overlap evidence is absent or ambiguous.
- Apply script-aware spacing: Latin words need normal separation, while CJK adjacency must not receive an invented ASCII space.
- Preserve ASR punctuation and line structure; do not perform translation or grammar rewriting in the merger.
- If a region is empty or low-confidence, retain neighboring authoritative text and expose the gap in diagnostics instead of inventing a bridge.

Acceptance: no duplicated overlap words, no missing boundary audio, no unwanted CJK spaces, and no language normalization during merge.

## Phase 7: Make cleanup faster and safer

Use an observable two-speed pipeline:

1. Run a deterministic floor immediately: verbal punctuation, safe whitespace, list structure, and obvious ASR artifacts.
2. Skip model cleanup when the text is already clean and contains no eligible grammar errors.
3. Extract protected spans before any local cleanup.
4. Classify language per span using region metadata first, script evidence second, and NaturalLanguage detection only as a fallback.
5. Clean eligible spans with the language-neutral Auto prompt or the matching language prompt, never a fixed dominant-language prompt for a mixed document.
6. Validate protected-span equality, script preservation, edit distance, punctuation balance, list balance, and unexplained additions.
7. Fall back to the deterministic floor on timeout, cancellation, unsupported language, engine failure, or guardrail rejection.

Add a strict verbatim mode for users who want only transcription and deterministic punctuation.

Acceptance examples:

- `Mach bitte einen Termin for next Tuesday.` stays mixed.
- `[Chinese] can you send me die Rechnung bitte?` keeps Chinese, English, and German.
- Names, numbers, URLs, negation, and quoted text survive cleanup unchanged.

## Phase 8: Improve perceived speed and cancellation

- Publish stage state immediately: recording, transcribing region N, merging, cleaning, delivering, or cancelled.
- Keep partial region results internal until the final deterministic merge; do not insert out-of-order text into the host field.
- Allow cancellation from the keyboard dictation button and the in-app cancel control at every stage.
- Cancel the active engine task, cleanup task, translation task, watchdog, and pending delivery together.
- Re-check session generation and cancellation after every await so an old dictation cannot write into a newer one.
- Preserve the raw transcript when cleanup is cancelled, while avoiding a second insertion.

Acceptance: cancellation feels immediate, no late text appears after cancel, and a new recording can start without waiting for stale cleanup.

## Phase 9: Prediction and grammar boundaries

- Keep typing-time prediction separate from dictation cleanup.
- Use a weighted mixture of recent language/script evidence instead of switching the whole dictionary from one detector result.
- Abstain for ambiguous mixed-language context or unsupported scripts rather than falling back to English.
- Keep invisible next-key routing off the touch-critical path and invalidate stale work on every edit, selection change, host-field change, page change, and new dictation session.
- Keep post-dictation continuation suggestions disabled by default, asynchronous, explicit-tap only, and invalidated when host text or selection changes.

## Phase 10: Verification and rollout

1. Add deterministic Core tests for audio-quality policy, adaptive segmentation, range coverage, merge overlap, CJK spacing, language evidence, protected spans, cleanup fallback, and cancellation.
2. Run identical captured audio through installed WhisperKit and Parakeet candidates on supported physical devices.
3. Measure cold and warm model load, warm per-region decode, cleanup latency, peak memory, interruptions, airplane mode, background execution, and long recordings.
4. Verify raw transcript, merged transcript, cleaned transcript, and optional suggestion as separate states.
5. Run the full repository test suite and the normal Release build.
6. Only after the evidence passes, create a release build and perform device/TestFlight validation.

## Recommended implementation order

1. Phase 1 measurement and captured-run reports.
2. Phase 2 capture diagnostics and buffer lifetime cleanup.
3. Phase 4 model capability/load reliability.
4. Phase 5 language evidence and Phase 6 merge hardening.
5. Phase 7 cleanup fast path and guardrail tightening.
6. Phase 8 cancellation and stage-progress validation.
7. Phase 3 adaptive segmentation tuning using the captured corpus.
8. Phase 9 prediction refinements.

This order avoids choosing a new model to compensate for bad audio, incorrect boundaries, or unsafe cleanup.

## Execution prompt

> Implement `docs/dictation-processing-improvements-plan.md` in `/Users/enricomini/Documents/Github/sAiity-dictus`. Preserve all unrelated dirty and untracked work. Do not add or restore Qwen. Keep WhisperKit/Parakeet local, sequential, cancellable, and compatible with the current App Group, generation guards, background execution, timeout, and memory policies. Start with measurement and captured-run metadata, then improve capture diagnostics, model load reliability, per-region language evidence, overlap/script-aware merging, cleanup fast paths and guardrails, cancellation, and only then adaptive segmentation and prediction. Preserve mixed-language output by default, never silently translate or replace authoritative ASR text, keep post-dictation suggestions disabled by default, and add focused tests for every behavior change. Run the full DictusCore suite and the normal `sAiity-iOS` Release build. Do not upload or install a build until separately authorized.
