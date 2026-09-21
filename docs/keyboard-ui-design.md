# Keyboard UI

Visual rules for the sAiity keyboard. Geometry and material tokens live in
`VoiceOnlyKeyboardPolicy`. SwiftUI draws the plates. UIKit owns the hits on the
dictation board, the letter keys, and the emoji pager.

This is the current system, plus the shape later code should converge on.
Do not treat the numbers below as a redesign. The number-pad inset, key
heights, period plate, and dictation switch were tuned on device and stay as
they are.

## Split

| Layer | Owner | Job |
| --- | --- | --- |
| Frames | `VoiceOnlyKeyboardPolicy` | Where a control sits, and how big the glass face is inside the hit |
| Plates | `KeyboardGlassSurface` | Liquid glass, solid fill, or the accessibility fill |
| Hits | `ImmediateKeyButton`, `KeyboardActionButton`, `UISwitch`, `EmojiPagerCollectionView` | Touches, holds, paging |

A plate never receives the touch. `KeyboardGlassSurface` turns hit testing
off for every plate, including the board. The key control in front of the
plate is the hit target. Solid fills are opaque, so a clear control behind
or under them was being skipped; key controls keep a faint fill so the hit
reaches them in both materials.

The emoji list stays a `UICollectionView`. Do not wrap it in a second glass
rectangle. The suggestion lane has no extra glass behind it.

## Materials

One modifier decides the fill. `KeyboardInteractionPreferences.liquidGlassEnabled`
switches the look. It must not switch which view owns the touch.

| Preference | Control plate | Board |
| --- | --- | --- |
| Liquid glass, iOS 26 | `.glassEffect(.regular.interactive())` | `.glassEffect(.regular)` |
| Liquid glass, older iOS | `.regularMaterial` | `.regularMaterial` |
| Solid | `tertiarySystemFill` | no extra fill |
| Reduce Transparency | `secondarySystemFill` | `secondarySystemFill` |
| Increase Contrast | `systemFill` | `systemFill` |

Colors are system colors. The only green is `UISwitch.onTintColor = .systemGreen`
on the keyboard-dictation switch, matching Settings. Do not tint keys, the mic,
or the board to show that switch.

## Radii

Continuous corners. Name the radius at the call site; do not pass a raw number
when a token exists.

| Token | Value | Used for |
| --- | --- | --- |
| `keyCornerRadius` | 8 | Letter and symbol plates when Key containers is on |
| `commandKeyCornerRadius` | 18 | ABC, 123, emoji, shift, delete, space, return, utility chrome |
| `numberPadKeyCornerRadius` | 22 | Digit, ABC, and delete plates on the number pad |
| `emojiHighlightCornerRadius` | 13 | Pressed emoji cell |

Capsules stay capsules: the dictation mic, the language chip, and the space
bar on the voice page. The dictation on/off control is a system `UISwitch`,
not a drawn capsule.

## Hit and face

The finger target and the glass face are different rectangles.

- Command chrome (delete, Caps, page switches, emoji, return) uses the full
  hit rect, then `commandVisualInset` (8) to shrink the plate.
  `commandVisualSize(for:)` is that shrink.
- Letter keys fill their grid cell. The plate is the cell when Key containers
  is on, and nothing when it is off. `letterKeyPlate()` is the only switch.
- The ABC-page period is a command-sized hit (`letterPeriodFrame`) with a
  letter-width plate (`periodKeyPlateWidth` 34). The plate height is the
  command face height, `commandVisualSize`, so it lines up with ABC, 123, and
  emoji. The hit stays the full slot.
- Number-pad keys fill their cells. Padding is the pad's edge
  (`numberPadEdgeInset` 14), not an inset on each key. Spacing is
  `numberPadKeySpacing` 10 and `numberPadRowSpacing` 8.
- Emoji cells are their own 44pt targets. Do not grow a cell into its
  neighbor.

Minimum hit is 44pt on the short side (`controlSize`, `bottomActionHitHeight`,
`actionHitSize`). A smaller plate is fine. A smaller hit is not.

## Plates

Two modifiers, one material implementation.

- `letterKeyPlate(cornerRadius:)` — letters and symbols. Draws only when Key
  containers is on. Default radius `keyCornerRadius`. The number pad passes
  `numberPadKeyCornerRadius` because those keys are wide.
- `commandKeyPlate(cornerRadius:)` — always on. Default radius is
  `commandKeyCornerRadius`.
- `CommandKeyFace` — the symbol or short label on that plate. Callers pass the
  plate size. The hit target stays outside the face.

`appleControlSurface` only forwards to `keyboardGlass`. Capsules (the mic, the
language chip, the voice-page space bar) and the board shape use it because
they are not command rectangles. Do not add another material branch.

## Controls

| Control | Draw | Hit |
| --- | --- | --- |
| Letter, symbol, number digit | `letterKeyPlate` | `ImmediateKeyButton` / `ImmediateVariantKey` |
| Page switches, space, return, Caps | `commandKeyPlate` or `utilityGlyph` | UIKit overlay on the dictation board and letter page; SwiftUI button only where the overlay is off |
| Delete | `KeyboardDeleteButton` plate | Same button; hold deletes a word |
| Period on ABC | `letterKeyPlate` at `periodKeyPlateWidth` | Full command slot |
| Dictate | Capsule mic | `DictationMicButton` in the overlay |
| Keyboard dictation on/off | `UISwitch`, green when on | The switch itself, tested before the mic's expanded hit |
| Emoji | Cell glyph, highlight radius 13 | `EmojiKeyButton` inside the collection view |
| Suggestions | Text chips, radius 8 | The chip button. No glass well behind the row |

Dictation-board chrome (`areaMode` `.keys` and `.recording`) is drawn in
SwiftUI and hit-tested by the UIKit overlay (`voiceBoardUsesUIKitHits`).
Misses on that overlay return nil so the window can reach the view behind it.
Returning the hosting view from the overlay drops the emoji pager out of the
hit chain, and swipes stop working.

The Giella keyboard view stays hidden. It is not a second surface.

## Type and symbols

- Key captions: system 16pt semibold for command icons, system 14pt semibold
  for short command labels such as ABC and 123.
- SF Symbols for delete, mic, emoji, dismiss, paste, and language.
- Sentence case on accessibility labels. The compact language indicator may
  stay `AUTO`.
- Press feedback is the existing highlight on the key that was hit. Prediction
  must not recolor, resize, or move a key.

## Field keys

The ABC bottom row follows the host field. The choice lives in
`HostFieldPolicy.letterFieldKeys`. Email shows `@` in place of emoji and keeps
the period key. URL shows `/` and `.com`, and the return key says Go. Twitter
shows `@` and `#`. Web search keeps the standard keys and says Go. Number,
decimal, and phone fields open the number pad. Numbers and punctuation opens
the symbol page.

## Popups

Press previews, popouts, and hold menus use `keyboardGlass` and the corner
radius of the key that opened them: `keyCornerRadius` for letters and symbols,
`numberPadKeyCornerRadius` for the number pad, `emojiHighlightCornerRadius`
for emoji tones. The selected hold option uses the same label highlight as a
pressed key.

## Out of scope

The host app (Home, Models, Settings, onboarding, recording) keeps native
grouped lists and system controls. This file does not restyle those screens.
The vendored Giella theme is unused while that view is hidden.
