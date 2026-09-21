# Build 119 — 2026-09-15

Version 1.0.0 (119), archived from the existing dirty `saiity-fork` checkout.
Existing changes were preserved; no GitHub push or CI run was performed.

On top of build 118:

- The keyboard no longer reads the pasteboard on a timer, on appear, or when the host field changes. Paste still reads it only when the user taps Paste.
- Spacebar cursor joystick ticks keep firing while the finger is held. Origin (the original press) is the only stop. A held offset keeps walking that direction until the finger returns to the origin or lifts.

Verification:

- DictusCore: 1615 tests, 1 skip, 0 failures after skipping the pre-existing host `UserDictionaryLoggingTests` suite and the host-timing `testEstimatorCostIsNegligibleOnANormalDictation` flake.
- Release archive and App Store Connect export passed.
- App, keyboard and widget archive metadata all report build 119.
- IPA: `/tmp/sAiity-export-119/DictusApp.ipa`
- SHA-256: `9d119ee1a72e677120ccd520e87f3b576db5fcac93c8e6261e4799a00348ba78`

Limitations: no physical iPhone was connected. This build is a TestFlight candidate. Compilation and mocked tests do not prove joystick feel or clipboard-banner absence on a real device.

Distribution: App Store Connect upload succeeded on 2026-09-15 at 18:17 local time (`Uploaded package is processing` / `Upload succeeded`).

App Store Connect web confirmation of Internal Testing was not completed in this pass. Do not treat Internal Testing as confirmed until the build page shows Complete and the Internal group.

Internal TestFlight testers can install 1.0.0 (119) once Apple finishes processing the upload.
