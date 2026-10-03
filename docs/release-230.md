# Build 230 — 2026-10-03

Version 1.0.0 (230), uploaded following the TestFlight pattern: dirty→WIP commit; bump +1; push branch; local archive scheme sAiity-iOS; assign sAiity Beta Testers after VALID.

## What to test

- Native experience direction: Speak, recording/results, onboarding, and Live Activity share the SwiftUI voice controls.
- Dictation-board faces keep the current frame and touch owners, with the vector mark, adaptive blue primary/recovery faces, and flat service treatment. Listening animation respects Reduce Motion.
- Character/command plates, circular bottom controls, whole-row 2pt gaps, Space cursor mapping, holds, and repeats stay as previously accepted.

## Delivery evidence

- Branch `cursor/keyboard-surface-fixes-a66e` at the bump commit (pushed to `enrzh/saiity-fork`).
- Commits: `16775605` wip: native experience direction for speak, recording, and live activity; `c620bb05` chore: bump build to 230.
- Archived with `sAiity-iOS`, Release, Xcode 27.0 Build version 27A266a. No `git reset --hard`. Desktop repos untouched.
- App, keyboard and widget report `1.0.0 (230)`, under `de.aiity.saiity.ios.beta`. Display name remains `sAiity`.
- Archive: `/tmp/saiity-testflight-230.Nd7tFd/DictusApp.xcarchive`.
- Archive log: `/tmp/saiity-testflight-230.Nd7tFd/archive.log`, ending in `** ARCHIVE SUCCEEDED **`.
- Upload log: `/tmp/saiity-testflight-230.Nd7tFd/upload.log`. At 16:03:16 CEST: `Uploaded package is processing`, `Upload succeeded`, `** EXPORT SUCCEEDED **`.
- Export disables automatic build-number changes (`manageAppVersionAndBuildNumber` false). Marketing version remains 1.0.0.
- Archived keyboard binary SHA-256: `3ce8f238828210a71865febd075c7ea8305dc0d8bc29c78b2f6d814442db8bef`.
- App Store Connect build id `65fbd61f-a68d-4757-99fb-532b9a0af4a0` reached `VALID` and is assigned to internal group `sAiity Beta Testers` (`786d9407-ccb4-4253-8270-369405a5a665`). `internalBuildState` = `IN_BETA_TESTING`.

## Notes

No new testers were invited and no App Store submission was made.
