# Build 111 — 2026-09-15

Version 1.0.0 (111), archived from the existing dirty `saiity-fork` checkout.
Existing changes were preserved; no GitHub push or CI run was performed.

Dictation and keyboard changes on top of build 110:

- Spoken cleanup now drops fillers (`like`, `um`, `yeah`, `so basically` restarts), keeps the corrected time (`2am, oh sorry, 4am` → `4am`), and removes restated duplicates. Auto-mode fact checks allow that numeric self-correction without inventing amounts.
- Accessory lane no longer shows live word suggestions. Paste, emoji categories, and dismiss remain.
- Key hit slop is 2pt so neighboring keys and delete no longer overlap the 5pt gap. Suggestion updates no longer rebuild the keyboard on every keystroke.

Verification:

- DictusCore: 1589 tests, 1 skip, 0 failures after skipping the pre-existing host `UserDictionaryLoggingTests` suite and the host-timing `testEstimatorCostIsNegligibleOnANormalDictation` flake.
- Release archive and App Store Connect export passed.
- App, keyboard and widget archive metadata all report build 111.
- IPA: `/tmp/sAiity-export-111/DictusApp.ipa`.
- SHA-256: `9d2c7c611a09bca7a1daa1fded4dc28b7d4dc33e68e3cdb3c24801877f85ec68`.

Limitations: no physical iPhone was connected. This build is a TestFlight candidate. Compilation and mocked tests do not prove dictation cleanup quality or fast-typing feel on a real device.

Distribution: App Store Connect upload succeeded on 2026-09-15 at 02:58 local time.

App Store Connect confirmation (2026-09-15):

- Build Uploads: 1.0.0 (111) Complete, Sep 15, 2026 2:58 AM.
- Build page `1.0.0 (111)`: Internal group assigned (1 tester). No Missing Compliance.
- Internal group Builds: 1.0.0 (111) Testing, expires in 90 days.
