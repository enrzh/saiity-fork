# Build 116 — 2026-09-15

Version 1.0.0 (116), archived from the existing dirty `saiity-fork` checkout.
Existing changes were preserved; no GitHub push or CI run was performed.

On top of build 115:

- ABC is no longer in the number-pad suggestion bar.
- On decimal pads, tap `,` / `.` inserts the separator; hold opens the letter keyboard. Phone pads use the same hold on `*`. PIN/OTP still has a dedicated ABC key on the empty bottom-left slot.

Verification:

- DictusCore: 1609 tests, 1 skip, 0 failures after skipping the pre-existing host `UserDictionaryLoggingTests` suite and the host-timing `testEstimatorCostIsNegligibleOnANormalDictation` flake.
- Release archive and App Store Connect export passed.
- App, keyboard and widget archive metadata all report build 116.
- IPA: `/tmp/sAiity-export-116/DictusApp.ipa`
- SHA-256: `294d1d0dade7d9bc448516b24abd17c118beaeb0f85e3f428aa58755a3416302`

Limitations: no physical iPhone was connected. This build is a TestFlight candidate. Compilation and mocked tests do not prove hold-to-ABC on a real device.

Distribution: App Store Connect upload succeeded on 2026-09-15 at 15:52 local time (`Uploaded package is processing` / `Upload succeeded`).

App Store Connect web confirmation of Internal Testing was not completed in this pass. Do not treat Internal Testing as confirmed until the build page shows Complete and the Internal group.

Internal TestFlight testers can install 1.0.0 (116) once Apple finishes processing the upload.
