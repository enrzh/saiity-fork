# Build 103 — 2026-09-14

Version 1.0.0 (103), archived from the existing dirty `saiity-fork` checkout.
Existing changes were preserved; no GitHub push or CI run was performed.

Includes the keyboard fixes on top of build 102:

- ABC and 123/#+= share the Caps/Delete last-row position.
- AUTO language chip is a UIKit dropdown again (Automatic, EN, DE, FR, ES). Clipboard no longer expands in the suggestion bar.
- Mixed-language dictation with Keep spoken language skips model polish so speech is not rewritten into one language.
- Swipe-to-type is removed; hold-for-accents works again with a broader variant set.
- Key haptics, emoji skin-tone hold, and emoji category bar taps/drag are restored.

Verification:

- Release archive and App Store Connect export passed.
- App, keyboard and widget archive metadata all report build 103.
- IPA: `/tmp/sAiity-export-103/DictusApp.ipa`.
- SHA-256: `71ec61147b61f5fe5d6d54f35a2dafce8a5428bd57b36512f3b74b825645ab3a`.

Limitations: this is a TestFlight candidate for device testing. Simulator compile does not prove last-row alignment, the language menu, hold-for-accents, or emoji category scrubbing on iPhone.

Distribution: App Store Connect upload succeeded on 2026-09-14 at 19:20 local time.
Apple then reported that the uploaded package was processing. TestFlight typically shows the build after that processing finishes.
