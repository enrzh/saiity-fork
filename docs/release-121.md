# Build 121 — 2026-09-15

Version 1.0.0 (121), archived from the existing dirty `saiity-fork` checkout.
Existing changes were preserved; no GitHub push or CI run was performed.

On top of build 120:

- Spacebar cursor drag maps finger movement onto a reconstructed visual layout (hard newlines plus optional soft wrap) and jumps with one `adjustTextPosition`. Vertical motion can leave a word/line instead of walking UTF-16 through the rest of the paragraph.
- Soft wrap is estimated from keyboard width (~8pt per character) and disabled for email, URL, number, phone, and web-search fields.
- Preferred column is kept across a vertical jump and reset 0.5s after the last step, and cleared when the space gesture ends.

Verification:

- Release archive and App Store Connect export passed.
- App, keyboard and widget archive metadata all report build 121.
- IPA: `/tmp/sAiity-export-121/DictusApp.ipa`
- SHA-256: `b69a2d0aed726dbce64164e99f2cf8ecc9af93a997ccac6aa35d43fd40563dd9`

Limitations: custom keyboards cannot use the host `closestPosition(to:)` / UITextView geometry, so the caret still lands on a reconstructed text position rather than floating in empty pixels. No physical iPhone was connected. Compilation does not prove 2D caret feel on a real device.

Distribution: App Store Connect upload succeeded on 2026-09-15 at 19:42 local time (`Uploaded package is processing` / `Upload succeeded`).

App Store Connect web confirmation of Internal Testing was not completed in this pass. Do not treat Internal Testing as confirmed until the build page shows Complete and the Internal group.

Internal TestFlight testers can install 1.0.0 (121) once Apple finishes processing the upload.
