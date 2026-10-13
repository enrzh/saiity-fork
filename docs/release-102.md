# Build 102 — 2026-09-14

Version 1.0.0 (102), archived from the existing dirty `saiity-fork` checkout.
Existing changes were preserved; no GitHub push or CI run was performed.

Includes the keyboard, settings, and dictation work on top of build 101:

- ABC and 123 bottom chrome is compact 123/ABC, then emoji, space, enter. Space uses the old right-side emoji width. `#+=` stays on the numbers key row.
- Dictation cleanup, grammar, and prediction honor “Keep spoken languages” vs a single typing language. Mixed multilingual output no longer forces the keyboard language.
- Suggestion-bar chip opens typing language (Automatic / EN / DE) and output language. Swipe typing is available on the letter page.
- Settings and Models cards restyled; Live Activity mark is circular.

Verification:

- Release archive and App Store Connect export passed.
- App, keyboard and widget archive metadata all report build 102.
- IPA: `/tmp/sAiity-export-102/DictusApp.ipa`.
- SHA-256: `019c8642cdc03548f10c0268e123c5e7a8e918eec736c64be4ac46d4a2ee64cd`.

Limitations: this is a TestFlight candidate for device testing. Simulator compile does not prove ABC/123 chrome, swipe typing, or the language sheet on iPhone.

Distribution: App Store Connect upload succeeded on 2026-09-14 at 16:23 local time.
Apple then reported that the uploaded package was processing. TestFlight typically shows the build after that processing finishes.
