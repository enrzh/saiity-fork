# Keyboard and app responsiveness checkpoint

## Implemented result

The new local development build is installed on the previously authorized paired iPhone Air as Syllivra 1.0.0 (242). Filtered device inventory matches its bundle installation URL to Apple's installer result. The package remains approximately 62.4 MiB allocated: 63,888 KiB for the app and 30,688 KiB for its keyboard, versus the preceding slim build's 63,840 KiB and 30,672 KiB.

The implementation is local and uncommitted on `cursor/keyboard-surface-fixes-a66e`, based on `b696d880`. All previous processing, slimming and unfinished native-core changes remain intact. No commit, push, upload, publication, release change or tester invitation occurred.

Native execution of the final request-race and UI/history probes remains pending because both permitted simulator slots are occupied by hAiity and Day. The current probes compile cleanly. Compilation does not establish their runtime assertions or rendered appearance. The dedicated sAiity simulator was shut down after observing more than two booted simulators; no other project's simulator was operated.

## Changes

- `FrequencyDictionary` groups retained words with an ASCII initial by their first UTF-8 byte. Prefix queries inspect that bucket instead of all 10,000 words. Non-ASCII initial characters keep the canonical Unicode matching path. Buckets preserve the original dictionary enumeration order and ranking uses the existing method.
- The three ordinary fallback words are ranked once after loading. Wider requests retain their existing ranking path. Invalid data, missing files and read failures reset the counts and derived state together; copies retain their independent values.
- `SuggestionState` checks cancellation before expensive partial-word and next-word stages. Every deferred clear checks the captured request token. The previous two abstention branches could clear a newer request after it had already been queued.
- Home observes the stored recent-history Data instead of decoding history on each dictation status transition. Appearance and foreground refreshes remain. Edits and restored originals use the same storage observation.
- The two older Home history rows have direct Copy and Share buttons, with 44-point frames and native accessibility labels. Full-text editing, existing copy feedback, semantic colors, system type and current hierarchy remain.

The native QA scripts now support `--compile-only` when the dedicated simulator cannot be booted within the device limit. Their compiler commands explicitly select the simulator SDK; this removes the earlier inherited macOS-sysroot warning. The prediction probe writes a temporary QA-preference snapshot so a separate process can restore those keys even after a native assertion aborts.

## Measured lookup work and trade-off

The final benchmark links the preserved pre-change and current implementations into one optimized native Mac executable. It alternates their order over nine iterations, consumes every returned word, checks rank parity, and times load, fallback and prefix lookup work separately. It uses the same compact public dictionaries and eleven ASCII/non-ASCII/missing prefixes. These are component measurements on the Mac, not iPhone typing or inference timings.

| Language | Dictionary load before / after | Prefix lookup before / after | Prefix time reduction | Index array slots |
| --- | ---: | ---: | ---: | ---: |
| German | 6.430 / 7.818 ms | 0.1644 / 0.0918 ms | 44.1% | 238,288 bytes |
| English | 5.462 / 5.775 ms | 0.1422 / 0.0890 ms | 37.4% | 220,288 bytes |
| Spanish | 8.106 / 8.577 ms | 0.1917 / 0.1009 ms | 47.3% | 241,792 bytes |
| French | 8.983 / 11.240 ms | 0.2535 / 0.1472 ms | 41.9% | 225,456 bytes |

Cached three-word fallback requests measured below 0.001 ms instead of 0.622–1.184 ms. They return the saved result instead of repeating the scan. The index arrays use approximately 0.21–0.23 MiB of String slots, plus bucket metadata; this is not a measured process-memory increase on the phone. The one-time dictionary-load cost increases by approximately 0.3–2.3 ms. The runtime cap remains 10,000 words and no source resource is changed.

The first Character-keyed index was rejected after it substantially increased dictionary-load cost. The shipped byte index keeps the inexpensive ASCII path and the existing Unicode behavior. Existing selection among cutoff ties remains nondeterministic; the tests verify tie priority within a loaded dictionary and do not claim identical independently loaded boundary members.

## Executed verification

- Final affected Core tests: 71 Debug tests and 71 Release tests, zero failures. Coverage includes Unicode/decomposed accents/emoji initials, case, tie order, limits, reloads, failures, value-copy isolation, swipe decoding, language safety, request gates, vocabulary completions, typing commits and recent-history policy.
- The original stale-request race was reproduced against a preserved pre-change simulator artifact: an older mixed-script abstention cleared a newer `hello` request. The failing run stops at that first assertion; the second branch and rapid-typing assertions still need the final native execution.
- Debug simulator build and signed Release device build passed. Strict signature verification passed separately for app, embedded keyboard and embedded widget on both configurations.
- Final app/keyboard/widget versions remain 1.0.0 (242), require iOS 17.0, and retain `group.de.aiity.saiity.ios.beta`. Main executable and dSYM UUID match: `F0A023E5-3908-3386-B49A-A7DCEC2C981B`.
- Final bundle checks preserve all compact frequency counts/cutoff ties, all eight n-gram/spellcheck files, every feedback sound name and the open-source notices. All original resource SHA-256 checks remain valid.
- Project plist syntax and diff whitespace checks passed.
- Apple's installer and filtered app inventory confirm the new same-bundle development update. No uninstall or app-data deletion occurred. No phone launch, physical interaction automation, microphone recording, private-transcript access, model download or permission change was performed.

The builds retain existing deprecation, actor-isolation and SDK switch warnings. The malformed-frequency and missing-resource tests intentionally emit diagnostics. This is not a warning-free project or a fresh distribution archive/export.

## Pending native checks

When a simulator slot becomes available, boot only `3ED8FD55-D525-45D1-9E1A-4A1354000FC0`, then run serially from the repository:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift scripts/test-multilingual-autocorrect.swift 3ED8FD55-D525-45D1-9E1A-4A1354000FC0 /tmp/saiity-app-improvement.dAZE5t/derived
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift scripts/render-product-results.swift 3ED8FD55-D525-45D1-9E1A-4A1354000FC0 /tmp/saiity-app-improvement.dAZE5t/derived
```

The prediction probe exercises current selected/spoken-language protections, both stale-abstention branches and rapid typing. The rendering probe uses the actual production storage declaration, change callback and reload method with an isolated fabricated-history suite. It checks append/edit/clear refreshes without decoding unchanged history for six fabricated stages, then renders the production result and older recent row at 320/402 points with normal and accessibility 3/5 text. Its edit destination and copy callback are inert fixtures; it does not test real sharing or clipboard delivery. Inspect the generated images before claiming layout validation.

Physical typing/haptics, sound onset, field/settings/Full Access parity, cross-app/background delivery, landscape feel, PiP/system Live Activity, real-model load/inference/cancellation/foreground-loss/memory, multilingual accuracy and end-to-end latency remain separate gates. Recognition evaluation needs licensed or expressly consented files. The first-party runtime migration remains unfinished.

## Evidence

`/tmp/saiity-responsiveness.KkEtOn` contains the preserved baseline keyboard artifact, paired benchmark source/binary/log, earlier rejected-index measurements, focused Core logs, the native race failure, clean probe compilation logs, Debug/Release build logs, final signature/resource checks and installation/inventory JSON. Render output will be under `/tmp/saiity-app-improvement.dAZE5t/derived/multilingual-result-renders` after the native probe is executed.
