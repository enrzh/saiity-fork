# Apple Keyboard Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task.

**Goal:** Deliver a stable 216-point voice keyboard with first-party iOS visual hierarchy and identical chrome across voice, emoji, and number modes.

**Architecture:** Keep `KeyboardState` and `KeyboardViewController` as existing owners. `VoiceOnlyKeyboardPolicy` remains the single geometry source; SwiftUI draws native visuals and UIKit owns proxy/input-mode actions. Alternate modes replace only the center content region.

**Tech Stack:** SwiftUI, UIKit, DictusCore, XCTest, iOS 17+, iOS 26 Liquid Glass availability checks.

## Global Constraints

- Preserve all dirty and untracked work.
- Surface height is exactly 216 points.
- All hit targets are at least 44 by 44 points.
- Do not add manager/service/factory/protocol abstractions.
- Do not push or upload TestFlight before physical acceptance.

### Task 1: Stable Apple Keyboard Geometry

**Files:**
- Modify: `DictusCore/Sources/DictusCore/VoiceOnlyKeyboardPolicy.swift`
- Modify: `DictusCore/Tests/DictusCoreTests/VoiceOnlyKeyboardPolicyTests.swift`
- Modify: `DictusCore/Tests/DictusCoreTests/VoiceOnlyKeyboardContractTests.swift`

**Interfaces:**
- Produce absolute frames for `language`, `delete`, `return`, `dictate`, four bottom-leading actions, and `dismiss`.

- [ ] Add failing tests for 320, 375, 390, and 430 point widths asserting top row, centered dictate region, one horizontal bottom row, no overlap, and 216-point bounds.
- [ ] Replace the 2-by-2 utility geometry with a horizontal bottom row and stable center frame.
- [ ] Assert 88-by-44 trailing actions, 44-point utilities, and compact visual sizes independently.
- [ ] Run `swift test --package-path DictusCore --filter 'VoiceOnlyKeyboard(Policy|Contract)Tests'`; expect zero failures.

### Task 2: Unified Voice Chrome

**Files:**
- Modify: `DictusKeyboard/KeyboardRootView.swift`
- Modify: `DictusKeyboard/KeyboardViewController.swift`

**Interfaces:**
- Consume Task 1 frames verbatim for both visuals and UIKit hit targets.

- [ ] Add source/contract tests proving there is one visible globe owner, embedded status, and no mode-specific duplicate utility actions.
- [ ] Render native semantic keyboard background and a fixed top/center/bottom hierarchy.
- [ ] Place status and state symbol inside the dominant dictate capsule without changing its frame.
- [ ] Render one UIKit-owned 18-point globe in a 44-point target and preserve `handleInputModeList(from:with:)`.
- [ ] Preserve fail-closed text proxy routing and recovery behavior.
- [ ] Run focused tests and a generic `DictusKeyboard` build; expect success.

### Task 3: Emoji And Number Content Regions

**Files:**
- Modify: `DictusKeyboard/Views/EmojiPickerView.swift`
- Modify: `DictusKeyboard/Views/EmojiCategoryBar.swift`
- Modify: `DictusKeyboard/KeyboardViewController.swift`
- Modify: `DictusKeyboard/KeyboardLayouts.swift`
- Modify: `DictusCore/Sources/DictusCore/KeyboardAreaMode.swift`
- Modify: `DictusCore/Tests/DictusCoreTests/KeyboardAreaModeTests.swift`

**Interfaces:**
- Alternate content must fit inside the content region while global chrome remains visible.

- [ ] Add failing tests proving emoji and numbers preserve common chrome and cannot add duplicate globe/delete/Return/dismiss actions.
- [ ] Constrain emoji grid and category controls to the center content region; remove duplicated global actions.
- [ ] Constrain the symbol layout to the center region and remove duplicated bottom-row system actions.
- [ ] Make the fixed mode control display `123` on voice and `ABC` in alternate modes.
- [ ] Run focused mode tests and generic build; expect success.

### Task 4: Keyboard Review And Physical Gate

**Files:**
- Review all files changed by Tasks 1-3.

- [ ] Run `swift test --package-path DictusCore`; expect zero failures.
- [ ] Run `git diff --check`; expect no errors.
- [ ] Run a signed build for the connected physical iPhone and install it with `devicectl`.
- [ ] Capture and inspect idle, failed, emoji, and number screenshots.
- [ ] Manually verify hold/release dictation, insertion, clipboard, delete, Return, `@`, emoji, numbers, next keyboard, and dismiss.
- [ ] Block release on any physical failure.
