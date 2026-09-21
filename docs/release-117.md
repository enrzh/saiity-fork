# Build 117 — 2026-09-15

Version 1.0.0 (117), archived from the existing dirty `saiity-fork` checkout.
Existing changes were preserved; no GitHub push or CI run was performed.

On top of build 116:

- The decimal separator key (`,` / `.`) shows a small ABC hint under the glyph. Phone `*` uses the same hint. Tap still inserts; hold still opens the letter keyboard.

Verification:

- DictusCore: 1609 tests, 1 skip, 0 failures after skipping the pre-existing host `UserDictionaryLoggingTests` suite and the host-timing `testEstimatorCostIsNegligibleOnANormalDictation` flake.
- Release archive and App Store Connect export passed.
- App, keyboard and widget archive metadata all report build 117.
- IPA: `/tmp/sAiity-export-117/DictusApp.ipa`
- SHA-256: `61cbb29be353b492967421f55555586672365c97fa8813300ac66427ad92ad9d`

Limitations: no physical iPhone was connected. This build is a TestFlight candidate. Compilation and mocked tests do not prove the ABC hint layout on a real device.

Distribution: App Store Connect upload succeeded on 2026-09-15 at 16:07 local time (`Uploaded package is processing` / `Upload succeeded`).

App Store Connect web confirmation of Internal Testing was not completed in this pass. Do not treat Internal Testing as confirmed until the build page shows Complete and the Internal group.

Internal TestFlight testers can install 1.0.0 (117) once Apple finishes processing the upload.
