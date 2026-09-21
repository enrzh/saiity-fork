# Build 105 — 2026-09-14

Version 1.0.0 (105), archived from the existing dirty `saiity-fork` checkout.
Existing changes were preserved; no GitHub push or CI run was performed.

Adds a user-selectable dictation cleanup / grammar backend on top of build 104:

- Settings → Dictation: **Cleanup model** picker for Apple Intelligence (on-device Foundation Models) or a registered Ollama cleanup model.
- Models → **Dictation cleanup**: Apple Intelligence row with Select/Active and availability, plus Select on custom Ollama cleanup rows.
- Apple Intelligence is the default for new installs. Existing installs that already had a valid Ollama cleanup model keep that choice. Choosing Apple Intelligence no longer silently yields to Ollama.
- Keyboard chrome, emoji category bar, models catalog, typing languages, and haptic intensity from the prior dirty tree remain in this archive.

Verification:

- DictusCore: 1576 tests, 1 skip, 0 failures after skipping the pre-existing host `UserDictionaryLoggingTests` suite.
- Debug simulator build of `sAiity-iOS` succeeded before the archive.
- Release archive and App Store Connect export passed.
- App, keyboard and widget archive metadata all report build 105.
- IPA: `/tmp/sAiity-export-105/DictusApp.ipa`.
- SHA-256: `11577ada31f079714cc6d94145e1c4e30fce6ff1a85cf09d2ce155689cf6783a`.

Limitations: no physical iPhone was connected. This build is a TestFlight candidate. Compilation and mocked tests do not prove Apple Intelligence quality, Ollama cleanup quality, Qwen device load, emoji-bar device drag, haptic feel, or keyboard touch behavior.

Distribution: App Store Connect upload succeeded on 2026-09-14 at 23:08 local time.

App Store Connect confirmation (ego-browser, signed-in session, 2026-09-14 ~23:12 local):

- Build Uploads: **1.0.0 (105)** status **Complete** (created Sep 14, 2026 11:08 PM).
- iOS Builds → Version 1.0.0: **105** status **Ready to Submit**, expires in 90 days, group **IN Internal**.
- Internal group assigned; testers in that group have access. No Missing Compliance / Processing banner.

Internal TestFlight testers can install 1.0.0 (105).
