# Build 123 — 2026-09-15

Version 1.0.0 (123), archived from the existing dirty `saiity-fork` checkout.
Existing changes were preserved; no GitHub push or CI run was performed.

On top of build 122:

- Suggestion bar, letter/symbol/number keys, and emoji cells use even 8pt insets from the glass and 6–8pt gaps between controls, so chrome no longer edges the board.
- Settings → Keyboard Key popups is Off / Popup / Popout. Popup is the balloon above the key. Popout enlarges out of the pressed key and fades. Existing “key popups on” installs stay on Popup.
- Solid dictation board no longer paints a nested grouped slab. Keys keep tertiary fill plates; the Listening capsule stays white.
- Picture in Picture uses system `AVPictureInPictureController` / video-call PiP. The custom overlay window is removed. Unsupported devices fail closed.

Verification:

- Release archive and App Store Connect export passed.
- App, keyboard and widget archive metadata all report build 123.
- IPA: `/tmp/sAiity-export-123/DictusApp.ipa`
- SHA-256: `ad0576e2e0562557238979950f59fc3aacfcb39626ee7d73fca659e683429347`

Limitations: no physical iPhone was connected. Compilation does not prove key spacing, popout feel, solid dictation chrome, or native PiP on a real device. PiP only runs in the app process, not inside the keyboard extension.

Distribution: App Store Connect upload succeeded on 2026-09-15 at 21:52 local time (`Uploaded package is processing` / `Upload succeeded`).

App Store Connect web confirmation of Internal Testing was not completed in this pass. Do not treat Internal Testing as confirmed until the build page shows Complete and the Internal group.

Internal TestFlight testers can install 1.0.0 (123) once Apple finishes processing the upload.
