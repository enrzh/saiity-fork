# Build 228 — 2026-10-02

Version 1.0.0 (228), uploaded following the TestFlight pattern: dirty→WIP commit; bump +1; push branch; local archive scheme sAiity-iOS; assign sAiity Beta Testers after VALID.

## What to test

- Whole bottom-row spacing: Period, Return, and field inserts fill horizontal targets so every visible gap is 2pt.
- Circular left controls, 45pt face heights, Space/Return alignment; Liquid Glass versus Solid.
- Keyboard UI unification plan notes; plate-gap regression check; general typing, Space, held Delete, emoji.

## Delivery evidence

- Branch `cursor/keyboard-surface-fixes-a66e` at `d2b522f2` (pushed).
- Commits: `07870b3d` wip: whole bottom-row spacing — Period/Return fill targets; `d2b522f2` chore: bump build to 228.
- Archived with `sAiity-iOS`, Release, Xcode 27.0 Build version 27A266a. No `git reset --hard`. Desktop repos untouched.
- App, keyboard and widget report `1.0.0 (228)`, under `de.aiity.saiity.ios.beta`. Primary icon assets are `Saiity`.
- Archive: `/tmp/saiity-testflight-228.Nddj27/DictusApp.xcarchive`.
- Archive log: `/tmp/saiity-testflight-228.Nddj27/archive.log`, ending in `** ARCHIVE SUCCEEDED **`.
- Upload log: `/tmp/saiity-testflight-228.Nddj27/upload.log`. At 23:18:35 CEST: `Uploaded package is processing`, `Upload succeeded`, `** EXPORT SUCCEEDED **`.
- Export disables automatic build-number changes (`manageAppVersionAndBuildNumber` false). Marketing version remains 1.0.0.
- Archived keyboard binary SHA-256: `bba20d733f37aa0d453333ee189ffa5257de8503b6dd098cd0e929fe46b6f58e`.
- App Store Connect build id `9a2d9a7c-e1be-414a-9ec7-37495bff8076` reached `VALID` and is assigned to internal group `sAiity Beta Testers` (`786d9407-ccb4-4253-8270-369405a5a665`). `internalBuildState` = `IN_BETA_TESTING`.

## Notes

No new testers were invited and no App Store submission was made.
