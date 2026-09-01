# Task 1 report

## Result

Shared keyboard geometry contract updated in `VoiceOnlyKeyboardPolicy.swift`.
The surface remains 216 points high; the standard insets are 6 points horizontally and 4 points vertically. The existing `Layout` now exposes explicit alternate-page accessory-row and below-row content frames. Runtime-height microphone fallback remains bounded, and 44-point action targets remain contained and non-overlapping at widths 320, 375, 390, and 430.

## TDD evidence

### RED

Command:

`swift test --package-path DictusCore --filter VoiceOnlyKeyboardPolicyTests/testSharedContractUsesSixByFourInsetsAndSplitsAlternatePageContent`

Output/result: failed during test compilation because `VoiceOnlyKeyboardPolicy.Layout` had no `alternateAccessoryRowFrame` or `alternateContentBelowAccessoryFrame`. This was the expected missing-contract failure.

### GREEN focused

Command:

`swift test --package-path DictusCore --filter VoiceOnlyKeyboard`

Output/result: `VoiceOnlyKeyboardContractTests` executed 37 tests with 0 failures; `VoiceOnlyKeyboardPolicyTests` executed 48 tests with 0 failures; total 85 tests with 0 failures.

### GREEN full

Command:

`swift test --package-path DictusCore`

Output/result: `DictusCoreTests.xctest` executed 1220 tests, 10 skipped, 0 failures. The command exited successfully. Existing warnings remain: an unhandled `polish-harness/README.md` package file and the pre-existing Swift 6 `Sendable` warning for `SpeechEngine`; one existing frequency-data diagnostic was printed during the suite.

## Files changed

- `DictusCore/Sources/DictusCore/VoiceOnlyKeyboardPolicy.swift`
- `DictusCore/Tests/DictusCoreTests/VoiceOnlyKeyboardPolicyTests.swift`
- `DictusCore/Tests/DictusCoreTests/VoiceOnlyKeyboardContractTests.swift`
- This report file.

## Review concerns

No task-blocking concerns. The alternate-page consumers still use `alternateContentFrame`; this task adds the explicit policy geometry requested without changing unrelated keyboard view files, as required by the brief.

## Commit

Final commit: the hash printed by `git rev-parse --short HEAD` after this report was committed; commit message is `feat: share keyboard geometry contract`.
