# sAiity Settings and Custom Models Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove visible legacy settings, limit selectable keyboard languages to English and German, and let users register validated custom ASR or cleanup model sources without confusing them with built-in models.

**Architecture:** Preserve legacy enum cases and persisted identifiers for migration, but expose only English/German in `allCases` and settings. Add one small Codable custom-model record in DictusCore, persisted in the App Group, with source-kind validation and role-specific lists. Extend the existing model page with a native add form. Registered Ollama cleanup models use the app's OpenAI-compatible local HTTP path; custom ASR entries remain configuration-only until a format-specific runtime is available and are never silently selectable as built-in WhisperKit/Parakeet models.

**Tech Stack:** Swift 6, SwiftUI, Codable, URLSession, App Group UserDefaults, existing DictusCore tests.

## Global Constraints

- Preserve unrelated dirty changes and do not delete or reset the worktree.
- Only English and German are selectable user languages; legacy French/Spanish values must degrade safely to English.
- ASR and cleanup model entries are separate roles and cannot be mixed.
- Validate Hugging Face/NVIDIA URLs and model metadata before saving; accept Ollama only for cleanup models.
- Never claim arbitrary custom ASR models are runnable by the built-in WhisperKit/Parakeet pipeline.
- Remove the support email action and link support to `https://github.com/enrzh`.
- Add Dictus attribution to the in-app licenses page.

### Task 1: Language and legacy settings cleanup

**Files:**
- Modify: `DictusCore/Sources/DictusCore/SupportedLanguage.swift`
- Modify: `DictusCore/Sources/DictusCore/TranscriptionLanguage.swift`
- Modify: `DictusApp/Views/SettingsView.swift`
- Modify: `DictusApp/Views/LicensesView.swift`
- Test: `DictusCore/Tests/DictusCoreTests/SupportedLanguageActivationTests.swift`
- Test: `DictusCore/Tests/DictusCoreTests/KeyboardLanguagePreferenceTests.swift`

- [x] Make `SupportedLanguage.allCases` return only `.english` and `.german`; keep legacy cases parseable and map system French/Spanish to English.
- [x] Make stored legacy French/Spanish transcription selections resolve to `.autoDetect` or English without appearing in settings.
- [x] Remove the Sounds/settings row that belongs to the forked keyboard configuration while retaining model and dictation controls.
- [x] Replace the mailto support row with a GitHub profile link and add a Dictus MIT attribution block.
- [x] Add regression tests for selectable-language scope and legacy-value fallback, then run them.

### Task 2: Custom model records and validation

**Files:**
- Create: `DictusCore/Sources/DictusCore/CustomModel.swift`
- Modify: `DictusCore/Sources/DictusCore/SharedKeys.swift`
- Modify: `DictusApp/Models/ModelManager.swift`
- Test: `DictusCore/Tests/DictusCoreTests/CustomModelTests.swift`

- [x] Define `CustomModelRole` (`asr`, `cleanup`), `CustomModelSource` (`huggingFace`, `nvidia`, `ollama`), and a Codable `CustomModel` containing id, display name, repository URL, role, and optional model name.
- [x] Validate HTTPS Hugging Face URLs, NVIDIA model URLs, and Ollama URLs; reject non-URLs, unsupported hosts, and Ollama ASR entries.
- [x] Persist custom records as JSON under a new App Group key, with deduplicated IDs and delete support.
- [x] Add tests for valid/invalid hosts, role/source restrictions, round-trip persistence values, and duplicate replacement.

### Task 3: Native custom model UI

**Files:**
- Modify: `DictusApp/Views/ModelManagerView.swift`
- Create: `DictusApp/Views/AddCustomModelView.swift`
- Modify: `DictusApp/Views/ModelCardView.swift`

- [x] Add an `Add` toolbar action that presents a native form with role and source pickers, name, URL, and optional Ollama model name.
- [x] Show validation errors inline and disable Save until the record passes validation.
- [x] Render separate “Custom speech recognition” and “Custom cleanup” sections with delete confirmation; distinguish available Ollama cleanup registrations from configuration-only ASR entries and route valid Ollama cleanup entries through the app runtime.
- [x] Keep built-in model download/select/delete behavior unchanged.

### Task 4: Verification

**Files:**
- Modify: `DictusCore/Tests/DictusCoreTests/AppleAppFoundationContractTests.swift` only if existing source contracts need updating.

- [x] Run focused custom/language tests.
- [x] Run `git diff --check`.
- [x] Build the iOS simulator target with the single approved SimSlim device.
- [x] Add and verify the app-target Ollama cleanup path with offline HTTP contract tests; normalize the Ollama endpoint so a base URL already ending in `/v1` is not duplicated.
- [x] Review the final diff; no TestFlight release was created.

## Actual closeout status (2026-09-01)

- Custom ASR registrations are currently configuration-only. Even when the URL and variant look compatible with WhisperKit, the app has no custom download, selection, file-integrity checking, or loading path for them; they must not be described as runnable.
- Valid Ollama cleanup registrations are wired into `PolishCoordinator`. The UI distinguishes available cleanup registrations from configuration-only ASR registrations.
- Ollama endpoints are normalized; a base URL that already contains `/v1` does not receive a duplicate `/v1`.
- Fresh verification: `swift test --package-path DictusCore --scratch-path /tmp/saiity-dictus-final-core` completed with 1175 executed, 10 skipped, and 0 failures; `git diff --check` passed; `xcodebuild build -project Dictus.xcodeproj -scheme sAiity-iOS -destination platform=iOS Simulator,id=AC636497-5EC6-4AD4-BD83-E5E2458FA702 -derivedDataPath /tmp/saiity-dictus-simslim-final CODE_SIGNING_ALLOWED=NO` completed with `BUILD SUCCEEDED`.
- Publishing and TestFlight are not included in this task.
