# Build 128 — 2026-09-16

Version 1.0.0 (128), archived from the existing dirty `saiity-fork` checkout.
Existing changes were preserved; no GitHub push or CI run was performed.

On top of build 127 (121 reconstruction), this restores build 126 keyboard/models/presence behavior:

- Solid dictation board: UIKit owns 123/ABC/emoji/mic/space/return/delete/paste/language when material is solid; hosting interaction is off on the voice board.
- Key popups Off / Popup / Popout, liquid glass material picker, and optional key containers (default off). Command keys keep plates.
- Letter/symbol keys pack at 42pt with 6pt gaps and 12pt row pitch; 36pt suggestion lane with extra window height for a larger glass inset.
- Native Picture in Picture on leave-app via `DictationPresencePicker` (Off / Live Activity / PiP).
- Whisper Large v3 and Large v3 Turbo offered as new downloads (RAM-gated). Model cards show Accuracy and Speed gauges. Add custom model UI removed from the models page.
- Emoji grid clipped inside the inset at compact height; category scrub in bar + UIKit overlay.
- Layout hint lists all four shipped layouts including QWERTZ Deutschland.

Also kept: spacebar cursor `routeCursorEnded` on auxiliary pages (127 fix).

Verification:

- DictusCore: 1637 tests, 1 skip (`UserDictionaryLoggingTests` excluded), 0 failures.
- Debug simulator build of `sAiity-iOS` succeeded before this archive.
- Release archive and App Store Connect export passed.
- App, keyboard and widget archive metadata all report build 128.
- IPA: `/tmp/sAiity-export-128/DictusApp.ipa`
- SHA-256: `1870e613d71eae9867009da61dc2f3a69fb9f384fd2e5adf7fbdac6b92606831`

Limitations: no physical iPhone was connected. Compilation does not prove solid-board hits, PiP on leave-app, or emoji scrub on a real device. PiP runs in the app process only.

Distribution: App Store Connect upload succeeded on 2026-09-16 at 09:22 local time (`Uploaded package is processing` / `Upload succeeded`).

Internal TestFlight testers can install 1.0.0 (128) once Apple finishes processing the upload.
