# Syllivra processing speed and cleanup

October 12, 2026. Implemented locally on `cursor/keyboard-surface-fixes-a66e`, starting from clean HEAD `b696d880` (build 242). The user's request covers project cleanup and faster transcription/processing. This pass makes no commit, push, release upload or phone installation.

## Changes

- Region-aware cleanup combines adjacent, independently revalidated regions of the same language into one model call. Each candidate must fit the selected engine's existing context estimate. Language changes, uncertain fragments, script changes and both sides of an overlap keep separate calls. The shared deadline, sequential inference ownership, cancellation, fact/structure/language guards and deterministic fallback remain in effect. Counts still describe original regions. A rejected combined call returns the whole batch's floor without retrying its individual regions.
- `SpeechLanguageEvidence` retains the same-script language-switch result it already computes. `PolishPostpass` reuses that result instead of scanning all candidate boundaries a second time. Language thresholds and boundary candidates are unchanged. The existing language probe, script set and letter count are also reused during source validation.
- Whisper transcription reuses the audio-quality result's gain instead of analyzing the same recording twice. Regional gain and low-confidence decode retry behavior are unchanged.
- Removed the unused direct-Whisper compatibility loading/fallback path from `TranscriptionService` and its duplicate injection. `DictationCoordinator` already installs a prepared `SpeechModelProtocol` engine for every transcription; those engines retain load, release and decoding ownership.
- Corrected a dictionary-log test that expected Debug-only word-bearing events in Release. Debug still verifies those opt-in diagnostics; Release verifies counts without words even when the developer toggle is set. Production logging was not changed.

## Measurements

Optimized native macOS 27.0.1 build, same machine and fabricated text, nine timed iterations after one warm-up for each deterministic operation. Each executable statically links its corresponding Core implementation. These are local component measurements, not iPhone inference or Stop-to-insertion results.

| Deterministic cleanup input | Before median | After median | Reduction |
| --- | ---: | ---: | ---: |
| 117 characters | 46.852 ms | 23.156 ms | 50.6% |
| 936 characters | 130.818 ms | 66.002 ms | 49.5% |
| 2,808 characters | 150.355 ms | 77.166 ms | 48.7% |

The same three English speech regions used three engine calls before and one after. With an explicitly simulated fixed 200 ms engine cost, three trials gave a median of 758.831 ms before and 299.715 ms after. All original regions and text were retained. This demonstrates reduced per-call overhead; a real model's generation cost depends on the combined output length and can differ.

For a synthetic 60-second audio buffer, audio quality plus a duplicate gain scan took 2.028 ms median. Reusing the quality result took 1.052 ms. That saves one preparation scan; it is not a twofold ASR speed claim. Audio was generated mathematically; no microphone, room recording or private transcript was used.

Apple Foundation Models returned `unavailable(...modelNotReady)`. No settings or model downloads were changed, and no native model speed or semantic-quality claim follows from the simulated engine.

## Verification

- Release Core suite: 1,947 tests, one existing ASR capture skip, zero failures.
- Debug Core suite: 1,947 tests, the same existing skip, zero failures.
- Regression coverage includes call consolidation, language switches, uncertain fragments, both sides of overlap boundaries, engine context limits, rejected amounts, cancellation and retained language-switch evidence. The batching and overlap regressions failed before their fixes; existing multilingual/fact/structure/vocabulary tests remain active.
- App/keyboard/widget Debug simulator build: passed. Strict signature verification passed for the app and both extensions; all three carry build number 242. No simulator or phone installation was performed.
- Diff whitespace check: passed.

Evidence and benchmark source: `/tmp/saiity-processing-speed.NbIEtX`. Logs include `regions-red.log`, `regions-green.log`, `evidence-red.log`, `evidence-green.log`, `overlap-red.log`, `core-release-final.log`, `core-debug-final.log`, `baseline-final.log`, `after-final.log`, `baseline-apple.log` and `app-build.log`. Final benchmarks run against the completed source after the overlap fix. Existing warnings include unused variables and SDK deprecations. A malformed-frequency fixture intentionally emits a decode error during the successful Core suite.

The app build reuses `/tmp/saiity-app-improvement.dAZE5t/derived` and the existing pinned packages under `/tmp/saiity-mobile-language.nxZiwA/derived/SourcePackages`; FluidAudio already has the required Swift 5 compatibility setting. Builds, tests and inference checks ran serially.

## Recoverable cleanup

Moved the ignored, untracked generated Core build output from `DictusCore/.build/out` to `/Users/enrico/.Trash/saiity-dictus-core-build-out-2026-10-12`. It measured 260,636 KiB, approximately 255 MiB. This removes generated material from the checkout; disk space remains occupied until Trash is emptied. SwiftPM can rebuild it. The old output can also be moved back if its original path has not been regenerated.

The signed `build/TestFlight-240` archive/export, model artifacts, transcript/history data, prior QA evidence, tracked planning reports and all Git/recovery metadata were preserved.

## Remaining limits

Actual iPhone ASR/processing latency, cold/warm model loads, memory and foreground/background behavior remain unmeasured. Native-language meaning review and licensed or expressly consented recognition recordings remain necessary for semantic accuracy evidence. A larger batch can fail a real tokenizer check or a guardrail and fall back as a whole. The current edits are local and are not evidence about Apple processing, tester availability or an installed phone build.
