# Build 118 — 2026-09-15

Version 1.0.0 (118), archived from the existing dirty `saiity-fork` checkout.
Existing changes were preserved; no GitHub push or CI run was performed.

On top of build 117:

- Spacebar tap-and-hold is a cursor joystick, not a trackpad. Origin is the original press, with a dead-zone area around that point. Displacement from the origin keeps stepping the caret (characters on X, lines on Y) until lift, including while the finger is still. A short tap still inserts a space.

Verification:

- DictusCore: 1614 tests, 1 skip, 0 failures after skipping the pre-existing host `UserDictionaryLoggingTests` suite and the host-timing `testEstimatorCostIsNegligibleOnANormalDictation` flake.
- Release archive and App Store Connect export passed.
- App, keyboard and widget archive metadata all report build 118.
- IPA: `/tmp/sAiity-export-118/DictusApp.ipa`
- SHA-256: `71ff7ef1d4ea19ea719fc04234ca081448ae68467e20c67615527e9a5fb21ff4`

Limitations: no physical iPhone was connected. This build is a TestFlight candidate. Compilation and mocked tests do not prove joystick feel on a real device.

Distribution: App Store Connect upload succeeded on 2026-09-15 at 17:11 local time (`Uploaded package is processing` / `Upload succeeded`).

App Store Connect web confirmation of Internal Testing was not completed in this pass. Do not treat Internal Testing as confirmed until the build page shows Complete and the Internal group.

Internal TestFlight testers can install 1.0.0 (118) once Apple finishes processing the upload.
