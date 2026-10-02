# Build 226 — 2026-10-02

Version 1.0.0 (226), uploaded following the TestFlight pattern: dirty→WIP commit; bump +1; push branch; local archive scheme sAiity-iOS; assign sAiity Beta Testers after VALID.

## What to test

- Trackpad cursor polish and key-grid typing harness updates from the keyboard surface WIP.
- Keyboard UI unification plan notes; general typing, Space, held Delete, emoji, and Liquid Glass versus Solid.

## Delivery evidence

- Branch `cursor/keyboard-surface-fixes-a66e` at `adea88ad` (pushed).
- Commits: `57ec0185` wip: trackpad cursor, key-grid typing harness, keyboard UI plan; `adea88ad` chore: bump build to 226.
- Archived with `sAiity-iOS`, Release, Xcode 27.0 Build version 27A266a. No `git reset --hard`. Desktop repos untouched.
- App, keyboard and widget report `1.0.0 (226)`, under `de.aiity.saiity.ios.beta`. Primary icon assets are `Saiity`.
- Archive: `/tmp/saiity-testflight-226.hNRL4p/DictusApp.xcarchive`.
- Archive log: `/tmp/saiity-testflight-226.hNRL4p/archive.log`, ending in `** ARCHIVE SUCCEEDED **`.
- Upload log: `/tmp/saiity-testflight-226.hNRL4p/upload.log`. At 13:47:03 CEST: `Uploaded package is processing`, `Upload succeeded`, `** EXPORT SUCCEEDED **`.
- Export disables automatic build-number changes. Marketing version remains 1.0.0.
- Archived keyboard binary SHA-256: `8f21b26be40e905f31a7a67ffe59f1f74701e629655bd1513de96dd49e002615`.
- App Store Connect build id `c0d1ab19-dc92-4ed8-b3fe-d9a87e003797` reached `VALID` and is assigned to internal group `sAiity Beta Testers` (`786d9407-ccb4-4253-8270-369405a5a665`).

## Notes

No new testers were invited and no App Store submission was made.
