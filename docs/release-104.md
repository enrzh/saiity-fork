# Build 104 — 2026-09-14

Version 1.0.0 (104), archived from the existing dirty `saiity-fork` checkout.
Existing changes were preserved; no GitHub push or CI run was performed.

Implements `docs/model-and-keyboard-stabilization-plan.md` on top of build 103:

- Qwen cache/repair/cancellation policy kept; cancellation never marks the model ready; catalog copy does not present Qwen as verified or recommended.
- ASR capture schema/scorer (`ASREvaluation`) for identical recorded runs; no recorded corpus was scored.
- Cleanup preservation tests extended; multilingual Auto still skips model polish; raw transcript is stored in a single last-dictation snapshot.
- Swipe decoder gained dwell/spatial ranking; letter-page swipe stays off so hold-for-accents keeps working. Prediction remains default-off.
- Settings → Troubleshooting → Report last dictation: preview, omit-text by default, native share sheet, never auto-sent.

Verification:

- DictusCore: 1565 tests, 1 skip (`DICTUS_ASR_RESULTS` unset), 0 failures after skipping the pre-existing host `UserDictionaryLoggingTests` suite.
- Debug simulator build of `sAiity-iOS` for iPhone 17 produced `DictusApp.app` with CFBundleVersion 104.
- Release archive and App Store Connect export passed.
- App, keyboard and widget archive metadata all report build 104.
- IPA: `/tmp/sAiity-export-104/DictusApp.ipa`.
- SHA-256: `e0dbf417fe3d7c81e85ef77562730781883b6b40eb3f48d802c1a6bd66604bc7`.

Limitations: no physical iPhone was connected. This build is a TestFlight candidate. Compilation and mocked tests do not prove Qwen device load, ASR quality, cleanup model quality, swipe feel, or keyboard touch behavior.

Distribution: App Store Connect upload succeeded on 2026-09-14 at 21:48 local time.

App Store Connect confirmation (ego-browser, signed-in session, 2026-09-14 ~21:52 local):

- Build Uploads: **1.0.0 (104)** status **Complete** (created Sep 14, 2026 9:48 PM).
- iOS Builds → Version 1.0.0: **104** status **Ready to Submit**, expires in 90 days, group **IN Internal**.
- Build detail: Internal group assigned with **1** tester; testers in that group have access. No Missing Compliance / Processing banner.

Internal TestFlight testers can install 1.0.0 (104).
