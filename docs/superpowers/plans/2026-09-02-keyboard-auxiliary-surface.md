# Keyboard Auxiliary Surface Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task.

**Goal:** Remove the rectangular keyboard background layer, simplify Emoji and symbols pages, and add a shared Emoji/123 control-order preference.

**Architecture:** Keep the current `UIInputView` plus SwiftUI root and `VoiceOnlyKeyboardPolicy`. The outer input view exposes the system backdrop, while one inset surface owns all page content. UIKit remains the hit-target owner for voice mode; SwiftUI owns auxiliary mode controls to avoid duplicate coordinate systems. A small App Group-backed enum is the only new shared state.

**Tech Stack:** Swift 5, SwiftUI, UIKit keyboard extension, Swift Package Manager `DictusCore`, Xcode Simulator, SimSlim.

## Global Constraints

- Preserve all existing dirty, untracked, and ahead-of-origin work.
- Use only SimSlim device `AC636497-5EC6-4AD4-BD83-E5E2458FA702` on iOS 26.5 for runtime verification.
- Do not use DeviceHub, a physical iPhone, iPhone Mirroring, extra simulators, TestFlight, or release publishing for this task.
- Do not add a manager, service, factory, or provider layer.
- Keep every interactive target at least 44 by 44 points.
- Use semantic system colors/materials and existing reduced-transparency, reduced-motion, and increased-contrast fallbacks.
- The default control order is `Emoji, 123`.
- The auxiliary top accessory row contains no revert, dictate, delete, or enter controls.

### Task 1: Shared background and control-order contract

**Files:**
- Modify: `DictusKeyboard/InputView.swift`
- Modify: `DictusCore/Sources/DictusCore/SharedKeys.swift`
- Create: `DictusCore/Sources/DictusCore/KeyboardAccessoryOrder.swift`
- Modify: `DictusCore/Sources/DictusCore/VoiceOnlyKeyboardPolicy.swift`
- Create: `DictusCore/Tests/DictusCoreTests/KeyboardAccessoryOrderPreferenceTests.swift`

**Interfaces:**
- Produce `KeyboardAccessoryOrder: String, CaseIterable, Codable` with `emojiFirst` and `numberFirst`, a semantic display title, and App Group read/write helpers.
- Extend `VoiceOnlyKeyboardPolicy.layout(for:surfaceHeight:controlOrder:)` with a default of `.emojiFirst`; all existing callers remain source-compatible.
- The policy must expose one inset surface frame and bottom auxiliary content/control frames without retaining the old top accessory row.

- [ ] Write tests for default/fallback preference, persistence, and deterministic frame ordering.
- [ ] Run `swift test --package-path DictusCore --scratch-path /tmp/saiity-keyboard-order-red` and verify the new tests fail because the preference and frame contract are absent.
- [ ] Implement the transparent `KeyboardInputView` initializers and the minimal shared preference/policy changes.
- [ ] Run the same focused tests and then `swift test --package-path DictusCore --scratch-path /tmp/saiity-keyboard-order-green`; record the output.
- [ ] Commit only Task 1 files with `feat: share keyboard auxiliary control order`.

### Task 2: Settings control-order Picker

**Files:**
- Modify: `DictusApp/Views/SettingsView.swift`
- Create: `DictusCore/Tests/DictusCoreTests/KeyboardOrderSettingsContractTests.swift`

**Interfaces:**
- Consume `KeyboardAccessoryOrder` from Task 1 and bind the Picker to `UserDefaults(suiteName: AppGroup.identifier)` using the existing settings style.
- Display exactly two choices: `Emoji, 123` and `123, Emoji`; default to `Emoji, 123`.

- [ ] Add a source contract test proving the settings page uses the App Group store, exposes both choices, and does not write a local-only preference.
- [ ] Run the focused contract test and verify it fails before the settings control exists.
- [ ] Add the compact native Settings row in the existing Keyboard section; do not restore removed legacy settings.
- [ ] Run the focused test and the full `swift test --package-path DictusCore --scratch-path /tmp/saiity-keyboard-settings-green`.
- [ ] Commit only Task 2 files with `feat: add keyboard control order setting`.

### Task 3: SwiftUI Emoji and symbols surfaces

**Files:**
- Modify: `DictusKeyboard/KeyboardRootView.swift`
- Modify: `DictusKeyboard/Views/EmojiPickerView.swift`
- Modify: `DictusKeyboard/Views/EmojiCategoryBar.swift`
- Modify: `DictusKeyboard/KeyboardLayouts.swift`
- Create: `DictusCore/Tests/DictusCoreTests/AuxiliarySurfaceContractTests.swift`

**Interfaces:**
- Consume the Task 1 layout frames and `KeyboardAccessoryOrder.current`.
- `EmojiPickerView` accepts a `onBackToVoice` closure and passes it to a fixed leading microphone control in `EmojiCategoryBar`.
- `LiquidSymbolPageView` renders Emoji and microphone controls in its lower-left cluster and the page toggle directly above Emoji.

- [ ] Add contract tests for no old accessory-row rendering, no per-category glass effect, fixed Emoji mic, symbols bottom cluster, and one shared inset surface.
- [ ] Run the focused contract test and verify it fails against the current top-row/per-category implementation.
- [ ] Make the root render a single inset surface around each mode; remove the auxiliary top row and search affordance.
- [ ] Remove category-item glass backgrounds, preserve one shared pointer highlight, add fixed return mic, and reserve only the bottom category/control lane.
- [ ] Render symbols controls in the same coordinate system as the grid, preserving delete/Return and page transitions.
- [ ] Run the focused tests and `swift test --package-path DictusCore --scratch-path /tmp/saiity-keyboard-surfaces-green`.
- [ ] Commit only Task 3 files with `feat: simplify auxiliary keyboard surfaces`.

### Task 4: UIKit integration and final verification

**Files:**
- Modify: `DictusKeyboard/KeyboardViewController.swift`
- Modify: `DictusCore/Tests/DictusCoreTests/VoiceOnlyKeyboardContractTests.swift`

**Interfaces:**
- Consume the order-aware policy frames from Task 1.
- UIKit voice controls use the selected Emoji/123 order. All auxiliary UIKit controls are hidden and cannot intercept SwiftUI controls.
- Returning to voice removes any auxiliary-only glass view and restores normal voice configuration.

- [ ] Add/adjust contract tests for voice order consumption, auxiliary UIKit control hiding, hit-target ownership, and no auxiliary top-row frames.
- [ ] Run those tests and verify the new assertions fail before the integration change.
- [ ] Update `layoutVoiceActionControls()` and auxiliary mode transitions to use the shared order and SwiftUI ownership.
- [ ] Run focused tests, `git diff --check`, and a fresh signed simulator build.
- [ ] Install the app on SimSlim and verify light/dark voice, Emoji, and symbols pages, fixed mic returns, symbols page switching, delete/Return, and visual absence of the square layer.
- [ ] Commit only Task 4 files with `fix: route auxiliary keyboard controls through SwiftUI`.

### Final review

- [ ] Review the complete diff against the pre-task base, including all existing dirty files without staging them.
- [ ] Run `swift test --package-path DictusCore --scratch-path /tmp/saiity-keyboard-auxiliary-final` and record test count/failures.
- [ ] Run `xcodebuild build -project Dictus.xcodeproj -scheme sAiity-iOS -configuration Debug -destination 'platform=iOS Simulator,id=AC636497-5EC6-4AD4-BD83-E5E2458FA702' -derivedDataPath /tmp/saiity-keyboard-auxiliary-final-build`.
- [ ] Restore SimSlim to light appearance and leave the device as the only booted simulator.
- [ ] Do not publish, upload TestFlight, or clean unrelated worktree files.
