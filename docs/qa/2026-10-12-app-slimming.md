# App slimming verification

## Result and scope

The signed Release development app payload fell from 99,372 KiB (97.0 MiB) to 63,840 KiB (62.3 MiB), a 35.8% reduction. The final package was installed on the previously authorized paired iPhone Air, and filtered device inventory confirmed Syllivra 1.0.0 (242) at the installation location returned by Apple's installer.

Work remains local and uncommitted on `cursor/keyboard-surface-fixes-a66e`, based on `b696d880`. Existing processing-speed changes and unfinished first-party inference work were preserved. No commit, push, TestFlight upload, publication, release change or tester invitation occurred. The historical archive/export artifacts were preserved.

This pass changes generated bundle resources and normal Release symbol stripping. It retains the current model backends, language/model choices, all 29 feedback sound names, preferences, App Group and iOS 17.0 minimum. It adds no production dependency or runtime owner.

## Changes

- `scripts/slim-app-resources.py` reads the unchanged frequency-word cap from `FrequencyDictionary.swift`. It retains every word at or above the 10,000th highest source count, including all cutoff ties. The runtime still applies its existing 10,000-word cap.
- The same script converts original stereo 16-bit 48 kHz WAV sounds to native ALAC CAF. It decodes each result through Apple's audio tools and compares normalized PCM before accepting it. Source WAVs remain intact; only stale generated WAV copies are removed.
- `SoundFeedbackService` prefers CAF with WAV fallback. Catalog names, stored selections, volume, cached players and lifecycle routing retain their existing owners and behavior.
- Xcode build phases are the sole producers of the compact frequency files and generated Sounds folder. Their outputs are declared explicitly so resource writes trigger signing.
- Release uses non-global symbol stripping with separate dSYM generation. The final main binary and dSYM share UUID `0E8B92BC-8C6F-3DA8-B1DF-BE6384E2B832`.

The proposed n-gram representation change was rejected because the measured candidate increased size by about 5%. The complete existing n-gram and spellcheck files remain unchanged.

## Size evidence

Allocated app/keyboard sizes use `du -k -s` on the same Release device-build path and development-signing configuration before and after the pass. File sizes use exact byte counts. These are package payload measurements; they exclude downloaded user models and are not App Store download estimates.

| Resource | Before | After |
| --- | ---: | ---: |
| Whole app, allocated | 99,372 KiB | 63,840 KiB |
| Keyboard bundle, allocated | 35,976 KiB | 30,672 KiB |
| Main executable | 47,660,944 bytes | 23,015,680 bytes |
| Four frequency JSON files | 2,784,957 bytes | 636,143 bytes |
| 29 feedback sounds | 5,439,702 bytes | 1,177,329 bytes |
| Eight n-gram/spellcheck files | 27,451,985 bytes | 27,451,985 bytes |

## Frequency preservation and load work

Every generated dictionary equals the source set of words whose counts reach the cutoff, with exact original counts. The final built files also match the already verified compact probe files byte-for-byte.

| Language | Source words | Eligible bundled words | Full load median | Compact load median |
| --- | ---: | ---: | ---: | ---: |
| German | 40,000 | 10,001 | 19.66 ms | 5.15 ms |
| English | 40,000 | 10,000 | 18.64 ms | 4.20 ms |
| Spanish | 49,585 | 10,003 | 26.34 ms | 5.32 ms |
| French | 40,292 | 10,002 | 21.30 ms | 5.35 ms |

These are nine-iteration medians from optimized native Mac code using the current `FrequencyDictionary`. The probe checks exact ranks above the cutoff and zero ranks below it. The existing runtime's selection among boundary ties is nondeterministic; retaining every tie preserves eligibility, not identical selected tie members.

The measured dictionary-load improvement is about 3.8–5.0 times on this Mac. It does not measure iPhone keyboard startup, transcription, cleanup, translation or model-inference latency.

## Verification

- The resource self-check has failing-before/passing-after evidence for cutoff ties and covers malformed counts, unsafe/symlink destinations, synthetic lossless audio and source preservation. Run it with `/usr/bin/python3 scripts/slim-app-resources.py --self-test`.
- Relevant deterministic Core checks passed: 26 selected Debug tests and 45 selected Release tests, zero failures. These are focused runs, not a claim that the whole suite was repeated. The malformed-frequency test's decode diagnostic is expected.
- Native audio checks loaded all 29 final CAF files through `AVAudioFile` and `AVAudioPlayer` on the Mac. Every PCM sample, frame count, processing format, channel count and duration matched its original. No sound playback or recording was performed.
- All eight final n-gram/spellcheck resources and the bundled open-source notices matched their source files byte-for-byte. All 41 original sound/frequency/n-gram/spellcheck source hashes remained unchanged.
- The final Release device build and Debug simulator build passed. Strict signature verification passed separately for the app, embedded keyboard and embedded widget.
- An unchanged second simulator build passed, and all three signatures were checked again. The first script version had rewritten frequency resources without declaring outputs, allowing Xcode to skip keyboard signing. That failure was reproduced before fixing the build graph; manual re-signing was not used as a fix.
- App, keyboard and widget remain 1.0.0 (242), require iOS 17.0, and retain their existing bundle identifiers. Each final development signature contains `group.de.aiity.saiity.ios.beta`.
- Project plist syntax and diff whitespace checks passed.

The initial and final compaction builds emitted existing deprecation and concurrency warnings, including recording-permission APIs, older `onChange`/logging APIs, actor isolation in model/Live Activity/PiP owners, and switch exhaustiveness. They remain open; this pass does not claim a warning-free project. The unchanged incremental build emitted no warnings.

## Phone update

After the final signature and resource checks, Apple's native installer successfully updated the same `de.aiity.saiity.ios.beta` app. Filtered inventory confirmed its version and matched its bundle URL to the new installer result. No uninstall or app-data deletion occurred. No app launch, UI automation, microphone use, permission change, model download or private-transcript access was performed.

This installation is a development build using the existing signing identity. It is not a TestFlight release or proof of Apple processing/tester availability.

## Evidence and remaining gates

Evidence is in `/tmp/saiity-slim.CJRSqb`: resource/audio red-green logs, `frequency-speed.log`, focused Core logs, `simulator-signing-fix.log`, `simulator-incremental.log`, `device-signing-fix.log`, separate final signature logs, `final-resources.log`, `final-sound-native.log`, `final-entitlements.log`, source SHA-256 records, `install-final.json` and `installed-after.json`. The final device app is in `/tmp/saiity-phone-install.mD5pGL/derived/Build/Products/Release-iphoneos/DictusApp.app`.

Physical typing/haptics and sound onset, field/settings/Full Access parity, cross-app/background delivery, landscape, PiP/system Live Activity, real-model load/inference/cancellation/foreground loss/memory, multilingual meaning and end-to-end latency remain separate unverified gates. Recognition evaluation still requires licensed or expressly consented files. The first-party inference migration remains unfinished, so active third-party runtimes were retained. A fresh distribution archive/export was not made during this pass.
