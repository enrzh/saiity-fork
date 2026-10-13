# Build 115 — 2026-09-15

Version 1.0.0 (115), archived from the existing dirty `saiity-fork` checkout.
Existing changes were preserved; no GitHub push or CI run was performed.

On top of build 114:

- Number-pad digits match the letter keyboard: plain glyphs, no per-key glass containers. ABC and delete keep command chrome.
- On numeric host fields (`numberPad` / `decimalPad` / `phonePad` / OTP), 123 from the dictation board, letter keyboard, and emoji page returns to the 3×4 pad instead of the symbols page. Other fields still open 123 symbols.

Verification:

- DictusCore: 1609 tests, 1 skip, 0 failures after skipping the pre-existing host `UserDictionaryLoggingTests` suite and the host-timing `testEstimatorCostIsNegligibleOnANormalDictation` flake.
- Release archive and App Store Connect export passed.
- App, keyboard and widget archive metadata all report build 115.
- IPA: `/tmp/sAiity-export-115/DictusApp.ipa`
- SHA-256: `0d0ba8598198efcf8aae5f326f6a89ec26fa5c0a2520a7133672f4269f8ba283`

Limitations: no physical iPhone was connected. This build is a TestFlight candidate. Compilation and mocked tests do not prove number-pad styling or 123 routing on a real device.

Distribution: App Store Connect upload succeeded on 2026-09-15 at 15:34 local time (`Uploaded package is processing` / `Upload succeeded`).

App Store Connect web confirmation of Internal Testing was not completed in this pass. Do not treat Internal Testing as confirmed until the build page shows Complete and the Internal group.

Internal TestFlight testers can install 1.0.0 (115) once Apple finishes processing the upload.
