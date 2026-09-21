# Build 125 — 2026-09-15

Version 1.0.0 (125), archived from the existing dirty `saiity-fork` checkout.
Existing changes were preserved; no GitHub push or CI run was performed.

On top of build 124:

- Dictation board: SwiftUI inset chrome no longer intercepts taps; UIKit keeps 123/ABC/emoji/mic/space/delete/return.
- Letter/symbol/number keys use optional plates via Settings → Key containers (default off). Popout unchanged.
- Native keyboard height scale restored to 1.0; letter grids drop duplicate vertical padding for tighter native rows.
- PiP prepares the inline video-call source while recording and starts when leaving the app.
- Models: removed custom ASR add section; catalog cards show Accuracy/Speed index plus gauges.
- Emoji grid clips inside the inset at compact height; category scrub is UIKit-only in the accessory lane.

Verification:

- DictusCore: 1636 tests, 1 skip (`UserDictionaryLoggingTests`), 0 failures.
- Debug simulator build of `sAiity-iOS` for iPhone 17 succeeded before archive.
- Release archive and App Store Connect export passed.
- App, keyboard and widget archive metadata all report build 125.
- IPA: `/tmp/sAiity-export-125/DictusApp.ipa`

Limitations: no physical iPhone was connected. PiP only runs in DictusApp, not the keyboard extension.

Distribution: App Store Connect upload succeeded on 2026-09-15 at 23:36 local time (`Uploaded package is processing` / `Upload succeeded`).

Internal TestFlight testers can install 1.0.0 (125) once Apple finishes processing the upload.
