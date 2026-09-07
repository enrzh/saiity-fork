# Native Keyboard Surface Redesign

## Goal

Make the sAiity keyboard read as a native iOS voice keyboard: one inset rounded
glass surface, a centered white press-and-hold microphone, native full-width
emoji and symbols content, and a dedicated accessory row for alternate pages.

## Current implementation

The source and focused contract tests now implement the following:

- The auxiliary accessory row is owned by UIKit and spans the full native
  `UIInputView` width. Its backdrop is the native input-view backdrop; SwiftUI
  does not paint an inset surface behind the emoji or symbols grid.
- The row contains four UIKit hit targets: revert to voice, the white
  press-and-hold microphone, delete, and Return/confirm. The microphone is
  centered independently of the unequal left and right control groups.
- Emoji search has been removed. `EmojiPickerView` uses the available full
  width for the emoji grid and keeps its category bar below the grid.
- Symbols content is provided by the vendored keyboard grid below the UIKit
  accessory row. The symbols pages retain their native page navigation and
  use three content rows.
- Dictation failures render as an independent red error lane outside and below
  the microphone button. The lane has its own bounded geometry and does not
  take part in microphone hit testing.
- The shared geometry contract covers the inset voice surface, runtime height,
  supported widths, containment, non-overlap, narrow fail-closed behavior, and
  44-point minimum hit targets.

## Global constraints

- Preserve all existing dirty and untracked files.
- Keep the runtime keyboard height supplied by UIKit; the shared fallback remains
  216 points.
- Keep the implementation in `VoiceOnlyKeyboardPolicy`, `KeyboardRootView`, and
  `KeyboardViewController`; do not add a manager/service/factory layer.
- Every interactive target remains at least 44 by 44 points.
- Use semantic system colors/materials and respect reduced transparency, reduced
  motion, and increased contrast.
- The globe/switch-keyboard control is removed from this keyboard.
- Use SimSlim only for runtime keyboard verification. Do not use the physical
  iPhone or iPhone Mirroring, and do not upload TestFlight from this task.

## Task 1: Shared geometry contract (implemented)

`VoiceOnlyKeyboardPolicy` defines the approximately 6-point horizontal and
4-point vertical inset, keeps the 216-point shared fallback, and derives the
alternate accessory row and content frame below it. The policy and focused tests
cover widths 320, 375, 390, and 430, runtime heights, narrow fallback behavior,
containment, non-overlap, and 44-point hit targets.

## Task 2: SwiftUI surfaces and microphone visual (implemented)

`KeyboardRootView` keeps the inset rounded voice surface and white microphone
visual, while the `UIInputView` supplies the native keyboard backdrop. Auxiliary
content begins below the policy accessory row. The accessory visuals are owned
by UIKit, so SwiftUI does not introduce duplicate actions. Existing voice-page
status and translation behavior remains in place.

## Task 3: Alternate-page accessory row and UIKit routing (implemented)

`KeyboardViewController` installs the full-width UIKit accessory controls on both
emoji and symbols pages, hides the voice-only controls there, routes the
revert/microphone/delete/Return actions, handles microphone touch-down/up, and
keeps delete repeat behavior. `EmojiPickerView` supplies the search-free full
width emoji content. `Vendored/Views/KeyboardView.swift` supplies the symbols
grid below the row and preserves symbols-page navigation. Contract tests cover
ownership, visibility, geometry, routing, and content placement.

## Remaining runtime verification

The following is still outstanding and must be verified with SimSlim before any
runtime or release claim:

- Build and launch the keyboard through the authorized SimSlim path only.
- Capture voice, emoji, and symbols pages in light and dark appearance.
- Confirm the accessory row is visually full width on the native input-view
  backdrop and that no inset/duplicate surface appears.
- Exercise all four accessory hit targets, including microphone touch-down/up,
  delete long-press repeat, Return, and revert-to-voice.
- Confirm emoji content has no search UI and fills the expected width.
- Confirm all three symbols rows are visible and not clipped at the actual
  runtime keyboard height, including page transitions between symbols pages.
- Check the red error lane in the failed-dictation state and confirm it remains
  outside the microphone hit target.
- Check light/dark appearance, reduced transparency, reduced motion, increased
  contrast, and accessibility hit areas.

Do not use a physical iPhone, iPhone Mirroring, or TestFlight for this task.

## Completed static verification

- Focused and full `swift test --package-path DictusCore` contract/geometry
  coverage passes locally (139 tests, 0 failures at the time of review).
- `git diff --check` passes.
