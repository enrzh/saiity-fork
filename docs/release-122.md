# Build 122 — 2026-09-15

Version 1.0.0 (122), archived from the existing dirty `saiity-fork` checkout.
Existing changes were preserved; no GitHub push or CI run was performed.

On top of build 121:

- Emoji category tap and drag restored. The glass well is non-interactive; a UIKit overlay with a duration-0 long-press plus the SwiftUI category bar both jump pages by category.
- Whisper Large v3 and Large v3 Turbo are listed as downloadable models (gated to ≥6 GB RAM, not A12/A13). sherpa-onnx and SenseVoice were assessed only and not added; there is no loadable runtime for them.
- Suggestion bar and its controls are 32pt. Extra keyboard window height stays 44pt so the liquid-glass typing surface grows instead of shrinking with the bar.
- Glass inset and letter/symbol/number key grid use 4pt padding and spacing. Letter labels are 24pt. Bottom 123/ABC/space/return stay 44pt.

Verification:

- Release archive and App Store Connect export passed.
- App, keyboard and widget archive metadata all report build 122.
- IPA: `/tmp/sAiity-export-122/DictusApp.ipa`
- SHA-256: `542c4ac04f55cf3290019b9d56c6c46c9c3e93875b777c7ce92cf5ecc9d7c86b`

Limitations: no physical iPhone was connected. Compilation does not prove emoji-category feel, large-model downloads, or the new glass/key layout on a real device.

Distribution: App Store Connect upload succeeded on 2026-09-15 at 20:54 local time (`Uploaded package is processing` / `Upload succeeded`).

App Store Connect web confirmation of Internal Testing was not completed in this pass. Do not treat Internal Testing as confirmed until the build page shows Complete and the Internal group.

Internal TestFlight testers can install 1.0.0 (122) once Apple finishes processing the upload.
