# sAiity product quality plan

Status: current accepted product direction, updated October 2, 2026. Existing
product changes and beta/quality tooling are implemented locally; physical-device
and participant evidence remains separate. Competitive targets below are pending.

## Product promise

sAiity combines everyday typing with private dictation and conservative cleanup.
People can speak naturally across supported languages, correct the result in
place and recover their original words. Readiness, recording and processing are
distinct states. The keyboard remains usable when a processing model is unavailable.

The main quality measure is the proportion of explicitly rated delivered
dictations that people find usable unchanged. Unrated results, failures and
cancellations are reported separately. Editing speed, Stop-to-proxy latency,
protected facts, mixed-language preservation, battery and memory are supporting
measures. A saved edit is evidence of editing; ordinary continued typing is not.

## Competitive quality target — October 2

The user wants sAiity to surpass Typeless and Wispr Flow as an everyday dictation
product. Local recognition and local cleanup are the foundation: privacy, offline
availability and user control. Overall superiority still requires demonstrated
accuracy, responsiveness, reliability and everyday usefulness. Competitor quality,
speed and current capabilities have not been measured in this repository.

The target experience is: speak naturally, release, receive usable text in the
right field, and correct or recover it without leaving the keyboard. Preserve
the speaker's voice and mixed languages. Model selection should require little
attention and never disguise unsupported speech as supported.

Use these as engineering targets, not achieved results or advertising claims:

| Area | Target and evidence |
| --- | --- |
| Useful output | At least 95% of explicitly rated short everyday dictations usable unchanged, with at least 100 rated deliveries per priority language. Report every failure and unrated result separately. Start with English, German, Chinese and their mixed-language cases; retain other documented language support. |
| Responsiveness | For 5–10 second dictations on the physical Air, aim for warm release-to-insertion p50 at most 1 second and p95 at most 2 seconds. Include capture finalization, recognition, cleanup and insertion. Report cold starts, longer speech, thermal state and each model separately; targets need phone measurements. |
| Meaning | Zero known unresolved cleanup changes to names, numbers, negation, uncertainty or spoken language in the release corpus. Review legitimate formatting and explicit self-corrections against the audio; a keyword match alone cannot establish preservation. |
| Reliability | Zero lost drafts, duplicate/late insertion, wrong-field edits or stuck capture in the tested host-app/interruption matrix. Verify mic-on haptics and ordinary typing physically. Good averages cannot excuse these failures. |
| Local operation | After explicit model download, airplane-mode recognition and selected local cleanup remain usable. Missing local artifacts produce an honest fallback or setup state; never silently switch to a server. |
| Sustained use | Measure standby power, repeated-dictation memory and latency under heat. Avoid an unbounded warm engine or overlapping inference; assess whether users keep sAiity as their everyday keyboard during the existing seven-day beta. |

Prioritize the work in this order:

1. Close reproducible device regressions and run a real speech baseline with the
   existing corpus, scorer, original/result review and session timing. The corpus
   currently supplies reference text, not captured speech or competitor results.
2. Make language coverage a hard constraint in automatic recommendations. Today
   `ModelSelectionProfile` selects using hardware and catalog size/speed/accuracy
   estimates. Its auto-detection filter includes Parakeet v3, whose documented
   coverage excludes Chinese. Auto-detection is not broad language coverage.
   Trace runtime selection and fallback before changing policy; preserve manual
   choices and disclose their limits. This finding does not identify the model
   behind the user's earlier Chinese dictation.
3. Tune recognition and cleanup using the failed cases and stage timings. Improve
   names, approved vocabulary, spoken corrections and mixed-language preservation
   through the current shared paths. Select default models from repeatable phone
   quality/speed evidence instead of adding models to make the catalog larger.
4. Prototype incremental recognition only if recognition dominates the measured
   wait and the existing engine supports it. Keep partial text provisional,
   final insertion singular, and capture cancellation/session ownership intact.
   Prove a latency improvement without lost words, extra battery drain or lower
   accuracy before enabling it by default.
5. Compare the resulting experience with both competitors, then use the existing
   beta to assess setup, editing, keyboard switching and sustained daily use.

For comparisons, use the same explicitly consented or licensed recordings when
the apps support file input, otherwise use matched scripted speaking sessions
and disclose that the acoustic input differs. Record app versions, phone/OS,
languages, processing options, network conditions and cold/warm state. Review
final outputs without app labels and record usability, editing effort, protected
facts and visible release-to-text time. Compare raw WER/CER only where raw output
is available; never reconstruct a competitor's hidden transcript or assign its
output to one of our catalog models. Unsupported language cases remain product
coverage failures rather than disappearing from the comparison. Repeat on a
second supported phone before making broad claims. Reuse the existing beta
protocol for participation, consent and distribution.

## Accepted experience

- Recognition now follows the macOS selector: Streaming / Whisper Auto, a
  separate model selection per path, and independent Realtime text. Qwen3-ASR
  0.6B/1.7B are speech models, separate from Qwen cleanup models. The iOS MLX
  implementation requires a physical iPhone with iOS 18+, conservatively gated
  to 6/8 GB RAM respectively, and the foreground app. Whisper remains the
  background keyboard path. Qwen availability is not an iPhone quality claim.
- Speak leads with readiness and dictation. Balanced, device-recommended and
  Precise presets remain near the voice model. Models is accessible from Speak
  and Settings; manual selection remains available.
- Apple Foundation Models, Gemma 3 1B and Qwen 2.5 0.5B/1.5B remain supported
  processing choices. Local MLX requires the foreground app. Explicitly chosen
  server processing remains optional and clearly distinguished from local processing.
- The suggestion bar remains, with advisory multilingual suggestions and
  reversible correction. It never silently replaces an inserted dictation.
- Shared UIKit input, bottom bar, holds, repeat sessions, field-specific keys,
  material rendering and haptics remain the existing owners. Interface polish
  must not introduce a second touch layer.
- The current full emoji category rail remains centered above Space, with
  momentum, blank-area swipes, variants and accessibility gestures intact.
- Personal dictation vocabulary requires explicit approval. New words added
  in Vocabulary are approved; automatically learned entries are not promoted
  unless the user chooses Use in dictation. Preserve spelling/case, bound hints,
  treat them as data, and retain language/fact guardrails. A disabled vocabulary
  preference suppresses hints without deleting stored entries.
  Whisper supports native recognition hints; Parakeet currently receives these
  spellings only in cleanup. Additional acoustic vocabulary rescoring would load
  extra resources and is deferred until controlled phone quality/memory evidence.
- Original/result comparison and reversible local restoration belong beside
  the result and in saved history. The keyboard's temporary result menu shares
  the output-language control, retaining its language choices and geometry.
  Field restoration requires the same document, no selection, unchanged trailing
  context and a fully verified insertion. Short replacement is bounded; longer
  or unreadable results offer copying rather than guessing about text ownership.
- History-off prevents new transcript history, including original/result pairs.
  Current recovery may hold transient text. Model debug logs remain metadata-only
  unless diagnostic consent and history both allow text. Reporting/sharing is
  explicit; beta feedback is voluntary and local.

## Work and evidence

1. Implement personal vocabulary using the existing Vocabulary screen, shared
   prompt contract and Whisper prompt-token API. No new model or dependency.
2. Reuse one original/result action component in recording and history. Keep old
   history decoding, original text when saving edits, existing copy/share, and
   safe keyboard ownership. Add explicit usable/needs-editing feedback.
3. Put the primary job first on Speak without removing the requested presets,
   model entry points or current preferences.
4. Provide a repeatable 40-case quality corpus and captured-run scorer that reuse
   `ASREvaluation` and `polish-harness`. Require hashes, model/device/revision
   metadata, outcomes and actual timings. An empty template cannot score as a pass.
5. Verify tests, signed build and isolated UIKit behavior. Then verify real host
   apps, actual typing/haptics, denied access, interruptions, orientation and
   materials on physical devices. Preserve user changes and avoid retrying unchanged
   blockers. Do not record room audio in automated QA.
6. Run a seven-day beta with 5–10 consenting people and several supported phones.
   Use [the beta protocol](/Users/enricomini/Documents/Github/sAiity-dictus/docs/product-beta-protocol.md).
   Testers and distribution must be concretely selected; this task does not send
   invitations or authorize another TestFlight upload.

## Implementation checkpoint

- Speak now leads with readiness and dictation, followed by its existing model
  presets and entry point. Settings retains direct model selection.
  A fresh-install check also found premature microphone prompting from automatic
  standby. Automatic restoration now requires completed onboarding and an existing
  grant; setup or an explicit dictation action owns the initial permission request.
- Vocabulary stores up to 32 explicitly approved, case-preserving terms (64
  characters/six words each) separately from automatic typing observations.
  One task-local snapshot follows ASR, cleanup and detached inference. Whisper
  receives a bounded native token prompt; every cleanup backend receives the
  shared glossary. Optional server cleanup gets only whole-term hints already
  present in its transcript. Cache/session identity includes the hint content.
- One result component handles comparison, copying/sharing and reversible
  local restoration in Recording and History. Saved entries decode older records,
  preserve originals across edits and store optional local acceptance feedback.
  History-off prevents new original/result history. Current delivery carries the
  original transiently and consumes it once.
- The keyboard reuses the output-language menu for Copy original, Restore
  original where fully verified and Undo dictation. Restoration checks document
  identity, selection, trailing context and every deletion; it is capped at 200
  graphemes to avoid an unmeasured long synchronous replacement. Longer/unreadable
  results offer copying. Typed commands/cursor motion cancel an ongoing Undo,
  and completed delivery/restoration clears stale suggestions.
- The 40-case corpus, pending capture generator and scorer are runnable through
  the existing harness without a model. Invalid hashes, unfinished cases,
  placeholder metadata and malformed inserted outcomes are rejected. Failures,
  silence hallucinations, protected facts and explicit ratings stay separate.
- The PRD now leads with current scope. Older conflicting plans are marked
  archived without erasing their historical evidence. The seven-day beta has a
  concrete invitation draft, consent rules, daily tasks and review protocol.

Verification: **1,876 Core tests, one existing skip, zero failures**; focused
quality checks pass. Production UIKit typing checks and delivery/recovery checks
pass in the isolated QA simulator, including changed document/typing/selection
refusal. The shared result renders at 320/402pt widths with normal text and AX3/AX5;
inspection led to shorter accessible button labels and untruncated transcript
wrapping. These are component/layout and synthetic input evidence, not proof of
phone haptic feel, acoustic accuracy, host-app integration or system Glass rendering.

The final simulator Debug build and serialized signed device Release build pass;
deep strict signature verification passes. Local build **224** is installed on
the physical Air and isolated QA simulator. Native screenshot/accessibility
inspection confirms Welcome no longer triggers the microphone request with
undetermined permission. The stale initial dialog was denied in the isolated
simulator, then its permission was reset to the original undetermined state.

Logs: `/tmp/saiity-product-{core,typing,recovery,render}.log`,
`/tmp/saiity-product-sim.log`, `/tmp/saiity-product-final-release.log`,
`/tmp/saiity-product-phone-install.log`. Result-layout images are
`/tmp/saiity-product-result-{320,402}-{normal,large,largest}.png`; the corrected
first-use screen is `/tmp/saiity-product-welcome.png`. An overlapping earlier
Release attempt hit the build database lock; the final serialized run passes.

The physical Air last reported `passcodeRequired: true`, so actual phone typing,
haptic feel, acoustic quality, denied Full Access recovery, background power and
host-field behavior remain unverified. Native UIKit harnesses do not load the
app's dictionary resources, so their passing routing/recovery checks are not
proof of real autocorrection quality. No testers have been contacted, no room
audio recorded, no source committed/pushed and no release uploaded. The beta
requires selected consenting participants and their actual seven-day use;
audio/latency/battery runs require accessible physical devices and consented files.

## Release gates

### Qwen dictation and macOS selector — October 2

The existing model picker is reused in Speak, Settings and Models for the
Streaming / Whisper Auto fork. Each remembers its own selected model. Qwen3-ASR
0.6B and 1.7B reuse the macOS 4-bit checkpoint IDs and pause-final behavior.
Realtime text appears only for Qwen; disabled means recognition waits for Stop.
Legacy installed Parakeet remains selectable without pretending to offer the
new Qwen preview. Existing Whisper selections and profiles remain available.

`QwenSpeechEngine` implements the existing speech protocol, uses the checked
download receipts for both ASR and Silero VAD, loads offline and retains phone
cache bounds. Downloads, repair, cancellation and deletion use ModelManager.
The four required library modules are now versioned in `Vendor/QwenASRRuntime`,
from upstream revision `e8f459d9b3689fe324125eeaafcf2617799808a5`. Existing
MLX 0.30.6 and Swift Transformers 1.1.9 pins are preserved. Availability annotations
and cancellation are maintained in source; Qwen no longer rewrites an SPM checkout.
There are no server, CLI, TTS or binary-artifact targets. The package remains
linkable by the iOS 17 app, while Qwen's adapter is gated to iOS 18+. The original
Apache license is retained and included in the app's license notices.

The sample-clock buffer is ported from macOS and tested for bounded silence,
pause boundaries, 10-second forced cuts and singular Stop flush. Preview reads
leave the authoritative capture untouched. Qwen inference is serialized in one
actor; decoded regions use the shared script-aware merger. Live output is an
in-memory app preview. The final result reuses translation, cleanup, original
recovery and session-bound insertion. Cancel/new sessions reject stale previews
and final delivery. Model changes are refused during active dictation.

MLX recognition is deliberately foreground-only. In-app Qwen and keyboard
Whisper/installed Parakeet choices are now independent: a Qwen app choice does
not disable the keyboard. Leaving the app cancels Qwen capture/processing.
Qwen does not silently substitute a different recognizer. Explicit in-app
dictation remains independent of the keyboard-service toggle. The upstream Core
ML alternative is not enabled: its
source documents multi-sentence truncation, so it is not a safe background parity
replacement without separately validated model artifacts.

Verification: the 1,882-test Core run found one old hard-coded catalog count;
that assertion was updated for the two new approved models. **93 targeted tests
then pass**, including new sample conservation, preview isolation, migration,
language coverage, route selection and unavailable-Qwen checks. The signed
device and isolated simulator builds pass. Simulator physical touch tests verify
both Qwen size choices, Realtime on/off, hiding Realtime on Whisper and restoring
Qwen 1.7B with Realtime on after switching back. No model download or microphone
recording was started during these UI checks. Actual Qwen load/inference,
airplane-mode recognition, live preview timing, memory and foreground-loss behavior
still require the physical phone and licensed/consented speech.
The local development build 224 installed successfully on the Air while locked;
that installation does not establish Qwen inference or accuracy. TestFlight is
unchanged. Large accessibility text uses a native menu for engine selection and
a shortened visual Qwen label with its full model name retained for VoiceOver.

### Session, model and service hardening — October 2

All six follow-up implementation requests are present locally:

- Capture the recognition model at session start and reuse it at Stop. Model
  selectors and completed-download runtime changes defer until finalization ends.
  Queued preparation checks session ownership before release, after release and
  before committing prepared objects. Fallbacks cannot change a successor's policy.
- Preserve requested models separately from ready models. An undownloaded manual
  Qwen choice survives navigation and a process restart, with a download action.
- Cancel Qwen in both token loops, drain submitted GPU work, and await teardown
  before allocating another engine. Cancel/error also cancel pending model loading;
  rejected or failed Qwen preparation releases its resources before returning.
- Copy preview audio in at most 8,000-sample batches under the capture lock.
  Catch up without extra idle sleeps; merge only decoded regions and publish only
  changed text. Stop retains every captured sample and performs one final flush.
- Keep app and keyboard model preferences/readiness independent. Legacy keyboard
  keys continue to describe the keyboard model; the app has separate ready-model
  keys. Streaming and Whisper preferences retain the requested choice.
- Build the small versioned Qwen package directly. The project lockfile now has
  13 remote pins; no Qwen checkout patch or unrelated speech package graph remains.

The user's additional service-control request uses the same shared preference
and coordinator action. One native keyboard power control appears next to the
dictation-board control in the accessory lane on Letters, Symbols, Emoji and
host number pads. Speak exposes a native button toggle. The Lock Screen and
expanded Dynamic Island expose the power action in every phase, alongside Finish
while recording. Disabling cancels active work and releases audio without ending
the standby activity. Enabling a cold microphone requests app preparation through
the existing URL; older iOS versions use a Link for that foreground action.
Permission/model failures return the service preference to Off. Enablement is
not evidence of an installed model or warmed microphone.

Verification: **1,890 Core tests, one existing skip, zero failures**. Four native
Qwen tests pass, including actual interruption of both token loops with a tiny
decoder and no model download/audio capture. Production UIKit checks pass for
all four accessory pages in both materials, native hit targets, preserved key
geometry and existing typing/holds/cursor/category behavior. The isolated app
retains pending Qwen 1.7B and independent Keyboard Automatic after a cold restart.
Speak's native button uses its full label as the hit target; physical-style
simulator taps reach the action and denied microphone access reverts it to Off.
The largest text setting keeps the complete label in a scrollable row. This is
layout evidence, not a passed physical accessibility or microphone gate.
The final 150 focused checks pass after the button correction. Final Debug
simulator and signed Release builds and deep strict signatures pass.
Logs: `/tmp/saiity-service-controls-{core-tests,typing,simulator-build,device-build}.log`
and `/tmp/saiity-runtime-final-tests.log`.
Button artifacts are `/tmp/saiity-service-controls-final-off-ui.json`,
`/tmp/saiity-service-controls-speak.png` and `/tmp/saiity-service-controls-large.png`.

The latest local build remains **224**, installed on the isolated QA simulator.
The physical Air most recently became unavailable with CoreDevice error 4016;
the older build-224 installation does not establish installation of these final
changes. Phone cancellation latency, real Qwen load/inference/memory/accuracy,
mic-on haptics, service toggles in system Live Activities and the existing host,
Full Access, PiP and landscape gates remain open. Competitive latency/quality
targets are not achieved measurements. No room audio or model download was
started, and no commit, push or TestFlight upload is part of this work.

### Microphone-on haptic regression

The user reports vibration disappearing while the microphone is active. The
pulled phone debug mirror contains `allowed=true` haptics requests alongside
`restoreDefaultModeFailed` errors (OSStatus 560557684). That mirror ends before
the latest user reproduction, so it does not establish the current hardware
cause. A successful allowance setter is not evidence of a felt vibration.

The shared engine enabled voice-processing input and voice-chat routing even
for standby, then attempted to change the session mode while input was running.
Dictation now keeps `.default` input mode throughout standby and capture and
requests haptics before session activation, retaining the checks after activation
and engine start. The voice-processing unit and live mode switches are removed;
existing sample conversion, quality analysis and conservative gain remain.
This also avoids voice-chat mode implicitly selecting Bluetooth HFP routing.
Engine-start diagnostics record mode, actual voice-processing state and reported
haptic allowance without transcript content.

The new source-contract regression fails before the change; **74 targeted audio
lifecycle, capture, haptic-preset and logging tests pass** afterward. This checks
configuration and sample safety, not physical feedback. The signed Release build
and strict signature verification pass; the patched local build 224 is installed
on the physical Air. TestFlight was not updated. Phone standby/recording
feedback in Default/Snappy, Off remaining silent, repeated capture, Bluetooth
route behavior and noisy-speech quality still require a manual device check.
No room audio was captured in automated QA.

### Reported annotation regression

A user-provided dictation contained `(speaking in foreign language)` before
Traditional Chinese. The exact annotation filter recognized `speaking foreign
language` but missed the version with `in`. One allowlist entry fixes final
assembly across parentheses, square brackets, asterisks and capitalization.
The regression failed before the change and passes afterward; **62 relevant
cleanup/assembly/span tests pass**. Ordinary mentions and parentheticals remain.
The Chinese characters are preserved verbatim; their recognition accuracy cannot
be assessed until the spoken language and intended sentence are known.
The signed Release build and strict signature verification pass. The patched
local build 224 is installed on the physical Air. This follow-up did not upload
to TestFlight or run an audio capture.

Every planned touch performs one action; no lost/duplicate insertion or stuck
control in the tested matrix. Original recovery cannot modify another field or
newer typing. Materials change appearance only. Retain accessibility labels,
largest app text sizes, Reduce Motion, Reduce Transparency and stable accessory
height. Measure idle/background power and model-switch memory on real devices.

Evaluate the same consented audio with/without hints and before/after cleanup,
including accents, code switching and noise. Do not infer acoustic accuracy or
haptic feel from simulator checks, nor overall acceptance from a few good samples.
Require manual review of protected-fact flags and silence hallucination. Keep
cold/warm timing distributions separate; compare the same device, OS, model,
revision, style and thermal conditions.

## Settings simplification — October 3

The Settings landing page now has seven native navigation rows: Dictation,
Keyboard, Models, Words & shortcuts, Dictation history, Setup & help and About.
It fits on one screen at normal text size, with a scrollable layout at larger
sizes. Everyday dictation and typing preferences stay visible in their relevant
pages. Processing backend/Live Activity choices and advanced keyboard controls
start collapsed. Emoji tones and per-key variants keep a direct Keyboard entry.
Models remains directly accessible from Settings, and the shared recognition
selector retains Streaming/Whisper, pending downloads and independent keyboard
selection. No preference keys, defaults, model choices or saved values were removed.
The shorter typing explanation retains supported-language and preservation limits.

One native grouped-list shell supplies the detail pages and reserves bottom
scroll space above the floating tab bar. Help groups setup, microphone access,
troubleshooting and support; About retains licenses, privacy and version. The
existing English-only app localization policy is retained.

Verification: 63 focused app/settings/model/lifecycle checks pass, along with
simulator Debug, signed Release and strict signature checks. Physical-style
simulator taps verify the seven landing rows, recognition and keyboard-model
selectors, both advanced disclosures and Vocabulary/Text replacements navigation.
At accessibility text sizes, decorative row icons give way to the full labels
in the scrollable native list; normal text size is restored after QA.
No model download, microphone capture, preference
change, commit, push or TestFlight upload was started by these checks.
The updated development build 228 is installed on the isolated QA simulator.
Physical-device integration gates remain separate.

Preview: `/tmp/saiity-simple-settings-root.png`.
Logs: `/tmp/saiity-simple-settings-{core,simulator-build,device-build}.log`.

## Native experience redesign — October 3

The approved design is integrated in development build 229: Speak presents
readiness and recent words, configuration moves behind Voice options, recording
and results prioritize unframed text with direct Copy/Edit/Original controls, and
onboarding exposes one next setup action. A small shared presentation component
reuses the adaptive action blue and existing vector mark across app, native
keyboard faces and Live Activity. The seven-row Settings structure and existing
runtime, preference, recovery and service-action owners are retained.
Native Edit/Save QA also found and fixed a stale Speak history preview. Saved
edits now appear immediately; the original transcript survives the edit. QA used
temporary transcript data and restored the prior history afterward.

Core/input checks, final Debug and signed Release builds, strict signatures and
the isolated simulator install pass. Native light/dark and larger-text captures
and tested activity height limits are recorded in
`docs/design/saiity-experience-direction.md`. Presentation fixtures use inert
dependencies; they do not establish recognition quality, latency, microphone-on
haptics, physical PiP or system Live Activity/Island behavior. Those gates and the
previous physical-device integration checks remain open. No automated room audio,
model download, commit, push, release change or TestFlight upload occurred. The
continuation heartbeat remains paused.

## Whole-app completion — October 4

Implemented locally in development build 232:

- Spoken languages guide automatic installed-model selection and explicit
  download recommendations for both app and keyboard. Broad support is the
  default; Chinese/English excludes English-only and European-only models,
  Cantonese excludes older Whisper families, and unsupported combinations stay
  unresolved. Catalog quality notes can suggest a larger model, but do not
  establish acoustic quality on this phone. Manual/pending choices survive.
  Runtime and failed/deleted-artifact fallback paths retain coverage constraints.
  These preferences do not set the ASR language or change typing/translation.
- Welcome offers Speak here or Use in other apps. App-only setup skips keyboard
  installation/Full Access, can close its trial without losing setup, and does
  not restore keyboard standby on launch. Explicit keyboard enable opts into
  restoration; Setup & help retains keyboard setup. A compatible installed model
  remains an explicit alternative to downloading a recommendation.
- Voice options and Dictation settings separate In sAiity from From your
  keyboard, retaining shared engine/model selectors and independent readiness.
  Spoken-language selection uses a searchable native list. No download starts
  from a recommendation alone.
- Shared failure presentation supplies readable permission, storage, download,
  model, foreground and audio recovery. Qwen load/memory errors do not claim
  foreground loss. Recording can open Models & downloads and retry explicitly;
  the original/result state is retained while the recovery sheet is dismissed.
  Active dictation remains visible despite a stale preparation error.
- Keep last recording briefly is off by default. It retains one foreground
  clip, at most the last 60 seconds, in memory for up to five minutes. Native
  replay is explicit and unavailable during recording/finalization. Expiry,
  app loss, preference disable, new admitted dictation, cancellation and reset
  clear it. Background completion cannot re-retain audio. WAV preparation is
  cancellable and session/generation guarded, and playback respects standby
  ownership. Replay does not save or export audio.

The existing 40-case scorer and timing tools now have a concrete pending phone
run in `docs/qa/phone-quality-run.md` and a generated large-v3 capture sheet.
Every outcome remains pending; no audio/model download or accuracy, latency,
thermal or power measurement was performed by generating it.

Verification: 1,902 Core tests pass with one existing skip; the new tests cover
language coverage/quality constraints, independent manual choices, app-only
gates, recovery classification, bounded replay, expiry and synthetic PCM/WAV
encoding/cancellation. Debug and signed Release builds pass. Native fixtures
use inert dependencies and establish layout only. Phone audio/feel/system
integration remain separate gates; the unchanged CoreDevice blocker was not
retried. No commit, push, release change or TestFlight upload was performed.
The continuation heartbeat remains paused.

Native physical-style taps on the isolated QA simulator verify the new language
list, Chinese/English selection and its persisted combined value, the replay
preference switching On/Off, and the app-only path through denied microphone
access to Prepare your voice. That page has no keyboard installation card;
its dictation action remains disabled while no model is installed. Normal and
largest-text screens were inspected. Search is visible; simulator HID text
injection did not enter a query, so interactive filtering is not claimed.
Audio playback/recognition and the successful model-backed onboarding trial
remain physical/file-audio gates. QA restores the original language/replay/setup
preferences, undecided microphone permission and normal text size. The app
remains service Off with its pending Qwen choice preserved.

## Source of truth

The October 4 keyboard correction in `docs/keyboard-ui-unification-plan.md`
retires the iOS styling option, adjusts the shared bottom row, adds Key flash,
keeps an inset-independent native emoji canvas and removes the autocorrection
language dependency from vocabulary learning. Core/native/build checks pass;
physical remote emoji delivery and exact system-keyboard alignment remain
unverified. The earlier iOS styling direction is superseded by this request.

The later unlocked-Air check closes a narrower part of that gate: actual
inset-off Glass emoji taps, category navigation and blank Recents swipes work
after painting the native shared owner. The latest development Debug 232 is
installed on Air with the existing preferences/models preserved. Ordinary
typing and keyboard presentation in the setup field and X's empty composer
work. The reported Q appearance is still unreproduced; its 16:13 event predates
the retained log window starting 16:15. Additional view-identity diagnostics
and a private Debug export now allow the next occurrence to be inspected.
Mic-on feel, the wider host/material/orientation matrix, speech/model quality,
PiP and system Live Activity gates remain separate. No audio capture, model
download or TestFlight upload accompanied this check.

This document and the current PRD define product direction. The
[keyboard plan](/Users/enricomini/Documents/Github/sAiity-dictus/docs/keyboard-ui-unification-plan.md)
and [runtime plan](/Users/enricomini/Documents/Github/sAiity-dictus/docs/dictation-runtime-and-prompt-review-plan.md)
record their implementations and verification limits. Older plans retain historical
evidence but their Qwen exclusions, suggestion-bar removal and model-navigation
instructions are superseded. Do not execute their old implementation prompts.
