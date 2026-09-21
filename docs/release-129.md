# Build 129 — 2026-09-16

Version 1.0.0 (129), archived from dirty `saiity-fork` checkout.

## Fixes

- **Solid dictation board hits:** SwiftUI owns voice-board chrome when liquid glass is off; UIKit owns it when glass is on.
- **Native key pitch:** 40pt keys, 5pt horizontal gap, 9pt row gap (pack, don’t stretch).
- **Spacebar:** 18pt corner radius on auxiliary pages.
- **PiP on leave-app:** Fallback status from App Group dictation state; PiP source attaches on background scenes.
- **Layouts:** Dvorak, Colemak, Workman, Norman added to layout picker.
- **Emoji:** Tighter grid (6pt row gap, 2pt vertical inset); category bar no longer blocks scrub gestures.

## Verification

- DictusCore: 1637 tests, 1 skip (`UserDictionaryLoggingTests`), 0 failures.
- Debug simulator build succeeded.
- Archive/export/upload succeeded 2026-09-16 ~09:55.
- IPA: `/tmp/sAiity-export-129/DictusApp.ipa`
- SHA-256: `8faa761c4441690554650c7b99b95a488460ca3437b0c969422a59d63a30e2ac`

Distribution: App Store Connect upload succeeded (`Upload succeeded` / processing).
