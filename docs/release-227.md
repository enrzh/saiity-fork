# Build 227 — 2026-10-02

Version 1.0.0 (227), uploaded following the TestFlight pattern: dirty→WIP commit; bump +1; push branch; local archive scheme sAiity-iOS; assign sAiity Beta Testers after VALID.

## What to test

- Circular bottom-bar chrome faces and tighter bottom-bar spacing/control-width policy.
- Period-frame layout on letter pages; Space/Return alignment; Liquid Glass versus Solid.
- Keyboard UI unification plan notes; general typing, Space, held Delete, emoji.

## Delivery evidence

- Branch `cursor/keyboard-surface-fixes-a66e` at `3359e598` (pushed).
- Commits: `d974703f` wip: circular bottom-bar chrome and spacing policy; `3359e598` chore: bump build to 227.
- Archived with `sAiity-iOS`, Release, Xcode 27.0 Build version 27A266a. No `git reset --hard`. Desktop repos untouched.
- App, keyboard and widget report `1.0.0 (227)`, under `de.aiity.saiity.ios.beta`. Primary icon assets are `Saiity`.
- Archive: `/tmp/saiity-testflight-227.VSjryN/DictusApp.xcarchive`.
- Archive log: `/tmp/saiity-testflight-227.VSjryN/archive.log`, ending in `** ARCHIVE SUCCEEDED **`.
- Upload log: `/tmp/saiity-testflight-227.VSjryN/upload.log`. At 18:10:21 CEST: `Uploaded package is processing`, `Upload succeeded`, `** EXPORT SUCCEEDED **`.
- Export disables automatic build-number changes (`manageAppVersionAndBuildNumber` false). Marketing version remains 1.0.0.
- Archived keyboard binary SHA-256: `c967f644adfa5fed4608aae7f4284946533f719ff25978d5596e08c1cdf504e8`.
- App Store Connect build id `046598a8-12c6-4bbf-8f3b-934a0477406d` reached `VALID` and is assigned to internal group `sAiity Beta Testers` (`786d9407-ccb4-4253-8270-369405a5a665`). `internalBuildState` = `IN_BETA_TESTING`.

## Notes

No new testers were invited and no App Store submission was made.
