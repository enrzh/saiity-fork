# sAiity 1.0.0 (79)

Prepared 2026-09-12 from the existing dirty `saiity-fork` checkout at `0d578fa0`.
Existing keyboard/audio changes and untracked work were preserved. No GitHub CI or push was run.

## Implemented

- New app-only teal accent and typographic hierarchy. Speak, Models and Settings root navigation.
- Replaced the main dashboard, recording composition and controls, keyboard handoff mock-phone animation, model-preparation waveform/rotating messages, and active onboarding page compositions.
- Reworked preference sections and model cards; model search by name, engine or language, plus compact/multilingual/engine filters.
- Removed accuracy/speed percentages from model cards. Added three preview WhisperKit exports; catalog now has 23 entries. Qwen and Parakeet remain integrated.
- Corrected Distil-Whisper language metadata to English-only and corrected several Whisper download-size estimates against repository bytes.
- Downloads now retain a cancelable task outside recycled model rows. Model preparation takes precedence over missing-model copy. MetricKit aggregate reports appear in persistent diagnostics.
- Added French translations for the new primary interface copy. Licenses and internal identifiers remain intact.
- Replaced the legacy icon generator with validation of the curated sAi icons, preventing accidental regeneration of the old three-bar logo.

## New preview exports

Repository: https://huggingface.co/argmaxinc/whisperkit-coreml

| Export | Repository bytes | Language | Memory gate |
|---|---:|---|---|
| `openai_whisper-small.en_217MB` | 217878408 | English | Excludes A12/A13 |
| `openai_whisper-medium.en` | 1529674079 | English | 6 GB; excludes A12/A13 |
| `openai_whisper-large-v3-v20240930_547MB` | 549554198 | Multilingual Turbo, 4 decoder layers | 6 GB; excludes A12/A13 |

Verified repository exports contain compiled audio encoder, mel spectrogram, decoder and configuration files. These exports are not in Argmax's current explicit iPhone support matrix; they are labelled previews and are never automatic recommendations. Physical-device decoding/accuracy, memory and thermal behavior remain unverified. No claim of new model families or improved ASR accuracy is made.

## Validation

- `swift test --package-path DictusCore`: 1498 tests, zero failures (`/tmp/saiity-79-core-tests.log`).
- Xcode 27 RC simulator build, app and both extensions: succeeded (`/tmp/saiity-79-simulator.log`).
- Headless iOS 27 simulator inspection: onboarding navigation, microphone denial recovery, Speak, Models and Settings pages. Simulator onboarding was bypassed with a launch argument for page inspection; this does not prove keyboard onboarding or ASR on a phone.
- Device Release archive: succeeded (`/tmp/saiity-79-archive.log`).
- Distribution export: succeeded (`/tmp/saiity-79-export.log`).
- Exported IPA's app, keyboard and widget all report build 79. Archived app icon was decoded and visually confirmed as turquoise sAi.
- `git diff --check`: passed.

## Release artifacts and remaining step

- Archive: `/tmp/sAiity-build-79.xcarchive`
- Export options: `/tmp/sAiity-export-options-79.plist`
- IPA: `/tmp/sAiity-export-79/DictusApp.ipa`
- IPA SHA-256: `be6764b2a1897201a9fdc7ea262382dda69e258446aa2cc4dd29cf07ef5e85ce`

Transporter confirms version 1.0.0 (79) was **DELIVERED on 2026-09-12 at 11:12**, using the IPA and SHA-256 above. Apple currently reports "The app is processing"; internal testing readiness is not yet confirmed. The App Store Connect browser session has expired, so browser verification requires signing in again; Transporter can also show internal testing readiness. Do not upload this build again.

Hourly automation `finish-saiity-redesign-and-testflight` remains active until upload and internal testing readiness are confirmed. Delete it only after completion.
