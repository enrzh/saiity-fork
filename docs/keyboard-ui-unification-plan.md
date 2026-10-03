# Keyboard UI unification

Use shared keyboard geometry, native touch owners and passive material faces.
The original material pass below is followed by the expanded interaction,
processing and Icon Composer scope accepted on 2026-09-30.

Design rules: [keyboard-ui-design.md](keyboard-ui-design.md).

## Why

`KeyboardGlassSurface` and `appleControlSurface` implement the same liquid
glass / solid / accessibility branches. Command corners are the literal `18`
in `KeyboardRootView`, `AuxiliaryBottomBar`, and `KeyboardDeleteButton`.
Emoji press highlight uses another literal, `13`. A new key today has to pick
a path by copying a nearby call site, and the two paths can drift (they
already differ on whether `.board` skips the solid fill the same way).

The live input owners are now `NextKeyboardHost`, `KeyboardSurfaceView` and
the controller's action overlay. The grid, bottom bar, emoji collection and
dictation buttons receive native touches; their material faces remain passive.

## Keep

- `VoiceOnlyKeyboardPolicy` frames, including `numberPadEdgeInset` 14,
  full-cell number-pad keys, `numberPadKeyCornerRadius` 22, and
  `periodKeyPlateWidth` 34.
- `letterKeyPlate` gated on Key containers. Command plates stay always on.
- Emoji as a collection view. No glass well behind the suggestion lane.
- The dictation on/off button uses the same native command face as Delete.
  Its enabled microphone plate is green; it has no caps-lock state.
- Overlay misses return nil, including on the emoji page.
- Giella stays hidden.

## Order

### 1. Name the remaining radii

Add `commandKeyCornerRadius` (18) and `emojiHighlightCornerRadius` (13) next
to `keyCornerRadius` in `VoiceOnlyKeyboardPolicy`. Point
`commandKeyPlate`'s default and the emoji cell highlight at those tokens.

Replace the `18` arguments in `KeyboardRootView`, `AuxiliaryBottomBar`, and
`KeyboardDeleteButton` with the token. Leave capsule shapes as capsules.

Update the contract tests that currently require the literal
`RoundedRectangle(cornerRadius: 18`. They should require the token instead,
so a later radius change is one edit.

No frame, inset, or material change in this step.

### 2. Delete the second material function

Implement `appleControlSurface` as a call to `keyboardGlass` (or replace its
call sites with `commandKeyPlate` / `keyboardGlass`). One branch for liquid
glass, solid, Reduce Transparency, and Increase Contrast.

Preserve current hit behavior: control plates do not hit-test; the board
shape does. `utilityGlyph` stays non-interactive and accessibility-hidden,
because the overlay button is the control.

After this, a material bug is fixed in `KeyboardGlassSurface` only.

### 3. One face for command chrome

Add a small SwiftUI face, used by delete, ABC / 123 / emoji, return, and the
voice-board utilities:

- symbol or short label
- plate via `commandKeyPlate`
- hit size and plate size passed in, using `commandVisualSize(for:)` when the
  plate is the inset face

`KeyboardDeleteButton` keeps its hold-to-delete-word behavior and its UIKit
highlight. The new face replaces the repeated `Image` + frame + plate stack,
not the gesture.

Letter keys and number-pad digits retain optional character plates. Period
belongs to the native bottom bar and always retains its plate.

### 4. Lock the split in tests

Extend the existing contract tests rather than adding a snapshot suite:

- `appleControlSurface` no longer contains its own `glassEffect` branch.
- Command call sites use `commandKeyCornerRadius`.
- Emoji highlight uses `emojiHighlightCornerRadius`.
- `letterKeyPlate`, `commandKeyPlate`, the number-pad edge inset, the period
  plate width, the nil overlay miss, and the on/off button's `systemGreen` stay
  asserted as they are today.

## Do not do in this pass

- Restyle Home, Settings, onboarding, or the recording screen.
- Change number-pad padding, key height, or corner radius.
- Move live input controls into the SwiftUI material layer.
- Animate or resize keys from prediction.
- Move emoji paging into SwiftUI.

## Status

Steps 1–4 are in the tree. Command and emoji radii are named. Plates go through
`KeyboardGlassSurface`. Delete, ABC, 123, emoji, return, shift, and the
voice-board utilities use `CommandKeyFace`.

### Live structure and remaining gates (2026-09-30)

The controller owns three native input components on `KeyboardInputView`:

- `NextKeyboardHost` owns the ABC, symbols and number-pad grids.
- `KeyboardSurfaceView` owns `KeyboardBottomBarView` (including Period),
  `EmojiPagerView`, the category control and Emoji Delete.
- `PassthroughControlsView` owns accessory and dictation-board actions.

`KeyboardRootView` draws the shell and bounded error text and supplies the URL
bridge. It no longer draws the live accessory or dictation buttons. Each native
control contains its own `KeyboardNativeControlFace`, using the shared command
metrics and UIKit materials. The bottom-bar period contains its plate and labels
inside its touch control. The category visual host is a child of its category
control; a passive native inset spans the Emoji pager and bottom bar. Material changes
update those faces without replacing any input control. The unused full-row
SwiftUI bar renderer has been removed. Legacy page renderers remain inactive
until physical-device parity is verified.

`KeyboardInputView.nativeTouchOwners` now routes to those native components
explicitly. UIKit's subview order and `CALayer.zPosition` are different ordering
systems; a material host moved above a control must not become its hit owner.
The board and bottom bar also enumerate only their actual controls. Empty Emoji
space returns the collection view itself, whose native pan owns the gesture;
the extra decorative blank control has been removed.

The Open sAiity fallback belongs to each cached `KeyboardViewController`.
`KeyboardState` reads the current controller's opener. Dismissing a keyboard no
longer clears a shared callback that only SwiftUI's initial `onAppear` installed.

Character plates grow slightly (43.5pt height, 5.5pt horizontal gaps), retaining
the measured 54pt row pitch. These are tuned visible frames, not Apple's exact
accessibility target rectangles. The geometry suite checks growth, pitch,
non-overlap and plate containment.

Verification is deliberately split:

- Core tests and Debug builds pass; the signed device product verifies.
  The current suite reports 1,841 tests, one skipped, zero failures. Debug build
  221 is installed on the shared 18 Pro, with the embedded keyboard binary
  checked against the build.
- A controlled UIKit text-field host using the compiled production controller
  exercises Period, native page switching, blank Recents swipes, both materials,
  accessory actions and the app handoff. This is not a keyboard-extension run.
  The final component build inserts Period in both materials; empty Recents
  drags move the native collection from offset 0 to 210 in both. Open sAiity
  reaches the app's microphone permission prompt, which was not approved.
  A dismissal/reappearance check confirms the cached controller retains its
  opener, followed by another successful physical-tap app handoff. Dense live
  bar/Emoji hit checks pass with an interactive visual sibling added above them.
- `scripts/test-key-grid-overlay-routing.swift` compiles the production input
  view and checks hidden/detached owners, empty collection space and an
  obstructing material view in both appearances. Its 10,000-sample simulator
  run measured about 2.46 microseconds per root hit test. This measures routing
  cost, not physical typing latency. Run it from the repository root with
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift scripts/test-key-grid-overlay-routing.swift <simulator-udid> <derived-data>`.
- Real extension delivery is now observed on Device Hub's 18 Pro after moving
  faces into the native controls. On 2026-09-30, controller `0BCD39D3` recorded a
  blank-area hit on `EmojiPagerCollectionView` followed by native pan beginnings
  at offsets 248, 392 and 564. An ABC bar tap changed Emoji to Letters; Period
  recorded touch-down, a one-character proxy insertion and uncancelled release.
  The accessory return button changed Letters to the dictation board. Open
  sAiity reached the recovery owner and returned `extensionContext.open`
  success, followed by the app appearing. These are extension outcomes, distinct
  from the isolated text-field host checks. The earlier lack of injected touch
  traces is not a blanket simulator limitation for the current keyboard.
- Solid was selected through the app's material picker, but the subsequent
  real-extension attempt produced no valid gesture outcome. Both materials are
  verified in the isolated host; real-extension Solid behavior remains pending.
  The original Glass preference was restored after the check. Temporary QA
  simulators were removed; production app data and recent emojis were retained.
- The paired physical iPhone Air was unavailable during these checks. Physical typing, settings,
  responsiveness and behavior-parity gates remain open. No TestFlight upload or
  release-state change is part of this verification.

### Momentum, primary control and typing follow-up (2026-09-30)

- Emoji uses UIKit's normal deceleration, with reloads still deferred until
  tracking and deceleration finish. Its single native inset now spans the whole
  surface, including the bottom bar. It is passive and excluded from hit routing.
- The return-to-board accessory uses `mic.fill`. The shared native primary face
  has a leading 34pt icon badge and a 14pt action label in the existing 54pt target.
  Microphone hold/release, cancel and recovery handlers are unchanged.
- Settings hide Automatic cleanup when Foundation Models is unavailable and
  hide Writing style unless cleanup is enabled and usable. Existing keyboard
  preferences have live consumers and remain available; stored values are retained.
- Overlapping accent/plain presses previously produced `sa` for A-down, S-down,
  S-up, A-up. Pending accent text now settles before the next press, proxy
  insertion, Space, deletion or cursor movement. Case is captured at press time;
  the settled finger cannot insert a second time when released. Accent holds
  still select variants. One native preview host is reused across presses.
- `scripts/test-key-grid-typing.swift` links the compiled production keyboard.
  It checks overlap and simultaneous timestamp order, one-shot Shift, cancellation,
  accent hold, exactly-once settlement, preview reuse, both material branches,
  inset coverage and blank-space routing. Run with the same simulator/derived-data
  arguments as the routing check. The baseline used 100 preview hosts; the new
  path uses one. A 100-sample simulator run measured about 0.125ms before and
  0.045ms after per preview press/release. This is a synthetic input-path measure,
  not physical end-to-end typing latency.
- Core tests: 1,841, one skipped, zero failures. Simulator and signed device
  builds pass, including strict signature verification. The updated development
  app is installed on the shared 18 Pro; its embedded keyboard hash matches the
  build (`243012ed3d3bd102c2f53d979ee8a097b5b103478c9ae03dde41f0fc8753b2a6`).
- The production-controller host records swipe offset increasing after release
  in Glass and Solid. Its inset contains the bottom-bar frame; Period inserts
  and the microphone accessory returns to the board. An actual Glass extension
  in the app's Vocabulary field also records Period insertion and a blank hit
  reaching `EmojiPagerCollectionView`. Controller `F8BA64AE` then records native
  deceleration, ending at offset 6171. The temporary field text was not saved.
- The physical Air became reachable again. The current signed development
  app, 1.0.0 (221), is installed and launches there. Device Hub computer control
  still times out, and AXe supports only the simulated device. Physical gesture,
  typing-feel and settings-parity verification remains open. The heartbeat stays
  active; there is no TestFlight upload or release-state change.

### Haptic presets (2026-09-30)

Keyboard haptics is now a native Off / Default / Snappy picker. Default uses the
existing ordinary-key rigid impulse at 0.42; Snappy uses the exact no-argument
rigid impact previously used by Emoji Delete. Both `keyTapped` and `playInputClick`
route through one cached emitter, so letters, emoji delete and keyboard action
buttons agree. Off suppresses custom haptics while system keyboard clicks retain
their existing sound policy. Dictation outcomes and cursor-selection cues keep
their semantic patterns and follow Off's enablement gate.

Legacy off/boolean-disabled preferences stay Off; on/light/medium/strong migrate
to Default. Persistence still mirrors the legacy boolean. Selecting a preset
previews it, refreshes the app cache and notifies the extension through the
existing preferences notification; keyboard appearance also reloads the cache.

The production UIKit check intercepts both impact-generator methods and verifies
all three modes through a letter press and the actual Emoji Delete control.
The app picker was exercised from Default to Snappy and back to Default on the
18 Pro. Core tests report 1,842 tests, one skipped, zero failures. Both builds and
strict signature verification pass. The final app is installed on the 18 Pro
and physical Air as development build 221; the current simulator keyboard hash
is `89dfd9451b481eeb019b09a87916aa6ce32e0733083260d2757657f71ed638da`.
Physical vibration feel remains a hands-on verification gate.

### Expanded scope and final verification (2026-09-30)

| Accepted request | Current implementation |
| --- | --- |
| Shared tap and hold | `KeyboardHoldSession` supplies cancellable common-run-loop recognition for grids, Period, emoji, Space and Delete. Cached voice-board cursor recognition refreshes on appearance and preference changes. |
| Hold speed and per-key options | Slow / Default / Fast / Snappy; Settings previews ABC, 123, #+=, emoji categories and host-specific pads. A shared catalog filters alternates while retaining ordinary taps. The grid fingerprint includes variants so an already mounted page refreshes. |
| Shared keys and feedback | All three typing pages use `NextKeyboardHost`; all command faces share metrics; ordinary input uses Off / Default / Snappy haptics. The bottom bar owns Period. |
| Cleanup, processing and grammar | One existing polish pipeline and guardrail path; concise shared instructions preserve names, numbers, negation and mixed languages. Apple Foundation Models remains the default. App-only MLX supports Gemma 3 1B and Qwen 2.5 0.5B / 1.5B Instruct, all quantized to 4-bit. |
| Model settings | Dictation switches among installed ASR models directly in Settings. Processing selection downloads and prepares a local model before persisting the choice, with progress and cancellation. Models remains available. |
| Typing and languages | The live adaptive path now checks completed words for language changes. Typing correction and prediction support English, German, French and Spanish; uncertain scripts and sensitive fields stay unchanged. This is not universal multilingual correction. |
| New icon | `DictusApp/Saiity.icon` was imported, saved, reopened and exported in Apple Icon Composer. Its three separate SVG voice ribbons replace the initials. The app icon, shared app mark and widget mark use this design. |
| Dictation on/off and glyph | Native microphone / microphone-slash button; native primary face retains its glyph and restarts pulse on attachment. Hold/release dictation behavior is retained. |
| Accessories and emoji categories | 32pt accessory lane with 48pt action targets. Monochrome category icons and a selected capsule; the pager stops above the category hit expansion. |
| Host input types | Decimal, digit and phone pads, plus contextual Return labels. Names, addresses, postal codes, cards, telephone numbers, credentials, URLs and codes suppress inappropriate correction/prediction. Phone zero can hold for `+`. |

The final Core suite passes **1,848 tests, one skipped, zero failures**. Both
Debug builds and strict device signature verification pass. Development build
221 is installed on Device Hub's 18 Pro and the paired physical Air. The
installed simulator keyboard matches the build's SHA-256:
`684ff36ceef699348830af34533c4e8e3b8ee547ff83e27ca510ffdd6482cab0`.
The built app's `CFBundleIconName` is `Saiity`.

The compiled UIKit check passes overlapping press order, one-shot Shift,
cancelled accents, popup reuse, actual haptic-generator dispatch, all hold
speeds, live alternate reload, repeat cancellation, host pads, category edges,
category/pager separation and stable primary glyphs. Its final 100-sample
preview median is 0.048ms with one retained host. The 10,000-sample routing
check passes at about 5.11 microseconds per hit. These are simulator component
measurements, not physical end-to-end typing latency.

The latest **actual extension** on the 18 Pro also verifies:

- Settings changes hold speed to Snappy and disables `à`; shared preferences
  contain `letter:a = [à]`, and the subsequent held-A popup omits `à`.
- Period inserts through the proxy in Glass and Solid. With Key containers
  off in Solid, its bottom-bar plate remains visible.
- A drag beginning in blank Recents space reaches the native collection.
  Glass releases at offset 187 and decelerates to 342; Solid releases at 191
  and decelerates to 341. Neither run inserts an emoji.
- The wider accessory microphone returns Emoji to the dictation board in both
  appearances. The microphone on/off button receives native presses.
- Settings switches installed ASR from Automatic to Tiny and back. The
  processing menu exposes Apple, Gemma and both Qwen models.

AXe's short tap sometimes misses a native Settings switch. A single HID
down/up session with a 180ms duration reaches the switch. Holds need one HID
session too; splitting down/up into separate CLI processes is not equivalent.
Test text was not added to Vocabulary. Test preference values were restored.

Physical Air processing used the public fixture
`uh i i will send the invoice tomorrow`, with accepted output
`I will send the invoice tomorrow.`:

| Model | Earlier measured pipeline time | Active MLX memory |
| --- | --- | --- |
| Gemma 3 1B | 1.57s | 735MB |
| Qwen 2.5 0.5B | 0.86s | 281MB |
| Qwen 2.5 1.5B | 1.41s | 871MB |

A final Qwen 0.5B run on the installed build passes in 0.34s after 1.88s
preparation. These are individual short samples, excluding download; they are
not a distribution or evidence of Typeless/WhisperFlow parity. Qwen's mixed
German/English/Chinese rewrites failed preservation checks and were rejected.
The span-aware pipeline keeps uncertain spans on the deterministic floor.
Gemma's mixed fixture was interrupted by the foreground guard.

The MLX buffer cache is limited to 16MB after an earlier model-switch jetsam.
Only one model is retained. Downloads reuse the existing downloader with byte
progress, stall handling and relative-path validation. Preparation cancels
on backgrounding; generation cancels when the app resigns active and never
returns a cancelled partial response. Local processing requires the app to
stay open; Apple remains the background option. Actual interruption behavior
under longer device workloads still needs verification.

Remaining gates: physical typing latency and feel, vibration feel, physical
settings parity and broader mixed-language quality. Device Hub native computer
control is currently unavailable; AXe controls the simulated 18 Pro, not the
physical Air. The final reinstall on Air succeeds; its subsequent launch is
denied by iOS because the phone is locked. Inactive legacy renderers remain
until device parity passes.
The heartbeat covers this expanded scope and stays active. No TestFlight upload,
commit, push or release-state change was performed.

### October 1 follow-up

The accepted follow-up keeps the existing emoji category gesture logic and
restores the compact circle / expanding capsule styling. The enabled service
button uses an opaque green face so Glass does not leave a persistent halo.

Space now acknowledges touch-down, commits on release, and does not insert a
space after cursor hold. The board and typing bar share its native control.
Every Delete owner shares one repeat clock and preset haptic. Horizontal cursor
movement emits a selection tick for each crossed character with one proxy call
per movement. Press faces update immediately; release keeps its short fade.
Correct-word spell-check results are cached as well as corrections, and usage
persistence runs after Space's touch event. Layout uses the actual host height
so the 32pt accessory lane is not shifted partly outside a shorter field.

Emoji hold settings provide named skin-tone switches for ordinary emoji, with
individual settings retained for joined combinations. Filtering matches Unicode
scalars so a modifier inside a grapheme is recognized. Page navigation stays at
the top of the settings screen.

Settings links to Models. ASR and local cleanup cards share the same heading;
cleanup cards expose preparation, cancellation, selection, deletion, storage,
parameter count and Info. Speak and Models share native Balanced / detected
iPhone / Precise segments. Presets only select compatible installed models,
prefer multilingual variants and de-rate under memory/thermal pressure. Their
recommended download remains visible even if the general catalog omits it.
Switching a preset does not rewarm an unchanged, already-ready model.

Completed downloads persist a checked receipt. Subsequent preparation validates
the configured file paths and sizes locally and works offline. Incomplete or
invalid receipts return to the normal download/repair path. Upstream model
updates remain explicit delete/download operations.

Setup uses one shared permission observer across onboarding and Settings. A
new probe is verified by the currently attached keyboard's `hasFullAccess`.
Denied permission is delivered directly because a keyboard without Full Access
may be unable to write the App Group. Cached controllers answer explicit probes
and recheck on appearance. A real test field verifies access without dictating.
The generated 24-second silent video uses native AVKit PiP when supported, with
inline playback and written instructions as fallback. Its audio ownership
temporarily pauses standby, preserves the user's service setting and restores
the previous session when the guide ends. A running PiP survives navigation
away from the inline player.

Live Activity uses a vector-only version of the Composer voice ribbons, brighter
status typography, a blue keyline and a semantic Lock Screen card. Apple's
Dynamic Island background remains system-controlled. The unused waveform view
has been removed. Licenses are separate expandable cards with 22 bundled
notices, including the MLX dependencies, AOSP, fastcluster and VBx. CLI-only
Argument Parser and excluded eSpeak frameworks are not included in these cards.

Final automated verification for this follow-up:

- Core: **1,850 tests, one skipped, zero failures**. The new checks cover global
  tones versus joined emoji, preset choices, compatibility and memory pressure.
- Compiled UIKit: overlapping typing, holds, repeat cancellation, feedback
  presets, one vibration per Delete repeat, five consecutive cursor selection
  ticks, immediate Space feedback and hold without space insertion pass.
  A final 100-sample Space press/release median is 0.016ms; this measures the native
  control and callback, not autocorrection/proxy end-to-end latency.
- Actual 18 Pro app: Settings opens Models; cleanup Info works; Speak changes
  among all three presets and returns to Balanced; tone toggles update the
  shared mask; license cards expand. The real setup field receives the current
  extension handshake and changes Full Access to Verified. The installed
  extension renders the restored compact category circle and flat green
  microphone plate without the glass halo. Test tone and profile preferences
  were returned to their initial behavior.
- The silent video's four frames were rendered and inspected. Settings handoff
  works. AVKit reports `PiP supported: false` on the shared 18 Pro simulator;
  that device therefore offers inline playback and written instructions.
  Physical PiP/background playback and denied-permission refresh still need
  device verification; do not claim them from source or positive permission
  alone.
- Both Debug builds and the device signature pass. Development build 221 has
  been installed on the simulated 18 Pro and physical Air; later finishing
  changes are included in the final install. iOS blocks the physical Air launch
  because the phone is locked. Device Hub native control also times out. Its
  Home/Lock simulator commands did not produce a usable Live Activity capture,
  so system rendering remains pending despite the new vector mark and successful
  widget build. Physical typing/haptic feel, broader mixed-language quality and
  behavior parity remain open gates.
- The opt-in download check passes valid offline receipts, truncated weights
  and relative-path rejection. The final 10,000-sample root-routing check passes
  in both materials at about 4.73 microseconds per hit. Preview press/release
  remains about 0.049ms with one retained host; no general physical typing speedup
  is claimed from these simulator component timings.

No commit, push, TestFlight upload or release-state change is authorized by this
follow-up. Preserve inactive legacy input paths until their parity gate passes.

### TestFlight delivery requested October 1

The user subsequently authorized “push to testflight”. The current working tree
was archived and uploaded as **1.0.0 (222)**. The app, keyboard and widget versions
match, the Release archive passes deep strict signature verification, and Xcode
reports `Upload succeeded` / `** EXPORT SUCCEEDED **` at 08:52:58 CEST. See
`docs/release-222.md` for the archive, logs and keyboard binary digest.

Apple processing completion and assignment to the existing tester group remain
unverified because App Store Connect requested a fresh browser sign-in. Ego task
space 65 was handed to the user for authentication. This request authorizes this
TestFlight delivery only; no commit, Git push, App Store submission or future
upload was performed. All remaining physical/device-parity gates above stay open.

### October 1 material, tone, sizing and landscape follow-up

The next accepted request adds six changes after the TestFlight 222 upload:

- One passive `KeyboardNativeControlFace` backdrop now sits below every page,
  including the bottom bar and number pad. The separate emoji backdrop and
  SwiftUI board background are removed from the live rendering path. Settings
  exposes **Keyboard inset**, default On, independently of Glass versus Solid.
  The inset preference changes appearance only; it never changes hit owners or
  geometry.
- **Default skin tone** lives with tap-and-hold emoji options. The shared catalog
  applies it to ordinary emoji taps, displayed glyphs and the initial hold choice.
  Explicit Recents, including Original, keep their recorded variant; joined
  combinations retain their individual behavior. Choosing a default enables that
  tone, disabling it resets the default to Original, and individual alternate
  masks still win.
- Character plates use the existing **45pt** metric with a **54pt** row pitch.
  The optional digit row requests another native row instead of dividing the
  same height among four rows. The grid borrows 0.5pt from the gap above the bar
  so the taller plates keep the same centre as Emoji Delete. A truly smaller
  landscape/host surface still fits its available bounds.
- The category track is symmetric about the actual Emoji Space frame. It keeps
  room for the expanded rail rather than compressing its icons to the Space key's
  width. Category gesture logic, selection and accessibility remain unchanged.
- Live Activity and Island share `DictationActivityStatus`, `ActivitySignal`,
  `ActivityAction` and the detail view. The card has a clear phase title, concise
  instructions, one 44pt action, recording timer/level bars and private transcript
  preview. Persistent phase symbols replace the unreliable indeterminate widget
  spinner. The existing ActivityKit state format and intents are retained.
- Popup hosts use normal containment and no inherited safe-area padding. Popup
  faces fill their resolved rectangle; compact sources get a shorter preview.
  Popout grows from the actual source size/anchor in 120ms and respects Reduce
  Motion. Resizing cancels old fingers/previews and repeat sessions, preserving
  Shift/Caps for the same page. Moving the bottom-bar Period also dismisses its
  stale popup.

Verification: **1,852 Core tests, one skipped, zero failures**. Simulator and
signed device Debug builds pass, and deep strict signature verification passes.
The production UIKit script passes inset toggling in both materials, inclusion
of the bottom bar, category/Space centring, landscape popup/popout bounds,
rotation cancellation and resumed typing, Period preview cancellation, existing
holds, haptics and repeat behavior. The synthetic preview median is about 0.050ms
with one retained host; Space is about 0.042ms. These exclude text-proxy,
autocorrection and physical latency.

Seven activity states were rendered and visually inspected in light and dark;
landscape previews were rendered in both materials. These component images do
not establish system Island/Lock Screen rendering. Logs are
`/tmp/saiity-oct1-followup-{core,focused,sim,device,typing,render}.log`; card images
are `/tmp/saiity-oct1-activity-{light,dark}.png`.

The app exposes both new settings and the material menu changes to Solid. The
default-tone UI selection was interrupted when another task took over the shared
18 Pro; its adapter's actual persistence and filtering pass the Core test, but
the complete UI-to-extension gesture check remains pending. The original shared
material preference was restored through the running app's preferences API.
No Recents or vocabulary fixtures were saved.

Component checks moved to the isolated **sAiity Keyboard QA** 18 Pro simulator,
`A4E54392-A584-48AE-A0A0-EEB4807923FD`, where the latest development app is installed.
Its AXe automation session timed out; do not reuse the hAiity task's shared device
to finish these checks. The physical Air is currently unreachable with CoreDevice
error 4016. Physical typing/material parity, landscape animation feel, settings
interaction and system Activity rendering remain open gates. No room audio was
recorded. These changes are newer than uploaded TestFlight 222 and were not
committed, pushed or uploaded.

### TestFlight 223 delivery

The subsequent request “create a testflight” authorized delivery of the latest
follow-up. The current working tree was archived and uploaded as **1.0.0 (223)**.
All three bundle versions agree; deep strict archive signature verification passes.
Xcode reports `Upload succeeded` / `** EXPORT SUCCEEDED **` at 12:37:12 CEST.
The archive, logs and keyboard binary digest are recorded in `docs/release-223.md`.

Apple processing completion and availability to the existing tester group remain
unverified: ego task space 65 remains handed to the user for sign-in, with no
returned browser control. No commit, Git push, App Store submission or future
upload was authorized or performed. Device/parity gates remain open.

### Full category bar and native-sized bottom faces

The latest request replaces the collapsing category circle with a permanently
visible full rail, still centered above the actual Emoji Space key. Drawing and
native taps use one equal-cell metric, including the rail's inner padding.
Selection has a filled glyph and capsule highlight in both materials. Horizontal
drag, repeated category taps and VoiceOver increment/decrement remain available.
The old expansion/offset callbacks, subscriptions and published state are removed.

The bottom bar now uses **45pt visible faces**, matching the existing character
metric, inside a **53pt hit lane** with the same 4pt visual inset above and below.
Space, Period, page switches, field-specific keys and Return share that height.
The voice board and retained auxiliary geometry use the same lane. ABC/123/#+=
character rows move **9pt upward**, retaining their plate widths/heights and 54pt
pitch; Shift/Delete remain aligned with Emoji Delete. Host number pads retain
their existing full-surface layout because they have no separate bottom bar.

Verification: **1,853 Core tests, one skipped, zero failures**; both Debug builds
and deep strict device signature verification pass. The production UIKit check
verifies 45pt bottom faces on each shared page, all ten category cells across
three widths, out-of-bounds drags and accessibility selection. Existing input,
hold, cursor, deletion, Period and landscape checks also pass. A geometry check
compares the previous 44pt bottom lane with the new lane and proves the 9pt shift
without shrinking character plates.

Solid and Glass category components and the production ABC/symbol/Emoji surfaces
were rendered and inspected. Whole-keyboard images use layer rendering, which
cannot establish the system compositor's Glass appearance; they provide layout
evidence, not physical-device verification. Useful previews:
`/tmp/saiity-oct1-category-{solid,glass}.png` and
`/tmp/saiity-oct1-fullbar-solid-{letters,panel,emoji}.png`. Logs are
`/tmp/saiity-oct1-fullbar-{core,sim,device,typing,render}.log`.

The latest development app is installed on the isolated sAiity Keyboard QA
simulator. Physical Air remains unreachable with CoreDevice error 4016; phone
verification remains pending. These changes are newer than uploaded TestFlight
223. No additional upload, commit, push, saved text fixture or room recording
was performed.

### Service controls on every surface — October 2

The existing native service button now moves into the accessory lane beside
Return to dictation board on Letters, Symbols, Emoji and number pads. One shared
layout reserves its target without changing the 32pt lane or key/bottom-bar
geometry. The filled/unfilled power glyph, selected state and On/Off accessibility value
are used across both materials. Speak uses a native button toggle; the Lock Screen
and expanded Island keep a reversible power control in every dictation phase.

All writers share the service preference. The app owns preparation and disable
cleanup. An explicit enable from a cold keyboard/Live Activity can open sAiity
for preparation; recording requires a separate dictation action. Permission or
model failures revert to Off. Existing physical Full Access and service/microphone
verification requirements remain open.

Verification: 1,890 Core tests, one skip, zero failures; production UIKit checks
verify reachable power targets beside the board control on all four pages in
both materials. Signed Release and simulator Debug builds and strict signatures
pass. The native action disables the service and refreshes On/Off without changing
pages. Speak's full-width hit target reaches its action; a denied-microphone
enable returns to Off. Largest-text labels wrap in the scrollable list.
These are newer local build-224 changes; physical Air installation is
blocked by the most recent CoreDevice 4016 failure. No additional upload occurred.

### Spacebar cursor stops at a line boundary — October 2

Horizontal Space movement previously clamped to an estimated visual row and
accumulated a preferred column past that row's end. This stopped travel at wraps,
newlines or the edge of the proxy's nearby-text window, and made reversal wait
for the accumulated overshoot to be undone.

The shared cursor mapper now sends horizontal deltas directly to the host and
clears that stale preferred column. The host owns actual document boundaries;
nearby context no longer imposes a horizontal limit. Existing vertical/diagonal
row mapping, movement density, stationary-finger behavior and Space tap/hold
ownership are retained. This change applies to the board and typing Space owners.

The regression checks fail before the change; **100 focused cursor and keyboard
contract checks pass** afterward. The production UIKit Space control moves a native
text view across multiple newlines and rolling 12-character context windows in
one hold, reverses back to its starting position, stays still without travel and
inserts no Space. Existing typing, hold, cursor-feedback and material checks pass.
Debug simulator and signed Release builds and deep strict signatures pass.
The patched local development build **225** is installed on the isolated QA
simulator. Physical host-app feel remains pending on the previously unavailable
Air. No microphone capture, commit, push or TestFlight upload was performed.
Logs: `/tmp/saiity-space-cursor-{before,core,native,simulator-build,device-build}.log`.

### Circular bottom controls and smaller gaps — October 2

The compact buttons beside Space now have true 45×45pt circular faces, with
45×53pt touch targets. Shared bottom-row spacing is 2pt rather than 4pt; removing
the oval faces' horizontal inset also reduces the visible gap between the left
buttons from 12pt to 2pt. Space reclaims the available width. Period retains its
existing 34pt face and 44pt target, and Return keeps its generous target.
Letters, Symbols, Emoji and the dictation board use the same circle and spacing
metrics in Solid and Glass. Character heights and the bottom lane remain intact.

Verification: **1,892 Core tests, one existing skip, zero failures**, followed by
136 focused geometry checks after retaining the compact-layout visibility guard.
Production UIKit typing, overlapping touches, holds, Period, Space cursor travel,
category and service-control checks pass. Native component previews of all three
shared bottom bars were rendered and inspected in both materials. Layer rendering
establishes Solid appearance and layout; it does not establish system Glass
compositing or actual phone feel. Debug simulator and signed Release builds and
strict signatures pass. The updated local development build 226 is installed on
the isolated QA simulator; these changes were not uploaded to TestFlight.

Artifacts: `/tmp/saiity-round-bottom-after-{letters,symbols,emoji}-{solid,glass}.png`.
Logs: `/tmp/saiity-round-bottom-{full-core,core,native,simulator-build,device-build}.log`.

### Whole bottom-row spacing correction — October 2

The user clarified that the smaller gaps must cover the complete row, including
Space, punctuation and Return. The earlier change reduced the target spacing but
kept a 5pt horizontal inset on Period and 4pt on Return, leaving their visible
gaps larger than the circles' gaps.

All bottom-row faces now fill their horizontal targets. Period uses its existing
44pt target width, and Return and field-specific inserts share the bottom-row
face sizing. Every visible gap is 2pt. The existing button centres, touch targets,
keyboard height, circular left controls and 45pt face heights stay anchored.
The board and retained SwiftUI renderer use the same sizing rule.

A regression check measures the actual native plate rectangles across the
complete row and both materials; it fails against the prior build and passes
afterward. All 136 focused geometry checks and the production UIKit input harness
pass. The first broad UIKit run had a held-Delete timer assertion while building
and rendering concurrently; its isolated rerun passes without changing that test.
Simulator Debug and signed Release builds and deep strict signatures pass.
Native Solid previews were inspected; layer renders do not establish system Glass
compositing. The updated local development build 227 is installed on the isolated
QA simulator. These changes are newer than the uploaded build 227 and were not
committed, pushed or uploaded in this follow-up.

Preview: `/tmp/saiity-round-bottom-whole-row-letters-solid.png`.
Logs: `/tmp/saiity-whole-row-{before,core,native,render,simulator-build,device-build}.log`.

### Larger Caps, layer toggles and Delete — October 3

Caps/Shift, the row-level 123 and #+= toggles, and Delete now reuse the bottom
bar's 45pt face height and full-width sizing. Emoji and dictation-board Delete
share that geometry. The board's target grows from 44pt to 45pt around its existing
centre, preserving character-row and bottom-bar positions. Command radius, glyphs,
press treatment and compact accessory controls retain their existing settings.

Cramped landscape faces remain bounded by their resolved row height. The shared
edge calculation also accounts for the face's offset from the grid inset, keeping
wide commands inside their touch targets and clear of neighbouring keys.

Verification: **141 focused geometry/style checks pass**. The production UIKit
harness checks both symbol toggles, Caps and Delete across portrait and cramped
landscape in both materials, plus the actual native Emoji and board Delete faces.
Its existing typing, holds, cursor and service-control checks pass. Simulator Debug
and signed Release builds and deep strict signature checks pass. Native Solid
component previews were rendered and inspected; layer renders do not verify system
Glass compositing or physical typing feel. The updated local development build
**228** is installed on the isolated QA simulator. These changes are newer than the
uploaded build 228; no commit, push or TestFlight upload occurred.

Previews: `/tmp/saiity-round-bottom-command-size-{letters,symbols,emoji}-solid.png`.
Logs: `/tmp/saiity-command-size-{before,core,native,render,simulator-build,device-build}.log`.

### Native experience integration — October 3

The approved experience direction is implemented in local development build 229.
The dictation-board faces reuse the current frame and touch owners, with the
existing vector mark, adaptive blue primary/recovery faces and flat service
treatment. Listening animation respects Reduce Motion. Character/command plates,
the circular bottom controls, whole-row 2pt gaps, Space cursor mapping, holds,
repeats and haptic delivery retain their accepted geometry and behavior.

The shared SwiftUI action components also serve Speak, recording/results,
onboarding and Live Activity presentation. Power still changes availability;
starting capture and Finish remain separate actions. No new input owner or
runtime dependency was added and inactive legacy input remains.

Verification: 1,892 Core tests with one existing skip and zero failures, 123 final
app/keyboard contracts, the production UIKit input harness, simulator Debug and signed
Release builds, and deep strict signatures pass. Build 229 is installed on the
isolated QA simulator. Forty native presentation fixtures pass, including tested
Live Activity heights within 160pt. Actual system rendering, microphone-on haptic
feel and the existing physical integration gates remain pending. The last Air
CoreDevice 4016 blocker was not retried. No upload, commit or push occurred.

Detailed scope, captures and limitations:
`docs/design/saiity-experience-direction.md`, native implementation checkpoint.
Logs: `/tmp/saiity-native-design-{all-core,core,input,simulator-build,device-build,render}.log`.

## Check

Unit tests listed above, then a Debug install on the paired phone. On device,
confirm letter keys, the number pad (inset from the glass, tall keys), emoji
page swipes, the microphone on/off button, and both solid and
liquid glass. A token rename that does not touch frames should look identical.
