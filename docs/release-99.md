# Build 99 — 2026-09-14

Version 1.0.0 (99), archived from the existing dirty `saiity-fork` checkout.
Existing changes were preserved; no GitHub push or CI run was performed.

Includes the keyboard chrome and dictation-cleanup work on top of build 98:

- Strip ASR event labels such as `(singing)~`, `[kiss]`, `[BLANK_AUDIO]`, `♪`.
- Grammar floor after cleanup/translation; next-word chips still off by default.
- Return-to-dictation-board moved into the suggestion lane, left of keyboard-down.
- Shared bottom bar on spacebar pages: 123, ABC, space, emoji, enter.
- Emoji uses that same bar, with categories and delete above it.
- Native-style mode-button placement; pinned 44pt delete row on ABC/123/#+=.
- Spacebar cursor tracking continues while the finger stays down.
- Killed-app recovery uses heartbeat only; a leftover Live Activity is not proof the app is alive.

Verification:

- Release archive and App Store Connect export passed.
- App, keyboard and widget archive metadata all report build 99.
- IPA: `/tmp/sAiity-export-99/DictusApp.ipa`.
- SHA-256: `3334a58b850d47ebed54ca6650e21536cfd51908000aad0e861bf1dee592e740`.

Limitations: this is a TestFlight candidate for device testing. Simulator compile does not prove keyboard chrome, spacebar trackpad, or killed-app recovery on iPhone.

Distribution: App Store Connect upload succeeded on 2026-09-14 at 13:25 local time.
Apple then reported that the uploaded package was processing. TestFlight typically shows the build after that processing finishes.
