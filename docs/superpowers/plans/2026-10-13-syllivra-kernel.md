# Syllivra Kernel Migration Implementation Plan

**Goal:** Remove the `DictusCore` package/module from the live app, keyboard, widgets, tooling and CI; host the maintained shared kernel and owned native inference under Syllivra names.

**Architecture:** `SyllivraKernel` is the lightweight shared product. `SyllivraInference` is the app/harness-only native runtime using Core ML and the owned tokenizer. Preserve maintained shared behavior and licensed source/data instead of reimplementing proven algorithms. Add a concrete cached-token decoding loop to the existing native artifact owner; no additional Manager/Service/Factory layer.

The user's October 13 instruction supersedes the earlier plan's requirement to keep `DictusCore`. Removing that package identity is a shared-kernel cutover. Removing WhisperKit/FluidAudio/MLX/Qwen's vendor runtime is still a separate inference migration: complete compatible trained exports and real-model parity remain required. A copied or renamed inherited implementation is not newly authored source. Preserve license notices and provenance.

## Constraints

- Preserve every current dirty/untracked change, source/data hash, Git recovery file, model artifact, historical archive and QA checkpoint. Stay on `cursor/keyboard-surface-fixes-a66e`, baseline `b696d880`.
- Retain 1.0.0 (242), iOS 17.0, bundle IDs, App Group, persisted keys, model/style/language choices, result recovery, text/fact guards and generation/cancellation identity.
- Native stateful decoding is guarded for iOS 18/macOS 15. The shared kernel never imports the native inference product.
- No microphone recording, private transcript access, model download or permission change. Synthetic licensed numeric fixtures establish algorithm behavior only.
- Main runs tests/builds/inference serially. No duplicate worker, release mutation, commit, push, upload or publication. Existing development phone-update authorization persists; phone interaction QA remains separate.

## Task 1: Remove the legacy shared package

- [x] Add/run the failing graph test requiring a local `SyllivraKernel` dependency in all three consumers and rejecting the legacy package path/product.
- [x] Save the current diff and an archive of the package source/fixtures. Move the existing package and source/test target directories to `SyllivraKernel`/`SyllivraInference` without losing untracked files or ignored recovery output.
- [x] Mechanically migrate imports, package/target/product names, Xcode references, CI/cache/lint paths, native QA scripts, language tooling and current contributor docs. Keep historical dated QA evidence and persisted identifiers unchanged.
- [x] Run package isolation/behavior suites and audit live source/build paths for legacy imports/products. The kernel manifest must contain no external package dependencies.

## Task 2: Implement owned cached-token decoding

- [x] Add failing real-Core-ML fixture checks for fresh-state prefill, greedy EOS, output exhaustion, context/ID admission, expired deadlines and cancellation.
- [x] Add `NativeModelArtifacts.generate(using:inputTokens:maximumNewTokens:endTokenIDs:deadline:)` using reusable input/mask arrays, one per-request state, exact graph/tensor contract validation and finite logits. No completion is returned after cap exhaustion or cancellation.
- [x] Expose `native-generate` in the existing harness for explicitly supplied numeric token files/approved native exports. Use the same kernel loop; no duplicate decoder or implicit model download.
- [x] Validate cached numerical behavior using the owned untrained fixture. Keep trained-model, tokenizer-family, physical-memory/latency, all speech backends and dependency-removal gates open where their inputs are absent.

## Task 3: Verify and hand off

- [x] Run final Debug/Release kernel/inference suites and the native-generation/inspection commands. Record all skips and fixture limits.
- [x] Build app/keyboard/widget serially with the migrated product names and existing pinned packages. Verify strict signatures, versions/App Group, source and bundled resources, native product isolation and absence of linked `DictusCore`.
- [x] Prepare the signed same-bundle development phone update, install and match filtered inventory to the installer URL when connected. Preserve all user data.
- [x] Record current architecture, provenance, exact checks and the remaining native-model inputs in `docs/qa/first-party-core-baseline.md`. Keep all changes local and uncommitted.

## Verified result

`DictusCore` is removed from the live package/import/product graph. The app, keyboard and widgets now consume `SyllivraKernel`; only the app/harness link `SyllivraInference`. The owned cached decoder executes the existing synthetic Core ML fixture with EOS/truncation/cancellation/context checks. Debug and Release each pass 2,003 tests, with one existing skip and zero failures. Fresh signed builds and the same-bundle development phone update pass; the package remains approximately 62.4 MiB. See [the current checkpoint](../../qa/first-party-core-baseline.md).

This completes the shared-kernel migration and native decoding primitive. The earlier complete-model migration is still blocked on compatible trained exports, tokenizer contracts for other families, reference outputs and authorized physical quality/memory/latency evidence. No copied/inherited shared code is claimed as independently authored, and the still-needed WhisperKit/FluidAudio/MLX/Qwen/DeviceKit consumers are disclosed rather than removed before replacement.
