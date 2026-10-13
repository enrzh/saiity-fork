# sAiity 1.0.0 (240): local candidate readiness

Prepared October 9, 2026 on the MacBook from HEAD `6605e9dd` plus the uncommitted changes in the [product plan](superpowers/plans/2026-10-09-product-quality-and-testflight.md). No commit, push, upload, release change or tester invitation was made. Build 240 has not been checked for uniqueness in App Store Connect.

## Changes in this candidate

- Distinct events at the same time survive deterministic cleanup, model prompts and fact guardrails. Segment merging preserves decimal points/commas, times, email addresses and URLs, including overlaps.
- Keyboard delivery is bound to the starting document. Controller replacement selects the new target before ready-result handling; unavailable or changed targets retain pending text. Recognition, translation, cleanup and error reporting reject canceled/stale sessions. Empty recognition ends as No speech detected.
- Space and snippets validate the live suffix before deleting. Valid dictionary words do not pollute learned vocabulary. Initial dictionary work runs on the existing prediction queue; mapping, teardown and readiness publication preserve the latest request. The accepted exact-word rule across explicitly enabled dictionaries stays in place.
- Whisper variants have independent receipts. Offline checks validate recorded file sizes, safe paths and compiled-model structure; old installs need valid configuration, graph and weights. Download cancellation is honored before task registration and is reported as cancellation.
- Setup supports Back, explicit continuation after microphone permission and Set up later with dictation Off. Model progress/cancellation stays inline under a persistent task owner. Voice options lead with languages and recommendations; detailed choices are disclosed. Reopening a result restores it.
- Privacy/support documentation describes downloads, optional server cleanup, clipboard actions, local history/replay and diagnostic consent accurately. Diagnostic Clear remains available for older records, removes current/legacy files, rejects queued old entries and surfaces failures. Internal probes stay out of Release diagnostics. App, keyboard and widget ship privacy manifests.

## Verified local artifacts

| Artifact | Location/state |
| --- | --- |
| Signed archive | `/Users/enrico/Documents/GitHub/sAiity-dictus/build/TestFlight-240/DictusApp.xcarchive` — Apple Development signed, the standard input to distribution export |
| App Store IPA | `/Users/enrico/Documents/GitHub/sAiity-dictus/build/TestFlight-240/export/DictusApp.ipa` — Apple Distribution signed, local export only |
| IPA SHA-256 | `fc2aceff86af1b07cfe1ec5d642f7ab4fa6c1145753e7092f9cae9982d69d9a9` |
| Export options | `docs/export-options-local-candidate.plist`: destination `export`; automatic build-number changes disabled |
| Detailed logs | `/tmp/saiity-product-review.H68Ksv` |

App `de.aiity.saiity.ios.beta`, keyboard `.keyboard` and widget `.widgets` all report `1.0.0 (240)`, use team `H8FW6W6K2D` and App Group `group.de.aiity.saiity.ios.beta`. The exported profiles are valid App Store profiles with debugging disabled. All three bundles pass strict signature verification; packaged privacy manifests and runtime license notices were inspected. App minimum OS is iOS 17. Qwen/local MLX hardware and foreground requirements remain independent.

The first archive attempt encountered a migrated wildcard profile without App Groups. Xcode automatic provisioning retrieved the correct beta profiles; the final archive/export succeeded. This does not prove upload acceptance or Apple privacy-review acceptance.

## Verification evidence

- Core: `swift test --jobs 4` — **1,915 tests, one existing skip, zero failures** (`core-final.log`).
- Debug simulator build and Release archive of app/keyboard/widget passed. Existing dependency pins and the FluidAudio compatibility step were retained.
- `test-model-downloads.swift`: production receipt validation and delegate cancellation before/during/after registration passed with tiny local fixtures and no network download.
- `test-keyboard-text-safety.swift`: production punctuation/Unicode replacement, known-word learning, paused obsolete mapping and interrupted readiness publication passed. The loader/publication races and other fidelity/integrity regressions failed before their fixes; RED/GREEN logs are retained.
- `test-multilingual-autocorrect.swift`: exact enabled-language protection, mixed-language fallback, scoped maps and rapid language changes passed.
- `test-key-grid-typing.swift`: typing, overlapping/canceled holds, repeats, continuous Space cursor motion, variants, Emoji blank-area/inset routing, field layouts, shared power controls and plate geometry passed. Haptic calls were observed; physical feel was not measured.
- `test-dictation-result-recovery.swift`: live insertion, original/result recovery, field handoff, retained pending delivery and repeated notification refusal passed.
- Production-view fixtures covered normal/maximum text and light/dark states. AXe 1.8.0 was installed for native app checks on the dedicated sAiity simulator. Physical-style touches verified the disclosed model choices, Streaming/Whisper, both Qwen options, independent Realtime, denied-microphone power recovery, setup Back/defer and cold-stage resume. Pending Qwen 1.7B/Realtime survived restart without a model download. Real app navigation titles render correctly; the standalone layer renderer has limitations for UIKit navigation/materials.
- Synthetic timing logs describe simulator code paths only. They are not phone typing latency, ASR accuracy, processing latency, thermal or battery measurements.

QA used `3ED8FD55-D525-45D1-9E1A-4A1354000FC0` (sAiity Product QA, iPhone 17 Pro, iOS 26.5). hAiity's simulator and the physical phone were not operated. Microphone access was denied; no room recording or voice-model download was started. SimSlim and ego-browser remain unavailable. The requested Sol implementation workers returned HTTP 503 before editing; main-agent work and review continued without Luna or substitute workers.

Native QA ended with normal text size, light appearance, Whisper selected, Realtime off and keyboard dictation Off. Microphone permission remains denied. The saved pending Streaming 1.7B choice was retained, and the deferred setup path landed in Speak without requiring a recording or model installation.

## Remaining gates

Before treating this as a fully verified product release, check real typing/haptics with the microphone on, cross-app/background delivery, field/settings and default-tone extension parity, denied Full Access, landscape feel, physical PiP and system Live Activity power/rendering. Qwen/local models still need consented or licensed-file inference, cancellation/foreground-loss, memory, multilingual accuracy and latency evaluation on supported hardware.

The published privacy page/support destination, App Store privacy answers and required-reason declarations need online review through ego-browser. This local document does not publish a website or change those answers. Confirm the next unused build number before any separately authorized upload; Apple acceptance, processing and tester availability are still unverified.

The 30-minute completion monitor remains active and quiet on unchanged state. It must not re-run passed checks or retry old provider/tooling failures without a source change or new evidence. No further upload is authorized by this preparation.
