# Task 5 Report: Product Settings and Language Cleanup

Status: DONE_WITH_CONCERNS

## Requirements

- Removed the native iOS Settings app integration resource `DictusApp/Settings.bundle`.
- Removed the Settings.bundle file reference, group entry, and app resources build entry from `Dictus.xcodeproj/project.pbxproj`.
- Verified the existing product language implementation exposes only English and German through `SupportedLanguage.allCases` and `TranscriptionLanguageMode.settingsOptions`.
- Verified existing compatibility behavior: persisted French and Spanish transcription values resolve to English; unsupported keyboard language values resolve to English; implicit legacy French keyboard state migrates to automatic mode without changing the separate transcription preference.
- No user-facing Dictus wording or French/Spanish choices were found on the current SettingsView/onboarding surfaces that required in-scope changes. Existing Dictus identifiers and non-user-facing compatibility comments were left untouched.
- Model-management, license, and keyboard files were not modified.

## Changed Paths

- `Dictus.xcodeproj/project.pbxproj`
- `DictusApp/Settings.bundle/Root.plist` (deleted)
- `.superpowers/sdd/task-5-report.md`

The pre-existing untracked `.superpowers/brainstorm/` directory was preserved and not staged.

## Verification

### Diff and contract checks

Command:

```text
git diff --check
rg -n 'Settings\\.bundle|AA1000C1|AA0000C1' Dictus.xcodeproj/project.pbxproj DictusApp
```

Outcome: passed. No Settings.bundle references remain; `git diff --check` reported no errors.

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
xcodebuild -project Dictus.xcodeproj -scheme DictusApp -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/saiity-dictus-task5-derivedData CODE_SIGNING_ALLOWED=NO build
```

Outcome: passed. `** BUILD SUCCEEDED **`.

Warnings: existing API deprecation warnings, including `AVAudioSession.recordPermission`, `onChange(of:perform:)`, and keyboard trait APIs. These are outside this task.

## Commit

`978a9a97e3436a83d36fb1d83347108ada809f15` (`chore: clean up settings integration`)

## Concerns

- This task was verified by focused unit tests and simulator-target app compilation. No runtime UI inspection or physical-device validation was performed.
- The build uses `/Applications/Xcode-beta.app` and emits pre-existing warnings; none are introduced by this task's changed paths.
