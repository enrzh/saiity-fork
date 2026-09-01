# Task 5 Report: Product Settings and Language Cleanup

Status: DONE_WITH_CONCERNS

## Requirements

- Removed the native iOS Settings app integration resource `DictusApp/Settings.bundle`.
- Removed the Settings.bundle file reference, group entry, and app resources build entry from `Dictus.xcodeproj/project.pbxproj`.
- Verified the existing product language implementation exposes only English and German through `SupportedLanguage.allCases` and `TranscriptionLanguageMode.settingsOptions`.
- Verified existing compatibility behavior: persisted French and Spanish transcription values resolve to English; unsupported keyboard language values resolve to English; implicit legacy French keyboard state migrates to automatic mode without changing the separate transcription preference.
- Removed app-facing French localization entries from the app and keyboard string catalogs. Legacy French/Spanish raw values, internal types, and compatibility tests remain intact; only English and German remain product-selectable.
- Kept the sAiity brand in onboarding and current setup copy; no broad internal Swift type rename was made. License/model wording and keyboard behavior implementation were left untouched.
- Model-management, license, and keyboard files were not modified.

## Changed Paths

- `Dictus.xcodeproj/project.pbxproj`
- `DictusApp/Settings.bundle/Root.plist` (deleted)
- `DictusApp/Localizable.xcstrings`
- `DictusKeyboard/Localizable.xcstrings`
- `.superpowers/sdd/task-5-report.md`

The pre-existing untracked `.superpowers/brainstorm/` directory was preserved and not staged.

## Verification

### Diff and contract checks

Commands:

```text
git diff --check
test ! -e DictusApp/Settings.bundle
! git grep -n -E 'Settings\\.bundle|AA1000C1|AA0000C1' -- Dictus.xcodeproj/project.pbxproj DictusApp
jq -e 'all(.strings[]?; ((.localizations // {}) | has("fr") | not))' DictusApp/Localizable.xcstrings
jq -e 'all(.strings[]?; ((.localizations // {}) | has("fr") | not))' DictusKeyboard/Localizable.xcstrings
```

Outcome: passed. The resource is absent, project references are absent, both catalogs contain no `fr` localization entries, and `git diff --check` reported no errors. This is a focused content/project contract and does not depend on a hard-coded test fixture path.

### Focused core tests

Command:

```text
swift test --package-path DictusCore --filter 'TranscriptionLanguageModeTests|KeyboardLanguagePreferenceTests|SupportedLanguageActivationTests'
```

Outcome: passed. 29 tests executed, 0 failures.

Warnings: existing unhandled polish-harness README warning and existing Swift 6 Sendable warning for `SpeechEngine`.

### App build

Command:

```text
DEVELOPER_DIR=/Applications/Xcode-beta.app xcodebuild -project Dictus.xcodeproj -scheme DictusApp -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/saiity-dictus-task5-review-derivedData CODE_SIGNING_ALLOWED=NO build
```

Outcome: passed. `** BUILD SUCCEEDED **`.

Warnings: existing API deprecation warnings, including `AVAudioSession.recordPermission`, `onChange(of:perform:)`, and keyboard trait APIs. These are outside this task.

## Commit

`eaa3ec602fd322cd7d316cb1cce74aaa5b8a458e` (`fix: clean app-facing language localization`)

## Concerns

- This task was verified by focused unit tests and simulator-target app compilation. No runtime UI inspection or physical-device validation was performed.
- The build uses `/Applications/Xcode-beta.app` and emits pre-existing warnings; none are introduced by this task's changed paths.
