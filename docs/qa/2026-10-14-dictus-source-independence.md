# Dictus source replacement checkpoint

## Scope and source status

The user authorized the Dictus-specific replacement after the license inventory. The migration plan is [Dictus source independence](../superpowers/plans/2026-10-14-dictus-source-independence.md). It preserves the existing product, native UI, installed preference/data formats, bundle identifiers, App Group and separately licensed speech/keyboard components.

The baseline is `69bb19af6657e9ba0be5880ef70fab3bd25e4671`, immediately before the original fork commit `593148a2`. The first path comparison found 200 current source files with upstream counterparts. `scripts/audit-dictus-provenance.rb` records path, origin path, SHA-256, size and unchanged/module-only/modified status. It also checks exact-content renamed files and separately bundled `Dictus/Sounds`. The script explicitly does not infer independent authorship from a new path, changed hash or low text overlap.

`/private/tmp/codex-task.q5fqmfwm/artifacts` retains the pre-replacement source diff, untracked-file list, initial inventory and parser self-check. `/private/tmp/codex-task.txjcy12_/artifacts` contains the expanded current inventory: all 29 sound files are byte-identical to upstream. The expanded inventory has 58 unchanged, 48 module-name-only, 154 modified and 123 paths with no matched original path. These are review categories, not counts of legally independent files. No original Git or recovery data was deleted.

The full removal is unfinished. Dictus-derived capture/coordinator, model-management, keyboard/prediction integration, views, widget and resource implementations remain. The root MIT license and in-app Dictus notice are retained. Replacements in this checkpoint have been reviewed against the current behavioral contracts; they are not a legal clearance of their source ancestry.

## Replacement implementation

| Existing owner | Implemented behavior and compatibility |
| --- | --- |
| `AppGroup` | One cached native UserDefaults suite with the existing beta group identity and native container lookup. |
| `DarwinNotificationCenter` | Native CF notification subscriptions have distinct registration identities. A retiring registration cannot remove its successor, and an optional subscriber token permits exact-owner removal. Existing notification names and name-only callers remain compatible. Callbacks execute outside the lock. |
| `GlobeKeyTutorialPage` | Stores its own two subscription tokens, avoids duplicate registrations, and removes only those subscriptions on disappearance. Earlier owners retain their listeners. |
| `KeyboardDictationURL` | Preserves case-insensitive scheme/host, explicit prepare and unknown-intent fallback. Rejects conflicting source parameters, credentials and ports before admission. |
| `DictationSessionLivenessPolicy` | Preserves recording/processing thresholds, startup uncertainty, prior-session heartbeat rejection and clock rollback behavior. Nonfinite shared timestamps remain unproven. |
| `UserDictionary` | Keeps installed keys, counts/timestamps, repetition threshold, Unicode/single-character explicit vocabulary, legacy migration, expiry, pruning, bounded retention and diagnostic consent paths. It salvages valid entries from a malformed map, saturates counts, serializes local mutations and only rewrites pending words when that map changes. One-entry eviction uses a direct minimum selection; imported larger overflow uses bounded sorting. |
| `TranscriptionService` | Retains existing engines, language snapshots, readiness/release APIs and telemetry. Validates cancellation, empty/nonfinite audio and runtime readiness before inference. A revision snapshot rejects results after cancellation, release or runtime replacement, even when an engine ignores cancellation. |
| `AppGroupDiagnostic` | Uses a unique native shared-preference probe per invocation and removes only that probe, preventing concurrent processes from clearing each other's diagnostic values. |
| `PolishAvailabilityGate` | Keeps the two-refusal threshold, per-engine refusal run, process-lifetime blocked engine and distinction between served and unattempted outcomes in a smaller implementation. |

No new production Manager/Service/Factory/Protocol layer, package dependency, model download or recording was introduced. Existing user edits are retained; original storage and wire identifiers deliberately remain compatible.

## Executed checks

- `/private/tmp/codex-task.lsj3l7mi/artifacts/handoff-red.log`: new URL and timestamp cases failed against the old implementation. Existing native notification tests passed before replacement.
- `/private/tmp/codex-task.ksfkuh_a/artifacts/handoff-green.log`: 185 focused handoff, generation, delivery, cold-start, ownership, undo, liveness and app-foundation checks passed.
- `/private/tmp/codex-task.fo6p6230/artifacts`: 1,979 kernel tests with one existing skip plus 41 inference tests passed, zero failures. The compiled production Darwin handoff delivered an exact synthetic Unicode payload across two Mac processes.
- `/private/tmp/codex-task.gnj194ou/artifacts/vocabulary-red.log`: one malformed-map regression failed four assertions; valid words were lost by the old all-or-nothing cast.
- `/private/tmp/codex-task._7nczdqt/artifacts/vocabulary-green.log`: 131 vocabulary, pruning/logging/write-cost, learned-completion, correction and responsiveness checks passed. The follow-up override command omitted required arguments and failed before running its checks; `/private/tmp/codex-task.767zmjef/artifacts/overrides.log` records the corrected passing invocation.
- `/private/tmp/codex-task.8msxd9v9/artifacts/observer-ownership-red.log`: compilation first rejected the absent subscriber-token API. `/private/tmp/codex-task.ayabfpex/artifacts` records 159 passing ownership/vocabulary/app checks and the passing two-process native handoff with token support.
- `/private/tmp/codex-task.5noc_3gt/artifacts/transcription-owner-red.log`: the production owner with synthetic speech doubles admitted empty/nonfinite/unready input and returned results after cancellation/replacement/release. `/private/tmp/codex-task.e1_kp661/artifacts/transcription-owner-green.log` passes those cases, task cancellation, language snapshots and awaited release. This is owner behavior, not real ASR inference.
- `/private/tmp/codex-task.zf0nuexq/artifacts/diagnostic-red.log`: the old diagnostic removed another probe's value. `/private/tmp/codex-task.r0r4j1lz/artifacts/diagnostics-processing.log` records 1,983 shared-kernel tests, one existing skip and zero failures after the diagnostic/processing replacements.
- `/private/tmp/codex-task.72rrft_e/artifacts/kernel-release.log`: final Release package run passed 1,983 kernel plus 41 inference tests, 2,024 total, with one existing skip and zero failures. Test timing output is Mac-only evidence; no phone speed improvement is claimed.

The serial Debug simulator and signed Release app/keyboard/widget builds succeeded in `/private/tmp/codex-task.72rrft_e/artifacts`. Strict Debug signatures pass independently for all three bundles, and the production native app fixture compiled without rendering. The signed Release app is retained at `/private/tmp/codex-task.72rrft_e/artifacts/DictusApp.app`. The build wrapper initially stopped during metadata validation because `codesign --entitlements -` produced its default diagnostic text rather than XML. No build was repeated. `/private/tmp/codex-task.1ngvnhlt/artifacts` contains the corrected `codesign --xml` verification, independent strict Release signatures, bundle/version/minimum-OS/team/App Group checks and the final source inventory. Bundled notice JSON matches the source byte for byte. All three bundles retain 1.0.0 (243), iOS 17.0, team `H8FW6W6K2D` and `group.de.aiity.saiity.ios.beta`. The signed app measures 63,908 KiB with `du -sk`.

The same-bundle development build was installed on the iPhone Air under the user's existing installation authorization. `/private/tmp/codex-task.d9z1dxiv/artifacts` contains the successful installer receipt, independent filtered listing and identity checks. The new bundle URL matches the receipt; App Group identity and container remain unchanged. iOS reported a different application data-container path; private contents and migration were not inspected. The app was not launched or operated, and no uninstall was performed. Prior metadata is retained in `/private/tmp/codex-task.21fd_rjo/artifacts/installed-before.json`.

Source/caller review and `git diff --check` pass. Integration is verified for this checkpoint; the remaining source and physical acceptance steps in the plan remain unchecked.

## Remaining verification

Actual phone typing, intentional spelling overrides, microphone-on haptics, background/cross-app delivery, field/Full Access parity, landscape, PiP/system Live Activity and real-model cancellation/load/memory/accuracy/latency remain separate gates. The four already booted hAiity/Day simulators prevented use of the dedicated sAiity simulator within the two-device limit. None was operated or shut down. Native compilation and Mac process signaling do not prove physical app/keyboard behavior.

No room audio, private transcripts, phone UI operation, permission change, commit, push, upload or release operation ran. Failed/interrupted scratch remains preserved; successful commands retain evidence and clean only their own verified scratch. The existing recovery heartbeat remains active because source and release-readiness gates are incomplete.
