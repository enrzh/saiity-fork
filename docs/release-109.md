# Build 109 — 2026-09-15

Version 1.0.0 (109), archived from the existing dirty `saiity-fork` checkout.
Existing changes were preserved; no GitHub push or CI run was performed.

UI and dictation changes on top of build 108:

- Held delete now repeats haptic feedback on every deletion tick.
- Double-tap shift locks Caps Lock (0.5s window). A further tap turns it off.
- Transcript language setting removed. Dictation always auto-detects and keeps mixed speech. Leftover single-language values are overwritten on launch.
- Suggestions after dictation toggle and unused post-dictation chip path removed. Live as-you-type chips remain.

Verification:

- DictusCore: 1581 tests, 1 skip, 0 failures after skipping the pre-existing host `UserDictionaryLoggingTests` suite and the host-timing `testEstimatorCostIsNegligibleOnANormalDictation` flake.
- Release archive and App Store Connect export passed.
- App, keyboard and widget archive metadata all report build 109.
- IPA: `/tmp/sAiity-export-109/DictusApp.ipa`.
- SHA-256: `1c4f5712e0f4861a780be225be8e2bce1a8f5b41503a8d423b1dc1bef79d5e2c`.

Limitations: no physical iPhone was connected. This build is a TestFlight candidate. Compilation and mocked tests do not prove delete-hold haptics, caps-lock timing, or mixed-language dictation quality on a real device.

Distribution: App Store Connect upload succeeded on 2026-09-15 at 01:39 local time.

App Store Connect confirmation (ego-browser, signed-in session, 2026-09-15 ~01:43 local):

- Build Uploads: **1.0.0 (109)** status **Complete** (created Sep 15, 2026 1:39 AM).
- iOS Builds → Version 1.0.0: **109** status **Ready to Submit**, expires in 90 days, group **IN Internal**.
- Build detail **1.0.0 (109)**: Internal group assigned (1 tester). Testers in that group have access.
- No Missing Compliance / Processing banner on the build page.

Internal TestFlight testers can install 1.0.0 (109).
