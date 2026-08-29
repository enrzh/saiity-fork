# sAiity Dictus Fork Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Produce a sAiity-branded iOS app on Dictus's working dictation base with the sAiity voice-only Liquid Glass keyboard, expanded compatible models, and simplified settings.

**Architecture:** Preserve Dictus's `UnifiedAudioEngine`, `DictationCoordinator`, App Group command channel, model loading, polishing, and text-proxy delivery. Change only product identity, keyboard presentation, compatible model metadata, and settings navigation.

**Tech Stack:** Swift 6, SwiftUI, UIKit custom keyboard extension, AVAudioEngine, WhisperKit, FluidAudio, ActivityKit.

## Global Constraints

- Do not alter Dictus's recording or background-audio lifecycle.
- Do not expose a model unless an existing Dictus runtime can load it.
- Keep the keyboard voice-only; no alphabetic, numeric, emoji, suggestion, autocorrect, sound, or haptic surfaces.
- Use native materials and Liquid Glass where available.
- Preserve MIT attribution.
- Keep `/Users/enrico/Documents/GitHub/sAiity-iOS/.worktrees/saiity-ios-implementation` untouched.

---

### Task 1: sAiity Product Identity

**Files:**
- Modify: `Dictus.xcodeproj/project.pbxproj`
- Modify: `DictusApp/Info.plist`
- Modify: `DictusKeyboard/Info.plist`
- Modify: `DictusWidgets/Info.plist`
- Modify: `DictusApp/DictusApp.entitlements`
- Modify: `DictusKeyboard/DictusKeyboard.entitlements`
- Modify: `DictusWidgets/DictusWidgets.entitlements`
- Modify: visible strings under `DictusApp`, `DictusKeyboard`, and `DictusWidgets`

**Interfaces:**
- Produces: sAiity display names, `de.aiity.saiity.ios` bundle namespace, shared App Group, and `saiity` URL scheme.

- [ ] Replace visible Dictus identity and project build identifiers with sAiity identity.
- [ ] Keep internal Swift type names unless they leak into UI or persistence contracts.
- [ ] Verify no visible `Dictus` strings remain outside attribution/license content.
- [ ] Build the generic iOS target.

### Task 2: Voice-Only Liquid Glass Keyboard

**Files:**
- Modify: `DictusKeyboard/KeyboardRootView.swift`
- Modify: `DictusKeyboard/KeyboardViewController.swift`
- Reuse design from: `/Users/enrico/Documents/GitHub/sAiity-iOS/.worktrees/saiity-ios-implementation/Keyboard/VoiceKeyboardView.swift`

**Interfaces:**
- Consumes: existing `KeyboardState`, dictation start/stop actions, `textDocumentProxy`, next-keyboard, return, delete, and dismiss callbacks.
- Produces: one voice-only keyboard surface with centered hold gesture and existing Dictus dictation lifecycle.

- [ ] Replace key-grid presentation with the sAiity voice-only control layout.
- [ ] Apply native material/Liquid Glass styling and stable compact geometry.
- [ ] Keep accessibility identifiers for microphone, delete, return, switch, and dismiss.
- [ ] Remove alphabetic, number, emoji, suggestion, autocorrect, haptic, and sound UI paths from the rendered surface.
- [ ] Build the keyboard extension.

### Task 3: Compatible Model Catalog

**Files:**
- Modify: `DictusCore/Sources/DictusCore/ModelInfo.swift`
- Modify: `DictusApp/Models/ModelManager.swift` only where catalog wiring requires it.

**Interfaces:**
- Consumes: Dictus WhisperKit and Parakeet runtime identifiers.
- Produces: selectable catalog containing all currently supported Dictus models plus every compatible sAiity model.

- [ ] Map sAiity's model list to Dictus runtime support.
- [ ] Add WhisperKit-compatible and Parakeet-compatible entries with accurate size/language metadata.
- [ ] Keep automatic language detection as the default policy.
- [ ] Do not add Nemotron, Moonshine, SenseVoice, Omnilingual, or Qwen entries unless this fork contains a loadable runtime for them.
- [ ] Build model management and onboarding surfaces.

### Task 4: Simplified Settings

**Files:**
- Modify: `DictusApp/Views/SettingsView.swift`
- Modify: related settings destinations only when no longer reachable.

**Interfaces:**
- Produces: settings without keyboard language, layout, number row, haptics, sounds, autocorrect, transcription-language picker, or About destination.

- [ ] Remove the unwanted Keyboard settings rows and destinations.
- [ ] Persist automatic transcription language as the effective value.
- [ ] Remove About navigation while retaining required license files in the bundle/repository.
- [ ] Build the complete app and run `git diff --check`.

### Task 5: Replacement Handoff

**Files:**
- Modify: `README.md`
- Review: complete attributable diff.

**Interfaces:**
- Produces: a clean sAiity fork branch ready to connect to the private source repository.

- [ ] Document the sAiity product and Dictus MIT attribution.
- [ ] Confirm recording engine and coordinator files have no behavioral modifications.
- [ ] Commit the fork implementation on `saiity-fork`.
