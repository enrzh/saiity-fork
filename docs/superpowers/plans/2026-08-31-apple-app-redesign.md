# Apple App Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task.

**Goal:** Redesign every user-facing sAiity app screen into one coherent native iOS product without removing functionality.

**Architecture:** Preserve existing coordinators and model/subscription state. Views adopt a shared semantic visual vocabulary through existing `DictusColors` and `DictusTypography`; each existing screen is simplified in place using native SwiftUI navigation, lists, controls, alerts, and progress.

**Tech Stack:** SwiftUI, UIKit interoperability, StoreKit, Foundation Models, XCTest, iOS 17+, iOS 26 native tab and glass APIs.

## Global Constraints

- Preserve all features, state machines, dirty work, and App Group contracts.
- Prefer existing files and native controls; add no speculative architecture.
- Support Dynamic Type, VoiceOver, Reduce Motion, Reduce Transparency, Increase Contrast, light, and dark modes.
- Do not push or upload TestFlight before physical keyboard acceptance.

### Task 1: Semantic Foundation And Native Shell

**Files:**
- Modify: `DictusCore/Sources/DictusCore/Design/DictusColors.swift`
- Modify: `DictusCore/Sources/DictusCore/Design/DictusTypography.swift`
- Modify: `DictusApp/Views/MainTabView.swift`

- [ ] Add contract tests for semantic colors/type usage, native three-tab shell, and safe-area-correct tab content.
- [ ] Remove fixed low-contrast text treatments and decorative surface tokens.
- [ ] Keep native `TabView` and per-tab `NavigationStack`; fix bottom content using safe-area behavior rather than universal padding.
- [ ] Verify light/dark and accessibility environment branches build.

### Task 2: Home And Dictation Flow

**Files:**
- Modify: `DictusApp/Views/HomeView.swift`
- Modify: `DictusApp/Views/RecordingView.swift`
- Modify: `DictusApp/Views/TestDictationView.swift`
- Modify: `DictusApp/DictationView.swift`

- [ ] Add tests for one readiness blocker/action, one primary action, explicit copy feedback, and actionable standalone errors.
- [ ] Replace card stacking with native sections and one readiness summary.
- [ ] Make recording a focused modal task with stable controls, live/raw text, processed result, retry, and close.
- [ ] Add modal/accessibility semantics and state announcements without changing coordinator lifecycles.
- [ ] Verify Reduce Motion and large Dynamic Type layouts.

### Task 3: Models

**Files:**
- Modify: `DictusApp/Views/ModelManagerView.swift`
- Modify: `DictusApp/Views/ModelCardView.swift`
- Modify: `DictusApp/Views/ModelLanguageDetailView.swift`
- Modify: `DictusApp/Views/ModelLoadingOverlay.swift`

- [ ] Add tests for every model state, byte progress, selected state, retry, and deletion confirmation.
- [ ] Convert model cards to concise native rows with stable action placement.
- [ ] Keep download/preparation status explicit and accessible.
- [ ] Move delete behind a menu and confirm with model name and consequence.
- [ ] Make language coverage a scannable native detail list.

### Task 4: Settings And Secondary Screens

**Files:**
- Modify: `DictusApp/Views/SettingsView.swift`
- Modify: `DictusApp/Views/SoundSettingsView.swift`
- Modify: `DictusApp/Views/DebugLogView.swift`
- Modify: `DictusApp/Polish/PolishDebugView.swift`
- Modify: `DictusApp/Views/DiagnosticDetailView.swift`
- Modify: `DictusApp/Views/LicensesView.swift`
- Modify: `DictusApp/Views/PaywallView.swift`
- Modify: `DictusApp/Views/PaywallPresentation.swift`

- [ ] Add tests for section order, native control types, confirmation alerts, copy/export feedback, and purchase states.
- [ ] Rebuild Settings as grouped native sections containing only shipped behavior.
- [ ] Standardize secondary navigation, toolbar actions, scrolling, safe areas, and accessibility.
- [ ] Remove decorative paywall glow/gradient/card nesting while retaining products, purchase, restore, legal text, and errors.

### Task 5: Four-Stage Onboarding

**Files:**
- Modify: `DictusApp/Onboarding/OnboardingView.swift`
- Modify: all existing files in `DictusApp/Onboarding/`

- [ ] Add tests for four semantic stages and every required gate.
- [ ] Consolidate welcome, permissions, availability checklist, real keyboard trial, and completion into one native setup container.
- [ ] Keep model download progress and preparation status truthful and resumable.
- [ ] Replace hidden text-field completion with explicit real dictation success.
- [ ] Add scrollability, safe-area primary actions, step accessibility values, and state announcements.

### Task 6: Whole-App Verification

- [ ] Run all DictusCore and app tests; expect zero failures.
- [ ] Run generic and signed physical-device builds.
- [ ] Inspect every tab, pushed page, sheet, alert, onboarding stage, keyboard mode, light/dark appearance, and accessibility setting.
- [ ] Run `git diff --check` and independent final code/design review.
- [ ] Install the signed build and collect fresh physical-device screenshots before release consideration.
