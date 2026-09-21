# Build 98 — 2026-09-14

Version 1.0.0 (98), archived from the existing dirty `saiity-fork` checkout.
Existing changes were preserved; no GitHub push or CI run was performed.

Includes the current optional post-dictation suggestions and Settings cleanup,
Qwen artifact/loading safeguards, and Auto cleanup fact-preservation checks.
Suggestions default off and require explicit acceptance. Language analysis runs
off the main thread; stale document context invalidates suggestions.

Verification:

- Core: 1,544 tests, one skipped, zero failures.
- Simulator app build passed.
- Release archive and App Store export passed.
- App, keyboard and widget archive metadata all report build 98.
- IPA: `/tmp/sAiity-export-98/DictusApp.ipa`.
- SHA-256: `c3f2c9e2dfcc643158c1a8d33cd81f2704da58c14090bd8959b8cba7e2296dc0`.

Limitations: no physical iPhone Qwen load/inference verification or comparative
ASR latency/accuracy benchmark. Live cleanup evaluation was blocked by Apple
Foundation Models `modelNotReady`. Automated safeguards are conservative checks,
not proof of semantic preservation for every language. Prediction quality and
device interactions remain unverified. This release does not complete that work.

Distribution: Transporter confirmed delivery on 2026-09-14 at 08:52 local time.
Transporter subsequently confirmed that the app finished processing. Internal
TestFlight readiness is not yet explicitly verified; the browser requires login.
