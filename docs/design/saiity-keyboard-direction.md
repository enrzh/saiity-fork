# sAiity keyboard design plan — October 3

Status: implemented locally. The verification checkpoint below records the final
result. These changes are newer than TestFlight 230 and have not been uploaded.
This extends the [native experience direction](saiity-experience-direction.md).
The source baseline is the build-230 implementation at `fcf7c107`.

## Direction

Make typing feel familiar and visually precise. Keep the existing positions;
make letters easy to read, commands easy to distinguish and voice easy to find.
The product's identity comes from its three-bar voice mark and blue action.
Use system type, neutral surfaces and purposeful press feedback.

The current keyboard has sound geometry but uneven visual emphasis. Solid
character and command plates resolve to nearly the same fill. Letter glyphs use
22pt Light, while commands use stronger glyphs and generously rounded shapes.
The bottom circles, Space capsule and emoji category rail each have their own
treatment. Accessories add another group of small pill faces above them.
My design judgment is that these competing treatments make the keyboard feel
assembled from separate controls.

Review evidence: current UIKit/SwiftUI styling and layout sources, plus the
October 3 Solid component captures for Letters, Symbols and Emoji. Those captures
predate the final app redesign and show component layout without the complete
host backdrop/accessory lane. The September 30 board screenshot is historical
layout evidence; its old colors are superseded. System Glass and phone feel need
new native review during implementation.

## Accepted geometry

Preserve 45pt portrait character and command plates, the 53pt bottom lane, 2pt
visible bottom-row gaps, the true circular controls beside Space, the established
button centres and the optional digit row. Preserve the number pad's resolved
tall keys and the stable accessory/window height. Both materials retain the
existing optional inset preference and its stored value.

The full emoji category rail stays centred above Space. Existing taps, scrubbing,
momentum, category jumps, tone holds, explicit Recents and joined combinations
remain the behavioral contract. The host keeps horizontal document boundaries
for Space cursor travel. Holds, repeats, overlapping touches and cancellation
keep their existing owners.

## Proposed presentation

| Area | Change | Starting specification |
| --- | --- | --- |
| Letters and symbols | Give input keys clearer separation from the backdrop and quieter command keys | Keep 8pt character corners; compare 22pt Regular against current Light for letters/digits; retain the supported punctuation sizing |
| Commands and Space | Make wide keys look more like keys, with less capsule emphasis | Preview 12pt corners for Caps, layer toggles, Delete, Return and Space against current 18pt commands/capsule Space; use a quieter 14pt Regular Space label; keep the two left controls fully circular |
| Number pads | Use the same foreground/plate hierarchy with more readable digits | Preview 22pt Regular digits and 14pt plate corners against the current 22pt Light / 22pt corners; keep secondary phone labels and all frames |
| Accessory lane | Reduce competing bezels and align glyph weight/optical centres | Plain language/Paste/Dismiss faces; subtle press backgrounds; preserve power immediately beside the board control on other pages |
| Emoji | Let glyphs carry the page; make selection clearer | Keep the full 22pt visual category rail, all icons and existing expanded gesture track; one selected background plus filled selected symbol |
| Voice board | Give the central state and voice action a clear relationship | One short state label, actual available preview, one primary action in its existing slot; retain independent power, Finish/cancellation semantics and recovery |

These radii are design candidates, not measurements of Apple's keyboard. Compare
native renders before choosing them. Changing radius or glyph weight must not
shrink a plate or move a key. Preserve user-selected plate visibility.

### Surface and color

Use the current host backdrop and one optional inset surface. Solid input plates
should separate visibly from that surface; command plates should have a restrained
neutral fill. Resolve the roles with adaptive system colors and check them on the
actual keyboard backdrop. Avoid adding individual-key shadows to create depth.

Glass keeps its current native material and inactive visual layers. Apply the
same glyph, shape and state hierarchy in both materials. Keep tint concentrated
on the voice action, with the enabled service control using the existing blue
glyph and a distinct selected shape. Preserve the flat service face.

Reuse `saiityAction` / `saiityOnAction`: light `#245DE3` / `#FFFFFF`, dark
`#8CADFF` / `#101A35`, with existing high-contrast variants. The established
opaque action pairs measure 5.60:1 and 7.81:1. Measure the actual composited
keyboard colors separately; those figures do not establish Glass contrast.

Host-specific Return labels already exist. Carry Go/Search/Send/Done consistently
through the active faces, keeping the existing proxy action. Keep the ordinary
Return neutral; preview emphasis for host submission actions without implying
that the keyboard can send content independently.

### State and motion

Press feedback should appear immediately inside the key. Keep the existing
80ms press-in / 160ms release baseline; compare a restrained 0.97 command scale
against 0.94. Use the same state rules across grid commands, Emoji Delete and the
bottom bar. Keep Caps armed/locked visibly distinct from a pressed key.

Use the existing preview/variant sessions for letters, accents and punctuation.
Give popup bodies the same type, corners and material hierarchy. Preserve their
landscape placement, clipping bounds, reuse and interruption on rotation/page
changes. Reduce Motion uses a visible fill change without scale. Retain existing
haptic presets and optional sound behavior.

On the voice board, labels must describe the actual coordinator action: Start,
Finish, Cancel or Open sAiity. Display only existing session-bound preview data.
Keep enablement separate from recording. Put a concise error in the existing
status region and leave detailed setup/model explanations in the app.

## Implementation sequence

1. **Native comparisons.** Extend the existing native fixture approach to complete
   keyboard surfaces with inert state: Letters, both symbol layers, numeric/phone
   pads, Emoji and board states. Compare current/proposed shapes and glyph weights
   at 320/402pt, portrait/landscape, Solid/Glass and light/dark. Use native rendering
   to choose the treatment; verify Glass in a real host separately. No live capture
   or model download is needed for these fixtures.
2. **Shared appearance.** Extend existing style owners with only the plate/color
   roles needed by multiple consumers. Keep geometry in `VoiceOnlyKeyboardPolicy`,
   command treatment in `CommandKeyStyle`, grid drawing in `KeyGridView` and native
   control faces in `KeyboardNativeControlFace`. Apply the same resolved values to
   the existing passive SwiftUI Glass faces. Add no new input layer or dependency.
3. **Page polish.** Apply the accessory, Emoji, number-pad, board and popup changes
   through their active owners. Review the entire keyboard in host fields so a
   polished isolated key does not hide crowding in the full layout. Style the
   current accessory lane; `ToolbarView`/`SuggestionBarView` are not mounted by the
   active host and should not be revived as part of this presentation work.
4. **Verification.** Run the existing geometry and production UIKit interaction
   checks after implementation, build/sign the app and install it on isolated QA.
   Use before/after frame comparisons to catch accidental height/position changes.
   Verify typing, holds, repeats, Space travel/reversal, emoji momentum, variants,
   service actions and landscape popup cancellation. Measure draw/press work using
   the existing instrumentation under comparable conditions.

For accessibility, measure text contrast, check Bold Text/Increase Contrast,
Reduce Motion/Transparency, long host labels and the largest text sizes. Keep
labels and selected/adjustable states accessible. Audit the compact accessory
and category targets in their actual coordinate space so expanded targets do not
overlap neighboring input. Don't claim every dense key/category slot is 44pt;
preserve the existing gesture/accessibility alternatives and verify reachability.

Physical typing, microphone-on haptics, host-field parity and landscape feel are
separate gates. Resume physical checks when device access changes; the last
CoreDevice 4016 failure is not a reason to retry an unchanged blocker. Use the
isolated QA simulator, not hAiity's shared device. Never record room audio during
automated QA. Keep inactive legacy input until real behavior parity passes.

Completion means the pages read as one keyboard, accepted geometry stays intact,
every visible state matches its action, the relevant input/build checks pass and
physical limits are reported honestly. This plan adds no appearance settings,
recognition/model features or release actions.

## Implementation and verification checkpoint

The native keyboard now has adaptive opaque input plates in Solid, 22pt Regular
letters/digits, 12pt commands and Space, 14pt number-pad corners and the retained
45pt circles. Space uses Regular text. Punctuation hints are 11pt with a shared
adaptive foreground. Commands depress by 3% using the existing press/release clock.
The passive SwiftUI faces and UIKit drawing/control faces read the same roles.
Reduce Transparency/Increase Contrast use opaque semantic backgrounds.

Language, Paste, board and Dismiss accessories have quieter faces. The flat power
control remains available in its original positions. AUTO fits without shrinking
below 11pt. Host Return titles and their accent follow the existing field policy
on Letters, Symbols and Emoji; non-letter pages retain their page navigation.
All Return actions still use the existing proxy route.

The full emoji rail retains its position and gesture owner, with a clearer rounded
selection marker. Popup/variant text uses the same Regular treatment. The board
shows a separate state/elapsed label and accurate Finish/Cancel actions. Compact
voice faces stack their mark and full action label within the existing frame.
A bounded delivered-text preview appears only while the existing recovery offer
is verified against the same document, selection and surrounding text, and only
in idle/ready. It creates no live transcript stream or new result owner.

Verification evidence:

- **1,891 Core tests, one existing skip, zero failures.** Updated existing visual
  contracts reflect the approved shapes and shared palette.
- The production UIKit input harness passes overlapping typing, shared command
  sizes, holds/repeats/cancellation, both materials, optional insets, the category
  rail and momentum, variants, landscape previews, Space travel/reversal,
  haptic delivery instrumentation and native service controls. Added checks verify
  host Return labels/navigation and opaque accessibility fills. The tested Solid
  foreground/background combinations have a minimum contrast of **5.597:1** on
  the fixture backdrop. This does not measure system Glass compositing.
- **160 before/after native layouts** cover Letters, both symbol layers, numeric
  and phone pads, Emoji and four board states at 320/402pt, portrait/landscape,
  Solid/Glass and light/dark. Their key plate, target and control frame maps are
  identical. **64 additional native renders** cover meaningful large-text layouts
  at the largest content-size trait. Visual review caught and corrected AUTO and
  compact voice-label truncation.
- Final simulator Debug and signed generic-device Release builds pass. Both deep
  strict signature checks pass. The final Debug app is installed on isolated QA
  simulator `A4E54392-A584-48AE-A0A0-EEB4807923FD`.
- Final synthetic component timings: preview press/release median **0.055ms**,
  p95 **0.145ms**, one reused preview host; Space press/release median **0.013ms**,
  p95 **0.025ms**. These measure instrumented component work, not phone input
  latency, dictation processing, or an established improvement over a baseline.

Captures live outside the repository under
`/Users/enricomini/.codex/visualizations/2026/09/07/01a07d2b-a9ca-7dd3-9542-e9bac2049c97/`:
`saiity-keyboard-before/`, `saiity-keyboard-after/` and `saiity-keyboard-large/`.
The runnable renderer is `scripts/render-native-keyboard.swift`; `--large` renders
the large-text set. It uses inert proxy data and restores its fixture preferences.
Logs/build artifacts: `/tmp/saiity-keyboard-design.Qnx1D2/`, including
`all-core-tests.log`, `native-input.log`, `simulator-build.log`, `device-build.log`,
`render.log` and `large-render.log`.

Actual phone typing, mic-on haptics, host-field/settings parity, landscape feel and
system Glass remain physical verification gates. The earlier Air CoreDevice 4016
blocker was not retried. No microphone capture or model download was performed.
The existing broader PiP, Live Activity and Qwen gates remain separate. Legacy
input remains, and the continuation heartbeat stays paused. No commit, push,
release change or TestFlight upload occurred.

### Emoji list expansion follow-up

The user requested more space for emojis, ending immediately above the category
bar and flowing behind Delete. The native pager now ends at the category rail's
top edge, reclaiming its former 6pt reservation. Its four rows also reclaim the
separate 4pt command-row deduction. The existing 4pt inner grid padding remains.
Category and Delete positions are unchanged. Delete receives overlay touches
first; the list receives touches in its expanded area before the category's
invisible hit expansion. The visible rail retains its normal tap/drag owner.

110 focused Core checks and the production UIKit input harness pass, including
expanded-row routing, Delete overlap, rail taps, momentum, holds and cancellation
in both materials. Debug and signed Release builds and strict signatures pass.
The updated development app is installed on isolated QA. Sixteen native Emoji
renders cover both materials/appearances, 320/402pt and portrait/landscape at
`saiity-emoji-expanded/` beside the other captures. Logs are
`/tmp/saiity-keyboard-design.Qnx1D2/emoji-{core-tests,native-input,simulator-build,device-build,render}.log`.
No recording, model download, commit, push or TestFlight upload occurred.

### Minimal mockup integration and native fallback investigation

The user approved the example image's more minimal direction. The accessory lane
now has More on the left and power/voice together on the right on typing pages.
The native menu keeps Paste (or one-time code), Output language, Dismiss keyboard
and available original/result recovery actions. Menu contents refresh on opening.
The voice mark is blue; accessories have no resting bezels and More does not pulse.
The shared optional surface has a flat boundary, preserving its stored setting.
The emoji categories remain fully visible above Space with a selected symbol and
small underline, without a surrounding capsule. The expanded emoji list and
Delete overlay remain. Character/bottom plates, circles and all input owners keep
their accepted sizes and geometry. Glass remains a native material choice.

The accompanying report of a native keyboard labelled “Q” is **not reproduced**.
Source and built metadata declare sAiity / `en-US`, with the correct extension
principal class and ASCII capability. The keyboard has no call that advances to
Apple's input mode and no code assigning “Q” as its language. Simulator PlugInKit
lists the installed extension. The QA simulator's enabled-keyboard list contains
only Apple English, German and Emoji; its native keyboard in a text field is
expected and is not evidence of the reported phone failure. No physical crash
report from that reproduction is available in this checkout. Password/secure
fields, phone fields and host apps that reject extensions remain system-controlled.

The investigation did find a concrete crash risk in document-bound result preview
and recovery: UIKit may return nil for `documentIdentifier` during host attachment
or teardown, while Swift imports it as a non-optional UUID. A small nullable ObjC
inline shim in the existing bridging header now supplies the optional ID through
`HostInputTraits`. All preview/undo/original-restoration callers use it and require
a real matching document before destructive recovery. This removes the unsafe
bridge without weakening field identity checks. It is not proof of the “Q” cause.

Verification: 1,891 Core tests pass with one existing skip, followed by 76 final
keyboard contracts after the menu extraction. The production UIKit harness passes,
including native More contents/dismiss action and an actual ObjC nil/non-nil/nil
document getter. All key plate and grid target frames match the previous redesign.
160 native presentation renders and 64 large-text renders were reviewed. Final
Debug/signed Release builds and deep strict signatures pass. The latest app is
installed on isolated QA. Native menu contents/actions are checked in the harness;
actual system menu interaction and the reported phone fallback still need device
reproduction. No room audio, model download, commit, push or upload occurred.

Captures: `saiity-keyboard-minimal/` and `saiity-keyboard-minimal-large/` under the
existing visualization directory. Logs: `/tmp/saiity-keyboard-design.Qnx1D2/minimal-{core-tests,final-contracts,native-input,simulator-build,device-build,render,large-render}.log`.
The continuation heartbeat stays paused and physical gates remain open.

### Narrower grid commands follow-up

Caps/Shift, 123/#+= and grid Delete faces are 5.5pt narrower, reserving the
same spacing used between character keys. Outer edges and heights stay aligned.
The shared face resolver applies this only when drawing; placement, touch targets,
adaptive seams and the bottom bar retain their previous geometry.

114 focused Core tests and the production UIKit harness pass. Native command-gap
checks cover 320/402pt portrait and 667/852pt cramped landscape, both materials
and all grid pages. All geometry entries in 160 native captures match the prior
minimal keyboard; representative letters/symbol renders were reviewed. Debug and
signed Release builds and strict signature verification pass. The updated app is
installed on isolated QA. Captures: `saiity-command-width/` beside the earlier
matrices. Logs: `/tmp/saiity-keyboard-design.Qnx1D2/command-width-{core-tests,native-input,simulator-build,device-build,render}.log`.
Physical feel and system Glass compositing remain separate device checks.
No commit, push, release change, upload, recording or model download occurred.

## Design references

Apple Design's locally saved HIG references informed the platform requirements:

- `accessibility.md › Vision/Mobility`: "Convey information with more than color
  alone" and "Consider spacing between controls as important as size."
- `layout.md › Visual hierarchy`: "Align components with one another" to
  communicate organization and hierarchy.
- `typography.md › Supporting Dynamic Type`: "Maintain a consistent information
  hierarchy regardless of the current font size."
- `buttons.md › Best practices/Style`: "Always include a press state for a custom
  button" and "Use style — not size — to visually distinguish the preferred choice."
- `color.md › Liquid Glass color`: "Apply color sparingly to the Liquid Glass
  material, and to symbols or text on the material."
- `motion.md › Providing feedback`: "In apps, generally avoid adding motion to UI
  interactions that occur frequently."
- `virtual-keyboards.md › Best practices/Custom keyboards`: match field content
  and provide an obvious way to switch keyboards.
- `playing-haptics.md › Best practices`: "Make haptics optional."

Shape candidates, key hierarchy and typography comparisons are product design
judgments. Ponytail keeps the implementation on the current native owners and
shared style values; a new theme engine or alternate keyboard implementation
would add maintenance without helping this redesign.
