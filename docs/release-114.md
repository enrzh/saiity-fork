# Build 114 — 2026-09-15

Version 1.0.0 (114), archived from the existing dirty `saiity-fork` checkout.
Existing changes were preserved; no GitHub push or CI run was performed.

On top of build 113:

- Numeric host fields (`numberPad` / `decimalPad` / `phonePad` / OTP) open a glass 3×4 number pad, not the 123 symbols page. `namePhone` stays on letters.
- Digit/OTP pads use ABC, 0, and delete on the bottom row. Decimal pads use the locale separator (`,` in German). Phone pads use `*`, 0, and delete.
- ABC / dictation remain an escape; the next number field still reopens the pad. The 123 control on the dictation board and letter keyboard still opens the symbols page.

Verification:

- DictusCore: 1607 tests, 1 skip, 0 failures after skipping the pre-existing host `UserDictionaryLoggingTests` suite and the host-timing `testEstimatorCostIsNegligibleOnANormalDictation` flake.
- Release archive and App Store Connect export passed.
- App, keyboard and widget archive metadata all report build 114.
- IPA: `/tmp/sAiity-export-114/DictusApp.ipa`
- SHA-256: `3c2181ea143261becb8994cb413d252aaf4ef812425312c0f327f07dcef05345`

Limitations: no physical iPhone was connected. This build is a TestFlight candidate. Compilation and mocked tests do not prove number-pad auto-open, locale decimal separators, or German grammar rewrite on a real device.

Distribution: App Store Connect upload succeeded on 2026-09-15 at 14:52 local time (`Uploaded package is processing` / `Upload succeeded`).

App Store Connect web confirmation of Internal Testing was not completed in this pass. Do not treat Internal Testing as confirmed until the build page shows Complete and the Internal group.

Internal TestFlight testers can install 1.0.0 (114) once Apple finishes processing the upload.
