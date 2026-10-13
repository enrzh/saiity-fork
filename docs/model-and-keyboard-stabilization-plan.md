# Model and keyboard stabilization plan

## Objective

Make dictation, cleanup, prediction and keyboard interactions reliable, with
reproducible evidence. Prioritize fixing current failures over expanding the
model catalog. Finish with one verified TestFlight candidate.

This document is a plan, not evidence that its tasks are implemented. Reinspect
the repository before starting: it contains extensive existing changes, and
build numbers and release state may have advanced.

## Working rules

- Read repository and parent AGENTS.md and the Ponytail skill. Preserve all
  uncommitted/untracked work; do not reset or broadly rewrite the checkout.
- Inspect existing implementations and tests before adding replacements.
- Use ego-browser for websites. Use only Sub2API Luna for subagents; if that
  model is unavailable, work in the main task instead of substituting another.
- Keep inference local by default. No new cloud dependency, account requirement,
  model download, or external upload of diagnostic text without explicit need
  and authorization. Existing optional remote cleanup integrations remain optional.
- Keep ASR inference sequential and reuse loaded models. Preserve cancellation,
  background execution, session ownership, timeout and error-delivery behavior.
- Report source checks, automated tests, simulator behavior, device behavior,
  archive/export, upload and TestFlight readiness as separate verification gates.
- Do not claim accuracy or speed improvements without comparative measurements.

## 1. Establish a reproducible baseline

Inspect Git status, branch/HEAD, local instructions, recent changes and existing
release notes. Identify active work to avoid duplication. Inventory current
model identifiers, runtime versions, settings and regression coverage.

Run the current Core tests and supported app build. Record existing failures
separately from regressions introduced by this work. Identify an available
physical iPhone and an authorized, fixed audio corpus. Continue independent
work if device access is unavailable, but leave device gates explicitly open.

Deliverable: a short baseline report with device/runtime details, test/build
results and a checklist updated with evidence as each phase progresses.

## 2. Resolve Qwen loading on device

Trace download, cache validation, compilation, loading, activation and inference
end to end. Reproduce the reported failure before choosing a fix. Capture error
domain/code/underlying errors, artifact variant, failing stage, elapsed time and
available memory without logging dictated text by default.

Verify both f32 and int8 variants, including incomplete downloads, cancellation,
retry, cold activation and subsequent warm dictation. Keep repair downloads in
the visible Models workflow with progress and cancellation. Avoid loading a
validation engine and active engine simultaneously.

Acceptance:

- Both variants either successfully load and transcribe on the target device or
  have a demonstrated compatibility limitation with accurate user-facing state.
- Unsupported variants are not presented as working/recommended alternatives.
- Repair recovers the reproduced repairable failure; cancellation never marks a
  partial model ready or leaves the microphone/session stuck.
- Record actual device evidence. Passing a cache-policy test is insufficient.

## 3. Benchmark dictation quality and performance

Reuse `docs/asr-model-evaluation.md` and the existing scorer/fixtures. Build only
the missing capture path needed for reproducibility. Run identical authorized
16 kHz mono recordings through suitable existing models, one at a time.

Cover German, English, Mandarin, mixed-language switches with and without
silence, names, numbers, negation, quiet speech, background noise and no speech.
Use real recorded speech for quality comparisons; synthetic speech may be a
separately labelled smoke test. Do not treat text fixtures as recorded evidence.

Record model/artifact/runtime revisions, audio hashes, device/OS, load failures,
cold load time, at least three warm runs, decode latency, audio duration and
memory measurement method. Report WER/CER separately and retain failed cases.

Acceptance: a comparison on identical audio identifies supported tradeoffs.
Change model recommendations or decoding policy only where results justify it.
Do not advertise Parakeet as supporting Chinese or arbitrary code switching.

## 4. Improve cleanup preservation and usefulness

Review the existing Auto prompt, preprocessing, postprocessing and guardrails.
Preserve the explicit instruction that mixed-language spans remain in their
original language. Explicit translation is a separate user choice.

Extend tests with both beneficial and harmful edits: punctuation, grammar,
numeric formatting, self-corrections, names, identifiers, units, negation,
lists and mixed Latin/CJK text. Measure false rejections as well as harmful
acceptances. Tighten or relax heuristics only against these cases; regex checks
are not proof of semantic equivalence.

Preserve the authoritative raw transcript and provide an explicit revert action
where needed. Test engine failure, unavailable models, cancellation, truncated
responses and timeouts. Benchmark available cleanup engines before claiming one
is faster; do not add speculative model entries without a functioning runtime.

Acceptance: useful edits survive, known harmful edits fall back safely, and
raw text remains recoverable. Runtime evaluations distinguish successful model
output from deterministic fallback. Unavailable Apple models remain a blocker
for Apple-specific runtime claims, not a reason to report simulated success.

## 5. Improve optional prediction and swipe typing

Prediction must remain default-off, local and explicitly accepted. Match the
dictionary to actual text context and the requested output behavior. Do not
feed foreign-language context into another dictionary merely because it is the
selected keyboard language. Abstain on unsupported or ambiguous input.

Verify stale document/context, selection, edits, page changes, dismissal, new
dictation and preference changes. Keep expensive analysis off the insertion
critical path without introducing races in shared dictionary state.

For swipe typing, inspect the existing decoder and touch path. Add bounded
spatial scoring and repeated-letter handling using existing vocabulary and
geometry where possible. Test deliberate taps versus swipes, noisy paths,
layout variants, ambiguous paths and correction/undo behavior.

Acceptance: no silent replacement by post-dictation prediction; no stale inserts;
unsupported languages abstain; swipe decoding improves on a fixed path corpus.
Measure keyboard latency and memory rather than claiming native parity.

## 6. Stabilize keyboard interactions

Use a repeatable simulator/device matrix covering all pages and relevant layouts:

- Fast alternating/multitouch typing and transitions between taps and holds.
- Hold-to-dictate, app handoff, enabled/disabled dictation and interruptions.
- Delete tap, repeat timing, acceleration and release/cancellation.
- Spacebar cursor dragging with continued movement at either edge.
- Emoji scrolling from an emoji cell, category synchronization, recents and
  skin-tone selection without lost holds or clipped rows.
- Keyboard dismissal in one tap, touch-target alignment and stable page height.

Test several available host apps, including a secure field. Explain iOS-enforced
system keyboard fallback where applicable; do not promise to override it.
Fix shared gesture/layout causes rather than adding per-page workarounds.

Acceptance: record each scenario's result, device/OS and remaining limitation.
Source-string tests alone do not establish that touch interactions work.

## 7. Add an opt-in last-dictation issue report

Reuse existing diagnostics and transcript/undo state. Offer an explicit action
to review raw versus cleaned text, selected model, output mode, timings and
failure stage. Let the user omit text and preview the exact export before using
the native share sheet. Never send automatically or add persistent transcript
history as an incidental implementation detail.

Acceptance: report export is useful without transcript text; no credentials or
unrelated logs are included; text inclusion is explicit; retention is bounded
and documented. Add redaction/export tests and verify the share flow on device.

## 8. Verification and release

Run the existing Core tests and the repository's supported app build after
integration. Keep required dependency patches consistent with the actual build
directory. Run proportionate device regressions from the matrix above.

Prepare manageable reviewed change groups and release notes; do not stage or
commit unrelated existing work. Follow current user authorization for Git
commits/pushes and CI; this plan does not override an instruction to skip CI.

Before release, check the latest accepted build number live. Archive and export
with matching app/keyboard/widget versions. Upload through the authorized flow
and verify Apple processing and internal TestFlight readiness separately. Do
not call an uploaded package ready for testers until that state is confirmed.

Final report: changes, measured results, tests/build, device matrix, artifact
and build number, distribution state, and unresolved limitations. If device or
account access blocks completion, state exactly what is required. Do not mark
the whole plan complete or delete its completion monitor while gates remain open.

## Implementation progress — 2026-09-14

Ponytail skill was not found on this Mac mini. Sub2API Luna MCP is unavailable
(live tool discovery failed). Work continued in the main task. ego-browser remains
the website path for TestFlight confirmation.

Checkout: dirty `saiity-fork` at `0d578fa0`. Existing uncommitted keyboard, Qwen,
cleanup, ASR-eval, and prediction work was preserved. Marketing version 1.0.0,
accepted TestFlight build at inspect time: **103**. Next uniquely numbered build
is **104** after source verification.

No physical iPhone is connected (`devicectl` lists only simulators). No authorized
16 kHz mono corpus is present. Device, Qwen-runtime, ASR-benchmark, keyboard
touch-interaction, and TestFlight-internal-availability gates stay open until
those exist.

### 1. Baseline

- Git: `saiity-fork` / `0d578fa0`, heavily dirty; stash empty.
- Models in `ModelInfo.redesignCatalog`: Whisper tiny/base/small/medium (+en and
  compact/turbo variants), Parakeet v2/v3, Qwen3-ASR 0.6B f32/int8. Qwen is never
  the recommended identifier. Default new install remains `openai_whisper-tiny`.
- Core tests (scratch `/tmp/dictus-core-baseline`, mixed with in-progress edits):
  1561 tests, 1 skip (`DICTUS_ASR_RESULTS` unset). Pre-existing failures recorded
  separately: `QWERTZLayoutTests.testEszettIsReachableByLongPressOnS` (stale exact
  `["ß"]` after the 103 accent expansion; updated to require ß without forbidding
  ś/š) and `UserDictionaryLoggingTests` against the shared host `dictus_debug.log`
  (not introduced by this work; left in place).
- Connected hardware: none. Simulators present, including iPhone 17
  `D04DF9A7-2D66-4FB4-A4D9-1251993C0ED3`.

### 2. Qwen loading

Existing `QwenArtifactPolicy` + `Qwen3AsrEngine` cache validation, package
fallback recompile, cancellation, and non-transcript diagnostics were kept.
Added `canMarkReady` so cancellation/incomplete caches cannot be marked ready,
package-fallback/diagnostic tests, and ModelManager cancellation handling that
never appends the identifier to `downloadedModels`. Catalog copy now says device
load is not verified; Qwen is not recommended.

**Open:** f32/int8 load + transcribe on a physical iPhone. Cache-policy tests are
not device evidence.

### 3. ASR benchmark

`ASREvaluation` is now the capture schema/scorer (`emptyRun` / `validate` /
`score`). Fixtures remain text prompts. `testScoreCapturedRun` still skips
without `DICTUS_ASR_RESULTS`. Parakeet v3 templates exclude Chinese fixtures.

**Open:** identical recorded 16 kHz mono files, hashes, cold/warm device timings.

### 4. Cleanup preservation

Auto prompt already keeps mixed-language spans in their original language.
`skipsModelPolish` for multilingual Auto was already wired. Extended fact and
structure tests plus harness fixtures (units, identifiers, lists, self-correction).
Raw transcript is stored in the last-dictation snapshot for explicit revert/copy.

**Open:** live Apple FM / Ollama runtime eval (previously `modelNotReady` / no
Ollama). Regex/guardrail tests are not semantic equivalence.

### 5. Prediction and swipe

Prediction remains default-off (`SharedKeys.postDictationSuggestionsEnabled`).
Swipe decoder gained dwell-based repeated letters and spatial ranking on a fixed
QWERTY path corpus. Letter-page swipe is **not** re-enabled: build 103 removed it
so hold-for-accents works; `swipeWord` remains on `TextPredictionEngine` only.
This is a documented conflict with plan wording "keep swipe on the letter page".

**Open:** keyboard latency/memory on device; swipe quality vs native.

### 6. Keyboard interactions

103 layout/haptic/emoji/language-chip source contracts remain. Added a regression
that the letter page does not call `SwipeTypingDecoder` and Settings hosts the
issue-report view.

**Open:** simulator/device touch matrix in host apps, including a secure field.

### 7. Last-dictation issue report

`LastDictationIssueReport` stores one overwritten snapshot (raw/cleaned, model,
output mode, timings, failure stage). Settings → Troubleshooting → Report last
dictation previews the exact JSON, defaults to omitting transcript text, and
shares through the native share sheet. Copy-raw is gated on the include-text
toggle. Not sent automatically. Redaction/export tests cover omit-text and
bounded retention.

**Open:** share-sheet verification on a physical iPhone.

### 8. Verification / TestFlight

- DictusCore (scratch `/tmp/dictus-core-stabilization`, `--skip UserDictionaryLoggingTests`):
  1565 tests, 1 skip (`DICTUS_ASR_RESULTS` unset), 0 failures. The skipped
  UserDictionary host-log suite is a pre-existing App Group log-file issue, not
  introduced here.
- Debug `sAiity-iOS` for iPhone 17 simulator produced `DictusApp.app` with
  CFBundleVersion 104.
- Release archive `/tmp/sAiity-build-104.xcarchive`: app, keyboard, and widget
  all report 1.0.0 (104).
- IPA `/tmp/sAiity-export-104/DictusApp.ipa`
  SHA-256 `e0dbf417fe3d7c81e85ef77562730781883b6b40eb3f48d802c1a6bd66604bc7`.
- App Store Connect upload succeeded 2026-09-14 21:48 local. Apple reported
  “Uploaded package is processing.”
- Confirmed in App Store Connect after sign-in (ego-browser, ~21:52 local):
  Build Uploads **1.0.0 (104) Complete**; Version 1.0.0 row **Ready to Submit**
  with **IN Internal**; build detail has Internal group + 1 tester and no
  Missing Compliance. Internal testers can install this build.

Device, recorded-audio corpus, and Qwen-on-iPhone gates remain open. Do not
treat compilation as device-quality evidence.

