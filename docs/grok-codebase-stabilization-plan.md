# sAiity: codebase stabilization handoff for Grok

Date: 2026-09-22. Status: review and implementation plan, not implemented.

## Baseline and scope

Repository: `/Users/enricomini/Documents/Github/sAiity-dictus`.
Branch: `cursor/keyboard-surface-fixes-a66e`.
HEAD: `e275e1a1ec3a231ef34384a77a82a2be7c599e99` plus existing dirty changes.
Current local app, keyboard, widgets and project build metadata: 149.

This review covers the main application, keyboard, shared Core, audio/model and
cleanup pipeline, widgets, onboarding, persistence, verification and distribution
paths. Three Luna reviewers inspect separate areas. This is a broad static review,
not a claim that every line or physical-device behavior has been verified.
File line numbers below describe this snapshot and may move.

Preserve all existing modified and untracked files. Do not reset, clean, stash,
revert, commit, push, install or upload as part of this handoff unless separately
authorized. In particular preserve `docs/keyboard-feel-plan.md`,
`.superpowers/brainstorm/`, `graphify-out/` and `Dictus.xcodeproj/-Xcc/`.

Read repository and parent AGENTS.md. Some inherited documentation describes the
upstream Dictus app, old app groups and a clean `develop` release workflow. Resolve
current identity from project settings and entitlements instead. Preserve sAiity
branding and required third-party license notices.

## Product constraints

- No Qwen reintroduction. No new cloud dependency, account requirement or mandatory
  model download. Keep inference sequential and preserve cancellation, deadlines,
  background execution and session generation checks.
- Default transcription preserves all spoken languages. Translation is explicit
  opt-in; cleanup must not silently translate or alter protected facts.
- Optional post-dictation prediction remains disabled by default and inserts only
  after explicit acceptance into the same still-valid context.
- Keycaps, visible key spacing and keyboard geometry must not change as a side
  effect of invisible hit testing. No suggestion/autocomplete bar redesign.
- Open sAiity is a tap; prepared dictation starts on hold and ends on finger release
  with the existing bounded recording tail. Processing can be cancelled.
- Preserve a dedicated Recents viewport, continuous ordinary emoji scrolling,
  a draggable whole category capsule and a stationary selected-category marker.
- Glass versus solid is a rendering preference; touch ownership stays identical.

## How to execute

Work in small dependency-ordered fixes, using existing helpers and native UIKit
behavior before introducing custom infrastructure. Each finding needs a failing
behavioral reproduction or a concrete code-path proof, a focused fix and a result.
Do not replace the keyboard or speech architecture wholesale.

Track each item as `not started`, `implemented`, `verified`, or `blocked` and attach
the relevant evidence. A passing build, source-text assertion or successful upload
must never be described as a successful device interaction test.

## Prioritized implementation work

### K1 — Unblock emoji scrolling on non-variant touches (P1, code-path defect)

Evidence: `DictusKeyboard/Views/EmojiPickerView.swift:772-809,856-900`.
`touchesBegan` returns while the hold recognizer remains `.possible` when the point
is blank or the emoji has no variants. It never assigns `trackedTouch`, so movement
and release do not fail this recognizer. The collection pan requires it to fail.
The comment claiming `gestureRecognizerShouldBegin` will settle this is insufficient:
this path never attempts to begin recognition.

Minimal fix: explicitly fail an ineligible hold, retain normal cancellation behavior
and preserve ownership after a valid hold begins. Do not add another overlay or
toggle the pan recognizer during an active variant session.

Acceptance: the emoji scroll/hold matrix below passes, including blank Recents,
nonvariant glyphs and subsequent swipes. Add a UIKit-level check or a small reusable
gesture harness exercising real recognizer state transitions; checking that the
source contains `.failed` is not enough.

### K2 — Remove unsolicited manual emoji snapping (P1, code-path defect)

Evidence: `EmojiPickerView.swift:639-656` rewrites `targetContentOffset` to a page
origin in `scrollViewWillEndDragging`, despite `isPagingEnabled = false` and comments
promising free scrolling. That custom delegate path still implements snapping.

Minimal fix: keep UIKit's projected release offset for manual swipes. Keep explicit
category selection jumps separate; do not discard native momentum or add a second
deceleration timer. Validate that pending jump/reload callbacks cannot replay after
manual scrolling starts.

Acceptance: slow drags stop naturally, flicks retain momentum, category jumps still
work, and a manual return to Recents is not undone by a stale request.

### K3 — Diagnose remaining category/layout/mic failures without a rewrite (P1, runtime investigation)

Evidence entry points: `EmojiCategoryBar.swift:29-63,293-345`,
`EmojiPickerView.swift:330-345,586-631,709-722`,
`KeyboardViewController.swift:111-151,1508-1713`, and
`KeyboardRootView.swift:419-428,656-661`.

The earlier conversation overstated two findings. Variable-width sections already
use cumulative offsets and are not inherently faulty. A visual SwiftUI button with
a UIKit hit owner is intentional; its mere existence does not prove competing
owners or a stale-frame bug. Do not replace all sections with viewport-width pages:
that can reintroduce the very whitespace the user reported.

Trace an actual failing touch from window hit test through the current controller,
button callback and URL completion. Use existing bounded diagnostics without audio
or transcript contents. During a recognized hold inspect whether layout refreshes
temporarily hiding/disabling the mic interrupt its touch lifecycle. Prove this on a
device or UIKit harness before changing it. Verify category offset/index round trips
at actual keyboard widths, maximum content offset at Flags and Recents page stability.

Only fix a demonstrated mismatch. Keep one touch owner per control, shared geometry,
minimal computed category spacing, dedicated Recents width and visible open failures.
Do not blame extension caching without checking the installed extension build.

### K4 — Separate keyboard click sound from vibration preference (P2, confirmed coupling)

Evidence: `DictusCore/Sources/DictusCore/HapticFeedback.swift:214-221` returns before
`UIDevice.current.playInputClick()` when haptics are disabled, while
`DictusApp/Views/SettingsView.swift:64-65` describes a vibration-only setting.

Minimal fix: gate only the impact generator with the haptic preference, leaving the
system input-click call to obey platform sound settings. Do not use private APIs or
claim a custom Taptic pulse exactly reproduces Apple's private keyboard behavior.
Audit callers for duplicate emissions on one key action.

Acceptance: four combinations of sound/haptics enabled/disabled behave independently;
rapid taps and repeat delete do not accumulate delayed feedback.

### K5 — Bound adaptive touch bias without reversing accepted requirements (P2, product tradeoff)

Evidence: `AdaptiveTouchRouting.swift:36-83` contains English-derived fixed priors,
used by `SuggestionState.swift:226` and `KeyboardRootView.swift:870`.
These are not universal multilingual probabilities. However,
`docs/keyboard-feel-plan.md` explicitly accepted common-letter logic without typed
language detection. Do not blindly implement the reviewer's proposal for a new
language-aware predictor: that would reverse the accepted direction.

First verify centers, commands and protected host fields cannot be redirected and
that prior updates after deletion, cursor movement and context changes are fresh.
Keep cheap synchronous priors and static fallback. Document the English bias, measure
wrong-neighbor corrections in mixed German/English typing, and abstain where the
existing safety contract requires it. Any broader language-specific redesign is a
separate product decision, not a mandatory stabilization fix.

### D1 — Make model-preparation timeout meaningful (P1, confirmed timeout semantics)

Evidence: `DictusApp/Models/ModelManager.swift:772-801`, called around `356-366`.
The timeout uses a structured throwing task group. Cancelling its children does not
make the scope return until a cancellation-ignoring initializer exits. The timer
therefore cannot guarantee recovery from the hang it documents.

Minimal fix: reuse an existing suitable timeout helper if present; otherwise add a
small single-completion boundary allowing the caller to receive the timeout while
quarantining a late initializer. Preserve `prewarmTimeout`, logging and generation
checks. A timeout does not kill Core ML: retain ownership of the outstanding work
and prevent another preparation/inference operation overlapping it. Do not create
an unlimited sequence of detached retries or falsely claim the underlying work ended.

Acceptance: cancellation-ignoring finite fake initialization exceeds a short deadline,
caller returns on time, UI exits its indefinite spinner, late completion cannot
publish readiness for a newer model/session, and a second load does not run in parallel.
Test normal success, error and cancellation as well as timeout.

### D2 — Make cleanup caching respect the full request (P1, confirmed missing inputs)

Evidence: `DictusApp/Polish/PolishCoordinator.swift:212-241,375-381,450` and
`DictusCore/Sources/DictusCore/Polish/PolishResultCache.swift:8-29`.
Cache lookup precedes duration gates; the key omits recording-duration eligibility
and speech-policy dimensions that influence prompt/repair selection. A long-clip
model result may satisfy a short-clip deterministic request, and different speech
policies may share results for identical text. Conversely a skipped result can mask
an eligible model call later.

Minimal fix: decide cache eligibility before lookup and insertion. Bypass the cache
for duration-gated calls. Audit all output-affecting inputs, including transcription
mode/explicit language, STT engine/model, resolved prompt/mode, span policy, regions,
translation target, writing style and any mutable glossary. Use a small value key
or invalidate on changed policy; do not duplicate language detection merely to build
it. Keep memory bounds and existing cache dimensions. Do not cache cancelled results
or transient failures as successful cleanup.

Acceptance: identical text below/above the threshold in both orders; Whisper/Parakeet
repair policy differences; explicit/Auto language changes; style/glossary changes;
cancelled/failed call followed by retry. Assert actual selected engine calls and
returned output, not only key inequality.

### D3 — Validate multilingual quality before changing models (P2, evidence gap)

The pipeline reviewer did not establish another concrete capture/ASR/prediction
defect. Do not add models, shrink segments or redesign prompts speculatively.
Use existing evaluation tools to compare raw ASR, cleanup and prediction separately
on the same consented recordings. Include switches within a sentence without pauses,
short speech, overlapping segment boundaries, names/numbers/negation and unsupported
languages. Record model revisions, latency, memory and failures; compare against the
same baseline rather than synthetic text-only claims.

For each observed loss, fix the first stage that loses the content. Preserve sequential
inference, bounded region copies and installed-model fallback rules. Never advertise
Parakeet as universal language coverage or enable prediction by default. If no audio
or device is available, leave quality validation pending instead of inventing results.

### A1 — Unblock denied-microphone onboarding (P2, confirmed navigation gap)

Evidence: active route `DictusApp/Onboarding/OnboardingView.swift:47` and
`MicPermissionPage.swift:10-13,32-46`. The documented nonblocking permission step has
no continuation when denied, only Open Settings.

Minimal fix: add a secondary continue-without-microphone route, retain the permission
explanation and runtime readiness checks. Trace the remaining setup/try-it steps too:
do not merely move the user to another compulsory dictation dead end. Keyboard-only
use should remain possible while recording stays unavailable with actionable guidance.

Acceptance: first denial, previously denied permission, Settings return/grant, later
revocation and keyboard-only continuation. Exercise the active onboarding path,
not obsolete alternative setup views.

### A2 — Keep Live Activity service intent separate from readiness (P2, confirmed mismatch)

Evidence: `DictusApp/LiveActivityManager.swift:429-430,968-969` populates
`serviceEnabled` from `keyboardAudioReady`, while
`DictusWidgets/StopStandbyIntent.swift:34-54` toggles the actual `serviceEnabled`
preference with nil meaning enabled. Enabled but warming and disabled are different
states; the widget's next action must reflect the same preference as the app.

Minimal fix: reuse one existing service-preference reader/default across initial
activity, recovery, standby return and intent updates. Keep audio readiness separately
for recording eligibility. Do not equate an enabled switch with guaranteed mic access.

Acceptance: enabled/warming, enabled/ready, disabled, absent preference, interruption,
standby recovery and both widget toggle directions agree with the Speak page. Turning
off stops dictation/mic access while retaining the activity for re-enabling.

### A3 — Make diagnostic transcript retention match user expectations (P2, confirmed separate storage)

Evidence: `DictusApp/Views/HomeView.swift:340-375` controls recent history, but
`DictationCoordinator.swift:978-992,1971-1997` stores raw/cleaned diagnostic text in
`lastDictationIssueSnapshot` independently. This is local retention, not evidence of
network disclosure. Distinguish recent history, transient delivery text and issue
snapshots; do not clear pending keyboard delivery when changing a history setting.

Recommended minimal policy: while saving history is disabled, retain diagnostic
timings/error metadata without transcript fields. On disabling, clear transcript
fields from the existing issue snapshot, consistently with the chosen setting copy.
Keep existing-history retention/deletion semantics explicit; audit the actual
`RecentDictations.disable` implementation before describing its behavior. Diagnostic
export remains a deliberate user action and must explain what it includes.

Acceptance: successful and failed dictation with history off leaves no raw/cleaned
text in the issue snapshot; metadata remains useful, insertion still works, and
explicit clear actions cover the stores they promise to clear.

### R1 — Make release tooling safe and consistent (P2, confirmed script risks)

Evidence: `scripts/cut-testflight.sh:78-86` updates three plists but not the six
`CURRENT_PROJECT_VERSION` settings in `Dictus.xcodeproj/project.pbxproj:1210-1339`.
`scripts/promote-to-appstore.sh:61-87` force-moves local/remote release refs and later
switches branches without the clean/expected-branch preflight used by the cut script.

Minimal fix: synchronize version sources or adopt one canonical existing source with
explicit consistency validation. Add non-mutating preflight for branch, dirty state,
required tools and ref existence; refuse conflicting refs rather than force-pushing.
Keep execution opt-in and do not run either script against the user's live checkout
as a test. Avoid automatic admin merge as an implicit release side effect.

Acceptance: isolated temporary repositories cover dirty state, wrong branch, existing
local/remote refs, missing dependencies and synchronized app/extension/project build
numbers. Inspection of a later authorized archive must agree. No production refs or
App Store state should change while implementing this item.

## Execution order and review decisions

1. Establish baseline and behavioral harness; fix K1 and K2 first.
2. Reproduce K3, implement only proven touch/geometry fixes; complete K4 and K5 checks.
3. Fix D1 and D2; then perform D3 evaluation without speculative model changes.
4. Complete A1–A3, then R1 in isolated tests.
5. Full verification, updated evidence ledger and explicit unresolved device gates.

The three subagent reviews were read-only. Their suggestions were reviewed against
actual callers and accepted requirements. The prewarm issue is P1 here, not an
assertion of a currently reproduced P0 outage. Fixed-width emoji pages, blanket touch
architecture replacement and language-detection prediction are not prescribed.
No full tests/build or physical-device validation were run for this planning task.

## Implementation ledger — 2026-09-22

Baseline at start: HEAD `e275e1a1`, branch `cursor/keyboard-surface-fixes-a66e`, 23 dirty paths, build 149. `xcode-select` points at Command Line Tools. `詹。手机air` was offline. No commit, push, install, or upload.

| Item | Status | Evidence |
| --- | --- | --- |
| K1 | verified in harness, device pending | An ineligible hold stayed `.possible` because `touchesBegan` returned without a tracked touch, so move and release never failed it and the pan kept waiting. `EmojiHoldArbitration` now fails that touch immediately, fails a pre-recognition move past 8pt, and keeps ownership after `.began`. `EmojiHoldArbitrationTests` drives those transitions, including 20 blank swipes. This is not a UIKit touch injection. |
| K2 | implemented, device pending | `scrollViewWillEndDragging` rewrote `targetContentOffset` onto a page origin. That override is gone, so a manual swipe keeps UIKit's projected offset. A finger drag sets `userHasDragged` and a later reload cannot replay a category jump back to Recents. Explicit category jumps still call `setContentOffset`. The old source assertion that required the snap was wrong for continuous scrolling and was replaced. |
| K3 | blocked on device | Category offsets already use cumulative page widths. The voice-board mic is a UIKit hit over a non-interactive SwiftUI face; that split is intentional. No touch was captured from the window through the URL callback because the phone is offline. No geometry or mic rewrite. |
| K4 | implemented, device pending | `playInputClick()` gated the system click on the vibration preference. The impact now follows that preference; `UIDevice.current.playInputClick()` does not. Delete repeat still uses `keyTapped()` only. The four sound/haptic combinations were not exercised on a device. |
| K5 | verified, no redesign | Centers, commands, and non-adjacent `q`/`w` stay static in `AdaptiveTouchRoutingTests`. The table is documented as English unigram/bigram data, not a multilingual model. No language-detecting predictor was added. Mixed German/English wrong-neighbor counts were not measured on device. |
| D1 | verified for the race, device pending | `withPrewarmTimeout` waited on a task group, so a cancellation-ignoring initializer blocked the timeout. `IsolatedDeadline.race` returns at the deadline and leaves the work quarantined. `ModelManager` refuses a second prewarm while that work is outstanding and does not publish readiness from the late result. `IsolatedDeadlineTests` covers a 0.05s deadline against a 0.35s non-cancellable body, plus success, failure, and waiting out the leftover. A real Core ML hang was not reproduced. |
| D2 | verified for the admission rules | Cache lookup now happens only when the recording is at least `engineMinDuration` (2s). The key includes engine, model, transcription mode, output mode, keyboard language, translation target, span policy, regions, and writing style. A skipped or cancelled call is not stored. Polish does not read a glossary, so none is part of the key. `PolishCacheAdmissionTests` counts engine calls for short/long order, Whisper/Parakeet, language, style, failure, and cancel. |
| D3 | blocked | No consented recording or device was available. No model, segment, or prompt change. |
| A1 | implemented, UI pending | Denied microphone onboarding only offered Settings. It now has "Continue without microphone". The try-it step has "Finish setup without dictating", so keyboard setup is not stuck waiting for a recording. Not exercised in a simulator UI pass. |
| A2 | implemented | Live Activity `serviceEnabled` was filled from `keyboardAudioReady`. It now uses `KeyboardDictationService`, where a missing preference means enabled and audio readiness stays separate. The widget intent and the Speak toggle handler use the same reader. Turning the service off still cancels an active dictation and leaves the activity up. |
| A3 | verified | `RecentDictations.disable` keeps history entries and now clears `rawText` and `cleanedText` on the issue snapshot. New success and failure snapshots omit those fields while history saving is off. Metadata remains. The report screen says the export includes model, engine, stage, and timing, and transcript text only when the toggle is on. `HistoryDiagnosticRetentionTests`. |
| R1 | verified in `/tmp/saiity-release-test.2leGgi` | `cut-testflight.sh` now writes all six `CURRENT_PROJECT_VERSION` and `MARKETING_VERSION` settings and checks them against the three plists. `promote-to-appstore.sh` refuses a dirty tree, a conflicting local or remote release ref, and no longer force-pushes or admin-merges. Isolated runs covered wrong branch, dirty tree, a real 149→150→151 bump, and a conflicting `release/1.0.0`. The live checkout was not cut or promoted. |

Core suite: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test --package-path DictusCore` — 1746 tests, 1 skipped, 14 failures. All 14 are `UserDictionaryLoggingTests` and also fail alone with an empty `dictus_debug.log`. That logger was not part of this change.

App build: `xcodebuild build -scheme sAiity-iOS -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/saiity-grok-review-derived` after `scripts/patch-fluidaudio-swift5.sh`. **BUILD SUCCEEDED.** `git diff --check` is clean.

Device gates still open: emoji scroll and hold, category scrub, mic tap/hold, both materials, sound versus vibration, and the multilingual recordings named in this plan. The phone was offline, so none of those interactions were performed.

## Follow-up — reviewer findings

| Item | Status | Evidence |
| --- | --- | --- |
| Deadline cancellation | implemented | `IsolatedDeadline.race` resumes when the caller is cancelled, instead of waiting out the deadline. The initializer is quarantined the same way as a timeout. `testParentCancellationDoesNotWaitForTheDeadline`. |
| Quarantine vs cleanup and Parakeet | implemented | A timed-out or cancelled Whisper init sets `prewarmQuarantined` before the error handler. That handler does not delete model files while the flag is set. The quarantine task deletes them after the initializer exits. Parakeet throws `prewarmBusy` while the flag is set. |
| Failed cleanup cache | implemented | The cache stores a result only when the polish outcome is `.success`. Starting the engine and then returning the deterministic floor does not store. `PolishCacheAdmissionTests` covers a failed attempt followed by a retry that calls the engine again. |
| Protected-field touch prior | implemented | `updateAdaptiveTouchPrediction` and `noteTypedCharacter` clear the prior when `suggestionsAllowed` is false, which covers URL, email, and search fields. |
| Promotion starting branch | implemented | `promote-to-appstore.sh` now refuses to start unless the current branch is `develop`, before any fetch or ref change. |

## Verification and release boundary

Minimum behavioral acceptance matrix for the implementation:

| Area | Scenarios | Required result |
| --- | --- | --- |
| Emoji scroll | Empty, sparse and full Recents; start on blank space, glyph and row gap; 20 consecutive swipes | Scroll begins normally and does not freeze or replay an earlier category jump |
| Emoji hold | Variant/nonvariant emoji; jitter before recognition; drag far outside popup after recognition; release and cancellation | Hold and pan arbitrate once; popup stays until release/cancel; exactly one chosen emoji inserted |
| Category control | Every category in both directions; first and last category; narrow and wide keyboards | Whole glass bar moves; marker stays centered; Flags and Recents reachable; no offscreen target rebound |
| Scrolling position | Slow drag, fast flick, interruption by another touch | Expected native momentum; no unsolicited page snap |
| Mic | Recovery tap, ready hold, release while requested/recording, processing cancellation, app switch | One recognized action per touch, visible failure if opening is rejected, no stuck recording or late insertion |
| Keyboard | Fast alternating fingers, accent holds, space trackpad, repeat deletion, material change | No dropped/duplicated input, static visual keys, same touch ownership in both materials |
| Feedback | Sound on/off independently of haptics on/off | Keyboard clicks and haptic pulses obey their own preferences |
| Speech | Single-language baseline and switches without pauses; quiet speech, silence, boundary repeats | Preserve spoken languages/facts; no hallucinated completion or lost boundary text |
| Processing | Cancel at each stage, begin a new session, invalidate host text | Old tasks cannot publish output or mutate the new session |
| Setup/widgets | Full Access toggled in Settings, return to setup, keyboard launched; Live Activity on/off | Fresh state, accurate next-step guidance, no stuck microphone readiness |

For multilingual checks include `Schick mir bitte the updated invoice tomorrow.`,
`Can you send das Dokument an Peter?`, and `你好，can you send me die Rechnung bitte?`.
Capture raw ASR, cleaned text and optional prediction separately. Text fixtures alone
do not verify audio recognition. Reuse `docs/asr-model-evaluation.md`; record real
consented audio and device/model/runtime metadata before making accuracy claims.

Before editing record `git status --short`, `git diff --stat`, HEAD, selected Xcode,
device availability and installed bundle/build identity. Use local Xcode explicitly:
`xcode-select` currently points to CommandLineTools, not Xcode.

Core suite:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcrun swift test --package-path DictusCore
```

Follow `.github/workflows/ci.yml` for package resolution and the existing
`scripts/patch-fluidaudio-swift5.sh` compatibility step before the application build.
Use a separate DerivedData directory; do not modify tracked dependency code.

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild build -project Dictus.xcodeproj -scheme sAiity-iOS \
  -configuration Debug -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/saiity-grok-review-derived \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGNING_IDENTITY=""
git diff --check
```

These commands are handoff instructions, not tests run during this review. Build
149's prior release test result is historical evidence, not verification of future
Grok edits. Run focused meaningful regressions during implementation and the full
suite/build before declaring completion. Keep existing tests; replace an incorrect
assertion only when its product contract is demonstrably wrong, explaining why.

Device validation must exercise actual taps/holds/swipes in the keyboard extension,
both materials, different host apps, foreground/background and app-switch lifecycle.
Do not demand a reinstall as a substitute for diagnosis or erase user dictionaries,
history, recents or models. If device access is unavailable, mark these checks pending.

Do not run `scripts/cut-testflight.sh` blindly: it assumes clean `develop`, commits,
tags and pushes. This dirty beta checkout has a different authorized workflow.
When a later release is authorized, verify a fresh unique build in App Store Connect,
all embedded version numbers and beta bundle IDs, then separately verify archive,
export/upload, processing, Testing/Ready to Test, and the internal tester group.
Browser work must use ego-browser. Never expose credentials.

## Grok execution prompt

Implement `docs/grok-codebase-stabilization-plan.md` in the existing dirty checkout
at `/Users/enricomini/Documents/Github/sAiity-dictus`. Read the current code and
AGENTS.md first; preserve all existing changes. Complete the prioritized work below
in small fixes, recording evidence and unresolved device checks in this document.
Do not infer defects from comments alone. Reproduce each reported failure or prove
its code path before editing. Preserve the product constraints above, use native
platform mechanisms and existing helpers, and avoid speculative rewrites. Run
relevant behavioral regressions, the complete Core suite, an application build and
`git diff --check`. Do not equate string-contract tests with UIKit execution. No
commit, push, device installation or TestFlight release is authorized by this prompt.
Finish with changed files, verified behaviors, commands/results, and explicit
remaining limitations. If blocked, complete independent items and report the exact
blocker without claiming the whole plan complete.
