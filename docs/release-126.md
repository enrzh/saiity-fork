# Build 126 — 2026-09-16

Version 1.0.0 (126), archived from the existing dirty `saiity-fork` checkout.
Existing changes were preserved; no GitHub push or CI run was performed.

On top of build 125:

- Solid dictation board: the SwiftUI inset no longer intercepts taps. UIKit owns 123/ABC/emoji/mic/space/return/delete/paste/language. Hosting interaction is off on the voice board.
- Letter/symbol keys pack at native 42pt height with 6pt gaps and 12pt row pitch instead of stretching to fill the glass. Key containers stay off by default and only plate letters/symbols. Command keys (123, ABC, emoji, shift, delete, space, return) keep plates.
- Popout still enlarges and fades; it is independent of key plates.
- Picture in Picture prepares a real inline source (not a 2% alpha stub) and starts when leaving the app, including when recording already started in the background. A source window is used only when no key window exists. Custom HUDs stay gone.
- Keyboard layout picker already lists all four shipped layouts (AZERTY, QWERTY, QWERTZ, QWERTZ Deutschland).
- Models page has no Add Model path. Catalog cards show Accuracy and Speed indexes plus gauges.
- Emoji glyphs sit inside the glass at compact 4-row native height. Category tap/drag is owned by `CategorySwipeControl` in the bar and the UIKit overlay scrubber.

Verification:

- DictusCore: 1647 tests, 1 skip (`UserDictionaryLoggingTests`), 0 failures.
- Debug simulator build of `sAiity-iOS` for iPhone 17 succeeded before this archive.
- Release archive and App Store Connect export passed.
- App, keyboard and widget archive metadata all report build 126.
- IPA: `/tmp/sAiity-export-126/DictusApp.ipa`
- SHA-256: `e7f4acfa93d5ce5d4d7918ea6156d54e010375b2c4abc8e1bda743fcf061a381`

Limitations: no physical iPhone was connected. Compilation does not prove solid-board hits, native PiP on leave-app, or emoji category scrubbing on a real device. PiP only runs in the app process, not inside the keyboard extension.

Distribution: App Store Connect upload succeeded on 2026-09-16 at 00:23 local time (`Uploaded package is processing` / `Upload succeeded`).

App Store Connect web confirmation of Internal Testing was not completed in this pass. Do not treat Internal Testing as confirmed until the build page shows Complete and the Internal group.

Internal TestFlight testers can install 1.0.0 (126) once Apple finishes processing the upload.
