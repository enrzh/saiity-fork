# Build 106 — 2026-09-14

Version 1.0.0 (106), archived from the existing dirty `saiity-fork` checkout.
Existing changes were preserved; no GitHub push or CI run was performed.

UI polish on top of build 105:

- Emoji category slider: smaller selected capsule, weight/fill for the active icon.
- Models: `.labelStyle(.titleAndIcon)` so Download/Select/Info/Delete keep SF Symbols; compact `.controlSize(.small)`; no empty 44pt hole on the active model.
- Keyboard layout: Automatic + one layout type (AZERTY / QWERTY / QWERTZ) in Settings and the keyboard menu. Per-language layout rows are gone from the UI.
- Settings: three panels (Dictation, Keyboard, More).
- Speak: no marketing header; one readiness card; 44pt Start dictation. Recording overlay uses sentence-case “Transcript” / “Listening”.

Verification:

- DictusCore: 1576 tests, 1 skip, 0 failures after skipping the pre-existing host `UserDictionaryLoggingTests` suite and the host-timing `testEstimatorCostIsNegligibleOnANormalDictation` flake.
- Debug simulator build of `sAiity-iOS` succeeded before the archive.
- Release archive and App Store Connect export passed.
- App, keyboard and widget archive metadata all report build 106.
- IPA: `/tmp/sAiity-export-106/DictusApp.ipa`.
- SHA-256: `95432525f9ba91f47a799fe45b37c0275e0e0429e1cec7ae161482bf36088a9c`.

Limitations: no physical iPhone was connected. This build is a TestFlight candidate. Compilation and mocked tests do not prove emoji-bar device drag, haptic feel, keyboard layout feel, or Speak/Models layout on a real device.

Distribution: App Store Connect upload succeeded on 2026-09-14 at 23:41 local time.

App Store Connect confirmation (ego-browser, signed-in session, 2026-09-14 ~23:45 local):

- Build Uploads: **1.0.0 (106)** status **Complete** (created Sep 14, 2026 11:41 PM).
- Build detail **1.0.0 (106)**: Internal group assigned (1 tester). Testers in that group have access.
- No Missing Compliance / Processing banner on the build page.

Internal TestFlight testers can install 1.0.0 (106).
