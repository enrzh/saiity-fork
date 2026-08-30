# Keyboard Actions and Language Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement truthful ASR/translation selection, complete voice-keyboard actions and hit targets, system-language defaults with safe French migration, and physical-iPhone acceptance for the 216pt DictusKeyboard surface.

**Architecture:** Reuse KeyboardAreaMode, KeyboardCommand, SupportedLanguage, TranscriptionLanguageMode, DictationCoordinator, KeyboardState, KeyboardViewController, and existing proxy/emoji/number owners. Add only small value types and pure functions in DictusCore for shared capability/request/language contracts; the keyboard persists requests and the app translates only after authoritative final text. UIKit owns reliable hit controls while SwiftUI renders the existing surface.

**Tech Stack:** Swift 5, SwiftUI, UIKit keyboard extension, DictusCore Swift Package/XCTest, App Group UserDefaults, xcodebuild, devicectl.

## Global Constraints

- Keep the keyboard canvas at **216pt** high and center the microphone in the available central area.
- Use existing KeyboardAreaMode for mutually exclusive keyboard-area states.
- Add no Manager, Service, Protocol, Factory, Strategy, Adapter, Coordinator, Provider, Resolver, or Registry.
- Reuse EmojiPickerView, the existing number/symbol layer, shared App Group defaults, and existing model metadata.
- Use native iOS 26 Liquid Glass or existing semantic/material fallback; add no decorative glow, fake reflection, or gradient.
- Show AUTO only when the active ASR model supports multilingual automatic input-language detection.
- Translation target readiness is independent of ASR metadata and translation never executes in the keyboard extension.
- Delete/return use exact UIKit-backed 88x44pt hit areas; next/dismiss use declared UIKit-backed hit height at least 44pt.
- Keyboard language defaults to Automatic (System); explicit selection persists over locale changes.
- Migrate implicit legacy French only without evidence of explicit French; preserve explicit French.
- Preserve all dirty/untracked files; do not reset, stash, clean, or stage them.
- Unit/UI/simulator tests are supplemental; TestFlight is prohibited until physical iPhone acceptance is recorded.

---

## Current File Map

- DictusCore/Sources/DictusCore/KeyboardCommand.swift: existing delete/return/@ proxy mapping.
- DictusCore/Sources/DictusCore/KeyboardAreaMode.swift: existing single area-state authority.
- DictusCore/Sources/DictusCore/SharedKeys.swift: App Group key registry.
- DictusCore/Sources/DictusCore/SupportedLanguage.swift: four keyboard languages and layout defaults.
- DictusCore/Sources/DictusCore/TranscriptionLanguage.swift: existing STT mode storage/resolution.
- DictusCore/Sources/DictusCore/VoiceOnlyKeyboardPolicy.swift: existing 216pt geometry and rails.
- DictusKeyboard/KeyboardRootView.swift: SwiftUI surface, proxy actions, emoji and number views.
- DictusKeyboard/KeyboardViewController.swift: UIKit lifecycle and existing next/dismiss callbacks.
- DictusKeyboard/KeyboardState.swift: shared status and active controller.
- DictusApp/DictationCoordinator.swift: authoritative recording/transcription/insertion flow.
- DictusCore/Tests/DictusCoreTests/: host XCTest suite with language, area, status, and keyboard-contract tests.

## Task 1: ASR Capability, Translation Request, and App Final Hook

**Files:**
- Create: DictusCore/Sources/DictusCore/DictationLanguageRequest.swift
- Modify: DictusCore/Sources/DictusCore/SharedKeys.swift
- Modify: DictusCore/Sources/DictusCore/TranscriptionLanguage.swift
- Create: DictusCore/Tests/DictusCoreTests/DictationLanguageRequestTests.swift
- Modify: DictusKeyboard/KeyboardRootView.swift and KeyboardState.swift
- Modify: DictusApp/DictationCoordinator.swift
- Test: DictusCore/Tests/DictusCoreTests/DictationStatusTests.swift for ordering

**Interfaces:**
- ASRCapability(supportsAutomaticInputLanguage: Bool, sourceLanguage: SupportedLanguage?) exposes displaySourceCode: String.
- TranslationTargetReadiness(source: String, targets: Set<String>) exposes readyTargets(for: SupportedLanguage?) -> [SupportedLanguage], independent of ASR metadata.
- DictationLanguageRequest(mode: TranscriptionLanguageMode, translationTarget: SupportedLanguage?) exposes persist(to:) and static load(from:) -> Self.
- DictationCoordinator.processAuthoritativeFinalTranscript(_:request:) async -> String runs after final ASR output and before insertion/acknowledgement.
- The extension persists the request and never calls translation.

- [ ] **Step 1: Write the failing capability/request tests**

~~~swift
final class DictationLanguageRequestTests: XCTestCase {
    func testAutoRequiresMultilingualAutomaticASR() {
        XCTAssertEqual(
            ASRCapability(supportsAutomaticInputLanguage: true, sourceLanguage: nil).displaySourceCode,
            "AUTO"
        )
        XCTAssertEqual(
            ASRCapability(supportsAutomaticInputLanguage: false, sourceLanguage: .french).displaySourceCode,
            "FR"
        )
    }

    func testReadinessIsIndependentAndSupportsFixedFrenchSource() {
        let asr = ASRCapability(supportsAutomaticInputLanguage: false, sourceLanguage: .french)
        let readiness = TranslationTargetReadiness(source: "fr", targets: ["en", "de"])
        XCTAssertEqual(readiness.readyTargets(for: asr.sourceLanguage), [.english, .german])
        XCTAssertFalse(readiness.readyTargets(for: asr.sourceLanguage).contains(.spanish))
    }

    func testRequestRoundTripsModeAndTargetThroughDefaults() {
        let defaults = UserDefaults(suiteName: "dictus.plan.request-tests")!
        defaults.removePersistentDomain(forName: "dictus.plan.request-tests")
        let request = DictationLanguageRequest(mode: .autoDetect, translationTarget: .english)
        request.persist(to: defaults)
        XCTAssertEqual(DictationLanguageRequest.load(from: defaults), request)
    }
}
~~~

- [ ] **Step 2: Run RED and verify feature-missing failure**

~~~bash
swift test --package-path DictusCore --scratch-path /tmp/saiity-dictus-keyboard-language-red --filter DictationLanguageRequestTests
~~~
Expected: FAIL because the three value types are undefined, not because of a package/compiler error.

- [ ] **Step 3: Add minimal shared types and keys**

Add SharedKeys.dictationLanguageRequest = "dictus.dictationLanguageRequest". Implement:

~~~swift
public struct ASRCapability: Equatable, Sendable {
    public let supportsAutomaticInputLanguage: Bool
    public let sourceLanguage: SupportedLanguage?
    public init(supportsAutomaticInputLanguage: Bool, sourceLanguage: SupportedLanguage?) {
        self.supportsAutomaticInputLanguage = supportsAutomaticInputLanguage
        self.sourceLanguage = sourceLanguage
    }
    public var displaySourceCode: String {
        supportsAutomaticInputLanguage ? "AUTO" : (sourceLanguage?.shortCode ?? "--")
    }
}

public struct TranslationTargetReadiness: Equatable, Sendable {
    public let source: String
    public let targets: Set<String>
    public init(source: String, targets: Set<String>) {
        self.source = source
        self.targets = targets
    }
    public func readyTargets(for sourceLanguage: SupportedLanguage?) -> [SupportedLanguage] {
        guard sourceLanguage?.rawValue == source else { return [] }
        return SupportedLanguage.allCases.filter { targets.contains($0.rawValue) }
    }
}

public struct DictationLanguageRequest: Equatable, Sendable {
    public let mode: TranscriptionLanguageMode
    public let translationTarget: SupportedLanguage?
    public static let appGroupKey = SharedKeys.dictationLanguageRequest
    public init(mode: TranscriptionLanguageMode, translationTarget: SupportedLanguage?) {
        self.mode = mode
        self.translationTarget = translationTarget
    }
    public func persist(to defaults: UserDefaults = AppGroup.defaults) {
        defaults.set(mode.storedValue, forKey: Self.appGroupKey + ".mode")
        defaults.set(translationTarget?.rawValue, forKey: Self.appGroupKey + ".target")
    }
    public static func load(from defaults: UserDefaults = AppGroup.defaults) -> Self {
        Self(
            mode: .init(storedValue: defaults.string(forKey: Self.appGroupKey + ".mode")),
            translationTarget: defaults.string(forKey: Self.appGroupKey + ".target")
                .flatMap(SupportedLanguage.init(rawValue:))
        )
    }
}
~~~

- [ ] **Step 4: Run GREEN**

~~~bash
swift test --package-path DictusCore --scratch-path /tmp/saiity-dictus-keyboard-language-green --filter DictationLanguageRequestTests
~~~
Expected: all three tests PASS with 0 failures.

- [ ] **Step 5: Wire menu truth and final hook**

In KeyboardRootView, source display comes from active model capability. Render Transcribe from TranscriptionLanguageMode and only ready Translate to target entries from TranslationTargetReadiness. Fixed French ASR displays FR while French-to-English may remain available.

Capture the request at dictation start and call this after transcriptionService.transcribe(...) returns the authoritative final string:

~~~swift
@MainActor
func processAuthoritativeFinalTranscript(
    _ transcript: String,
    request: DictationLanguageRequest
) async -> String {
    guard let target = request.translationTarget, !transcript.isEmpty else { return transcript }
    let translated = await translationResult(for: transcript, target: target)
    return translated?.isEmpty == false ? translated! : transcript
}
~~~

Use the existing independent runtime when available; otherwise return original text with an explicit unsupported/recoverable result. Never process partials or acknowledge insertion before this hook.

- [ ] **Step 6: Test ordering and verify Task 1**

~~~swift
func testTranslationAndInsertionRemainBeforeAcknowledgement() {
    XCTAssertTrue(DictationStatus.processing.ownsKeyboardArea)
    XCTAssertFalse(DictationStatus.ready.ownsKeyboardArea)
}
~~~

~~~bash
swift test --package-path DictusCore --scratch-path /tmp/saiity-dictus-keyboard-language-task1 --filter 'DictationLanguageRequestTests|TranscriptionLanguageModeTests|DictationStatusTests'
~~~
Expected: all selected tests PASS and no test requires keyboard-side translation.

## Task 2: Keyboard Layout and Actions

**Files:**
- Modify: DictusCore/Sources/DictusCore/KeyboardCommand.swift
- Modify: DictusCore/Sources/DictusCore/VoiceOnlyKeyboardPolicy.swift
- Modify: DictusCore/Tests/DictusCoreTests/VoiceOnlyKeyboardPolicyTests.swift
- Modify: DictusCore/Tests/DictusCoreTests/VoiceOnlyKeyboardContractTests.swift
- Modify: DictusCore/Tests/DictusCoreTests/KeyboardAreaModeTests.swift
- Modify: DictusKeyboard/KeyboardRootView.swift and KeyboardState.swift
- Reuse: DictusKeyboard/Views/EmojiPickerView.swift, current number/symbol page, textDocumentProxy

**Interfaces:**
- Preserve KeyboardCommand.delete, .returnKey, .at, and proxyAction.
- Add actionHitSize = CGSize(width: 88, height: 44), bottomActionHitHeight = 44, and rightRailFrames(for:) -> (delete: CGRect, returnKey: CGRect).
- @ is left utility; delete/return are right rail; emoji is local; 123/ABC select existing layers.
- KeyboardAreaMode remains the only area authority.

- [ ] **Step 1: Write failing geometry/action tests**

~~~swift
func testDeleteAndReturnUseExactEightyEightByFortyFourFrames() {
    let frames = VoiceOnlyKeyboardPolicy.rightRailFrames(for: 390)
    XCTAssertEqual(frames.delete.size, CGSize(width: 88, height: 44))
    XCTAssertEqual(frames.returnKey.size, CGSize(width: 88, height: 44))
    XCTAssertFalse(frames.delete.intersects(frames.returnKey))
}

func testCanvasAndLiteralActionsRemainStable() {
    XCTAssertEqual(VoiceOnlyKeyboardPolicy.surfaceHeight, 216)
    XCTAssertEqual(VoiceOnlyKeyboardPolicy.bottomActionHitHeight, 44)
    XCTAssertEqual(KeyboardCommand.at.proxyAction, .insertText("@"))
}
~~~

- [ ] **Step 2: Run RED**

~~~bash
swift test --package-path DictusCore --scratch-path /tmp/saiity-dictus-keyboard-actions-red --filter VoiceOnlyKeyboardPolicyTests
~~~
Expected: FAIL because current command rectangles are 44pt and no exact 88x44 contract exists.

- [ ] **Step 3: Implement geometry and routing**

~~~swift
public static let actionHitSize = CGSize(width: 88, height: 44)
public static let bottomActionHitHeight: CGFloat = 44

public static func rightRailFrames(for width: CGFloat) -> (delete: CGRect, returnKey: CGRect) {
    let x = max(0, width - actionHitSize.width)
    return (
        CGRect(x: x, y: 0, width: 88, height: 44),
        CGRect(x: x, y: 44, width: 88, height: 44)
    )
}
~~~

Update KeyboardRootView identifiers to delete-backward, return-key, at-key, emoji-picker, number-layer, and letters-layer. Route delete/return/@ through existing proxy, emoji through local EmojiPickerView, 123 to existing number/symbol page, and ABC to .keys. Show disabled/error state when the existing owner is unavailable.

- [ ] **Step 4: Run GREEN and area tests**

~~~bash
swift test --package-path DictusCore --scratch-path /tmp/saiity-dictus-keyboard-actions-green --filter 'VoiceOnlyKeyboardPolicyTests|VoiceOnlyKeyboardContractTests|KeyboardAreaModeTests'
~~~
Expected: all selected tests PASS and area state remains single-source.

- [ ] **Step 5: Build keyboard target**

~~~bash
xcodebuild build -project Dictus.xcodeproj -scheme DictusKeyboard -destination 'generic/platform=iOS' -derivedDataPath /tmp/saiity-dictus-keyboard-actions-device CODE_SIGNING_ALLOWED=NO
~~~
Expected: ** BUILD SUCCEEDED **.

## Task 3: Responsive UIKit-Backed Next/Dismiss Controls

**Files:**
- Modify: DictusKeyboard/KeyboardViewController.swift
- Modify: DictusKeyboard/KeyboardRootView.swift
- Modify: DictusKeyboard/KeyboardState.swift
- Modify: DictusCore/Sources/DictusCore/VoiceOnlyKeyboardPolicy.swift
- Modify: DictusCore/Tests/DictusCoreTests/VoiceOnlyKeyboardPolicyTests.swift
- Modify: DictusCore/Tests/DictusCoreTests/VoiceOnlyKeyboardContractTests.swift

**Interfaces:**
- Add makeKeyboardActionButton(identifier:label:minimumHeight:action:) -> UIButton to the existing controller.
- next calls existing advanceToNextInputMode(); dismiss calls existing dismissal callback.
- UIButton frames are at least 44pt high with stable identifiers/labels, pressed state, and disabled/error state.

- [ ] **Step 1: Write failing minimum-hit test**

~~~swift
func testBottomActionsDeclareUIKitMinimumHitHeight() {
    XCTAssertGreaterThanOrEqual(VoiceOnlyKeyboardPolicy.bottomActionHitHeight, 44)
    XCTAssertEqual(VoiceOnlyKeyboardPolicy.surfaceHeight, 216)
}
~~~

- [ ] **Step 2: Run RED**

~~~bash
swift test --package-path DictusCore --scratch-path /tmp/saiity-dictus-responsive-red --filter VoiceOnlyKeyboardContractTests/testBottomActionsDeclareUIKitMinimumHitHeight
~~~
Expected: FAIL until the policy and UIKit bridge exist.

- [ ] **Step 3: Add real UIKit button bridge**

~~~swift
func makeKeyboardActionButton(
    identifier: String,
    label: String,
    minimumHeight: CGFloat = 44,
    action: @escaping () -> Void
) -> UIButton {
    let button = UIButton(type: .system)
    button.accessibilityIdentifier = identifier
    button.accessibilityLabel = label
    button.configuration = .plain()
    button.configuration?.contentInsets = .zero
    button.translatesAutoresizingMaskIntoConstraints = false
    button.addAction(UIAction { _ in action() }, for: .primaryActionTriggered)
    button.heightAnchor.constraint(greaterThanOrEqualToConstant: minimumHeight).isActive = true
    return button
}
~~~

Install real UIButtons in the existing input hierarchy, preserve separate regions, and let SwiftUI style only the visual content. The SwiftUI gesture must not be the only action path.

- [ ] **Step 4: Verify responsive widths and build**

~~~bash
swift test --package-path DictusCore --scratch-path /tmp/saiity-dictus-responsive-green --filter 'VoiceOnlyKeyboardPolicyTests|VoiceOnlyKeyboardContractTests'
xcodebuild build -project Dictus.xcodeproj -scheme DictusKeyboard -destination 'generic/platform=iOS' -derivedDataPath /tmp/saiity-dictus-responsive-device CODE_SIGNING_ALLOWED=NO
~~~
Expected: tests PASS and build SUCCEEDED; widths 320, 375, 390, 430 retain 216pt height, centered microphone, non-overlapping rails, and bottom controls at least 44pt.

## Task 4: Automatic(System) Default and Safe French Migration

**Files:**
- Modify: DictusCore/Sources/DictusCore/SupportedLanguage.swift
- Modify: DictusCore/Sources/DictusCore/SharedKeys.swift
- Create: DictusCore/Tests/DictusCoreTests/KeyboardLanguagePreferenceTests.swift
- Modify: DictusCore/Tests/DictusCoreTests/SupportedLanguageActivationTests.swift
- Modify: DictusKeyboard/KeyboardRootView.swift
- Modify: DictusApp/Views/SettingsView.swift only if it owns the existing keyboard-language setting

**Interfaces:**
- Add KeyboardLanguageSelection: Equatable, Codable, Sendable with .automatic and .explicit(SupportedLanguage).
- Add SupportedLanguage.fromSystem(locale:) -> SupportedLanguage.
- Add KeyboardLanguageSelection.resolve(locale:defaults:) -> SupportedLanguage, load(from:) -> Self, persist(to:), and migrateLegacyFrenchIfNeeded(in:).
- Never write or reinterpret SharedKeys.transcriptionLanguage during migration.

- [ ] **Step 1: Write failing locale/persistence/migration tests**

~~~swift
final class KeyboardLanguagePreferenceTests: XCTestCase {
    private func values() -> UserDefaults {
        let result = UserDefaults(suiteName: "dictus.plan.keyboard-language-tests")!
        result.removePersistentDomain(forName: "dictus.plan.keyboard-language-tests")
        return result
    }

    func testAutomaticUsesSystemLocale() {
        XCTAssertEqual(KeyboardLanguageSelection.resolve(locale: Locale(identifier: "de-DE"), defaults: values()), .german)
        XCTAssertEqual(KeyboardLanguageSelection.resolve(locale: Locale(identifier: "en-US"), defaults: values()), .english)
    }

    func testExplicitFrenchWinsAfterLocaleChanges() {
        let defaults = values()
        KeyboardLanguageSelection.explicit(.french).persist(to: defaults)
        XCTAssertEqual(KeyboardLanguageSelection.resolve(locale: Locale(identifier: "en-US"), defaults: defaults), .french)
    }

    func testImplicitLegacyFrenchBecomesAutomaticWithoutTouchingSTT() {
        let defaults = values()
        defaults.set("fr", forKey: SharedKeys.language)
        KeyboardLanguageSelection.migrateLegacyFrenchIfNeeded(in: defaults)
        XCTAssertEqual(KeyboardLanguageSelection.load(from: defaults), .automatic)
        XCTAssertNil(defaults.string(forKey: SharedKeys.transcriptionLanguage))
    }

    func testExplicitFrenchMigrationIsPreservedAndIdempotent() {
        let defaults = values()
        KeyboardLanguageSelection.explicit(.french).persist(to: defaults)
        KeyboardLanguageSelection.migrateLegacyFrenchIfNeeded(in: defaults)
        KeyboardLanguageSelection.migrateLegacyFrenchIfNeeded(in: defaults)
        XCTAssertEqual(KeyboardLanguageSelection.load(from: defaults), .explicit(.french))
    }
}
~~~

- [ ] **Step 2: Run RED**

~~~bash
swift test --package-path DictusCore --scratch-path /tmp/saiity-dictus-language-migration-red --filter KeyboardLanguagePreferenceTests
~~~
Expected: FAIL because selection type and functions are absent.

- [ ] **Step 3: Implement minimal preference and migration**

Add SharedKeys.keyboardLanguageSelection and keyboardLanguageMigrationVersion. Use key presence as explicit-choice evidence. Missing selection plus legacy language == "fr" and no explicit evidence becomes .automatic once; explicit .french remains explicit. Map fr/en/es/de from Locale.language.languageCode with English fallback.

~~~swift
public enum KeyboardLanguageSelection: Equatable, Codable, Sendable {
    case automatic
    case explicit(SupportedLanguage)

    public static func resolve(locale: Locale, defaults: UserDefaults) -> SupportedLanguage {
        switch load(from: defaults) {
        case .automatic: return SupportedLanguage.fromSystem(locale: locale)
        case .explicit(let language): return language
        }
    }
}
~~~

Migration is lazy/idempotent through shared defaults and never alters SharedKeys.transcriptionLanguage.

- [ ] **Step 4: Run migration and existing language tests**

~~~bash
swift test --package-path DictusCore --scratch-path /tmp/saiity-dictus-language-migration-green --filter 'KeyboardLanguagePreferenceTests|SupportedLanguageActivationTests|TranscriptionLanguageModeTests'
~~~
Expected: all selected tests PASS; locale, explicit persistence, French idempotence, and STT separation are proven.

- [ ] **Step 5: Wire display/settings**

Use resolve(locale:defaults:) for initial layout/language display, show Automatic (System) for automatic selection, persist explicit choices at the existing action, and keep transcription reads/writes on TranscriptionLanguageMode only.

- [ ] **Step 6: Run full shared suite**

~~~bash
swift test --package-path DictusCore --scratch-path /tmp/saiity-dictus-keyboard-language-final
~~~
Expected: full suite PASS with 0 failures and no disabled tests.

## Task 5: Integration, Signed Physical iPhone Acceptance, and Release Gate

**Files:**
- Modify: no production files unless a concrete Task 1-4 integration failure requires a focused fix.
- Test: focused suites from Tasks 1-4.
- Record: docs/superpowers/evidence/2026-08-30-keyboard-actions-and-language-acceptance.md only after a real device session.

**Interfaces:**
- Evidence identifies device, build commit, signed installation, and each checked behavior.
- Host/simulator evidence is supplemental and cannot complete the physical gate.
- No TestFlight upload/export/submission is part of this plan.

- [ ] **Step 1: Run focused integration tests**

~~~bash
swift test --package-path DictusCore --scratch-path /tmp/saiity-dictus-keyboard-integration --filter 'DictationLanguageRequestTests|KeyboardLanguagePreferenceTests|VoiceOnlyKeyboardPolicyTests|VoiceOnlyKeyboardContractTests|KeyboardAreaModeTests|DictationStatusTests'
~~~
Expected: all selected tests PASS for capability truth, independent targets, request persistence, migration, geometry, commands, and acknowledgement ordering.

- [ ] **Step 2: Build signed app and keyboard**

~~~bash
xcodebuild build -project Dictus.xcodeproj -scheme DictusApp -configuration Debug -destination 'generic/platform=iOS' -derivedDataPath /tmp/saiity-dictus-keyboard-signed CODE_SIGNING_ALLOWED=YES -allowProvisioningUpdates
xcodebuild build -project Dictus.xcodeproj -scheme DictusKeyboard -configuration Debug -destination 'generic/platform=iOS' -derivedDataPath /tmp/saiity-dictus-keyboard-signed CODE_SIGNING_ALLOWED=YES -allowProvisioningUpdates
~~~
Expected: both report ** BUILD SUCCEEDED ** and signed products exist under /tmp/saiity-dictus-keyboard-signed/Build/Products/Debug-iphoneos/.

- [ ] **Step 3: Install signed app on a physical iPhone**

~~~bash
xcrun devicectl list devices
DEVICE_UDID="$(xcrun devicectl list devices | awk '/available/ {print $3; exit}')"
xcrun devicectl device install app --device "$DEVICE_UDID" /tmp/saiity-dictus-keyboard-signed/Build/Products/Debug-iphoneos/DictusApp.app
~~~
Expected: an available physical device is listed and installation succeeds. If none is available, record physical gate unverified; do not substitute a simulator or upload to TestFlight.

- [ ] **Step 4: Execute and record physical acceptance**

In a real host text field, record PASS/FAIL for keyboard activation; Automatic (System); explicit persistence after locale change; truthful AUTO/fixed source; Transcribe; Translate selection; independent ready/unready target submenu; hold/release recording; final transcription/translation when available; insertion acknowledgement; delete; return; @; local emoji picker; 123; ABC; next; dismiss; interruption/background return; recoverable permission/microphone/model/timeout/translation/insertion/dismissal errors; collision-free 216pt surface; 88x44 and 44pt controls; light/dark; large Dynamic Type; VoiceOver; Reduce Motion; Reduce Transparency; Increased Contrast.

Expected: every applicable item PASS with evidence. Unsupported translation shows an explicit recoverable path and leaves original final text available.

- [ ] **Step 5: Verify hygiene and release gate**

~~~bash
git diff --check
git status --short --branch
~~~
Expected: no whitespace errors and existing dirty/untracked files remain. Only recorded physical acceptance can complete this gate. Do not run TestFlight commands.

## Self-Review Before Implementation Handoff

- [ ] Spec coverage: Task 1 covers ASR truth, independent targets, request propagation, App final hook, fallback, and no extension translation; Task 2 covers all actions and area authority; Task 3 covers UIKit controls, accessibility, and responsive geometry; Task 4 covers Automatic(System), locale mapping, persistence, French migration/idempotence, and STT separation; Task 5 covers integration, signed install, physical acceptance, and TestFlight prohibition.
- [ ] Placeholder scan: run `rg -n -i 'TBD|fill in|implement later|similar to task' docs/superpowers/plans/2026-08-30-keyboard-actions-and-language-implementation.md`; expected output is empty.
- [ ] Type consistency: DictationLanguageRequest.mode is TranscriptionLanguageMode; translationTarget and ASRCapability.sourceLanguage are SupportedLanguage?; KeyboardLanguageSelection is distinct from transcription mode; KeyboardCommand remains proxy source.
- [ ] Scope review: no new Manager/Service/Protocol/Factory/Strategy/Adapter/Coordinator/Provider/Resolver/Registry; existing owners remain responsible for recording, model readiness, proxy insertion, emoji, number layer, and lifecycle.

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-08-30-keyboard-actions-and-language-implementation.md`. Two execution options:

1. **Subagent-Driven (recommended)**: dispatch a fresh worker per task and review between tasks.
2. **Inline Execution**: execute the tasks in this session with checkpoints.

The implementer must use `superpowers:subagent-driven-development` for option 1 or `superpowers:executing-plans` for option 2, and must keep the physical-iPhone/TestFlight gate from Task 5.
