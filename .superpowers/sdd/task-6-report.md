# Task 6 Report: Custom ASR and Cleanup Model Management

## Status

Implemented and verified in the current `saiity-fork` checkout. Built-in model download, selection, preparation, and deletion paths were preserved. Existing untracked files were preserved.

## Changes

- `DictusCore/Sources/DictusCore/CustomModel.swift`
  - Enforced role/source restrictions: Ollama is cleanup-only and NVIDIA is ASR-only.
  - Removed the fixed Hugging Face ASR marker gate from local validation; valid repositories now reach remote `pipeline_tag`/`tags` validation.
  - Kept explicit offline/network failure messaging from the metadata pipeline.
  - Restricted NVIDIA ASR URLs to HTTPS `developer.nvidia.com` paths rooted at `nemo`, `riva`, `nvidia-nemo`, or `nvidia-riva`, with ASR evidence in the model path.
  - Rejected URL query and fragment components.
  - Made App Group loading tolerate malformed records individually and deduplicate loaded data.
  - Made persistence deterministically replace duplicates by ID or normalized identity, keeping the last registration.
- `DictusApp/Views/ModelManagerView.swift`
  - No changes required in this review follow-up; existing source/role, validation/runtime status, retained-entry, and deletion-confirmation UI remains intact.
- `DictusCore/Tests/DictusCoreTests/CustomModelTests.swift`
  - Added regression coverage for marker-free HF URLs, NVIDIA developer pages/error paths/valid ASR paths, runtime support states, persistence deduplication, and malformed records.

## Verification

- `swift test --package-path DictusCore --scratch-path /tmp/saiity-dictus-task6-green --filter CustomModelTests`
  - Passed: 13 tests, 0 failures.
- `swift test --package-path DictusCore --scratch-path /tmp/saiity-dictus-task6-full`
  - Passed: 1179 tests executed, 10 skipped, 0 failures.
- `git diff --check`
  - Passed with no output.
- `xcodebuild build -project Dictus.xcodeproj -scheme sAiity-iOS -destination 'generic/platform=iOS' -derivedDataPath /tmp/saiity-dictus-task6-ios CODE_SIGNING_ALLOWED=NO`
  - Passed: `** BUILD SUCCEEDED **`.

## Concerns

- Custom ASR registrations remain configuration-only unless they match the existing WhisperKit Core ML runtime contract; arbitrary Hugging Face or NVIDIA checkpoints are not presented as runnable.
- The build emitted pre-existing Swift 6 warnings about `SpeechEngine` Sendable conformance and `NSLock` use in an async test helper, plus the existing always-run build-info script notes. No new build errors occurred.
- No simulator runtime interaction or network-backed Hugging Face metadata check was performed, per request; metadata behavior is covered by deterministic local JSON tests and the offline error path remains explicit.

## Commit

Implementation commit: `31aafdfc1e01bcea8fefe2eb5ddb12340fef983a`.
