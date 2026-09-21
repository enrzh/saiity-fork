# Build 138 — 2026-09-17

Version 1.0.0 (138).

## Changes since 137

- **Emoji Recents:** blank-area swipes page the grid; empty cells no longer steal the pan.
- **Category bar:** floats over the emoji list like delete, slightly narrower than the spacebar, bottom-aligned with delete; Flags and later categories are reachable.
- **Delete:** ABC, 123, and emoji share `boardDeleteFrame`.
- **Hold popups:** letter / emoji / symbol variants follow the liquid-glass vs solid setting (beta App Group).
- **Dictation board:** mic taps reach the SwiftUI capsule; the UIKit overlay no longer swallows them.
- **Setup Full Access:** handshake is the only signal; the setup page re-reads it after Settings and Darwin.

## Verification

- Archive: `/tmp/sAiity-archive-138/DictusApp.xcarchive` (`CFBundleVersion` 138).
- App Store Connect upload succeeded 2026-09-17 ~01:52 local (`Upload succeeded` / processing).
- Info.plists + `CURRENT_PROJECT_VERSION` set to **138**.

TestFlight: enable **1.0.0 (138)** for **sAiity Beta** when processing completes.
