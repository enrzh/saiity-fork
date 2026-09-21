# Build 108 — 2026-09-15

Version 1.0.0 (108), archived from the existing dirty `saiity-fork` checkout.
Existing changes were preserved; no GitHub push or CI run was performed.

UI changes on top of build 107:

- Settings menu pickers now show a leading label: Cleanup model, Transcript language, Keyboard layout, Default keyboard.
- Models is its own Settings panel above Dictation.
- Cleanup model picker stays hidden unless an Ollama cleanup model exists.
- Suggestions after dictation keeps an explanatory caption and stays off by default.
- Keyboard haptics is a single on/off toggle.
- Speak/Home restores material dashboard cards, greeting, and a labeled Keyboard dictation toggle.

Verification:

- DictusCore: 1584 tests, 1 skip, 0 failures after skipping the pre-existing host `UserDictionaryLoggingTests` suite and the host-timing `testEstimatorCostIsNegligibleOnANormalDictation` flake.
- Debug simulator build of `sAiity-iOS` succeeded before the archive.
- Release archive and App Store Connect export passed.
- App, keyboard and widget archive metadata all report build 108.
- IPA: `/tmp/sAiity-export-108/DictusApp.ipa`.
- SHA-256: `a8ae996be445ad40f7d4fcedf1b022766dd2c0632683dae8ad4c8f64b582febe`.

Limitations: no physical iPhone was connected. This build is a TestFlight candidate. Compilation and mocked tests do not prove Settings label layout, haptic feel, Speak dashboard layout, or keyboard behavior on a real device.

Distribution: App Store Connect upload succeeded on 2026-09-15 at 01:05 local time.

App Store Connect confirmation (ego-browser, signed-in session, 2026-09-15 ~01:08 local):

- Build Uploads: **1.0.0 (108)** status **Complete** (created Sep 15, 2026 1:05 AM).
- iOS Builds → Version 1.0.0: **108** status **Ready to Submit**, expires in 90 days, group **IN Internal**.
- Build detail **1.0.0 (108)**: Internal group assigned (1 tester). Testers in that group have access.
- No Missing Compliance / Processing banner on the build page.

Internal TestFlight testers can install 1.0.0 (108).
