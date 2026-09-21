# Build 132 — 2026-09-16

Version 1.0.0 (132).

## Changes since 131

- **Typing feel:** larger key hit slop (6pt), UIKit touch routing for symbol keys, multi-touch on variant keys.
- **Emoji lane:** category bar flat in suggestion lane; UIKit scrubber owns tap/drag; tighter emoji grid spacing.
- **No word suggestions** in the top accessory bar (paste + language + dismiss only; prediction row not shown).
- Autocorrect-on-space remains when enabled in settings; suggestion bar is not populated while typing.

## Verification

- DictusCore keyboard contract tests pass.
- Archive: `/tmp/sAiity-archive-132/DictusApp.xcarchive` (`CFBundleVersion` 132).
- IPA: `/tmp/sAiity-export-132/DictusApp.ipa`.
- App Store Connect upload succeeded 2026-09-16 ~11:56 local (`Upload succeeded` / processing).
