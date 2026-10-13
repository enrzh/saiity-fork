# Build 120 — 2026-09-15

Version 1.0.0 (120), archived from the existing dirty `saiity-fork` checkout.
Existing changes were preserved; no GitHub push or CI run was performed.

On top of build 119:

- Spacebar cursor drag follows the finger at native density (~8pt per character) instead of waiting on joystick ticks. Holding still off the press origin still cruises; returning to that origin stops.
- Spacebar cursor drag no longer plays activation or per-character haptics. Space taps still click.
- In-app Settings → Keyboard: switches for Key popups and Liquid glass. Off makes keyboard chrome fully solid. Hold-to-more-options menus for keys and emoji use glass when Liquid glass is on.

Verification:

- Release archive and App Store Connect export passed.
- App, keyboard and widget archive metadata all report build 120.
- IPA: `/tmp/sAiity-export-120/DictusApp.ipa`
- SHA-256: `f59a156a7263938a937af954f7dc95750c08dfc319e0442bca15788058558423`

Limitations: no physical iPhone was connected. This build is a TestFlight candidate. Compilation does not prove cursor feel, haptics, or glass toggles on a real device.

Distribution: App Store Connect upload succeeded on 2026-09-15 at 18:49 local time (`Uploaded package is processing` / `Upload succeeded`).

App Store Connect web confirmation of Internal Testing was not completed in this pass. Do not treat Internal Testing as confirmed until the build page shows Complete and the Internal group.

Internal TestFlight testers can install 1.0.0 (120) once Apple finishes processing the upload.
