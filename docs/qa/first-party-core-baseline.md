# First-party native core: implementation checkpoint

## Current module migration: October 13, 2026

The live package is now `SyllivraKernel`, with shared `SyllivraKernel` and app/harness-only `SyllivraInference` products. The `DictusCore` package/module is removed from the current app/keyboard/widget build graph and live tooling. Older sections below record historical paths/results; use the current module names for new work. This supersedes the earlier plan's instruction to retain `DictusCore`.

The migration preserves all prior processing, dictionary, keyboard, prompt and native-core work, including untracked fixtures/source and ignored build recovery material. App Group, bundle IDs, 1.0.0 (242), iOS 17.0, stored keys and model/language/style choices retain their identifiers. Licensed inherited shared behavior/data and notices remain; changing the package name does not make inherited code independently authored. The native BPE/artifact implementation and the new cached decoding algorithm are maintained here using Apple frameworks.

`NativeModelArtifacts.generate(using:inputTokens:maximumNewTokens:endTokenIDs:deadline:)` now implements the owned Qwen single-token export loop. It validates exact graph/model input/output/state contracts, prompt/EOS token ranges, output/context admission, fresh per-request KV state, incremental causal masking, finite logits, greedy tie order, EOS and output-cap rejection. Input/mask arrays are reused within a request. Cancellation/deadline checks run before work, between predictions and after SDK return; a noncooperative Core ML prediction remains non-preemptible until it returns. The existing caller retains serialization, residency and foreground policy. Stateful generation is guarded for iOS 18/macOS 15; the shared package remains iOS 17 compatible.

The harness exposes `native-generate` for explicitly supplied public token IDs and native exports; it calls the same loop. The owned untrained Qwen cache graph executes to EOS, and a second command rejects a run without EOS at its cap. This is numeric algorithm evidence, not trained text output, ASR quality, physical memory or speed parity. Complete production model exports are still absent: the pinned source directory has no `model.safetensors`. No model download or recording ran.

Executed package checks: Debug and Release each pass 1,962 shared-kernel tests plus 41 inference tests, 2,003 total, one existing ASR capture skip and zero failures. The package has zero external package dependencies. Isolation checks require the shared kernel for all three consumers, native inference for the app only, and reject the old product/path. Exact-tokenizer and numerical-cache tests still pass. Live imports/products/scripts/lint/CI paths no longer use the old module names. Current contributor/language-tool docs were migrated; dated QA/planning evidence remains historical.

The production app still uses WhisperKit, FluidAudio, MLX/Qwen and DeviceKit where consumers have not yet passed their native replacement gates. The shared-package cutover and numeric native decoder do not close the earlier plan's complete third-party-runtime removal gate. Removing those implementations before compatible trained exports, raw-recognition/text parity and physical cancellation/memory/latency checks would break current model choices.

Fresh simulator and signed Release device builds pass from separate, newly created DerivedData directories. Strict signatures pass separately for the app, embedded keyboard and widget. Both builds retain versions, iOS 17.0, configured/signed App Group as applicable, exact compact frequency counts/cutoff ties, every original n-gram/spellcheck byte, all 29 feedback sound names and byte-identical notices. All 41 original resource source hashes still match. Build logs, bundled filenames and main executable symbol inspection contain no legacy `DictusCore`/`DictusInference` module. Native synthetic graphs/tokenizer test assets are absent from the app bundle. Main executable/dSYM UUID match: `39B27147-CEB5-3FCE-BD8E-A99FD972BA54`.

The same-bundle development update is installed on the authorized iPhone Air. Apple's installer reports success and filtered inventory matches its installation URL, bundle ID and 1.0.0 (242). No uninstall, user-data deletion, app launch or physical interaction/microphone QA occurred. Allocated bundle size is 63,908 KiB (approximately 62.4 MiB), including a 30,692 KiB keyboard: about 20 KiB/4 KiB above the preceding package, respectively.

The migrated native translation fixture and offline downloader receipt/cancellation checks pass using the new kernel library. Multilingual prediction/request and product/history probes compile for the fresh simulator artifacts; they were not executed or visually inspected because both permitted simulator slots were occupied by other projects. No simulator was operated. State-dependent native tests also retain explicit older-OS skips, and their final Debug/Release focused runs pass. Existing SDK/deprecation/actor warnings remain; SwiftLint is unavailable, so no lint pass is claimed.

The shared-package cutover is complete. Full first-party speech/text-backend replacement remains incomplete for the trained-model/physical parity reasons above. The current task added no compatibility `DictusCore` shim, new runtime package dependency or duplicate runtime owner. Historical archives, source provenance/notices and Git recovery state remain intact; the recovery heartbeat was not changed.

Evidence directory: `/tmp/saiity-kernel.2JRaLK`, including the preserved diff/source archive, failing package-graph test, passing isolation/decoder tests, full Debug/Release logs, package inventory, native generation/inspection/truncation logs, fresh app builds, separate signature/resource checks and installation/inventory JSON. All changes remain local and uncommitted; no push, upload, publication, permission change, private transcript or microphone access occurred.

Current commands, from the repository root:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path SyllivraKernel --jobs 2
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path SyllivraKernel -c release --jobs 2
SyllivraKernel/.build/out/Products/Release/polish-harness native-inspect \
  SyllivraKernel/Tests/SyllivraInferenceTests/Fixtures/qwen-cache \
  --model native-qwen-cache-probe --revision owned-qwen-cache-v1 --load
SyllivraKernel/.build/out/Products/Release/polish-harness native-generate \
  SyllivraKernel/Tests/SyllivraInferenceTests/Fixtures/qwen-cache \
  --model native-qwen-cache-probe --tokens /tmp/saiity-kernel.2JRaLK/public-probe-tokens.json \
  --eos 5 --max-tokens 4
```

The numeric token file is the public untrained golden input `[3, 7, 11, 5]`. Its expected completion is EOS with no output tokens. Existing real-model conversion/recognition/physical QA requirements remain below.

---

Implementation started October 12, 2026 against [the migration plan](../superpowers/plans/2026-10-12-first-party-dictus-core.md). Native artifact validation/loading, the owned Qwen tokenizer, and a cached Qwen conversion recipe with an executed untrained probe are implemented. The runtime migration is not complete.

## Source and scope

Working checkout: `/Users/enrico/Documents/GitHub/sAiity-dictus`, branch `cursor/keyboard-surface-fixes-a66e`, HEAD `b696d880`, build 242. The preceding uncommitted processing-speed pass and all Git recovery metadata were preserved. No commit, upload, release change, phone operation, model download, permission change or room recording occurred.

Implementation stays in the current feature checkout to include the accepted speed changes. No additional worker was spawned: the permitted `sub2api/gpt-6.1-sol` override is not advertised by the available worker tool. No alternate model was substituted. The existing recovery heartbeat was already paused and its status was preserved.

## Implemented

- A first-party `DictusInference` product/target inside the existing Core package. Only the app and off-device harness link it. A source/build-graph regression checks that the keyboard and widget do not link the new product.
- `NativeModelArtifacts` decodes schema version 1 and verifies model/revision bindings, manifest size, required files, SHA-256 values, relative paths, symlinks, graph membership, tensor names/types/shapes, integer/byte-size overflow, iOS state requirements, declared context axes, tokenizer vocabulary/EOS metadata and output vocabulary dimensions.
- Native graph loading supports `.mlmodel`, `.mlpackage` and `.mlmodelc`, compiles source graphs with Apple's SDK, rechecks integrity on load and compares the actual model's inputs/outputs/states with the declared contract. Cancellation is checked between validation, compilation and loading. The caller owns subsequent prediction/residency and must retain the existing cancellation/execution owner.
- `polish-harness native-inspect` verifies an explicitly supplied directory and expected model ID/revision. `--load` also compiles/loads graphs and checks real Core ML tensor descriptions, using CPU for this inspection. This command runs independently of Apple Intelligence and records no audio.
- An owned analytic Core ML fixture exercises actual compilation and prediction. Its six weights and three biases implement `logits = [[2,0],[0,3],[-1,-1]] * input + [0.5,-1,2]`. For `[1,2]`, native Core ML returns `[2.5,5,-1]` within the test tolerance. It contains no trained model, private text or audio and is bundled only with tests.

The fixture generator uses `coremltools==8.3.0` in an isolated virtual environment at `/tmp/saiity-first-party-core.2aRwH5/coreml-fixture-env`. This development tool and its Python dependencies are not in SwiftPM products or app/extension targets. It makes no network/model request; the isolated tool installation downloaded packages only.

## Verification

- First-party foundation: 24 tests cover positive loading/prediction, invalid/missing/tampered artifacts, unsafe paths, binding/schema failures, tensor/cache/vocabulary metadata, cancellation and app-only target ownership.
- Focused native checks plus applicable existing native-named Core tests: 51 tests, zero failures.
- Full Debug and Release suites each passed: 1,947 Core tests with one existing ASR capture skip, plus 24 inference tests; zero failures. SwiftPM runs the two XCTest targets separately (1,971 tests combined per configuration).
- The native CLI loaded the owned graph and reported verified integrity and SDK tensor contracts.
- App/keyboard/widget Debug simulator build passed. Strict signature verification passed for the app and both extensions. Xcode project syntax and diff whitespace checks passed. No simulator or phone installation was performed.
- The CLI rejected a different expected model ID with exit 1 before graph loading. The timing parser's synthetic self-check passed.
- SwiftLint was not available in this environment; no passing SwiftLint result is claimed.

Evidence directory: `/tmp/saiity-first-party-core.2aRwH5`. Relevant logs: `artifacts-red.log`, `artifacts-green.log`, `tokenizer-metadata-red.log`, `native-loading.log`, `native-foundation-green.log`, `native-extended.log`, `native-inspect.log`, `native-inspect-rejected.log`, `core-debug-final.log`, `core-release-final.log`, `app-build.log`. The vocabulary/EOS rejection tests failed before their stricter validation was added. Initial package/API absence is recorded separately from behavioral regressions. Build verification reused the pinned packages and already-applied FluidAudio compatibility setting; their existing consumers still require those dependencies.

Run the implemented native inspection from the repository root:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift run --package-path DictusCore \
  --scratch-path /tmp/saiity-first-party-core.2aRwH5/core polish-harness native-inspect \
  DictusCore/Tests/DictusInferenceTests/Fixtures/linear \
  --model native-linear-probe --revision owned-linear-v1 --load
```

Expected: verified artifact integrity and a loaded Core ML graph whose SDK tensor descriptions match the manifest. This command loads the graph; the native XCTest prediction case separately checks `[2.5,5,-1]`.

The validator currently handles fixed-shape multiarrays. Flexible shape bounds, non-array features and additional tokenizer/architecture families require a verified export contract before support is added. Manifest hash/tensor validation does not establish semantic quality, license rights or authenticity of an export's self-declared model/revision.

## Dependency baseline

The existing runtime packages remain required by current backends. Pinned source-cache inventory at this checkpoint:

| Package | Version |
| --- | --- |
| WhisperKit | 0.18.0 |
| FluidAudio | 0.12.4 |
| MLX Swift | 0.30.6 |
| MLX Swift LM | 2.30.6 |
| Swift Transformers | 1.1.9 |
| DeviceKit | 5.8.0 |
| Swift Argument Parser | 1.8.2 |
| Swift ASN.1 | 1.7.1 |
| Swift Collections | 1.6.0 |
| Swift Crypto | 4.5.1 |
| Swift Jinja | 2.4.2 |
| Swift Numerics | 1.1.1 |
| yyjson | 0.12.0 |

`DictusCore` and `QwenASRRuntime` are local packages; the latter remains third-party-derived runtime source. No package was removed prematurely. Retained keyboard helper/source/data provenance remains a separate migration task.

## Open gates and next inputs

No complete Qwen or Whisper Core ML export was found in this project or the existing pinned dependency assets. Real-model graph conversion, reference logits/KV behavior and native cleanup/recognition parity remain unverified. The analytic fixture cannot close these gates. Qwen tokenizer parity for the recorded cases is now verified as described below; Whisper and Gemma tokenizer contracts remain open.

Chrome Use was unavailable during the foundation pass. It worked during this continuation: the public Qwen 2.5 0.5B source, pinned revision and Apache-2.0 license text were read through Chrome. This closes that source lookup for this tokenizer artifact; other model/export licensing and provenance remain separate checks.

The next real-model milestone needs the revision-pinned Qwen 2.5 0.5B weights or complete Core ML export, its conversion provenance and reference logits/cache cases. The public tokenizer and its license/golden fixtures are available locally. A Whisper Tiny export requires the corresponding encoder/decoder/mel/tokenizer contracts. Local native inspection can then bind the expected identity, validate artifacts and check SDK tensor descriptions before any app routing changes.

The pinned weights page reports `model.safetensors`, 988 MB, SHA-256 `fdf756fa7fcbe7404d5c60e26bff1a0c8b8aa1f72ced49e7dd0210fe288fb7fe`. The previous continuation found Chrome's automatic multiple-download setting blocking the transfer and requested direction. No permission was changed or alternative website/download route used during that pass.

Latest state supersedes that permission blocker: the user said to continue after
the permission request. Chrome then showed multiple downloads already allowed,
so no permission toggle was needed. The pinned `config.json` downloaded through
Chrome. The weights request redirected to `us.aws.cdn.hf.co`, where Chrome showed
`ERR_BLOCKED_BY_CLIENT`; no weight file or partial weight file was found. AdBlock
reported zero blocked requests on that page, so the specific blocking component
has not been established. No extension/filter setting was changed and no
alternate browser or download route was used.

Actual phone latency, cold/warm preparation, memory, foreground/background execution, semantic review and physical keyboard/delivery behavior remain separate gates. No native-processing speed claim follows from this foundation.

## Qwen tokenizer continuation: October 12, 2026

The source checkpoint and accepted performance changes remain local and uncommitted. No additional worker, downloaded model-weight artifact, phone operation, recording, permission change, upload or release action occurred. The recovery heartbeat remains paused. Builds, tests and the native timing probe ran serially.

Implemented `DictusInference/BytePairTokenizer.swift` with Foundation and Swift alone. It validates the observed Qwen 2.5 BPE configuration, applies NFC normalization and the exact upstream pretokenization pattern, matches all added tokens, and performs ranked byte-pair merges. Unsupported normalization, splitting, padding, truncation, decoding and BPE options fail explicitly. Vocabulary IDs, the complete byte alphabet, merge dependencies and added-token identity/matching are checked before encoding.

Encoding checks cancellation before and between splits/merges; cancelled work returns no partial token list. Decoding rejects unknown IDs and concatenates raw bytes before UTF-8 decoding. `tokenBytes(for:)` exposes incomplete UTF-8 pieces without adding replacement characters, so the future token decoder can retain bytes across chunks. Generation/stream integration is still pending.

The test-only fixture uses the unmodified public tokenizer from `Qwen/Qwen2.5-0.5B-Instruct`, revision `7ae557604adf67be50417f59c2c2f167def9a775`. Tokenizer SHA-256 is `c0382117ea329cdf097041132f6d735924b697924d6f6fc3945713e96ce87539`. Its directory includes the upstream Apache-2.0 license and Alibaba Cloud attribution; see [fixture provenance](../../DictusCore/Tests/DictusInferenceTests/Fixtures/qwen2.5/README.md).

`scripts/generate-native-tokenizer-fixtures.py` freezes 78 exact-ID cases using the independent Hugging Face `tokenizers==0.21.4` implementation. That development dependency was installed only in the existing isolated Python environment. The generator makes no downloads or inference calls and reads no user transcripts. Golden SHA-256 is `9ff7fcdfacb8ae29141d4f9eae11517b69866d6106e69229865ff475f1ad0401`. No Python runtime or third-party tokenizer implementation enters the app or package products.

Validation executed:

- The tokenizer tests failed against empty API stubs before implementation. A later merge-dependency regression failed before validation was tightened; both red runs are recorded.
- All 34 inference tests passed in Debug and Release, with zero failures. These comprise the existing 24 foundation tests and 10 tokenizer regressions, including all 78 exact-ID cases. The unchanged 1,947 Core tests retain their preceding evidence; they were not rerun in this continuation.
- App/keyboard/widget Debug simulator build passed with the iOS 17 deployment target. Strict signature checks passed for the app and both extensions. The public tokenizer/golden test fixtures were absent from the built app bundle. No simulator installation or UI interaction was performed.
- Diff whitespace checks passed. No SwiftLint result is claimed.

An optimized native timing probe on `Mac16,12`, arm64, macOS 27.0.1 measured tokenizer work only. AC was attached; battery was 90% when recorded. A 1,620-byte public multilingual input encoded to 390 tokens in approximately 0.36 ms after loading. An 8,192-byte repeated-word input encoded to 1,024 tokens in approximately 180 ms with the initial per-pair scan, then 0.18 ms after equal-ranked pairs were merged together. The complete tokenizer loaded in approximately 0.29 seconds. These are single Mac observations, not p50/p95 measurements, inference benchmarks or iPhone speed claims. The varied-long-token scan remains a documented potential profiling limit.

Evidence: `/tmp/saiity-native-tokenizer.JE2SYO`, including `reference-tools.log`, `tokenizer-red.log`, `tokenizer-green.log`, `merge-order-red.log`, `native-debug-final.log`, `native-release-final.log`, `tokenizer-speed.log`, `tokenizer-speed-final.log` and `app-build.log`. The standalone timing source is `main.swift` in that directory and uses the production tokenizer file directly.

Reproduce the focused checks without a download or recording:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test \
  --package-path DictusCore --scratch-path /tmp/saiity-first-party-core.2aRwH5/core \
  --filter DictusInferenceTests
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test \
  --package-path DictusCore -c release --scratch-path /tmp/saiity-first-party-core.2aRwH5/core \
  --filter DictusInferenceTests
```

The app still uses its existing model backends. A tokenizer with correct sample IDs does not establish Qwen graph, KV-state, cleanup quality, phone latency or full runtime ownership parity. Those gates remain open.

## Cached graph conversion continuation: October 12, 2026

`scripts/convert-native-qwen.py` provides a development-only, offline export
recipe. It implements the single-token RoPE/grouped-query attention step with
one key/value state per layer and the model's existing norm/MLP/projection
weights. Core ML executes the exported graph; Torch/Transformers/coremltools
remain outside production targets. The script never downloads model files,
disallows remote code, verifies the pinned source hashes before loading, rejects
existing output directories, and writes the runtime manifest only after its
reference/native checks pass.

The recipe targets Qwen 2.5 0.5B with context 2,048, FP32 weights/activations and
FP16 KV state, using the iOS 18/macOS 15 state API. This is an initial numerical
conversion recipe, not the final memory/speed configuration or a catalog change.
The app retains its iOS 17 deployment and existing backends.

Its self-check constructs an untrained two-layer fixture with seed `20261012`,
vocabulary 32, hidden size 32, four query heads, two KV heads and context 16.
Cached logits match the full-prefix reference; Core ML matches the cached
reference and returns the same greedy token on four numeric inputs. Fresh Core
ML state reproduces the first prediction. FP16-cache comparison and conversion
comparison have separate tolerances, chosen before the checks. The Swift native
loading test independently compares all logits and fresh-state output using the
same small graph. [Fixture scope](../../DictusCore/Tests/DictusInferenceTests/Fixtures/qwen-cache/README.md)
records these limits. No pretrained language quality, EOS/output-cap behavior,
full-context processing, cancellation during decoding or phone behavior follows
from this test.

Two implementation failures were diagnosed and corrected. The converter rejects
whole-buffer `copy_` without a matching slice, so cache updates use slice
assignment. The Swift graph-member validator mixed `/tmp` and `/private/tmp`
spellings returned by macOS enumeration; paths now use the same normalization
as the root, with the containment/symlink/hash checks retained. The actual
stateful `.mlpackage` failed before the path fix and loaded/predicted afterward.

Executed evidence:

- The empty step failed the reference-logit check; incomplete-source validation
  also failed before implementation. Tampered and missing source inputs now fail
  before model loading.
- The final synthetic export, native Core ML predictions and fresh-state checks
  passed. A ready manifest hashes the graph, conversion record and golden data.
- All 35 inference tests passed in Debug and Release, with zero failures. The
  existing Core-suite evidence remains historical and was not rerun here.
- The native inspection CLI compiled/loaded the cache probe and verified actual
  SDK input/output/state contracts. Diff whitespace and project syntax passed.
- App/keyboard/widget Debug simulator build passed after the path fix. Strict
  signatures passed for the app and both extensions. Cache probe/conversion
  resources were absent from the app bundle. No installation was performed.

Evidence directory: `/tmp/saiity-native-qwen.sxedhK`. Logs include
`conversion-tools.log`, `cache-red.log`, `cache-green.log`, `cache-slice.log`,
`source-red.log`, `source-green.log`, `cache-final.log`, `native-cache-red.log`,
`native-cache-green.log`, `native-cache-path-green.log`, `native-debug.log`,
`native-release.log`, `native-inspect.log`, `app-build.log` and `missing-weights.log`.

The isolated environment now contains `coremltools==8.3.0`, `torch==2.5.1`,
`transformers==4.51.3`, `safetensors==0.5.3` and `tokenizers==0.21.4`. The tools
warn about Python's LibreSSL build, Torch 2.5.1 being newer than coremltools'
tested 2.5.0, and state-variable re-registration. The executed numerical tests
passed; these warnings do not establish full-model compatibility. No Python
package or generated probe is part of the production targets.

The pinned configuration hash is
`18e18afcaccafade98daf13a54092927904649e1dd4eba8299ab717d5d94ff45`. Config,
tokenizer and a copy of the recorded upstream license are staged in
`/tmp/saiity-native-qwen.sxedhK/source`. The real command currently exits 1 with
`Required local checkpoint file is missing or unsafe: model.safetensors` and
creates no model export. Once the exact file is supplied locally, the next
authorized development step is:

```sh
HF_HUB_OFFLINE=1 TRANSFORMERS_OFFLINE=1 \
  /tmp/saiity-first-party-core.2aRwH5/coreml-fixture-env/bin/python \
  scripts/convert-native-qwen.py --source /tmp/saiity-native-qwen.sxedhK/source \
  --output /tmp/saiity-native-qwen.sxedhK/qwen-export
```

This command still needs actual pretrained execution and review. The separate
Whisper, Gemma, Qwen ASR/VAD, Parakeet, dependency-removal, app-integration,
accuracy, physical-device and release gates remain open. All work remains local
and uncommitted; no phone operation, audio capture, upload or release change was
performed.

## Authorized local phone installation: October 12, 2026

The user explicitly requested “send the app to my phone.” An optimized Release
development build of the current dirty checkout was built and installed on the
paired iPhone Air running iOS 27.2. The app, keyboard and widget remain version
1.0.0, build 242. This is a local development update; no TestFlight upload,
commit, push or release change occurred.

The device build used isolated DerivedData and the existing pinned package
checkouts. Its initial signing attempt required a development team for package
resource bundles; supplying the existing project team as a build argument fixed
that failure without editing project settings. Strict signatures passed for the
app and both extensions. The signed App Group is
`group.de.aiity.saiity.ios.beta`. Relevant source hashes matched before and after
the build.

Apple's device installer returned success. A subsequent filtered device app
inventory confirmed Syllivra, `de.aiity.saiity.ios.beta`, 1.0.0 (242), at the new
bundle installation URL returned by the installer. The update used the existing
bundle ID; no uninstall or user-data deletion was performed. Artifact and
evidence directory: `/tmp/saiity-phone-install.mD5pGL`, including
`app-build-signed.log`, `install.json`, `installed-before.json`,
`installed-after.json`, source hashes and the signed Release app in
`derived/Build/Products/Release-iphoneos/DictusApp.app`.

The phone UI helper was unavailable, so transfer and installed-version checks
used Apple's native device tools. No app launch, UI automation, room recording,
permission change on the phone or model download was performed. Installation
does not close the physical typing, haptic, microphone, cross-app delivery or
real-model quality/performance gates. The app still uses its existing model
backends; the native runtime migration remains in progress.
