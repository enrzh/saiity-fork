# Build 100 — 2026-09-14

Version 1.0.0 (100), archived from the existing dirty `saiity-fork` checkout.
Existing changes were preserved; no GitHub push or CI run was performed.

Includes the emoji and 123-page chrome work on top of build 99:

- Emoji categories moved into the 44pt suggestion lane; paste/chips hide on that page.
- Delete floats over the bottom-right of the emoji grid.
- Emoji pages are free-scroll; paging lock is off so a swipe can stop between page widths.
- Emoji bottom bar uses the same 8pt gap as ABC/123, so the chrome no longer sits lower.
- 123/#+= pages use one wide ABC on the bottom left. `#+=`/`123` stay on the last key row.

Verification:

- Release archive and App Store Connect export passed.
- App, keyboard and widget archive metadata all report build 100.
- IPA: `/tmp/sAiity-export-100/DictusApp.ipa`.
- SHA-256: `b8a50a73f426b23615b2e654027cce311e45e8fb70cbb78895932f2207c6e37a`.

Limitations: this is a TestFlight candidate for device testing. Simulator compile does not prove emoji free-scroll, the floating delete, or the wide ABC control on iPhone.

Distribution: App Store Connect upload succeeded on 2026-09-14 at 14:05 local time.
Apple then reported that the uploaded package was processing. TestFlight typically shows the build after that processing finishes.
