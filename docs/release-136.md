# Build 136 — 2026-09-16

Version 1.0.0 (136).

## Changes since 135

- **Dictation:** keyboard no longer clears `keyboardAudioReady`; defers to sAiity prepare when audio/model not ready.
- **Emoji:** reload grid when layout height becomes valid (fixes blank emoji page).
- **Glass UI:** single inset Liquid Glass panel (no separate suggestion-lane bar).

## Verification

- Archive: `/tmp/sAiity-archive-136/DictusApp.xcarchive` (`CFBundleVersion` 136).
- App Store Connect upload succeeded 2026-09-16 ~17:30 local (`Upload succeeded` / processing).

TestFlight: enable **1.0.0 (136)** for **sAiity Beta** when processing completes.
