# Build 124 — 2026-09-15

Version 1.0.0 (124), archived from the existing dirty `saiity-fork` checkout.
Existing changes were preserved; no GitHub push or CI run was performed.

On top of build 123:

- Solid dictation-board chrome no longer steals taps from the UIKit overlay.
- Letter/symbol/number insert keys sit in the glass inset by default. Settings → Keyboard → Key containers restores per-key plates. Popout still enlarges and fades.
- Letter key metrics match native iOS (4pt inset, 6pt gap, 11pt rows, 43pt height).
- Picture in Picture prepares an inline video-call source while recording and starts when leaving the app. Hidden 1×1 source is gone.
- Keyboard layout picker already lists all four shipped layouts (AZERTY, QWERTY, QWERTZ, QWERTZ Deutschland).
- Models page no longer has Add Model. Each catalog card shows Accuracy and Speed gauges.
- Emoji glyphs clip inside the inset at compact row height. Category tap/drag is owned by the UIKit scrubber.

Verification:

- DictusCore: 1636 tests, 1 skip (`UserDictionaryLoggingTests`), 0 failures.
- Debug simulator build of `sAiity-iOS` for iPhone 17 succeeded before this archive.
- Release archive and App Store Connect export passed.
- App, keyboard and widget archive metadata all report build 124.
- IPA: `/tmp/sAiity-export-124/DictusApp.ipa`
- SHA-256: `d8fdc550f353232e0d43045e0ce799b7f6018aac7dc3155bf3cc55a72e83b98f`

Limitations: no physical iPhone was connected. Compilation does not prove solid-board hits, native PiP on leave-app, key-container toggle, or emoji category scrubbing on a real device. PiP only runs in the app process, not inside the keyboard extension.

Distribution: App Store Connect upload succeeded on 2026-09-15 at 22:58 local time (`Uploaded package is processing` / `Upload succeeded`).

App Store Connect web confirmation of Internal Testing was not completed in this pass. Do not treat Internal Testing as confirmed until the build page shows Complete and the Internal group.

Internal TestFlight testers can install 1.0.0 (124) once Apple finishes processing the upload.
