# sAiity experience study — October 3

The approved direction is now implemented in the native app, keyboard faces and
Live Activity presentation in local development build **229**. The proposal and
browser evidence below record the earlier design stage; the native checkpoint at
the end records implementation and its separate verification limits.

Interactive proposal: [saiity-experience-prototype.html](saiity-experience-prototype.html).
Open the saved file in Ego Lite. It is self-contained and needs no server,
framework, external font or network request.

## Direction

The daily job is speaking and using the resulting words. Model configuration
belongs behind Voice options; setup and failures expose the next useful action.
The visual identity comes from the existing asymmetric three-bar mark and blue
accent. Transcript content is unframed; controls use restrained, familiar shapes.

The user explicitly asked to avoid an AI-generated look. This study removes the
conversational hero question, slogans, decorative cards and repeated engine
metadata. The screen titles, recording states and actual words carry the design.

Three surfaces establish the vocabulary:

| Surface | Primary content | Primary action | Secondary controls |
| --- | --- | --- | --- |
| Speak | New dictation and a short recent-text list | Start dictation | Power, Voice options, Settings |
| Recording/results | Readable provisional or finished transcript | Finish / Dictate again | Cancel, Copy, Edit, Original |
| Dictation board | Current state in the existing keyboard footprint | Start / Finish / Cancel | Language, power, Delete and shared bottom row |

## Palette and type

All values below describe this proposal, not a system color guarantee.
Native integration should use adaptive assets and semantic system surfaces.

| Role | Light | Dark |
| --- | --- | --- |
| Surface | `#FAFAFC` | `#111318` |
| Raised surface | `#FFFFFF` | `#1B1F27` |
| Primary text | `#171A22` | `#F5F7FB` |
| Secondary text | `#646B78` | `#A3AAB8` |
| Action blue | `#245DE3` | `#8CADFF` |
| Text on action blue | `#FFFFFF` | `#101A35` |

Calculated WCAG contrast on the base surface: primary text 16.69:1 / 17.32:1;
secondary text 5.14:1 / 7.96:1; filled action text 5.60:1 / 7.81:1.
The icon's existing blue informs the accent; the darker light-mode action blue
keeps white button text above 4.5:1.

Use the system font. Body starts at 17pt, transcript at approximately 26pt and
screen title at approximately 32pt. App targets aim for at least 44pt. The typing
and bottom command plates remain 45pt, with the existing 53pt bottom lane and 2pt
visible gaps. Text-size and material controls are provided for reviewing the study.

Compact: one scrollable content column with a reachable voice action. Regular:
constrain the transcript to a readable column and keep controls near it.

```text
Speak                     Recording/result          Keyboard host
Title                     Brand              Close  Conversation
Local status       Power  State               Time  Message draft
New dictation             Transcript                Local status / Voice options
Voice options             Copy · Edit · Original    Language               Power
Recent words              Original, when requested  Recording state
Start dictation           Finish / Dictate again    Start / Finish / Cancel
Speak · Settings                                     Shared bottom row
```

The only recurring motion in the proposal is the listening mark. Reduced Motion
stops it; reduced transparency removes the browser blur approximation. Glass is
on chrome and command faces, not transcript content. System Glass, real haptics
and actual phone feel still need native verification.

## Native integration

| Existing owner | Proposed presentation change |
| --- | --- |
| `DictusApp/Views/HomeView.swift` | Replace the configuration-first List with the Speak workspace. Keep real readiness and coordinator actions. Move existing model pickers into Voice options. |
| `DictusApp/Views/RecordingView.swift` | Keep one transcript area and stable action placement. Reuse the production `DictationTranscriptResult` for copy/edit/original and feedback. |
| `DictusCore/Sources/DictusCore/Design` | Adapt the current color tokens and reuse the existing vector mark / waveform. Add a shared small presentation component only when multiple consumers need it. |
| `DictusKeyboard/KeyboardViewController.swift` and native faces | Change appearance through the current owners. Resolve all frames through `VoiceOnlyKeyboardPolicy`; preserve hit routing, Space cursor, repeats, holds and haptics. |
| `DictusWidgets/DictusLiveActivity.swift` | Carry the same state text, mark and action hierarchy into the existing activity components. Keep reversible power and separate Finish. |
| Settings and onboarding | Retain the simplified destinations. Apply the established type/color rules and use one next setup action per blocker. Preserve preferences and required notices. |

Keep the accepted runtime rules: app and keyboard model choices are independent;
Qwen stays in the foreground app; pending selections stay pending; changes apply
after session finalization; previews stay provisional; final delivery stays tied
to its requesting session. Enabling power prepares availability and never starts
recording automatically. Keep recovery and original text accessible.

## Prototype boundaries and verification

The earlier design-only turn created a reviewable proposal without replacing
production SwiftUI/UIKit views or changing build 229. Speech, elapsed time, model readiness,
recent history and host messages are sample fixtures. Browser clipboard copying
requires an explicit Copy click and has a selection fallback. No microphone,
model download, actual inference, real message sending or app preference writes
are involved. Prototype letter/symbol keys demonstrate layout only; they do not
replace the native keyboard's touch and gesture implementation.

Runnable browser check:

```sh
ego-browser nodejs <<'JS'
const repo = "file:///Users/enricomini/Documents/Github/sAiity-dictus/";
const { default: check } = await import(repo + "scripts/check-design-prototype.mjs");
const task = await taskSpace(75);
await check(task.page("p1"), repo + "docs/design/saiity-experience-prototype.html");
JS
```

The check verifies UI behavior through Ego Lite and uses an in-page clipboard sink
to preserve the user's OS clipboard. Actual native font scaling, rendering,
landscape animation, system Live Activity actions, host-field parity, typing,
microphone-on haptics and dictation quality/latency remain separate gates.
Production tests/builds were not repeated for that documentation-only proposal.
No commit, push, release change or TestFlight upload is part of this work.

### Verification evidence

The runnable check passes in Ego Lite task space 75. It covers syntax, shared
power and explicit start, cancellation, mixed-language sample delivery,
copy delivery into the test sink, edit/original recovery, pending model selection,
Finish surviving a pending next model, language selection, optional inset in both
materials, keyboard focus/return, reduced motion and responsive light/dark layouts.
Narrow larger-text checks keep the board action at 54pt. A visual review caught a
truncated model selector; larger-text rows now stack their label and picker.
The sample conversation also clears its composer.

Reviewed captures are outside the repository at
`/Users/enricomini/.codex/visualizations/2026/09/07/01a07d2b-a9ca-7dd3-9542-e9bac2049c97/saiity-design/`:
`light.png`, `dark.png`, `light-result.png`, `dark-result.png`,
`keyboard-large.png` and `voice-options-large.png`.
Check log: `/tmp/saiity-experience-check.log`.

Task space 75 is retained for the user to review. A future browser check must use
a space under agent control and respect Ego Lite's user-control handoff rules.

## Native implementation checkpoint — October 3

Speak now opens on a voice workspace with one readiness/recovery action anchored
above the native tab bar. Keyboard power stays compact and separate from starting
a dictation. Existing recognition, model and preset controls live in a native
Voice options sheet. Recent words use plain, leading-aligned previews and a small
action menu. The earlier Settings simplification remains the navigation structure.

Recording and results put the transcript first, without a decorative container or
pipeline strip. Copy, Edit and Original are directly available; Share and optional
quality feedback live in More. Edit uses a native TextEditor sheet and the existing
result callback. Original/result recovery remains reversible. Onboarding uses
direct titles and one next action, with the existing permission and setup owners.
Speak reloads its short history list after saving an edit, returning to the screen,
foregrounding the app or changing dictation state. This fixes the stale preview
found during native Edit/Save QA without adding a separate history store.

Shared adaptive action colors and `SaiityVoiceControls` supply the primary button,
action label and passive voice signal. The existing vector mark supplies both
SwiftUI and UIKit. Native dictation-board faces use the same blue and flat service
treatment through their current owners. Listening animation respects Reduce
Motion. This changes presentation without a new runtime or design dependency.

Live Activity and Dynamic Island use concise states, the vector mark and the same
action hierarchy. Reversible power and separate Finish keep their existing intents
and foreground URLs. Accessibility layouts drop redundant guidance and branding;
secondary/action text has a XXXL cap to stay inside ActivityKit's height limit.
These caps do not establish a physical accessibility pass.

### Native evidence

- Core suite: **1,892 tests, one existing skip, zero failures**. After the final
  history refresh correction, **123 app/keyboard contracts pass** (136 checks
  passed in the preceding presentation review).
- Production UIKit input harness passes for typing/overlapping presses, holds,
  repeats and haptic instrumentation, Space travel/reversal, both materials,
  portrait/landscape cancellation, command geometry and service controls.
  Instrumentation timings measure component work, not phone feel or dictation latency.
- Final simulator Debug and signed generic-device Release builds pass, with deep
  strict signature verification. The final app is installed on isolated simulator
  `A4E54392-A584-48AE-A0A0-EEB4807923FD`; its app debug binary SHA-256 matches the build.
- Physical-style simulator taps open Voice options at normal and accessibility
  text sizes. The native UI remains scrollable and its controls reachable. QA
  restores light appearance, normal large text, service Off and the original
  undetermined microphone permission.
- Native physical-style touches open the shared Edit sheet from saved history,
  change a temporary mixed-language fixture, save through the existing history
  owner and return to Speak with the changed preview immediately visible. The
  stored original remains intact. The temporary history key is restored after QA.
  `/tmp/saiity-native-design-edit-check.log` and
  `/tmp/saiity-native-design-refresh-saved-ui.json` record these checks.
- `scripts/render-native-experience.swift` renders 40 production-view fixtures at
  402/320pt, normal/accessibility3 and light/dark: Speak, listening, result, failure,
  welcome and five Live Activity states. Every tested activity measures at most
  160pt. Dependencies are inert and use a temporary defaults suite; these are
  presentation fixtures, not recognition or service-action checks. Layer rendering
  does not establish actual system Glass, Lock Screen or Island compositing.

Native captures are outside the repository at
`/Users/enricomini/.codex/visualizations/2026/09/07/01a07d2b-a9ca-7dd3-9542-e9bac2049c97/saiity-native/`.
Build/test logs: `/tmp/saiity-native-design-{all-core,core,input,simulator-build,device-build,render}.log`.
Actual simulator captures include `/tmp/saiity-native-design-speak-current.png`,
`/tmp/saiity-native-design-voice-options.png` and their large/dark counterparts.

### Remaining device gates

The physical Air's last CoreDevice 4016 failure is unchanged and was not retried.
Real typing and mic-on haptics, host-field/settings parity, default skin tone
propagation, denied Full Access changes, physical PiP, landscape feel, system Live
Activity/Island rendering and power, Qwen load/inference/cancellation/foreground
loss, memory, accuracy and latency remain unverified. Simulator AVKit's unsupported
PiP result is still a limitation. No room audio or model download was started.
Inactive legacy input remains until real behavior parity passes. Competitive
quality and latency numbers remain targets. The continuation heartbeat stays
paused. No commit, push, release change or TestFlight upload occurred.
