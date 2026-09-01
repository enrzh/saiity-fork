# Native Utility Visual Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace sAiity's decorative, brand-heavy presentation with a native Apple utility visual system across the app and voice-only keyboard.

**Architecture:** Keep the current SwiftUI screens, model lifecycle, dictation coordinator, and keyboard commands. Change presentation at the existing view and design-token boundaries: semantic system colors and text styles for app content, native navigation and grouped lists, and a quiet keyboard surface with one primary microphone control and compact SF Symbol rails.

**Tech Stack:** SwiftUI, UIKit keyboard extension, DictusCore shared design tokens, iOS 17 deployment target with iOS 26 Liquid Glass availability checks, Swift Package XCTest, `xcodebuild`.

## Global Constraints

- Use `systemBackground`, `systemGroupedBackground`, `secondarySystemGroupedBackground`, `label`, `secondaryLabel`, and the system tint for content and controls; do not use the teal brand color as a surface fill or as a decorative gradient.
- Use SwiftUI text styles (`.largeTitle`, `.title2`, `.headline`, `.body`, `.subheadline`, `.caption`) so Dynamic Type remains functional. Avoid custom fixed-size text except for icon sizing and stable keyboard geometry.
- Keep radii between 12 and 16 points for app surfaces. Do not nest cards or turn every row into a floating glass card.
- Keep tappable controls at least 44 points in both dimensions and provide accessibility labels for icon-only controls.
- Use Liquid Glass or material only for a functional floating control layer, the active microphone control, and the iOS 17 fallback. Content lists remain native grouped surfaces.
- Keep Reduce Transparency and Reduce Motion behavior explicit and readable.
- Preserve all seven model choices, model lifecycle states, language details, and confirmation-gated deletion.
- Do not add back keyboard layout, keyboard language, number row, haptics, sounds, autocorrect, transcripts, or About controls.
- Preserve unrelated dirty files and do not use destructive cleanup or broad staging.

---

### Task 1: Rebuild app surfaces with native hierarchy

**Files:**
- Modify: `DictusCore/Sources/DictusCore/Design/DictusColors.swift`
- Modify: `DictusCore/Sources/DictusCore/Design/GlassModifier.swift`
- Modify: `DictusApp/Views/MainTabView.swift`
- Modify: `DictusApp/Views/HomeView.swift`
- Modify: `DictusApp/Views/RecordingView.swift`
- Modify: `DictusApp/Views/ModelManagerView.swift`
- Modify: `DictusApp/Views/ModelCardView.swift`
- Modify: `DictusApp/Views/ModelLanguageDetailView.swift`
- Modify: `DictusApp/Views/SettingsView.swift`
- Modify: `DictusApp/Views/ModelLoadingOverlay.swift`
- Modify: `DictusApp/Views/ProBannerView.swift`
- Modify: `DictusApp/Views/PaywallView.swift`
- Modify: `DictusApp/Views/DebugLogView.swift`
- Modify: `DictusApp/Views/SoundSettingsView.swift`
- Modify: `DictusApp/Views/LicensesView.swift`
- Modify: `DictusApp/Views/SwipeBackOverlayView.swift`
- Modify: `DictusApp/Views/KeyboardModePicker.swift`
- Modify: `DictusApp/Onboarding/OnboardingView.swift`
- Modify: `DictusApp/Onboarding/WelcomePage.swift`
- Modify: `DictusApp/Onboarding/MicPermissionPage.swift`
- Modify: `DictusApp/Onboarding/KeyboardSetupPage.swift`
- Modify: `DictusApp/Onboarding/ModelDownloadPage.swift`
- Modify: `DictusApp/Onboarding/PolishTogglePage.swift`
- Modify: `DictusApp/Onboarding/GlobeKeyTutorialPage.swift`
- Modify: `DictusApp/Onboarding/OnboardingSuccessView.swift`
- Test: `DictusCore/Tests/DictusCoreTests/ModelInfoTests.swift` and existing design-related tests only when a behavior contract changes

**Interfaces:**
- Preserve `ModelManagerView(modelManager:)`, `HomeView(modelManager:onModelsRequested:)`, `RecordingView(mode:onComplete:)`, and all existing model-manager callbacks.
- Preserve `Color.dictusAccent` and other public compatibility symbols when removing their use from content surfaces; do not break package clients.

- [ ] **Step 1: Establish the baseline**

Run:

```bash
swift test --package-path DictusCore --scratch-path /tmp/saiity-dictus-redesign-baseline
```

Expected: the existing suite passes before the app-only changes.

- [ ] **Step 2: Replace decorative design usage with semantic system presentation**

Keep the existing public color aliases for source compatibility, but make app views use system background/grouped colors, `.primary`, `.secondary`, and `.tint`. Keep the glass modifier only as a functional material fallback and iOS 26 control effect; do not apply it to every content card.

- [ ] **Step 3: Restore native navigation hierarchy**

Use the existing `TabView` and `NavigationStack` structure with visible native navigation bars. Give Home a native large title (`sAiity`) instead of a custom dashboard header. Keep Models and Settings as native navigation destinations with their current titles and tab items.

- [ ] **Step 4: Simplify Home and Recording**

Use a system grouped background, a compact readiness section, a single bordered-prominent dictation action, and a recent-result section only when present. Keep Recording's stable waveform/status/microphone positions and all lifecycle/error behavior, but remove decorative full-screen gradient or oversized glass treatment. Use system text styles and semantic recording/error colors.

- [ ] **Step 5: Preserve and restyle Models and Settings**

Keep the complete seven-model Installed/Available catalog, progress and error states, language-detail navigation, active model handling, partial-download cleanup, and confirmation alerts. Use inset grouped rows with compact metadata rather than floating dashboard cards. Keep Settings limited to transcription, feature, permission, privacy, and help sections.

- [ ] **Step 6: Audit the remaining user-facing flows**

Apply the same native hierarchy to onboarding, model loading, paywall/pro banner, diagnostics, sound settings, licenses, swipe-back handoff, and the keyboard-mode preview. Keep each flow's existing actions and accessibility labels. Replace decorative gradients, hard-coded teal fills, all-caps explanatory copy, and nested glass cards with system backgrounds, native controls, semantic colors, and standard text styles. Do not remove a required onboarding or model-management step.

- [ ] **Step 7: Run the app package tests**

Run:

```bash
swift test --package-path DictusCore --scratch-path /tmp/saiity-dictus-redesign-app
```

Expected: 0 failures and no test hidden or disabled.

- [ ] **Step 8: Leave implementation changes in the worktree for the controller**

Do not reset or stage unrelated files. Report the exact app files changed, the command run, the result, and any visual caveat.

### Task 2: Refine the native voice-only keyboard

**Files:**
- Modify: `DictusKeyboard/KeyboardRootView.swift`
- Modify: `DictusCore/Sources/DictusCore/VoiceOnlyKeyboardPolicy.swift`
- Modify: `DictusCore/Tests/DictusCoreTests/VoiceOnlyKeyboardPolicyTests.swift`
- Modify: `DictusCore/Tests/DictusCoreTests/VoiceOnlyKeyboardContractTests.swift` only if the active surface contract changes

**Interfaces:**
- Preserve `KeyboardRootView(controllerID:)`, `KeyboardState` recording lifecycle, `textDocumentProxy` actions, URL handoff, and all four right-rail command identifiers.
- Keep the existing voice-only geometry contract and narrow-width protections, changing only the visual metrics necessary for the approved Native Utility direction.

- [ ] **Step 1: Add a failing geometry assertion for the approved primary control**

Extend the policy tests to assert that the centered microphone has a stable 56-64 point dimension, utility controls remain at least 44 points, and the center remains between equal rails at widths 320, 375, 390, and 430.

- [ ] **Step 2: Run the focused policy tests and observe the failure**

Run:

```bash
swift test --package-path DictusCore --scratch-path /tmp/saiity-dictus-redesign-keyboard --filter VoiceOnlyKeyboardPolicyTests
```

Expected: the new primary-control assertion fails against the current 44-point/capsule microphone geometry.

- [ ] **Step 3: Implement the quiet native keyboard surface**

Use the system keyboard background, remove any brand/header content, render one centered circular primary microphone control at the approved stable size, and keep compact 44-point SF Symbol utility controls on the rails. Use the system tint/recording colors, a Liquid Glass effect only for functional controls, material fallback for older iOS, and explicit Reduce Motion/Transparency behavior. Preserve all existing accessibility identifiers and labels.

- [ ] **Step 4: Run the focused policy and contract tests**

Run:

```bash
swift test --package-path DictusCore --scratch-path /tmp/saiity-dictus-redesign-keyboard --filter VoiceOnlyKeyboardPolicyTests
swift test --package-path DictusCore --scratch-path /tmp/saiity-dictus-dictation-contract --filter VoiceOnlyKeyboardContractTests
```

Expected: all focused tests pass with the new geometry and no legacy bridge wiring.

- [ ] **Step 5: Leave implementation changes in the worktree for the controller**

Do not reset or stage unrelated files. Report the exact keyboard files changed, the RED and GREEN commands/results, and any physical-device caveat.

### Task 3: Whole-branch verification

**Files:**
- No source changes unless a concrete build/test defect is found.

- [ ] **Step 1: Run the full shared suite**

```bash
swift test --package-path DictusCore --scratch-path /tmp/saiity-dictus-redesign-final
```

Expected: 0 failures.

- [ ] **Step 2: Build both iOS destinations**

```bash
xcodebuild build-for-testing -project Dictus.xcodeproj -scheme DictusApp -destination 'generic/platform=iOS' -derivedDataPath /tmp/saiity-dictus-redesign-device CODE_SIGNING_ALLOWED=NO
xcodebuild build-for-testing -project Dictus.xcodeproj -scheme DictusApp -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/saiity-dictus-redesign-simulator CODE_SIGNING_ALLOWED=NO
```

Expected: both commands finish with `** TEST BUILD SUCCEEDED **`.

- [ ] **Step 3: Run hygiene and visual smoke checks**

Run `git diff --check`, install the simulator app into the existing booted verification simulator, launch it, and capture one light-mode screenshot. Inspect Home, Models, and Settings for visible native navigation, readable system contrast, retained model actions, and no nested decorative cards. Do not create or reset simulator devices.

- [ ] **Step 4: Review the final diff**

Confirm that only the planned app/keyboard/design/test files changed, all seven models remain reachable, removed settings remain absent, the keyboard has no logo/header, and all existing commands/identifiers remain intact. Record physical iPhone interaction and TestFlight as unverified unless actually exercised.
