# Dictus source independence implementation plan

**Goal:** Replace the remaining Dictus-derived implementation and resources in the shipped app, keyboard and widget without changing the user's settings, model choices or dictation behavior.

**Architecture:** Keep existing app, keyboard and SyllivraKernel owners. Replace implementation in place from the observable contracts and behavioral tests, using native Apple APIs. Existing third-party speech engines, giellakbd and AOSP resources retain their separate licenses; their removal is outside this Dictus-specific migration.

**Tech stack:** Swift, SwiftUI/UIKit, Foundation/Core Foundation, AVFoundation, ActivityKit, Core ML and the currently pinned speech runtimes.

## Constraints

- Work in the current checkout because the accepted implementation is uncommitted and includes untracked source. Preserve every existing edit and Git recovery record.
- Do not commit, push, upload, publish or modify releases. The user's instruction authorizes implementation and existing same-bundle development installation, not phone UI operation, audio capture or model downloads.
- Keep bundle IDs, `group.de.aiity.saiity.ios.beta`, stored preference keys, URL and notification wire values, iOS 17.0 and 1.0.0 (243) compatible.
- Main owns serial tests/builds/inference. Only `sub2api/gpt-6.1-sol` workers are permitted; that worker override is currently unavailable, so implementation proceeds inline.
- Use `codex-task` for disposable outputs and retain reports/result bundles outside scratch. Reuse pinned package caches. Do not operate another project's simulator or exceed two booted simulators.
- Keep the Dictus MIT notice until the remaining inherited code/data has been replaced and reviewed. A module rename, changed file hash, text-similarity score or passing test does not establish source independence.

## Work and acceptance gates

- [x] **Inventory and recovery baseline.** Run `ruby scripts/audit-dictus-provenance.rb --self-test`, then save its JSON report, the current binary Git diff and existing untracked-file list in task artifacts. Baseline upstream is `69bb19af6657e9ba0be5880ef70fab3bd25e4671`, immediately before the original fork commit. Review binary resources and renamed paths separately from code. The scan includes the separately bundled `Dictus/Sounds` directory. Evidence: `/private/tmp/codex-task.q5fqmfwm/artifacts` and the updated integration inventory.
- [ ] **Shared handoff/storage contracts.** Replace inherited implementations in existing `AppGroup`, Darwin notifications, keyboard URL parsing, result transfer, session identity/liveness and cold-start/ownership policies. Preserve callback fan-out/removal, request identity, cancellation rejection, at-most-once consumption within a live extension and compatibility with pending app/keyboard messages. Preserve result recovery when a host proxy is unavailable; do not claim an atomic transaction across shared preferences and another app's text field. Run their behavioral tests after each replacement and add focused cases where the existing tests leave a real gap.
- [ ] **Preferences, history and model metadata.** Replace inherited implementations of stored settings, history/snippet/vocabulary storage, model catalog/repository rules and diagnostics. Preserve exact keys and Codable formats, explicit opt-outs, migration behavior, redaction, file integrity and last-model protection. Do not substitute unvalidated language/model claims.
- [ ] **Audio and app orchestration.** Replace the inherited recording/transcription, model residency/download and dictation lifecycle implementations inside their existing owners. Preserve preparation-only cold starts, bounded audio, interruptions, foreground/background admission, language identity, cancellation, original-result recovery and model-download atomicity. Native file fixtures must use synthetic or licensed inputs.
- [ ] **Keyboard and widget behavior.** Replace remaining Dictus-owned input/prediction integration, board controls, emoji handling, field policy, delivery/undo and presence/widget logic. Keep giellakbd/AOSP provenance where those independent components remain. Preserve intentional spelling overrides, full-access restrictions, geometry, haptics and native menus. Physical parity remains a separate gate.
- [ ] **App presentation and resources.** Replace any remaining inherited view/StoreKit/setup/diagnostic code that still ships; exclude proven dead code from compilation without discarding user edits. Audit original audio, icons, text catalog and generated resource provenance. Retain independently licensed datasets and their notices; do not declare a transformed original asset independently authored.
- [ ] **Integration and notice decision.** Run the full affected kernel/inference tests, serial Debug simulator and signed Release app/keyboard/widget builds, strict signatures and resource/entitlement checks. Refresh the provenance report and record each reviewed replacement by path/hash and behavioral evidence. Remove the app's Dictus source notice only if no substantial inherited shipped implementation/data remains. Preserve original repository/history attribution and all other applicable notices.

## Verification boundaries

Unit tests and source inventory do not prove physical typing, microphone haptics, cross-app delivery, PiP/system Live Activity, real-model accuracy, latency or memory. Those gates must remain explicit. A safe intermediate build must remain usable and retain required attribution while this migration is unfinished.

## Implemented checkpoint

Replacement implementation is present in the existing `AppGroup`, `AppGroupDiagnostic`, `DarwinNotificationCenter`, `KeyboardDictationURL`, `DictationSessionLivenessPolicy`, `UserDictionary`, `PolishAvailabilityGate` and `TranscriptionService` types. API and installed preference/wire values remain compatible. Onboarding now holds its own notification tokens so leaving the tutorial cannot unregister an earlier owner's listeners.

The native Darwin handoff has passed across two Mac processes with an exact synthetic Unicode payload. New regressions cover ambiguous URL sources/authority, nonfinite timestamps, a malformed vocabulary entry, saturated counters, diagnostic probe ownership and transcription admission/cancellation/runtime replacement. Existing vocabulary migration, expiry, eviction/pruning and spelling override checks pass. These are implementation checks, not a legal clearance of the rewritten paths or a physical keyboard/audio acceptance result.

The remaining unchecked steps above still apply. In particular, inherited capture/coordinator/model-management code, input/prediction integration, views, widgets and resources remain. No license notice may be removed on the basis of this checkpoint alone.

The checkpoint passes 2,024 Release package tests with one existing skip and zero failures, native Mac signaling/owner probes, serial Debug/Release builds and independent strict app/keyboard/widget signatures. Syllivra 1.0.0 (243) is installed in place on the iPhone Air; the app was not launched or operated. Exact artifacts and verification limits are in [the QA checkpoint](../../qa/2026-10-14-dictus-source-independence.md). Resume with the remaining capture/coordinator and shared-policy implementation; keep every current replacement and accepted user edit.
