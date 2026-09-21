# Keyboard UI unification

Make the keyboard draw every plate through one material path and one set of
named radii, without moving hit testing or changing the layout that is on the
phone now.

Design rules: [keyboard-ui-design.md](keyboard-ui-design.md).

## Why

`KeyboardGlassSurface` and `appleControlSurface` implement the same liquid
glass / solid / accessibility branches. Command corners are the literal `18`
in `KeyboardRootView`, `AuxiliaryBottomBar`, and `KeyboardDeleteButton`.
Emoji press highlight uses another literal, `13`. A new key today has to pick
a path by copying a nearby call site, and the two paths can drift (they
already differ on whether `.board` skips the solid fill the same way).

Hits are already in the right place: UIKit overlay for the dictation board,
`ImmediateKeyButton` for keys, `UICollectionView` for emoji, `UISwitch` for
the dictation toggle. Unification is visual. Do not fold those hits into
SwiftUI.

## Keep

- `VoiceOnlyKeyboardPolicy` frames, including `numberPadEdgeInset` 14,
  full-cell number-pad keys, `numberPadKeyCornerRadius` 22, and
  `periodKeyPlateWidth` 34.
- `letterKeyPlate` gated on Key containers. Command plates stay always on.
- Emoji as a collection view. No glass well behind the suggestion lane.
- `UISwitch` with `onTintColor = .systemGreen`. No custom colored mic capsule.
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

Letter keys and number-pad digits stay on `letterKeyPlate`. The period key
stays a letter plate inside a command hit. Do not force those through the
command face.

### 4. Lock the split in tests

Extend the existing contract tests rather than adding a snapshot suite:

- `appleControlSurface` no longer contains its own `glassEffect` branch.
- Command call sites use `commandKeyCornerRadius`.
- Emoji highlight uses `emojiHighlightCornerRadius`.
- `letterKeyPlate`, `commandKeyPlate`, the number-pad edge inset, the period
  plate width, the nil overlay miss, and `UISwitch` / `systemGreen` stay
  asserted as they are today.

## Do not do in this pass

- Restyle Home, Settings, onboarding, or the recording screen.
- Change number-pad padding, key height, or corner radius.
- Replace the dictation `UISwitch` with a drawn control.
- Animate or resize keys from prediction.
- Move emoji paging into SwiftUI.

## Status

Steps 1–4 are in the tree. Command and emoji radii are named. Plates go through
`KeyboardGlassSurface`. Delete, ABC, 123, emoji, return, shift, and the
voice-board utilities use `CommandKeyFace`.

## Check

Unit tests listed above, then a Debug install on the paired phone. On device,
confirm letter keys, the number pad (inset from the glass, tall keys), emoji
page swipes, the green Settings-style dictation switch, and both solid and
liquid glass. A token rename that does not touch frames should look identical.
