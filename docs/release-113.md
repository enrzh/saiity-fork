# Build 113 — 2026-09-15

Version 1.0.0 (113), archived from the existing dirty `saiity-fork` checkout.
Existing changes were preserved; no GitHub push or CI run was performed.

On top of build 112:

- Numeric host fields (`numberPad` / `decimalPad` / `phonePad` / OTP) open the existing glass 123 page instead of the letter or dictation board. `namePhone` stays on letters. ABC / dictation remain an escape; the next number field still reopens 123.
- The 123 layout is unchanged: number row, punctuation row, glass `#+=` / delete, then ABC, emoji, space, and return.

Verification:

- DictusCore: 1602 tests, 1 skip, 0 failures after skipping the pre-existing host `UserDictionaryLoggingTests` suite and the host-timing `testEstimatorCostIsNegligibleOnANormalDictation` flake.
- Release archive and App Store Connect export passed.
- App, keyboard and widget archive metadata all report build 113.
- IPA: `/tmp/sAiity-export-113/DictusApp.ipa`
- SHA-256: `21fe7d071f3b486f5667050058d12ed1ee2a12df5609e1461b5d40611eb0d5b8`

Limitations: no physical iPhone was connected. This build is a TestFlight candidate. Compilation and mocked tests do not prove number-pad auto-open, German grammar rewrite, or mixed-language preservation on a real device.

Distribution: App Store Connect upload succeeded on 2026-09-15 at 13:52 local time (`Uploaded package is processing` / `Upload succeeded`).

App Store Connect web confirmation was not completed in this pass: the TestFlight session required Apple ID sign-in, Bitwarden autofill did not populate the login fields, and passkey sign-in did not continue. Do not treat Internal Testing as confirmed until the build page shows Complete and the Internal group.

Internal TestFlight testers can install 1.0.0 (113) once Apple finishes processing the upload.
