# Dictation, Transcription, Cleanup, Grammar, and Prediction Plan

Status: implemented for the non-Qwen scope; physical-device validation remains pending. No release upload was performed.

This execution intentionally excludes Qwen model work. The repository's active
dictation path remains local WhisperKit/Parakeet infrastructure, with no Qwen
engine or Qwen model download added.

## Implemented scope

- Auto transcription keeps the existing sequential, VAD-first speech-region
  path and decodes each independent region with language detection enabled.
- Region metadata now records timing, detected language, character count,
  decode latency, confidence when available, and fallback information.
- Deterministic transcript merging preserves ASR punctuation, avoids unsafe
  Latin/CJK spacing changes, and removes overlap duplicates only when overlap
  evidence supports it.
- Multilingual output is the default. An explicit single-language output mode
  is persisted in settings without changing the underlying ASR task.
- Cleanup remains language-agnostic in Auto mode and retains mixed-language
  guardrails and protected-span checks.
- Invisible, script-aware prediction routing is coalesced off the touch path
  and abstains for ambiguous or unsafe mixed-language context.
- Optional post-dictation continuation suggestions are disabled by default,
  asynchronous, explicit-tap only, and fail closed when host context changes.
- A failed local model load now falls back once to an installed,
  device-compatible multilingual Whisper model; the selected model remains
  persisted and the fallback is logged for repair diagnostics.
- Prediction resets to the selected keyboard language for each new context,
  then applies only a confident language refinement. Existing keyboard
  languages without bundled trie files can still use system dictionary
  completions without adding a download.
- Core regression coverage was added for language mode migration, region
  segmentation/merging, cancellation, multilingual cleanup, prediction safety,
  and suggestion invalidation.

## Outcome

Make sAiity's offline dictation pipeline faster, more accurate, and safer for multilingual speech while keeping the raw/ASR transcript authoritative. Cleanup may improve presentation, grammar, and punctuation, but it must never silently translate, invent, or replace spoken content.

The default behavior remains mixed-language output. A separate explicit output mode may optionally request one target language; that mode must be a post-transcription transformation, never an ASR shortcut that causes multilingual Whisper to decode everything as English.

## Current baseline

- Audio is captured as 16 kHz mono `Float32`.
- WhisperKit Auto mode segments speech regions, decodes them sequentially, detects language independently per region, and merges the results without an LLM.
- Whisper Auto decoding uses `task: .transcribe`, `language: nil`, `detectLanguage: true`, a fresh prefill path, and no cross-region prefill cache.
- Parakeet remains a separate engine with its documented European-language limits. It is not the fallback for Chinese or arbitrary code-switching.
- Cleanup already has a deterministic floor, an Auto prompt, span-aware multilingual handling, cancellation, availability gates, and guardrails. These should be strengthened rather than replaced.
- Keyboard prediction currently uses local dictionaries/tries and `UITextChecker`; language adaptation is limited and must abstain when context is mixed or unsupported.

## Product rules

1. Mixed-language output is the default and preserves every spoken language.
2. One-language output is opt-in and clearly labeled. It may translate only because the user explicitly selected it.
3. ASR always transcribes what was spoken before any optional cleanup or translation step.
4. Cleanup never changes names, numbers, units, URLs, code, negation, or quoted text without strong evidence.
5. Prediction never inserts text automatically and never changes an already inserted transcript.
6. No cloud service, account, API key, or mandatory extra model download is introduced.
7. Models run sequentially on iPhone, stay warm between regions, and honor cancellation, generation guards, memory limits, and timeouts.

## Phase 0: Measurement and fixtures

Build one repeatable evaluation corpus before changing model selection:

- Record the same consented prompts as 16 kHz mono audio for English, German, Spanish, French, Mandarin, Hindi, Arabic, Portuguese, Russian, Japanese, and mixed-language switches.
- Include names, dates, currencies, units, URLs, negations, bullet-style lists, self-corrections, punctuation commands, short utterances, silence, noise, and long recordings.
- Store SHA-256 audio hashes, speaker/accent/device/OS metadata, model artifact revision, and raw output before cleanup.
- Score WER/CER by language, language-preservation rate, untranslated-span preservation, entity/number preservation, empty-output rate, cold-load time, warm decode time, peak memory, and end-to-end latency.
- Keep failures in the report. Do not select a model based only on successful cases.

Deliverable: a captured-run format that can compare supported Whisper variants and Parakeet on identical audio, with no weights or network dependency in unit tests.

## Phase 1: Capture and segmentation quality

Audit the audio before adding larger models:

- Verify sample rate conversion, channel mix-down, clipping, gain, leading/trailing silence, interruptions, and background audio.
- Keep the current VAD-first policy: meaningful silence around 300-500 ms, 150-250 ms context, merging of tiny regions, a 8-12 second hard maximum, and small overlap at forced cuts.
- Make the policy explicit and testable as a value type. Record the exact region boundaries used for every decode.
- Avoid retaining multiple full recordings. Pass one region at a time to the engine and release temporary copies immediately.
- Add an audio-quality fallback for very quiet or clipped input, but never amplify noise into a false transcript.

Acceptance: no dropped samples, no duplicated boundary words, no unnecessary fragmentation of a long single-language recording, and stable results across repeated runs.

## Phase 2: ASR engine and model strategy

### WhisperKit

- Keep multilingual Whisper as the reference path for Auto mode.
- Add richer per-region metadata: detected language, confidence when available, timestamps, region duration, decode latency, and fallback reason.
- Verify that every candidate model is locally installed, loadable on the target iPhone, and compatible with the current Core ML export before it appears selectable.
- Choose a device-aware default using measured warm latency, memory, and multilingual accuracy rather than catalog gauges.
- Keep one loaded WhisperKit instance across sequential regions. Never initialize one model per region.

### Parakeet

Keep Parakeet infrastructure working, but do not advertise it as a universal multilingual fallback. Its documented language set remains authoritative.

## Phase 3: Transcript authority and merging

- Keep `SpeechTranscriptionOutput` as the authoritative ASR result and preserve per-region records for diagnostics.
- Replace any plain separator join with a deterministic merger that understands Latin whitespace, CJK adjacency, punctuation, and overlap evidence.
- Remove only duplicate boundary material supported by region overlap and token/character agreement. Never deduplicate a legitimate repeated word without overlap evidence.
- Preserve ASR punctuation. Do not normalize scripts or translate during merging.
- Add confidence-aware fallback: if a region is empty or low-confidence, retain neighboring evidence and report the gap instead of inventing text.
- Add cancellation tests while a multi-region decode is in flight; no later region may write after cancellation or a newer session begins.

## Phase 4: Cleanup and grammar pipeline

Split cleanup into explicit, observable stages:

1. Deterministic floor: trim ASR artifacts, apply spoken punctuation, preserve line/list structure, and normalize only unambiguous whitespace.
2. Protected-span extraction: names, numbers, dates, currencies, units, URLs, email addresses, code-like text, quoted text, and explicit language/script boundaries.
3. Language-aware span classification using ASR region metadata first, NaturalLanguage detection second, and mixed/low-confidence passthrough as the safe result.
4. Sequential local cleanup of eligible spans with a language-neutral Auto prompt or the matching language prompt. Never send an entire mixed document to a fixed single-language prompt.
5. Guardrail validation: protected-span equality, script/language preservation, length and edit-distance bounds, punctuation/list balance, and no unexplained additions.
6. Deterministic fallback to the floor on timeout, cancellation, engine failure, unsupported language, or guardrail rejection.

Grammar improvements should target actual failure classes: capitalization, punctuation, sentence boundaries, agreement, articles, and spoken list formatting. They must not “correct” code-switches into a dominant language. Add a strict verbatim mode for users who do not want grammar changes.

Acceptance examples:

- `Mach bitte einen Termin for next Tuesday.` stays mixed in default mode.
- `你好，can you send me die Rechnung bitte?` preserves Chinese, English, and German.
- `Ich schicke dir the invoice tomorrow und 我晚上再确认。` remains mixed after cleanup.
- Names, numbers, identifiers, and negation survive cleanup byte-for-byte unless the user explicitly selects a transformation that permits otherwise.

## Phase 5: Multilingual output setting

Add one focused setting, defaulting to `Preserve spoken languages`:

- `Preserve spoken languages`: transcribe and clean in place; no translation.
- `Output one language`: the user chooses a target. ASR still runs in transcription mode first, then an explicit, guarded translation/rewriting stage runs after the authoritative transcript is captured.

Do not add a manual language-switch control to the keyboard. The setting belongs in the app and must be visible in diagnostics so test results identify the active mode.

## Phase 6: Typing grammar and prediction

Keep prediction separate from dictation cleanup.

### Typing-time prediction

- Preserve the invisible next-key routing layer: static visuals, separate hit-testing, bounded probability maps, no visual key resizing, and no suggestion UI dependency.
- Add script-aware candidate routing for Latin, CJK, and mixed text. Use recent context as a weighted mixture instead of switching the whole dictionary from one language detector result.
- Expand language support only where a local dictionary/checker is actually available. Unsupported or ambiguous languages must abstain instead of falling back to English.
- Keep prediction work coalesced and off the touch-critical path. Invalidate stale computations on every edit, selection change, host-field change, page transition, and new dictation session.

### Optional post-dictation continuation

- Keep it disabled by default and outside the insertion critical path.
- Show a suggestion only after successful cleanup, never auto-insert it, and require an explicit tap.
- Store the exact transcript/context/selection identity with each suggestion. Reject it if the host text changed.
- Preserve mixed languages and names; do not offer a continuation when language confidence is low or the model would need to translate.

## Phase 7: Performance, diagnostics, and privacy

- Log structured metadata, not audio or transcript content by default: model, region index, language/confidence, duration, chars, load/decode/cleanup latency, memory, and fallback reason.
- Add a debug export that can include opt-in redacted text and hashes for reproducible reports.
- Set budgets for cold model load, warm region decode, cleanup latency, total dictation latency, and peak memory on the oldest supported device.
- Keep all model work local and sequential. Cancel older sessions aggressively and preserve the current background assertion behavior.

## Phase 8: Verification and release gates

1. DictusCore unit tests for segmentation, overlap merging, CJK spacing, language preservation, cleanup guardrails, prediction invalidation, cancellation, and settings migration.
2. App-hosted model tests on identical recorded audio for supported Whisper and Parakeet candidates.
3. Physical-device tests for cold/warm load, short and long recordings, multilingual switching, airplane mode, memory pressure, interruption, and background execution.
4. Full repository tests and normal `sAiity-iOS` Release build.
5. Manual verification of raw transcript, cleaned transcript, and optional prediction as separate states.
6. Only after evidence passes: increment the globally available build number, archive, export, upload to TestFlight, wait for Apple processing, and verify the intended internal group.

## Success metrics

- Default mixed-language preservation >= 99% on protected language/script fixtures.
- No silent replacement of authoritative transcript by cleanup or prediction.
- Protected names/numbers/URLs/units preserved >= 99% on the evaluation corpus.
- No region audio loss or overlap duplication in deterministic tests.
- Warm dictation latency and peak memory remain within the measured device budget.
