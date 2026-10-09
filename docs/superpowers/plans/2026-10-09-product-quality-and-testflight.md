# sAiity product quality and TestFlight plan

**Goal:** Make private multilingual dictation dependable and approachable, then prepare a signed, reviewable beta candidate with honest verification evidence.

**Architecture:** Keep the app, keyboard, shared Core package and widget extension. Fix behavior in their current owners, reuse native controls and existing policies, and remove duplicate presentation where it serves the same job. Do not add speculative managers, services, protocols or a second keyboard architecture.

**Baseline:** October 9, 2026; `/Users/enrico/Documents/GitHub/sAiity-dictus`, source build 239, HEAD `6605e9dd`. Initial checkout clean. Whisper/Parakeet remain keyboard-compatible paths; Qwen stays foreground-only. The October 7 keyboard and multilingual typing work is present.

## Scope and authority

The user requested a whole-product function/design audit, then authorized implementation and local TestFlight preparation. A later message requested a concrete plan and `sub2api/gpt-6.1-sol` review agents; this document supplies the plan before implementation. Review workers use that exact model with Ultra reasoning. Luna is prohibited.

- Preserve existing files, preferences, models, recordings and Git recovery state.
- No commit, push, TestFlight upload, release publication, tester invitation or external message is authorized here.
- A prepared archive, an exported IPA, Apple upload acceptance, processing and tester availability are separate states.
- Never record room audio. Automated recognition work needs licensed or explicitly consented audio files; no model downloads during UI QA.
- Use SimSlim when available, a dedicated sAiity simulator, and no more than two booted simulators across the machine. Do not use hAiity's simulator or Xcode DeviceHub. Physical iPhone use needs explicit user direction.
- Websites use ego-browser only. The runtime is currently absent from this MacBook; live support/privacy pages and App Store Connect remain unverified until it is restored.
- Change core logic with a behavior regression; routine copy/layout changes need proportionate render/accessibility checks, not tests that merely freeze strings.

## Recommendation and alternatives

Choose a reliability-first product pass. Users should open sAiity, see one useful next action, speak, get faithful text and recover safely. The recognizable keyboard stays quiet; the voice mark and recording state carry the brand.

A further visual redesign would postpone the unmeasured device behavior without fixing it. More engines, cloud features or speculative abstraction would expand setup and failure paths before the existing ones have a quality baseline. Neither is the next beta's priority.

## What the inspection establishes

| Area | Evidence | Implication |
| --- | --- | --- |
| Privacy | `PRIVACY.md` promises no HTTP, no clipboard access and no transcript-bearing logs. Model downloads, optional Ollama cleanup, explicit Paste and opted-in diagnostics are reachable. | Correct the shipped explanation before asking people to trust it. |
| Setup | `OnboardingView` requires availability before Try; `MicPermissionPage` auto-advances after permission. Availability opens a full-screen loading cover. | Let people defer setup, keep download progress/cancel reachable, and avoid timed advancement. |
| Voice controls | `VoiceOptionsView`, Settings Dictation and Models each contain engine/model choices plus the advisor. | Put everyday language/voice options first; disclose specific model choices once in the context that needs them. |
| Keyboard | One native grid, shared bottom owner, opaque plates and multilingual exact-word maps already exist. | Retain geometry and visual direction; fix measured input behavior rather than restyling again. |
| Typing capability | Twelve layout languages exist, but bundled correction dictionaries are EN/FR/DE/ES. | Keep layouts, distinguish correction support, and preserve words outside the supported dictionaries. |
| Recovery | A new controller registers before becoming the shared insertion target; delivery lacks an originating-document check. | Bind a session to its starting field and capture the usable target before consuming. |
| Text fidelity | Time-only clause deduplication drops distinct events. Segment rejoining splits decimals, times and addresses. | Preserve facts before cleanup and keep Original faithful to recognition. |
| Typing | A prepared correction can delete a punctuation-bearing suffix; dictionary loading can remount an obsolete language after a newer failure. | Validate the live replacement suffix and serialize load/unload, including failures. |
| Models | Whisper accepts empty compiled-model folders; repository-root receipts collide between variants. Delegate cancellation can arrive before task registration. | Check per-variant artifacts offline and honor cancellation at registration. |
| Local data | History-off preserves saved entries by design. Older consented diagnostic text is retained until Clear, which may be disabled when recent count is zero. | Keep saved history intact; make diagnostic Clear reachable and clear both current and legacy files. |
| Monetization | Premium UI is disabled; no new entitlement problem was established. | Keep the beta free of unfinished paywalls and pricing claims. |
| Verification | The existing corpus has reference text and pending outcomes, not an acoustic benchmark. | No accuracy, battery or physical latency claim follows from unit/simulator success. |
| Build | Fresh package resolution and a simulator build succeed; Core baseline has one outdated copy assertion. | Restore the current verification gate, then archive the final source. |

These are source conclusions, not a claim that every iPhone interaction was observed. Independent review findings are checked against their connected callers before implementation; an uncertainty is a test gate, not automatically a bug.

## Work packages for this candidate

Checked boxes record implementation in source. Physical and online acceptance gates remain open as listed in the candidate readiness note.

### 1. Truthful privacy, support and product documentation

**Files:** `PRIVACY.md`, `README.md`, current section of `PRD.md`, `DictusApp/Views/SettingsView.swift`, `DictusApp/Views/AddCustomModelView.swift`, existing license/privacy UI.

- [x] Explain that speech recognition is on-device, model installation uses the network, and remote cleanup sends text only when that endpoint is explicitly chosen.
- [x] Explain Full Access as the shared app/keyboard connection; microphone permission and capture belong to the containing app. Do not promise microphone capture inside the extension.
- [x] Disclose explicit Paste, optional saved history, vocabulary, temporary replay and opted-in diagnostics accurately. Replace source-project contact/name claims with sAiity support information.
- [x] Use a project-specific support destination. Keep attribution/legal notices in About.
- [x] Keep required-reason manifests consistent with actual use.
- [ ] Verify the online privacy policy and App Store labels separately before publication.

**Acceptance:** Every network/data-bearing path named in the review has an accurate explanation. Core privacy checks and final archive manifests are inspected. No website is published by changing this repository.

### 2. Reachable, honest diagnostic controls

**Files:** `DictusCore/Sources/DictusCore/Polish/PolishMetricsRing.swift`, `DictusApp/Polish/PolishCoordinator.swift`, `DictusApp/Polish/PolishDebugView.swift`, existing ring/privacy tests.

- [x] Keep metadata useful while transcript collection is off by default.
- [x] Restore access to the existing diagnostic screen under advanced settings. Explain that disabling text collection affects new records and existing consented records remain until Clear.
- [x] Let explicit Clear run even when the recent seven-day count is zero, and remove current and legacy diagnostic files through the existing actor. Surface disk failures.
- [x] Keep previously saved dictation history unless the user chooses Clear. Explain history-off and diagnostic consent as separate decisions.
- [x] Verify queued writes and cold restart cannot resurrect explicitly cleared diagnostic records.
- [x] Keep export a user action; inspect disk and exported bytes, not just formatted log strings.

**Acceptance:** Real temporary-directory regressions cover current and older/legacy records, Clear, cold restart and write failures. Explicit history remains intact. No actual phone data is scrubbed during QA.

### 3. A short, recoverable first-use flow

**Files:** `DictusApp/Onboarding/OnboardingView.swift`, `MicPermissionPage.swift`, `KeyboardSetupPage.swift`, existing onboarding policy tests and render fixtures.

- [x] Add a clearly named setup-later route; it stops automatic keyboard standby and lands in an honest not-ready app state.
- [x] Let users move backwards through setup without resetting selections or downloads.
- [x] Advance microphone permission through a user's Continue action, including denied/return-from-Settings states.
- [x] Keep model install/preparation inline and cancellable where current ownership allows it; downloading does not erase the setup or language choices.
- [x] Preserve the silent PiP guide and real Full Access handshake. Do not replace iOS Settings verification with an assumed success flag.

**Acceptance:** App-only and keyboard paths work with granted, denied and not-yet-requested permissions; setup can be deferred without microphone capture. Cold restart resumes the current stage. Canceled installation stays resumable and never claims Ready from partial files.

### 4. Everyday voice options, without a model dashboard

**Files:** `DictusApp/Views/HomeView.swift`, `SettingsView.swift`, `KeyboardModePicker.swift`, `ModelManagerView.swift`, current rendering fixture.

- [x] Keep Speak to one truthful readiness summary, a recording action, recent text, keyboard power and a compact voice-options entry.
- [x] Lead voice options with spoken languages and the advisor. Keep Streaming/Whisper and independent Realtime text reachable.
- [x] Move specific app/keyboard model picks behind an explicit model-choice disclosure and preserve pending/manual choices. Full catalog, size/storage, retry and delete belong in Models.
- [x] Explain that advisor Apply changes model routing, not writing style, languages or recording. Show what will actually run from installed artifacts rather than a generic device badge.
- [x] Keep Writing style/output/cleanup in Dictation settings; advanced server and diagnostics remain secondary.

**Acceptance:** Current method/languages/readiness are understandable without opening the full model catalog. Apply never downloads or records, choices persist through restart, and every failure leaves a relevant action. Check native compact/large type, light/dark and disabled-during-finalization states.

### 5. Text fidelity, session cancellation and safe delivery

**Files:** existing keyboard controller/state and delivery owners, `PolishPostpass.swift`, `SpeechRegionSegmentation.swift`, `DictationCoordinator.swift`, existing recovery/cleanup/segmentation tests and native scripts.

- [x] Set the current controller before registration can consume a result. Pin a session's originating document identity, capture the insertion target before consuming and preserve recoverable text when the target differs. Keep the nullable UIKit identity shim and request/generation guards.
- [x] Remove time-only restatement deduplication: a call and a meeting at the same time must both survive, including with cleanup off.
- [x] Preserve decimals, clock times, email addresses and URLs through the real segment merge entry, including overlaps.
- [x] Check cancellation/session generation immediately after recognition/translation awaits and before shared cleanup, so a canceled session cannot cancel a newer session's cleanup.
- [x] End empty recognition promptly as No speech detected, release recording state and allow another attempt.
- [x] Test repeated ready notifications, keyboard replacement, cancel, field change and a detached host. Failure must leave either the pending delivery or existing recoverable original/result accessible.
- [x] Keep original/result/edit/copy/retry near delivered text. Reopening a finished or failed recording view must reconstruct its state from the coordinator instead of showing an empty listening placeholder.
- [x] Treat iOS's lack of an atomic transaction with another app's text proxy honestly. Never claim exactly-once delivery across process death.

**Acceptance:** Native delivery checks demonstrate no wrong-field deletion, no duplicate result, no late canceled insertion and no deliberate consumption with no usable target. Actual host-app background delivery remains a phone gate.

### 6. Typing and multilingual fidelity

**Files:** existing `TextPredictionEngine.swift`, `AOSPTrieEngine.swift`, `SuggestionState.swift`, native bridge, `KeyboardViewController.swift`, multilingual/native input scripts and related Core tests.

- [x] Preserve exact words only from the selected keyboard and explicitly configured, bundled dictionaries. Keep corrections in the selected language for mixed text.
- [x] Measure initial mounting and repeated context work. Keep disk/mapping work away from key delivery and preserve the bridge read/load mutex.
- [x] Close demonstrated stale-load/readiness races without adding another prediction layer; verify rapid language changes and changed spoken-language membership.
- [x] Validate live suffix/boundary before autocorrect or snippet deletion; preserve punctuation and Unicode normalization on mismatches.
- [x] Learn only words absent from the enabled dictionaries, carrying the existing background unknown-word result into prepared Space commits. Keep unknown multilingual learning with autocorrect off and secure-field exclusion.
- [x] Move initial dictionary/frequency loading onto the existing suggestion queue; abstain until ready instead of doing disk work during controller creation.
- [x] Recheck Space, cursor, Delete repeat, overlapping fingers, key variants and empty-emoji swipes on the one native owner.
- [x] Say which layout languages have correction dictionaries; do not remove valid layouts to conceal a missing dictionary.

**Acceptance:** Existing bilingual fixtures, bridge sanitizers and input harness pass. Current warm Space stays non-blocking. Phone haptics/typing feel and retained memory are separate observations.

Exact-word protection also accepts valid words in the active dictionary before old accent/contraction overrides. That is the user's requested rule. Do not reverse it to restore old `lai`/`lest` replacements; French-only `tres` may still expand while an enabled exact match protects it.

### 6a. Installed-model integrity and download cancellation

**Files:** `WhisperModelRepository.swift`, `ModelRepoDownloader.swift`, `ModelManager.swift`, existing model integrity/cancellation tests.

- [x] Store/check a receipt for each Whisper variant rather than overwrite a shared repository-root receipt.
- [x] Validate required model files and sizes before Ready. Legitimate older installs without a receipt may pass structural validation; empty or truncated folders may not.
- [x] Preserve independent readiness for two installed variants offline: corruption of one must not hide the other.
- [x] Store cancellation under the delegate's existing lock and honor it before task registration/resume. Normalize network cancellation as cancellation, without a false failure alert or selection changes.

**Acceptance:** Behavioral fixtures cover two variants, truncation/empty directories, legacy structural installs, cancel-before-registration and cancellation during work. No QA model download is needed.

### 7. Accessibility and visual consistency

**Files:** existing app/keyboard faces and page bodies, rendering scripts, `DictusWidgets/DictusLiveActivity.swift`.

- [x] Retain semantic opaque keys, 8pt character/12pt command corners, blank Space, wordless hold icon and the large state-colored dictation action.
- [x] Make inline models/settings/result content wrap at the largest text size, with 44pt primary actions and labelled icons. Preserve reduced motion/transparency and increased contrast behavior.
- [x] Replace stale or technical explanatory copy, including unsupported control claims, generic support and “faint backgrounds” after opaque plates became the default.
- [x] Inspect ready/loading/listening/cancel/error/off visual states, not just a pretty idle screen. Keep the candidate strip off.

**Acceptance:** Fresh light/dark and normal/maximum-text production-view renders are inspected. Static contrast measurements remain limited to their sampled surfaces. Real Live Activity/Island and PiP rendering are phone gates.

### 8. Tests, evidence and a reproducible beta cut

**Files:** existing Core tests, native scripts, `.github/workflows/ci.yml`, `ci_scripts/`, `README.md`, this plan and a candidate-readiness note under `docs/`.

- [x] Repair the baseline source assertion for the actual current language explanation; favor behavioral tests for new safety logic.
- [x] Run Core, targeted delivery/diagnostic/language regressions and available native checks. Record command, source revision, result and artifact paths.
- [x] Keep the current SwiftPM/runtime pins and documented FluidAudio Swift-5 compatibility step. Build app+keyboard+widget together with one Xcode operation at a time.
- [x] Produce a signed archive and distribution-signed local IPA with an export destination, using reviewed build/version parity. Do not use the existing upload-only export options for preparation.
- [x] Verify bundle IDs, embedded extension signatures, entitlements, privacy resources, licensed runtime notices and device/OS support in the artifact.
- [x] Record candidate changes and known limitations in tester notes; confirm the next unused build number and Apple processing only when upload is separately authorized.

**Acceptance:** Tests/build/archive/export are recorded as distinct checks. An IPA is not labelled uploaded or installable. A signing/tooling block is reported with its exact cause; retries need changed evidence.

## Quality work after the local candidate

The biggest remaining improvement is measured quality, not another interface overhaul.

1. Run the existing 40-case multilingual corpus with consented/licensed audio. Compare raw ASR with cleaned text for facts, negation, unfinished speech, names and Chinese/English/German mixing. Keep failures/silence hallucinations in the denominator.
2. Measure cold preparation and warm release-to-insertion p50/p95 separately; at least 20 insertions per group. Record model, revision, phone, thermal state, foreground/background and cleanup setting. No synthetic simulator number becomes a phone claim.
3. Run a seven-day beta with 5–10 explicitly approved volunteers. Track first successful dictation, results usable unchanged, switches back to the system keyboard and reasons, recovery failures and battery complaints. Invite nobody automatically.
4. Make device recommendations from those outcomes. Existing catalog speed/accuracy scores are estimates, not advertising measurements. Keep Qwen's foreground limitation visible.
5. Only then choose further product features. Prefer context-relevant vocabulary, conservative self-correction and better recovery over more modes. Offline/local remains a user-controlled processing choice, with optional server processing accurately disclosed.

## Design rules for execution

Use the existing system typography, semantic backgrounds and accessible `saiityAction`/`saiityOnAction` colors. Neutral controls and content carry the interface; the blue voice mark identifies recording, and red means Cancel. Existing grouped lists and native disclosures keep Models/Settings readable. No new gradients, hero metrics, pricing cards or generated aesthetic.

Apple Design references read for this review: accessibility/typography (legibility and Dynamic Type), layout (progressive disclosure), settings (“Minimize the number of settings you offer”), onboarding (teach through use and postpone nonessential setup), materials (“Use Liquid Glass effects sparingly”), buttons (purpose and press state), virtual keyboards (familiar switching), Live Activities and generative AI (truthful progress and reversible results).

## Checkpoint and completion monitor

- [x] Whole-product source map and first independent audit completed.
- [x] Exact `sub2api/gpt-6.1-sol`/Ultra routing verified for replacement review workers.
- [x] Recurring same-chat check active every 30 minutes: `check-saiity-product-completion`.
- [x] Baseline package resolution and simulator compilation checked; one outdated Core copy assertion recorded.
- [x] Independent findings reconciled and current-candidate changes implemented.
- [x] Final tests and visual/native checks recorded.
- [x] Signed archive and local IPA exported and verified.
- [x] Online/phone/Apple gates explicitly recorded without claiming success.
- [ ] Completion monitor deleted when all accepted gates close; pause and explain only if deletion is unavailable.

Current tooling: this MacBook has Xcode 27.0, correct beta signing profiles, and AXe 1.8.0. The dedicated sAiity QA simulator is available; hAiity's simulator is out of scope. SimSlim and ego-browser remain unavailable. No phone has been operated in this review.

### October 9 implementation checkpoint

- Current local source is `1.0.0 (240)` on the existing feature branch; no commit, push or upload. Build 240's availability/uniqueness in App Store Connect is unverified.
- The three requested Sol/Ultra implementation workers returned provider HTTP 503 before any edit and were closed. Main-agent local work continued; no Luna or substitute workers were used.
- Implemented: distinct-event preservation in deterministic cleanup, prompts and fact guardrails; internal numeric/address punctuation in segment merging; originating-field delivery and current-controller ordering; recognition/translation cancellation gates and immediate no-speech completion; prepared-Space suffix validation, known-word learning exclusion and deferred dictionary startup; serialized trie teardown; independent Whisper receipts/structural validation and download cancellation; reachable diagnostic Clear with queued-event and disk-failure handling; setup defer/back/inline cancel; voice-option disclosure; reopened result restoration; truthful privacy/support copy and app/keyboard/widget manifests.
- Core final run: **1,915 tests, one existing skip, zero failures**. Focused native downloader and production typing regressions pass. The stale-loader regression also failed against the baseline loader before passing; interrupted publication, legacy missing weights/invalid configuration and decimal commas have RED/GREEN evidence.
- Scratch evidence: `/tmp/saiity-product-review.H68Ksv`, including RED/GREEN logs, builds, native scripts, native app checks and production-view renders. Final artifacts and remaining gates are recorded in [the candidate readiness note](../../testflight-240-readiness.md).
- A dedicated sAiity QA simulator was created because none was migrated: `3ED8FD55-D525-45D1-9E1A-4A1354000FC0` (iPhone 17 Pro, iOS 26.5). Native harnesses use `simctl`; AXe was restored for actual app touches. hAiity's simulator is untouched and no more than two simulators were booted. No phone, room audio or voice-model download was used.
- The initial wildcard-profile signing block was resolved by Xcode automatic provisioning of the beta profiles. The final archive and local App Store export succeeded, with strict signature/version/App Group/privacy/license verification. Archive signing is Apple Development; the IPA is Apple Distribution signed. No upload occurred.

## Execution order

Fix text fidelity, delivery, cancellation and model integrity first, then truth/privacy and setup/voice-option clarity. Run the native/visual matrix after the final source, prepare the signed candidate, and close only the gates that have actual evidence. Broader restructuring, new dependencies, new cloud services, unconsented audio collection and unfinished monetization are outside this pass.
