# Build 223 — 2026-10-01

Version 1.0.0 (223), uploaded following the user's request, “create a testflight”.

## What to test

- The shared inset on all keyboard pages, its Settings toggle, and Liquid Glass versus Solid.
- Default emoji skin tone, per-key hold options, explicit Recents and the category selector centered above Space.
- Taller letter, number and symbol plates, including the optional number row.
- Popup and Popout in landscape, rotation during a held key and bottom-bar Period preview cancellation.
- Redesigned Live Activity and Dynamic Island phases, recording levels/timer, status icons and actions.

## Delivery evidence

- Archived the current working tree with `sAiity-iOS`, Release, Xcode 27.0 (27A266a). All existing changes were preserved; no commit, Git push or tag was created.
- App, keyboard and widget report `1.0.0 (223)`, under `de.aiity.saiity.ios.beta`. The compiled primary icon is `Saiity`.
- Archive: `/tmp/saiity-testflight-223.KMc5XG/DictusApp.xcarchive`.
- Archive log: `/tmp/saiity-testflight-223.KMc5XG/archive.log`, ending in `** ARCHIVE SUCCEEDED **`.
- Deep, strict archive signature verification passes.
- Upload log: `/tmp/saiity-testflight-223.KMc5XG/upload.log`. At 12:37:12 CEST it reports `Uploaded package is processing`, `Upload succeeded` and `** EXPORT SUCCEEDED **`. Export exits 0.
- Export disables automatic build-number changes. The three Info.plists and six project configurations advanced from 222 to 223; the marketing version remains 1.0.0.
- Archived keyboard binary SHA-256: `67872266b82cda956bd7702d72e3df9a88ded367c2860a402baf03ed45e6847f`.
- Existing source verification: 1,852 Core tests, one skipped, zero failures; production UIKit checks and both Debug builds pass. Detailed scope/evidence is in `keyboard-ui-unification-plan.md`.

## Pending

Apple processing completion and availability to the existing `sAiity Beta Testers` group are unverified. Ego-browser task space 65 remains delegated to the user from the earlier sign-in handoff; browser control has not been returned. No new testers were invited and no App Store submission was made.

Physical typing/material parity, haptic and landscape feel, the complete settings-to-extension interaction and system Live Activity rendering remain open gates. This beta upload does not close them or authorize another upload.
