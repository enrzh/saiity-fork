# Task 6 Report: Custom ASR and Cleanup Model Management

## Status

Implemented and verified in the current `saiity-fork` checkout. Built-in model download, selection, preparation, and deletion paths were left unchanged. Existing untracked files were preserved.

## Changes

- `DictusCore/Sources/DictusCore/CustomModel.swift`
  - Enforced role/source restrictions: Ollama is cleanup-only and NVIDIA is ASR-only.
  - Enforced HTTPS Hugging Face repository paths and NVIDIA developer repository paths.
  - Kept deterministic local ASR evidence checks and Hugging Face metadata validation.
  - Rejected URL query and fragment components.
  - Made App Group loading tolerate malformed records individually and deduplicate loaded data.
  - Made persistence deterministically replace duplicates by ID or normalized identity, keeping the last registration.
- `DictusApp/Views/ModelManagerView.swift`
  - Shows source and role for every saved custom registration.
  - Shows validation errors and runtime support limitations while retaining the entry.
  - Preserved the existing confirmation alert before custom deletion.
- `DictusCore/Tests/DictusCoreTests/CustomModelTests.swift`
  - Added provider/path validation coverage.
  - Added persistence deduplication coverage.
  - Added malformed-record safe-load coverage.

## Verification

- `swift test --package-path DictusCore --scratch-path /tmp/saiity-dictus-task6-final-core --filter 'CustomModelTests|AppleAppFoundationContractTests'`
  - Passed: 38 tests, 0 failures.
- `swift test --package-path DictusCore --scratch-path /tmp/saiity-dictus-task6-full-core`
  - Passed: 1178 tests executed, 10 skipped, 0 failures.
- `git diff --check`
  - Passed with no output.
- `xcodebuild -list -project Dictus.xcodeproj`
  - Confirmed `sAiity-iOS` scheme.
- `xcodebuild build -project Dictus.xcodeproj -scheme sAiity-iOS -destination 'generic/platform=iOS' -derivedDataPath /tmp/saiity-dictus-task6-ios CODE_SIGNING_ALLOWED=NO`
  - Passed: `** BUILD SUCCEEDED **`.

## Concerns

- Custom ASR registrations remain configuration-only unless they match the existing WhisperKit Core ML runtime contract; arbitrary Hugging Face or NVIDIA checkpoints are not presented as runnable.
- The build emitted pre-existing Swift 6 warnings about `SpeechEngine` Sendable conformance and `NSLock` use in an async test helper, plus the existing always-run build-info script notes. No new build errors occurred.
- No simulator runtime interaction or network-backed Hugging Face metadata check was performed; metadata behavior is covered by deterministic local JSON tests.

## Commit

Final commit: `feat: manage custom ASR and cleanup models`; exact hash is recorded by the final `git rev-parse HEAD` result.
