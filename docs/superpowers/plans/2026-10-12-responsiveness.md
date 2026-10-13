# Keyboard and App Responsiveness Implementation Plan

> Execute inline with `executing-plans`. Main owns serial tests, builds and native checks. Preserve the current dirty checkout and all previous work. Do not commit, push or upload.

**Goal:** Reduce repeated work during typing and dictation, preserve newer suggestions when an older request finishes, and make recent dictations easier to copy.

**Architecture:** Keep the existing prediction queue, request gates, `FrequencyDictionary` and Home view. Index retained frequency words with an ASCII initial by their first byte, keeping their original order within each bucket. Non-ASCII initial characters retain the original canonical Unicode lookup path. Cache only the three normal fallback words; wider requests retain their existing ranking path. Observe actual saved-history data instead of treating every dictation stage as a history change.

**Tech Stack:** Existing Swift/Foundation, SwiftUI/UIKit, native Apple simulator/device tools and public dictionaries. No dependency, new runtime owner or model replacement.

**Status:** Implementation, focused Core checks, signed builds and the authorized development phone update are complete. Native execution of the request-race/history/render probes remains pending: hAiity and Day occupy both permitted simulator slots, so the dedicated sAiity simulator stays shut down. The probes compile against the current artifact. See [evidence and remaining checks](../../qa/2026-10-13-responsiveness.md). No release operation occurred.

## Scope and boundaries

- Work on `cursor/keyboard-surface-fixes-a66e`, HEAD `b696d880`. Preserve the uncommitted processing, native-core and slimming passes.
- Keep iOS 17.0, version/build 1.0.0 (242), current App Group, model/language choices, correction guards, cancellation/request identities, typing/voice haptics and existing key geometry.
- Keep the 10,000-word runtime cap and all source dictionary/audio bytes. The ASCII index adds bounded in-memory arrays of retained words; record their storage and cold-load trade-off.
- No room recording, private-transcript access, permission changes, model downloads, commits, pushes, uploads or publication. Native checks use fabricated text and public dictionary resources.
- Use only the dedicated sAiity QA simulator `3ED8FD55-D525-45D1-9E1A-4A1354000FC0`; keep at most two simulators booted. Do not operate other projects' simulators.
- Previous phone-installation authorization permits the same-bundle development update after checks. It does not authorize microphone or physical interaction QA.

## Task 1: Reduce frequency lookup work

**Files:** `DictusCore/Sources/DictusCore/FrequencyDictionary.swift`, existing `DictusCore/Tests/DictusCoreTests/FrequencyDictionaryTests.swift`.

- [x] Benchmark current compact dictionaries using optimized native Mac code, measuring cold load, repeated `topWords(count: 3)` and `prefixCompletions(prefix:limit:)` separately.
- [x] Check Unicode/case/ranking, arbitrary limits, reload, malformed data, missing resources and value-copy isolation with real public API assertions.
- [x] Build the ASCII-initial buckets from `counts.keys` after a successful load. Filter the matching bucket, then use the unchanged `rankedCompletions` method. Non-ASCII initial characters use the original Unicode path. Cache the same three fallback words once; retain the full path for larger requests. Every failed load resets all derived state.
- [x] Run focused Core checks and the same benchmark. Reject the optimization if the steady-state gain does not justify its measured load/memory cost. Do not equate these component timings with iPhone inference latency.

## Task 2: Preserve newer keyboard requests

**Files:** `DictusKeyboard/TextPrediction/SuggestionState.swift`, existing native prediction probe or a bounded fabricated-input probe under the evidence directory.

- [x] Reproduce the stale deferred-clear failure against the preserved pre-change keyboard artifact. The source identifies the same unguarded path in partial-word and next-word prediction; the new probe exercises both, but its failing-before run stops at the first regression assertion.
- [x] Capture the current `DispatchWorkItem` weakly, as the adaptive prediction path already does. Check cancellation before expensive stages. Guard deferred abstention clears with `suggestionRequestGate.isCurrent(requestToken)`.
- [ ] Verify that an old uncertain request cannot clear newer suggestions or cancel the next request. Preserve protected-field, selected/spoken-language, explicit-vocabulary, rapid-space and undo behavior.

The current native probe compiles, and affected Core/request-gate contracts pass. Executing the final probe requires a free simulator slot; do not mark its runtime assertion passed from compilation alone.

## Task 3: Make Home refresh and actions lighter

**File:** `DictusApp/Views/HomeView.swift`.

- [x] Observe `SharedKeys.recentDictations` as native `@AppStorage` Data. Reload on actual stored-data changes, appearance and foreground entry; remove the coordinator-stage reload and redundant refreshes immediately after edits.
- [x] Put Copy and Share on the two older recent rows as labeled 44-point native buttons. Keep full-text editing available. Reuse the existing copy feedback and clipboard action; remove the one-action menu.
- [x] Retain semantic colors, system typography, current hierarchy, landscape/compact margins, accessibility labels and Dynamic Type. No new animation or visual redesign.
- [ ] Verify fabricated history updates and the current empty/history-disabled behavior without reading personal recordings or transcripts. Render or inspect the changed controls at compact width and large text when the dedicated simulator has a free slot.

## Task 4: Finish verification and handoff

- [x] Run affected Core checks serially: 71 tests in Debug and 71 in Release, zero failures. Compile native keyboard/history/render probes; their execution remains tracked above.
- [x] Build Debug simulator and signed Release device targets. Verify app/keyboard/widget signatures, version/App Group parity and original resource hashes.
- [x] Install the checked development update through the existing same-bundle path and confirm its new version/location in filtered device inventory.
- [x] Record exact measurements, regression evidence, warnings and any unverified simulator/physical/model gates. Keep the previous recovery heartbeat state and release artifacts intact.

## Design rationale

Keep the app's quiet dictation-first hierarchy, semantic surfaces and SF controls. The change makes an existing frequent action direct; it does not add another navigation layer. Apple guidance used here: `feedback.md › Best practices` recommends integrating feedback into the interface; `motion.md › Providing feedback` advises avoiding added motion on frequent interactions; `accessibility.md › Mobility` recommends 44-point controls; `virtual-keyboards.md › Best practices` requires matching the field's task. Existing field policy, hit targets and haptic paths are retained.

Larger model-runtime rewrites belong to the unfinished first-party-core plan. Lowering accuracy safeguards, rewriting the visual keyboard, and adding new runtime/service abstractions do not address the measured repeated work in this pass.
