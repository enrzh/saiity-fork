# Build 112 — 2026-09-15

Version 1.0.0 (112), archived from the existing dirty `saiity-fork` checkout.
Existing changes were preserved; no GitHub push or CI run was performed.

Dictation cleanup on top of build 111:

- Multilingual dictation now runs span-aware cleanup: a language-neutral floor strips Whisper sound tags, fillers, clock self-corrections, and restated duplicates, then confident monolingual sentence spans are polished sequentially. Mixed Latin+CJK in the same sentence stays on the floor and is not sent to the model.
- German grammar is no longer faked with regex on the floor. Clips shorter than about two seconds still skip the model.
- Product output mode remains multilingual.

Verification:

- DictusCore: 1600 tests, 1 skip, 0 failures after skipping the pre-existing host `UserDictionaryLoggingTests` suite and the host-timing `testEstimatorCostIsNegligibleOnANormalDictation` flake.
- Release archive and App Store Connect export passed.
- App, keyboard and widget archive metadata all report build 112.
- IPA: `/tmp/sAiity-export-112/DictusApp.ipa`.
- SHA-256: `c8869c8720d320111204490fb8500b6250a849176cfa2634367798d4a33d2be6`.

Limitations: no physical iPhone was connected. This build is a TestFlight candidate. Compilation and mocked tests do not prove German grammar rewrite or mixed-language preservation on a real device. Apple Intelligence was `modelNotReady` on the archive Mac, so on-device Foundation Model quality is unverified.

Distribution: App Store Connect upload succeeded on 2026-09-15 at 11:38 local time (`Uploaded package is processing` / `Upload succeeded`).

App Store Connect web confirmation was not completed in this pass: the signed-in TestFlight session had expired, Apple ID Continue stayed disabled after Bitwarden did not fill the login fields, and no App Store Connect API session was available to query processing. Do not treat Internal Testing as confirmed until the build page shows Complete and the Internal group.

Internal TestFlight testers can install 1.0.0 (112) once Apple finishes processing the upload.
