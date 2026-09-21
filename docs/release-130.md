# Build 130 — 2026-09-16

Version 1.0.0 (130), archived from dirty `saiity-fork` checkout.

## Changes

- **Removed Picture in Picture** — dictation presence is Off or Live Activity only; legacy PiP preference migrates to Live Activity.
- **Full-width keyboard glass** — inset surface spans the input width when rails fit (no side inset).
- **Proportional vertical growth** — keyboard height and letter/symbol grid metrics scale with the same factor as horizontal expansion vs the previous inset surface (~4% on 390pt phones).
- **Native-like key grid** — letter, symbol, and number pads use `scaledKeyGeometry` for spacing and row height.

## Verification

- DictusCore: keyboard/presence contract tests pass; `UserDictionaryLoggingTests` may fail in local env (unchanged).
- Release archive and App Store Connect export passed 2026-09-16 ~10:42 local.
- Archive: `/tmp/sAiity-archive-130/DictusApp.xcarchive` (app `CFBundleVersion` 130).
- Upload used direct `destination: upload` (IPA not retained in export folder).

Distribution: App Store Connect upload succeeded (`Upload succeeded` / `Uploaded package is processing`).
