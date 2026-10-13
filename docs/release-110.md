# Build 110 — 2026-09-15

Version 1.0.0 (110), archived from the existing dirty `saiity-fork` checkout.
Existing changes were preserved; no GitHub push or CI run was performed.

UI changes on top of build 109:

- Key popups toggle removed from Settings. The switch never changed the visible SwiftUI keyboard.
- Settings More is grouped into Help (Microphone, Troubleshooting, Get support) and About (Licenses, Privacy Policy, Version). Privacy sits in the card instead of a footer. External rows use an up-right arrow; in-app rows use a chevron. Denied microphone status is red. Extra bottom padding keeps the last rows above the floating tab bar.

Verification:

- DictusCore: 1581 tests, 1 skip, 0 failures after skipping the pre-existing host `UserDictionaryLoggingTests` suite and the host-timing `testEstimatorCostIsNegligibleOnANormalDictation` flake.
- Release archive and App Store Connect export passed.
- App, keyboard and widget archive metadata all report build 110.
- IPA: `/tmp/sAiity-export-110/DictusApp.ipa`.
- SHA-256: `27056ed326881c0c400006bd6d24b027b2fdd1ad627642dd7600746578af03b9`.

Limitations: no physical iPhone was connected. This build is a TestFlight candidate. Compilation and mocked tests do not prove Settings layout, microphone status color, or keyboard popup behavior on a real device.

Distribution: App Store Connect upload succeeded on 2026-09-15 at 02:22 local time.
