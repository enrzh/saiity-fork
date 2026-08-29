# sAiity Native Liquid Glass Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the app and keyboard presentation with the approved native sAiity Liquid Glass design while preserving all existing recording, model, settings, App Group, and insertion behavior.

**Architecture:** Keep the existing view models, `DictationCoordinator`, `ModelManager`, App Group preferences, keyboard bridge, and text-proxy pipeline. Update the existing SwiftUI views and add only thin state mapping or accessibility helpers where the current owners cannot provide the required presentation. Use iOS 26/27 Liquid Glass at availability-gated call sites and native material fallbacks on iOS 17-25.

**Tech Stack:** Swift 6, SwiftUI, UIKit keyboard extension, Swift Package Manager, XCTest, iOS 17 minimum deployment target.

## Global Constraints

- Use only the three supplied reference attachments as the visual source of truth.
- Preserve the existing recording, background-audio, transcription, polishing, model storage, App Group, keyboard lifecycle, and `textDocumentProxy` contracts.
- The complete model UI catalog is the seven identifiers listed in the approved specification; do not invent entries or ready states.
- Automatic language detection is represented as `Auto` and remains the existing transcription behavior.
- Use `NavigationStack`, `TabView`, `List`, `Toolbar`, `NavigationLink`, and `sheet` where specified; do not introduce `NavigationSplitView` or new Manager/Service/Factory/Strategy/Protocol/Adapter/Coordinator/Provider/Resolver/Registry layers.
- Keep the keyboard voice-only at a fixed 390x220 pt safe canvas with 44x44 pt hit regions where geometry permits.
- No visible user-facing string, accessibility label, alert, sheet, or toolbar may identify the product as Dictus.
- Support light/dark appearance, Dynamic Type, VoiceOver, Reduce Transparency, Reduce Motion, Bold Text, Increased Contrast, Button Shapes, and Voice Control using system semantics.

---

### Task 1: Native App Shell And Home

**Files:**
- Modify: `DictusApp/ContentView.swift`
- Modify: `DictusApp/Views/MainTabView.swift`
- Modify: `DictusApp/Views/HomeView.swift`
- Modify: `DictusApp/Views/RecordingView.swift`
- Test: `DictusCore/Tests/DictusCoreTests/DictationStatusTests.swift` (create if absent)

**Interfaces:**
- Consumes: existing `DictationCoordinator`, recording state, permission state, and recent activity source exposed by current app owners.
- Produces: a three-tab `TabView`; each tab owns a `NavigationStack`; Home renders real readiness, recording, processing, completion, and recoverable-error states without changing pipeline behavior.

- [ ] **Step 1: Write the failing state-mapping tests**

```swift
func testInsertionAcknowledgementIsRequiredBeforeCompletionLabel() {
    XCTAssertEqual(HomeRecordingPresentation(status: .processing, insertionAcknowledged: false).label, "Processing")
    XCTAssertEqual(HomeRecordingPresentation(status: .processing, insertionAcknowledged: true).label, "Inserted")
}
```

- [ ] **Step 2: Run the focused test and verify it fails**

Run: `swift test --package-path DictusCore --filter DictationStatusTests/testInsertionAcknowledgementIsRequiredBeforeCompletionLabel`
Expected: FAIL because `HomeRecordingPresentation` does not yet exist.

- [ ] **Step 3: Implement the minimal existing-view state mapping and shell**

Add the smallest mapping needed by `HomeView` and connect the existing coordinator actions. Preserve the existing recording/background calls and show the compact sAiity header, greeting, voice-input surface, real recent activity, and quiet Home/Models/Settings tabs. Use system semantic fonts/colors and availability-gated glass with material fallback.

- [ ] **Step 4: Run the focused test and app compile check**

Run: `swift test --package-path DictusCore --filter DictationStatusTests/testInsertionAcknowledgementIsRequiredBeforeCompletionLabel`
Expected: PASS.

Run: `xcodebuild -list -project Dictus.xcodeproj`
Expected: The project lists the app and keyboard schemes without modifying source files.

- [ ] **Step 5: Commit the independently reviewable app-shell change**

Run: `git add DictusApp/ContentView.swift DictusApp/Views/MainTabView.swift DictusApp/Views/HomeView.swift DictusApp/Views/RecordingView.swift DictusCore/Tests/DictusCoreTests/DictationStatusTests.swift && git commit -m "feat: add native sAiity app shell"`

### Task 2: Models Screen And Truthful Catalog States

**Files:**
- Modify: `DictusApp/Views/ModelManagerView.swift`
- Modify: `DictusApp/Views/ModelCardView.swift`
- Modify: `DictusApp/Views/ModelLanguageDetailView.swift`
- Modify: `DictusApp/Models/ModelManager.swift` only for presentation wiring
- Test: `DictusCore/Tests/DictusCoreTests/ModelInfoTests.swift`

**Interfaces:**
- Consumes: existing `ModelInfo`, model catalog, `ModelManager`, installation/download/loading/error state, and recommendation ordering.
- Produces: native `List` sections for Installed and Available, with truthful status labels and existing download/cancel/retry/delete/select actions for exactly the seven approved model identifiers.

- [ ] **Step 1: Add catalog and state assertions**

```swift
func testRedesignCatalogContainsExactlySevenApprovedIdentifiers() {
    XCTAssertEqual(Set(ModelInfo.redesignCatalog.map(\.id)), [
        "openai_whisper-tiny", "openai_whisper-base", "openai_whisper-small",
        "openai_whisper-small_216MB", "openai_whisper-medium",
        "parakeet-tdt-0.6b-v3", "openai_whisper-large-v3_turbo_954MB"
    ])
}
```

- [ ] **Step 2: Run the focused test and verify it fails**

Run: `swift test --package-path DictusCore --filter ModelInfoTests/testRedesignCatalogContainsExactlySevenApprovedIdentifiers`
Expected: FAIL because `redesignCatalog` does not yet exist.

- [ ] **Step 3: Implement the minimal catalog-backed List presentation**

Use the existing catalog and manager state. Add explicit text/accessibility values for active, installed, downloading, cancelling, failed, unavailable, loading, and queued states. Keep real sizes, engine data, availability filtering, retry behavior, and recommendation ordering. Do not add preview fixtures or fake model metadata.

- [ ] **Step 4: Run model tests and verify app compilation**

Run: `swift test --package-path DictusCore --filter ModelInfoTests`
Expected: PASS.

Run: `xcodebuild -project Dictus.xcodeproj -scheme DictusApp -destination 'generic/platform=iOS' build CODE_SIGNING_ALLOWED=NO`
Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Commit the model-screen change**

Run: `git add DictusApp/Views/ModelManagerView.swift DictusApp/Views/ModelCardView.swift DictusApp/Views/ModelLanguageDetailView.swift DictusApp/Models/ModelManager.swift DictusCore/Tests/DictusCoreTests/ModelInfoTests.swift && git commit -m "feat: render truthful model management"`

### Task 3: Settings And Product Identity

**Files:**
- Modify: `DictusApp/Views/SettingsView.swift`
- Modify: `DictusApp/Views/LicensesView.swift` only where navigation presentation requires it
- Modify: `DictusApp/Views/DiagnosticDetailView.swift` only where release visibility requires it
- Test: `DictusCore/Tests/DictusCoreTests/SharedKeysExtensionTests.swift`

**Interfaces:**
- Consumes: existing App Group keys, Live Activity availability, polish availability, permission routes, privacy/legal/help destinations, and localization system.
- Produces: grouped native settings with Auto language, real conditional preferences, privacy and legal/help destinations, no removed controls, and no visible `Dictus` product identity.

- [ ] **Step 1: Add preference contract assertions**

```swift
func testAutomaticLanguageUsesExistingAppGroupPreference() {
    let defaults = UserDefaults(suiteName: AppGroup.identifier)!
    defaults.set(nil, forKey: SharedKeys.transcriptionLanguage)
    XCTAssertEqual(TranscriptionLanguage.preference(from: defaults), .automatic)
}
```

- [ ] **Step 2: Run the focused test and verify it fails**

Run: `swift test --package-path DictusCore --filter SharedKeysExtensionTests/testAutomaticLanguageUsesExistingAppGroupPreference`
Expected: FAIL until the settings mapping exposes the existing automatic-language contract.

- [ ] **Step 3: Implement the minimal grouped settings presentation**

Read and write existing App Group-backed values, preserve side effects, retain only supported Live Activity and polish controls, show current permission state and system-settings routes, and exclude debug-only and removed keyboard controls. Replace visible Dictus product copy with sAiity while retaining internal source names and required attribution.

- [ ] **Step 4: Run tests and scan visible source strings**

Run: `swift test --package-path DictusCore --filter SharedKeysExtensionTests`
Expected: PASS.

Run: `rg -n --glob '*.swift' --glob '*.strings' --glob '*.plist' 'Dictus' DictusApp DictusKeyboard`
Expected: no user-visible product identity matches; internal identifiers and required attribution are reviewed individually.

- [ ] **Step 5: Commit the settings and identity change**

Run: `git add DictusApp/Views/SettingsView.swift DictusApp/Views/LicensesView.swift DictusApp/Views/DiagnosticDetailView.swift DictusCore/Tests/DictusCoreTests/SharedKeysExtensionTests.swift && git commit -m "feat: simplify sAiity settings"`

### Task 4: Voice-Only Liquid Glass Keyboard

**Files:**
- Modify: `DictusKeyboard/KeyboardRootView.swift`
- Modify: `DictusKeyboard/InputView.swift`
- Modify: `DictusKeyboard/KeyboardViewController.swift`
- Modify: `DictusKeyboard/DictusKeyboardBridge.swift` only for thin presentation callbacks
- Test: `DictusCore/Tests/DictusCoreTests/KeyboardDictationURLTests.swift`

**Interfaces:**
- Consumes: existing `KeyboardState`, bridge, `textDocumentProxy`, extension context, next-keyboard command, and press-to-talk lifecycle.
- Produces: fixed 390x220 voice-only layout with Auto control, centered hold microphone, concise status, right rail delete/return/@/dismiss controls, and system next-keyboard control.

- [ ] **Step 1: Add proxy-action assertions**

```swift
func testKeyboardCommandMappingPreservesLiteralActions() {
    XCTAssertEqual(KeyboardCommand.delete.proxyAction, .deleteBackward)
    XCTAssertEqual(KeyboardCommand.returnKey.proxyAction, .insertText("\\n"))
    XCTAssertEqual(KeyboardCommand.at.proxyAction, .insertText("@"))
}
```

- [ ] **Step 2: Run the focused test and verify it fails**

Run: `swift test --package-path DictusCore --filter KeyboardDictationURLTests/testKeyboardCommandMappingPreservesLiteralActions`
Expected: FAIL until the keyboard presentation command mapping is defined.

- [ ] **Step 3: Implement the fixed keyboard surface**

Replace the rendered key grid with stable safe-area constraints for 390x220. Use native Liquid Glass on iOS 26/27 and `Material`/semantic borders on iOS 17-25. Keep existing press-to-talk, insertion acknowledgement, proxy actions, dismiss, next-keyboard, accessibility labels, and lifecycle interruption behavior. Do not add app branding, logo, glow, fake waveform, gradient, or non-voice keys.

- [ ] **Step 4: Run tests and build the extension**

Run: `swift test --package-path DictusCore --filter KeyboardDictationURLTests`
Expected: PASS.

Run: `xcodebuild -project Dictus.xcodeproj -scheme DictusKeyboard -destination 'generic/platform=iOS' build CODE_SIGNING_ALLOWED=NO`
Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Commit the keyboard change**

Run: `git add DictusKeyboard/KeyboardRootView.swift DictusKeyboard/InputView.swift DictusKeyboard/KeyboardViewController.swift DictusKeyboard/DictusKeyboardBridge.swift DictusCore/Tests/DictusCoreTests/KeyboardDictationURLTests.swift && git commit -m "feat: add voice-only glass keyboard"`

### Task 5: Accessibility, Acceptance Verification, And Handoff

**Files:**
- Modify: `DictusApp/Views/HomeView.swift` only for final accessibility identifiers or labels
- Modify: `DictusApp/Views/ModelManagerView.swift` only for final accessibility identifiers or labels
- Modify: `DictusApp/Views/SettingsView.swift` only for final accessibility identifiers or labels
- Modify: `DictusKeyboard/KeyboardRootView.swift` only for final accessibility identifiers or labels
- Test: `DictusCore/Tests/DictusCoreTests/DictationStatusTests.swift`

**Interfaces:**
- Consumes: completed app, models, settings, and keyboard surfaces from Tasks 1-4.
- Produces: verified accessibility/state contracts, clean diff checks, and a reviewable redesign commit without product-code pipeline changes.

- [ ] **Step 1: Add final state truthfulness assertions**

```swift
func testInsertionStatusCannotPrecedeProxyAcknowledgement() {
    XCTAssertFalse(KeyboardStatus.processing(insertionAcknowledged: false).announcesInsertion)
    XCTAssertTrue(KeyboardStatus.processing(insertionAcknowledged: true).announcesInsertion)
}
```

- [ ] **Step 2: Run the focused test and verify it fails**

Run: `swift test --package-path DictusCore --filter DictationStatusTests/testInsertionStatusCannotPrecedeProxyAcknowledgement`
Expected: FAIL until the final keyboard status contract is present.

- [ ] **Step 3: Finish accessibility and adaptive-state wiring**

Ensure every icon-only control has an action label and value, state meaning is not color-only, Dynamic Type does not clip critical text, and Reduce Transparency/Motion preserve hierarchy and meaning. Add only identifiers required by UI tests and VoiceOver-oriented checks.

- [ ] **Step 4: Run full verification**

Run: `swift test --package-path DictusCore`
Expected: PASS.

Run: `xcodebuild -project Dictus.xcodeproj -scheme DictusApp -destination 'generic/platform=iOS' build CODE_SIGNING_ALLOWED=NO`
Expected: BUILD SUCCEEDED.

Run: `xcodebuild -project Dictus.xcodeproj -scheme DictusKeyboard -destination 'generic/platform=iOS' build CODE_SIGNING_ALLOWED=NO`
Expected: BUILD SUCCEEDED.

Run: `bad='T''B''D|T''O''D''O|P''L''A''C''E''H''O''L''D''E''R|F''I''X''M''E'; rg -n -i "$bad" docs/superpowers/plans/2026-08-29-native-liquid-glass-redesign.md`
Expected: no matches.

Run: `git diff --check`
Expected: no output and exit status 0.

Run: `git diff --name-only HEAD~4..HEAD -- DictusApp/Audio DictusApp/DictationCoordinator.swift DictusCore/Sources/DictusCore/Audio DictusKeyboard/KeyboardLifecycleProbe.swift`
Expected: no output; migration-boundary pipeline files remain unchanged.

- [ ] **Step 5: Commit the acceptance and handoff record**

Run: `git add DictusApp/Views/HomeView.swift DictusApp/Views/ModelManagerView.swift DictusApp/Views/SettingsView.swift DictusKeyboard/KeyboardRootView.swift DictusCore/Tests/DictusCoreTests/DictationStatusTests.swift && git commit -m "test: verify native redesign acceptance"`

Physical-device gate after this plan: switch to the keyboard in a real host text field on an iPhone, hold/release the microphone, confirm insertion acknowledgement, test delete/return/@/dismiss/next-keyboard, and repeat after app backgrounding. Simulator success does not replace this gate.
