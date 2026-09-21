# Build 127 — 2026-09-16

Version 1.0.0 (127), archived from the existing dirty `saiity-fork` checkout.
Existing changes were preserved; no GitHub push or CI run was performed.

On top of build 126, this reconstructs the build-121 feature set:

- Models: Whisper Large v3 / Turbo are no longer offered as new downloads; already-installed identifiers still resolve. Add custom model is restored. Accuracy/Speed gauges are gone; cards use `accuracyLabel` / `speedLabel`.
- Presence: Picture in Picture and leave-app PiP are removed. Live Activity is the only presence option. Stored PiP mode migrates to Live Activity.
- Keyboard settings: Key popups and Liquid glass are single toggles. Off/Popup/Popout and Key containers are gone. Insert keys always draw plates.
- Accessory lane is 44pt with matching window height. Letter/symbol grids fill the surface (4pt inset/gap, 6pt row spacing). Balloon popup only.
- Solid dictation board hits are SwiftUI-owned again. Compact emoji clipping is gone. Layout hint names AZERTY / QWERTY / QWERTZ; persisted layout values are unchanged.

Verification:

- Focused DictusCore rollback suites passed in the reconstruction pass.
- Full DictusCore: 1634 tests, 1 skip (`ASREvaluationTests` / unset `DICTUS_ASR_RESULTS`), 0 failures after `--skip UserDictionaryLoggingTests`.
- Debug simulator build of `sAiity-iOS` succeeded before this archive.
- Release archive and App Store Connect export passed.
- App, keyboard and widget archive metadata all report build 127.
- IPA: `/tmp/sAiity-export-127/DictusApp.ipa`
- SHA-256: `1d123760ac422225733f5c23eda2f0f3eb3db0b08ee327a176fbebb9872a7362`

Limitations: no physical iPhone was connected. Compilation does not prove 121-era keyboard hits, spacebar cursor, or Add custom model on a real device.

Distribution: App Store Connect upload succeeded on 2026-09-16 at 08:43 local time (`Uploaded package is processing` / `Upload succeeded`).

App Store Connect web confirmation of Internal Testing was not completed in this pass. Do not treat Internal Testing as confirmed until the build page shows Complete and the Internal group.

Internal TestFlight testers can install 1.0.0 (127) once Apple finishes processing the upload.
