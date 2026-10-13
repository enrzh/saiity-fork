# Build 107 — 2026-09-15

Version 1.0.0 (107), archived from the existing dirty `saiity-fork` checkout.
Existing changes were preserved; no GitHub push or CI run was performed.

UI and catalog changes on top of build 106:

- Emoji category bar: 8pt horizontal / 6pt vertical padding inside the 44pt suggestion lane; scrub hits use the same inset.
- AUTO pill always shows AUTO when keeping the spoken language, including ABC / 123. The menu is translation only (AUTO + languages). Keyboard layout stays in Settings.
- Live completions, corrections, and next-word predictions now update from the text field and appear in the accessory lane. Post-dictation suggestions stay opt-in.
- Models tab removed. Settings → Dictation → Models opens the catalog; the Speak entry is unchanged. New downloads are multilingual Tiny, Base, and Medium Whisper. Already-downloaded Parakeet / Qwen / Turbo still appear under Installed.
- Spacebar trackpad from the post-106 dirty tree remains 2D (characters + lines).

Verification:

- DictusCore: 1583 tests, 1 skip, 0 failures after skipping the pre-existing host `UserDictionaryLoggingTests` suite and the host-timing `testEstimatorCostIsNegligibleOnANormalDictation` flake.
- Debug simulator build of `sAiity-iOS` succeeded before the archive.
- Release archive and App Store Connect export passed.
- App, keyboard and widget archive metadata all report build 107.
- IPA: `/tmp/sAiity-export-107/DictusApp.ipa`.
- SHA-256: `6bac4e21e87ca2416f105d3fe82224396ef30caa59020a47f2d11db7502aea6f`.

Limitations: no physical iPhone was connected. This build is a TestFlight candidate. Compilation and mocked tests do not prove emoji-bar padding, AUTO menu feel, live suggestion quality, 2D spacebar feel, or Speak/Settings layout on a real device.

Distribution: App Store Connect upload succeeded on 2026-09-15 at 00:38 local time.

App Store Connect confirmation (ego-browser, signed-in session, 2026-09-15 ~00:41 local):

- Build Uploads: **1.0.0 (107)** status **Complete** (created Sep 15, 2026 12:38 AM).
- iOS Builds → Version 1.0.0: **107** status **Ready to Submit**, expires in 90 days, group **IN Internal**.
- Build detail **1.0.0 (107)**: Internal group assigned (1 tester). Testers in that group have access.
- No Missing Compliance / Processing banner on the build page.

Internal TestFlight testers can install 1.0.0 (107).
