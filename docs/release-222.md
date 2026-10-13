# Build 222 — 2026-10-01

Version 1.0.0 (222), uploaded at the user's explicit request, “push to testflight”.

## What to test

- Typing, Space, held Delete, cursor dragging, emoji paging and keyboard switching in both Liquid Glass and Solid styles.
- Haptic presets, hold speeds, per-key variants, emoji skin tones and consistent suggestion-bar height across text fields.
- Balanced, device-recommended and Precise model presets, local cleanup models and preservation of mixed languages, names and numbers.
- Refreshed Full Access setup, silent setup guide, Picture in Picture on a supported iPhone and the updated Live Activity.

## Delivery evidence

- Archived the current working tree using `sAiity-iOS`, Release, Xcode 27.0 (27A266a). User changes and Git history were preserved; no commit, Git push or tag was created.
- App, keyboard and widget all report `1.0.0 (222)`. Their bundle identifiers remain under `de.aiity.saiity.ios.beta`.
- Archive: `/tmp/saiity-testflight-222.iKincp/DictusApp.xcarchive`.
- Archive log: `/tmp/saiity-testflight-222.iKincp/archive.log`, ending in `** ARCHIVE SUCCEEDED **`.
- Deep, strict archive signature verification passes. The compiled primary icon is `Saiity`; the setup video and license notices are bundled.
- Upload log: `/tmp/saiity-testflight-222.iKincp/upload.log`. At 08:52:58 CEST it reports `Uploaded package is processing`, `Upload succeeded` and `** EXPORT SUCCEEDED **`; the export command exits 0.
- Export disables automatic build-number changes. The working tree's three Info.plists and six project configurations were advanced from 221 to 222.
- Archived keyboard binary SHA-256: `f578db2653af2075f16d6f362d39c9076f349f2ebb60ad6065d4b9fd4a33bc48`.

## Pending

Apple processing completion and availability to the existing `sAiity Beta Testers` group are not yet verified. App Store Connect requested a fresh sign-in; ego-browser task space 65 was handed to the user for authentication. No new testers were invited and no App Store submission was made.

The existing 1,850-test Core result, compiled UIKit checks and simulator evidence are documented in `keyboard-ui-unification-plan.md`. Physical typing and haptic feel, host-field parity, denied Full Access changes, physical PiP and system Live Activity rendering remain open. The upload does not close those gates.
