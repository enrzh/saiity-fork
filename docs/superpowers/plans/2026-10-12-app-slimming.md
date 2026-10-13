# Syllivra App Slimming Implementation Plan

> **For agentic workers:** Execute locally using `executing-plans`. Main owns serial verification/builds. Preserve the current dirty checkout and the unfinished first-party-core work. Do not commit, push or upload.

**Goal:** Reduce the installed app payload and keyboard frequency-data loading work while preserving all current language, model, sound and recovery choices.

**Architecture:** Use Apple's normal Release symbol stripping and lossless audio codec. Compact only generated bundle frequency resources that the existing loader already limits to its top 10,000 words. Keep source dictionaries, original WAV files, existing owners and preference identifiers intact.

**Tech Stack:** Existing Swift/Foundation/AVFoundation, Xcode build settings, Python standard library and macOS `afconvert`. No production dependency or additional service layer.

**Status:** Completed locally. The smaller signed development build is installed on the previously authorized paired phone. See [verification and limits](../../qa/2026-10-12-app-slimming.md). No commit, push, upload or release change occurred; the separate native-core migration remains unfinished.

## Scope and measured baseline

Implementation is authorized by the user's request to slim down and improve the working app. The initial installed development bundle is `/tmp/saiity-phone-install.mD5pGL/derived/Build/Products/Release-iphoneos/DictusApp.app`: 99,372 KiB allocated, approximately 97 MiB. Its main binary is 47,660,944 bytes; the four n-gram dictionaries total 25,690,692 bytes. Sounds occupy approximately 5.2 MiB. All measurement comparisons must use the same signing/configuration/destination and distinguish installed payload from an App Store download estimate.

Read-only probes show that `strip -S -x` reduces a copied app binary to 25,309,056 bytes. The original signed artifact is unchanged. Apple's ALAC codec reduces the example 92,238-byte feedback WAV to 20,071 bytes. All four frequency files contain 40,000–49,585 entries while `FrequencyDictionary` keeps only 10,000. Preserve every entry tied at the cutoff so no formerly eligible word is excluded.

An indexed n-gram result-list rewrite was rejected: nearly every result list is unique, and the proposed representation would increase these files by approximately 5%. Preserve all n-gram/spellcheck bytes and mmap behavior. Removing active model runtimes is still gated by the separate native-core parity plan.

## Global constraints

- Keep iOS 17.0, current bundle IDs, version/build 1.0.0 (242), all languages/models, sound names, preferences and recovery behavior.
- Preserve every existing source/untracked change, Git recovery state, model artifact and original source resource.
- Restrict preprocessing writes/deletions to explicitly validated generated `.app`/`.appex` bundle resources. Never modify user models, transcripts or app data.
- Build-phase processing must happen before final signing; verify app and both extension signatures afterward.
- Keep licensed data and notices. No room recording, model download, permission change or private-transcript access during checks.
- The previously authorized installation allows updating this same app on the paired phone after checks. It does not authorize microphone/model QA or release publication.

## Task 1: Compact the generated payload

**Files:** `Dictus.xcodeproj/project.pbxproj`; new `scripts/slim-app-resources.py`; existing `DictusApp/Services/SoundFeedbackService.swift`. Read the existing limit from `DictusCore/Sources/DictusCore/FrequencyDictionary.swift`; do not change the runtime cap.

- [x] Add a development/build script with a bounded self-check. Check fabricated cutoff ties, malformed counts and unsafe output destinations, then validate the real source dictionaries with more than 10,000 entries. Preserve the failing-before/passing-after evidence.
- [x] Generate compact keyboard frequency JSON retaining all counts at or above the 10,000th highest count, including ties. Keep the full checked-in source data unchanged. Validate generated data against the source eligible set and preserve exact counts.
- [x] Generate native ALAC `.caf` from each original feedback WAV using `/usr/bin/afconvert`. Decode the result back to PCM and require matching channels, sample rate, sample width, frame count and every sample before removing any stale generated WAV copy. Keep source WAVs and non-audio notices unchanged.
- [x] Update the existing playback owner's URL lookup to prefer `.caf`, with the existing `.wav` lookup as fallback. Keep the catalog, volume, playback cache, event routing and persisted names unchanged.
- [x] Add app/keyboard build phases before signing with explicit source inputs/generated outputs. Make them the sole producers of their bundle resources so unchanged incremental builds re-sign correctly; no new runtime owner.
- [x] Enable normal Release postprocessing/non-global symbol stripping with dSYM generation retained outside the shipped payload. Preserve Debug behavior and keep build product paths stable.

## Task 2: Verify preservation and measure the result

**Files:** Existing Core/inference tests and native verification scripts; new `docs/qa/2026-10-12-app-slimming.md`.

- [x] Run the resource script's fabricated-data self-check and all four real frequency comparisons. Verify every retained source word/count and cutoff tie; unchanged ranking/source-data regressions remain required.
- [x] Validate all converted sounds against original PCM and check native `AVAudioPlayer` loading/duration without playing or recording. No recognition test is implied.
- [x] Measure native frequency load work on full and compact public dictionaries with optimized code, checking top-word/ranking behavior and reporting ties honestly.
- [x] Run relevant Debug/Release deterministic tests, build the optimized device/simulator targets as appropriate, verify signature/version/App Group parity, and compare source/resource hashes. Repeat an unchanged simulator build to reproduce and close the incremental-signing regression.
- [x] Record exact before/after app, main binary, keyboard, frequency and sound sizes. Report warnings and remaining device/model/UI gates without turning bundle-size improvements into inference-speed claims.
- [x] Update the previously authorized phone installation only after the signed result passes. Verify the new installation URL/version through native device inventory; preserve user app data by using the same bundle ID and no uninstall.

## Acceptance

The bundle is measurably smaller, the four complete n-gram/spellcheck datasets remain identical, all sound PCM samples and catalog names are preserved, and frequency resources retain all words eligible under the existing 10,000-word cap. The signed app and both extensions build and install using the existing identity. Actual physical feedback/latency and the unfinished native-core migration remain separate gates.
