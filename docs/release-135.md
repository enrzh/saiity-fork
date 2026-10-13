# Build 135 — 2026-09-16

Version 1.0.0 (135).

## Changes since 134

- **App Group fix** — `AppGroup.identifier` aligned with entitlements (`group.de.aiity.saiity.ios.beta`) so model download and Full Access handshake work on setup.
- **Setup** — voice model install errors show the real message (e.g. missing container).

## Verification

- Archive: `/tmp/sAiity-archive-135/DictusApp.xcarchive` (`CFBundleVersion` 135).
- App Store Connect upload succeeded 2026-09-16 ~16:14 local (`Upload succeeded` / processing), build **135** in bundle.
- Archive path: `/tmp/sAiity-archive-135/DictusApp.xcarchive`
- Info.plists + `CURRENT_PROJECT_VERSION` set to **135**.

Distribution: in App Store Connect → TestFlight → **sAiity Beta**, enable build **1.0.0 (135)** when processing completes (add “What to Test” if prompted).
