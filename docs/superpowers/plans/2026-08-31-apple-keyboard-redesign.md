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
- Do not push or upload TestFlight from this verification run; physical acceptance remains a separate gate.

### Task 1: Stable Apple Keyboard Geometry

**Files:**
- Modify: `DictusCore/Sources/DictusCore/VoiceOnlyKeyboardPolicy.swift`
- Modify: `DictusCore/Tests/DictusCoreTests/VoiceOnlyKeyboardPolicyTests.swift`
- Modify: `DictusCore/Tests/DictusCoreTests/VoiceOnlyKeyboardContractTests.swift`

**Interfaces:**
- Produce absolute frames for `language`, `delete`, `return`, `dictate`, the left utility actions, and `dismiss`.

- [x] Add regression tests for 320, 375, 390, and 430 point widths asserting top row, centered dictate region, stable utility geometry, no overlap, and 216-point bounds.
- [x] Replace the 2-by-2 utility geometry with the approved left rail and stable center frame.
- [x] Assert 88-by-44 trailing actions, 44-point utilities, and compact visual sizes independently.
- [x] Run the focused keyboard coverage as part of the full shared suite; zero failures.

### Task 2: Unified Voice Chrome

**Files:**
- Modify: `DictusKeyboard/KeyboardRootView.swift`
- Modify: `DictusKeyboard/KeyboardViewController.swift`

**Interfaces:**
- Consume Task 1 frames verbatim for both visuals and UIKit hit targets.

- [x] Add source/contract tests proving there is one visible globe owner, embedded status, and no mode-specific duplicate utility actions.
- [x] Render native semantic keyboard background and a fixed top/center/bottom hierarchy.
- [x] Place status and state symbol inside the dominant dictate capsule without changing its frame.
- [x] Render one UIKit-owned 18-point globe in a 44-point target and preserve `handleInputModeList(from:with:)`.
- [x] Preserve fail-closed text proxy routing and recovery behavior.
- [x] Run focused tests and the generic iOS test build; both succeed.

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

- [x] Add regression tests proving emoji and numbers preserve common chrome and cannot add duplicate globe/delete/Return/dismiss actions.
- [x] Constrain emoji grid and category controls to the center content region; remove duplicated global actions.
- [x] Constrain the symbol layout to the center region and remove duplicated bottom-row system actions.
- [x] Make the fixed mode control display `123` on voice and `ABC` in alternate modes.
- [x] Run focused mode coverage and the generic iOS test build; both succeed.

### Task 4: Keyboard Review And Physical Gate

**Files:**
- Review all files changed by Tasks 1-3.

- [x] Run `swift test --package-path DictusCore`; 1,218 tests executed, 10 skipped, and 0 failures.
- [x] Run `git diff --check`; no errors.
- [ ] Run a signed build for the physical iPhone and install it with `devicectl`; intentionally not run because the approved test path is SimSlim-only.
- [x] Capture and inspect the idle keyboard in light and dark appearances on SimSlim.
- [ ] Manually verify the complete dictation and alternate-page interaction flow; interaction coverage remains a device/runtime follow-up.
- [x] Keep the release gate closed until the remaining runtime interaction evidence exists.

## Verification Record

- SimSlim device: `AC636497-5EC6-4AD4-BD83-E5E2458FA702` (`170/170` managed daemons disabled).
- Xcode: `xcodebuild build-for-testing -project Dictus.xcodeproj -scheme sAiity-iOS -destination 'generic/platform=iOS'` succeeded.
- Visual captures: `/tmp/saiity-dictus-simslim-keyboard-light-7247.png` and `/tmp/saiity-dictus-keyboard-dark-final.png` inspected.
