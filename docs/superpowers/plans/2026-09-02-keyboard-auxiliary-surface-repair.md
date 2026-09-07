# Keyboard Auxiliary Surface Repair

## Scope

Repair the remaining source contracts for the approved keyboard surface task in the existing `saiity-fork` checkout. The main implementation will handle shared geometry and UIKit ownership separately.

## Task 1: Category bar and root navigation cleanup

**Write set:**

- `DictusKeyboard/Views/EmojiCategoryBar.swift`
- `DictusApp/Views/MainTabView.swift`

**Requirements:**

- Keep the fixed leading `mic.fill` control and the horizontal category scroll view.
- Render every category with its monochrome SF Symbol via `Image(systemName: section.icon)`; do not reference or render `representativeEmoji` or `Text(emoji)`.
- Keep category controls unwrapped by per-category glass effects and preserve 44pt hit areas, semantic labels, and selected state.
- Remove the Models root `TabView` item from `MainTabView`, its tag, and its tab-specific navigation stack. Keep the existing Home and Settings tabs and their selection behavior intact; Settings remains responsible for the Models navigation link.
- Do not touch tests, shared policy, keyboard root, UIKit controller, or unrelated app behavior.

**Verification:**

- Run `swift test --package-path DictusCore --scratch-path /tmp/saiity-keyboard-surface-agent-red --filter 'AuxiliarySurfaceContractTests|VoiceOnlyKeyboardContractTests'` before the edit and confirm the relevant source-contract assertions fail.
- Run the same focused test after the edit and report the result.
- Run `git diff --check`.

## Global constraints

- Preserve all pre-existing dirty, untracked, and ahead-of-origin changes.
- Use native SwiftUI controls, semantic system colors, and no new manager/service/factory/provider layer.
- Report in concise Simplified Chinese with changed files, tests, and any concern.

## Task 2: Finish the keyboard surface and auxiliary pages

**Write set:**

- `DictusKeyboard/InputView.swift`
- `DictusKeyboard/KeyboardViewController.swift`
- `DictusKeyboard/KeyboardRootView.swift`
- `DictusKeyboard/KeyboardLayouts.swift`
- `DictusKeyboard/Views/EmojiPickerView.swift`
- `DictusKeyboard/Views/EmojiCategoryBar.swift`
- `DictusCore/Sources/DictusCore/VoiceOnlyKeyboardPolicy.swift`
- `DictusCore/Sources/DictusCore/KeyboardSymbolsLayout.swift`
- focused tests under `DictusCore/Tests/DictusCoreTests/`

**Requirements:**

- There is exactly one inset, rounded Liquid Glass surface for voice, Emoji, and both symbols pages. The area outside that shape must remain transparent so the native iOS keyboard backdrop is visible; no solid or squared intermediate layer may be introduced by `UIInputView`, UIKit hosting, or SwiftUI roots.
- Use one shared live layout from `VoiceOnlyKeyboardPolicy` for surface frame, page content, controls, and hit targets. The inset must be aligned identically on all three modes and use the real input-view height.
- Remove the legacy top suggestion/accessory row and ensure no hidden UIKit view intercepts Emoji or symbols controls. SwiftUI owns the complete Emoji and symbols page interaction.
- Repair both symbols pages as complete three-row layouts. All insert, delete, Return, and symbols1 <-> symbols2 actions must be reachable and must not be covered by the lower control lane. The lower-left lane is `#+=`/`ABC` above Emoji, with the microphone beside Emoji; it stays inside the shared surface and has non-overlapping 44pt hit targets.
- Keep the Emoji page search-free. Pin its category bar to the actual bottom of the shared surface. Keep only one fixed microphone return control at the leading edge, render category icons as undimmed monochrome SF/ASCII glyphs with no per-category glass, and keep the horizontal category scroll independent from the fixed microphone.
- Keep the voice page's current left/right control order preference, centered white microphone capsule, and real error message outside the capsule. UIKit hit targets must be transparent in their normal state and must not create a second visual surface when highlighted.
- Preserve the Models-only-from-Settings navigation already implemented in `MainTabView`.
- Add behavior-level regression tests for transparent ownership, shared surface frame alignment, complete symbols rows and actions, bottom Emoji anchoring, absence of the legacy row, and non-overlapping hit geometry. Tests must be written and run red before production edits, then green after the minimal fix.

**Verification:**

- Run focused core tests before the production edit and record the expected red result.
- Run focused tests and `swift test --package-path DictusCore` after the edit.
- Run `git diff --check` and one Xcode simulator build.
- Use only SimSlim `AC636497-5EC6-4AD4-BD83-E5E2458FA702` on iOS 26.5 for light/dark screenshots and interaction checks of voice, Emoji, symbols1, and symbols2. Do not use DeviceHub, a physical iPhone, iPhone Mirroring, extra simulators, release publishing, or TestFlight.

## Global constraints for Task 2

- Preserve all existing dirty, staged, untracked, and ahead-of-origin work; do not reset, clean, stash, or overwrite unrelated changes.
- Prefer the smallest existing-type/function change. Do not add a manager, service, factory, provider, resolver, registry, or adapter.
- Report changed paths, commands and exact test counts in concise Simplified Chinese.
