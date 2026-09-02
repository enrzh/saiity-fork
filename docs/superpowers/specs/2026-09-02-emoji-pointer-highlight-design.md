# Emoji Pointer Highlight

## Goal

Make the emoji picker read as one clean native keyboard surface. Emoji cells
must not look like separate glass buttons, while the emoji under a finger must
still have clear press feedback during tap and drag selection.

## Interaction

- Each emoji is rendered as a glyph in a fixed hit area with no per-cell
  background, glass effect, border, or shadow.
- The grid owns one temporary highlight. It is shown only while a touch is
  active and is positioned behind the currently targeted emoji cell.
- A zero-distance drag gesture updates the targeted cell continuously as the
  finger moves across the grid. The highlight moves with the target using a
  short, responsive animation and never leaves more than one highlight on
  screen.
- Releasing over a valid emoji inserts that emoji and clears the highlight.
  Releasing outside the grid clears the highlight without inserting anything.
- Voice, category navigation, recent emoji storage, and accessibility actions
  keep their current behavior.

## Visual treatment

The shared highlight uses the existing semantic keyboard material/color
conventions and remains legible in light mode, dark mode, increased contrast,
and reduced transparency. It is sized to the active cell rather than to the
emoji glyph, so the feedback reads as a soft native key-state glow without
creating a visible container for every emoji.

## Implementation boundary

Change `DictusKeyboard/Views/EmojiPickerView.swift` only for production
behavior unless a focused test requires an existing test file change. Reuse
the existing `pressedEmojiIndex`, `DragGesture`, and `emojiIndex(at:)` path.
Do not add a manager, service, factory, or new keyboard architecture.

## Verification

- Add a source contract test that fails while a cell owns
  `keyboardGlassEffect()` and passes only when a shared pointer highlight is
  present.
- Run the focused DictusCore tests and the full DictusCore suite.
- Build the signed app for the authorized SimSlim simulator.
- Inspect the emoji picker in light and dark appearance and exercise tap,
  hold, drag across cells, release outside, category changes, and accessibility
  activation.
- Confirm the category bar remains unchanged and no per-emoji glass container
  or clipping appears.
