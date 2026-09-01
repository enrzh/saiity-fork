# Task 6 Report: Custom ASR and Cleanup Model Management

## Status

Implemented the Task 6 second-review Important findings in the current `saiity-fork` checkout. Built-in model download, selection, preparation, and deletion paths were preserved. Existing untracked files were preserved.

## Changes

- `DictusCore/Sources/DictusCore/CustomModel.swift`
  - Restricted NVIDIA URLs to explicit `nemo`/`riva` roots followed by known ASR model families; forged paths such as `nemo/foo/whisper` are rejected.
  - Rejected userinfo and every explicit port, plus query and fragment components.
  - Added backward-compatible `remoteValidationState`; HF ASR registrations default to `needsVerification` and can only be saved after verification.
  - Distinguished HF HTTP 404 repository-not-found from other non-2xx temporary verification failures.
  - Preserved role/source restrictions, App Group malformed-record tolerance, and deterministic deduplication.
  - Made App Group loading tolerate malformed records individually and deduplicate loaded data.
  - Made persistence deterministically replace duplicates by ID or normalized identity, keeping the last registration.
- `DictusApp/Views/ModelManagerView.swift`
  - Saved HF ASR entries now retain verification state; the list explicitly shows needs verification or verified-but-runtime-unavailable.
- `DictusCore/Tests/DictusCoreTests/CustomModelTests.swift`
  - Added regression coverage for legal/forged NVIDIA paths, unsafe URLs, persisted validation state, and 404/non-2xx error classification, while retaining existing persistence/runtime tests.
  - Added coverage that Ollama loopback port `11434` is allowed while `11435` is rejected.

## Verification

- `swift test --package-path DictusCore --scratch-path /tmp/saiity-dictus-task6-final-custom --filter CustomModelTests`
  - Re-run after the regression fix; reached test-product linking but the Xcode beta command did not return a final summary within the execution window, so no pass count is claimed.
- Full DictusCore suite
  - Not run, per user instruction to prioritize focused code/tests/report and not wait.
- `git diff --check`
  - Passed with no output before commit.
- Generic iOS build
  - Not run to completion, per user instruction; no build result is claimed.

## Concerns

- Custom ASR registrations remain configuration-only unless they match the existing WhisperKit Core ML runtime contract; arbitrary Hugging Face or NVIDIA checkpoints are not presented as runnable.
- The build emitted pre-existing Swift 6 warnings about `SpeechEngine` Sendable conformance and `NSLock` use in an async test helper, plus the existing always-run build-info script notes. No new build errors occurred.
- No simulator, physical device, or network-backed Hugging Face metadata check was performed, per request.

## Commit

Implementation commit: `b0cc166`.
Regression fix commit: `c23508f`.
