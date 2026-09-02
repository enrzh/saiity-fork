# Emoji Pointer Highlight Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace per-emoji glass containers with one responsive shared highlight that follows the active touch target.

**Architecture:** Keep the existing `EmojiPickerView` state and zero-distance `DragGesture`. Wrap the grid in a local `ZStack`, draw one highlight behind the grid at the active cell's center, and leave the category bar and insertion path unchanged. No new coordinator, service, model, or file is needed.

**Tech Stack:** SwiftUI, XCTest source contracts, DictusCore package tests, Xcode, SimSlim.

## Global Constraints

- Each emoji remains in a fixed 44-point hit area with no per-cell background, glass effect, border, or shadow.
- The shared highlight is visible only during an active touch and follows the currently targeted cell.
- Releasing on a valid cell inserts once; releasing outside clears without insertion.
- Preserve voice, category navigation, recent emoji storage, and accessibility activation.
- Use SimSlim simulator `AC636497-5EC6-4AD4-BD83-E5E2458FA702` only; do not use the physical iPhone, DeviceHub, iPhone Mirroring, or TestFlight.
- Preserve all unrelated dirty and untracked worktree changes.

---

### Task 1: Shared Emoji Touch Highlight

**Files:**
- Modify: `DictusCore/Tests/DictusCoreTests/VoiceOnlyKeyboardContractTests.swift`
- Modify: `DictusKeyboard/Views/EmojiPickerView.swift`

**Interfaces:**
- Consumes: `pressedEmojiIndex`, `emojiIndex(at:)`, `insertEmoji(_:)`, and the existing `EmojiCategoryBar` call.
- Produces: a private `emojiPointerHighlight` view and a grid overlay that is driven by `pressedEmojiIndex`.

- [ ] **Step 1: Write the failing contract test**

Add this method to `VoiceOnlyKeyboardContractTests`:

```swift
func testEmojiGridUsesOnePointerHighlightInsteadOfPerCellGlass() throws {
    let picker = try source("DictusKeyboard/Views/EmojiPickerView.swift")
    let gridStart = try XCTUnwrap(picker.range(of: "LazyVGrid(columns: gridColumns"))
    let categoryStart = try XCTUnwrap(picker.range(of: "EmojiCategoryBar("))
    let gridBody = String(picker[gridStart.lowerBound..<categoryStart.lowerBound])

    XCTAssertFalse(gridBody.contains(".keyboardGlassEffect()"),
                   "emoji cells must not own individual glass containers")
    XCTAssertTrue(picker.contains("private var emojiPointerHighlight"),
                  "the picker must render one shared touch highlight")
    XCTAssertTrue(picker.contains("pressedEmojiIndex"),
                  "the shared highlight must follow the active emoji target")
    XCTAssertTrue(picker.contains("ZStack"),
                  "the highlight must be layered behind the emoji grid")
}
```

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```bash
swift test --package-path DictusCore --scratch-path /tmp/saiity-emoji-pointer-red --filter VoiceOnlyKeyboardContractTests/testEmojiGridUsesOnePointerHighlightInsteadOfPerCellGlass
```

Expected: the test fails because the current grid contains
`.keyboardGlassEffect()` and does not declare `emojiPointerHighlight`.

- [ ] **Step 3: Implement the minimal shared highlight**

In `EmojiPickerView.swift`:

1. Remove the `.background { RoundedRectangle ... .keyboardGlassEffect() }`
   modifier from the `Text(item.emoji)` cell. Keep its 44-point frame,
   content shape, accessibility action, and existing insertion behavior.
2. Replace the grid's direct `LazyVGrid` container with a `ZStack(alignment:
   .topLeading)` whose first child is the shared highlight and whose second
   child is the existing `LazyVGrid`. Keep the existing horizontal padding and
   gesture on the combined grid surface.
3. Add this private view and position it from the existing index:

```swift
@ViewBuilder
private var emojiPointerHighlight: some View {
    if let index = pressedEmojiIndex {
        RoundedRectangle(cornerRadius: 13, style: .continuous)
            .fill(.thinMaterial)
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
            }
            .frame(width: max(emojiCellWidth - 8, 36), height: rowHeight - 8)
            .position(
                x: CGFloat(index % 8) * emojiCellWidth + emojiCellWidth / 2,
                y: CGFloat(index / 8) * (rowHeight + rowSpacing) + rowHeight / 2
            )
            .allowsHitTesting(false)
            .transition(.opacity)
    }
}
```

The existing `onChanged` continues to assign `pressedEmojiIndex` from
`emojiIndex(at:)`, and the existing `onEnded` continues to insert the final
valid index before clearing the state. Use the existing animation on the
pressed index, or a short `.snappy` animation on the shared highlight, so the
highlight tracks cells without leaving stale highlights behind.

- [ ] **Step 4: Run the focused test and verify GREEN**

Run:

```bash
swift test --package-path DictusCore --scratch-path /tmp/saiity-emoji-pointer-green --filter VoiceOnlyKeyboardContractTests/testEmojiGridUsesOnePointerHighlightInsteadOfPerCellGlass
```

Expected: the focused test passes with no failures.

- [ ] **Step 5: Run the complete static test suite**

Run:

```bash
swift test --package-path DictusCore --scratch-path /tmp/saiity-emoji-pointer-full
```

Expected: all existing DictusCore tests pass.

- [ ] **Step 6: Build and verify the authorized simulator**

Run:

```bash
xcodebuild build -project Dictus.xcodeproj -scheme sAiity-iOS \
  -destination 'platform=iOS Simulator,id=AC636497-5EC6-4AD4-BD83-E5E2458FA702' \
  -derivedDataPath /tmp/saiity-emoji-pointer-simslim CODE_SIGNING_ALLOWED=NO
```

Install the resulting app with the existing SimSlim workflow, then inspect
the keyboard in light and dark mode. Exercise a tap, press-and-hold, drag
across several cells, release outside, category switching, and accessibility
activation. Confirm that only the active cell has a temporary highlight, the
glyphs have no individual containers, and the category bar remains unchanged.

- [ ] **Step 7: Commit only this feature's source and test files**

```bash
git add DictusCore/Tests/DictusCoreTests/VoiceOnlyKeyboardContractTests.swift DictusKeyboard/Views/EmojiPickerView.swift
git commit -m "fix: make emoji touch highlight follow the pointer"
```

Do not stage or modify the other existing dirty files.
