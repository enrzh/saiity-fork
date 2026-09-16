import Foundation
import XCTest

final class AppleAppFoundationContractTests: XCTestCase {
    private var repository: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    func testFullAccessHandshakeUsesADeclaredDarwinNotificationAndCrossProcessRefresh() throws {
        let notifications = try source("DictusCore/Sources/DictusCore/DarwinNotifications.swift")
        let keyboard = try source("DictusKeyboard/KeyboardViewController.swift")
        let availability = try source("DictusApp/Onboarding/OnboardingView.swift")

        XCTAssertTrue(notifications.contains("keyboardFullAccessChanged"))
        XCTAssertTrue(keyboard.contains("publishFullAccessHandshake()"))
        XCTAssertTrue(keyboard.contains("AppGroup.defaults.set(hasFullAccess"))
        XCTAssertTrue(keyboard.contains("SharedKeys.onboardingFullAccessHandshakeDate"))
        XCTAssertTrue(keyboard.contains("DarwinNotificationCenter.post(DarwinNotificationName.keyboardFullAccessChanged)"))
        XCTAssertTrue(availability.contains("DarwinNotificationCenter.addObserver(for: DarwinNotificationName.keyboardFullAccessChanged)"))
        XCTAssertTrue(availability.contains("DarwinNotificationCenter.removeObserver(for: DarwinNotificationName.keyboardFullAccessChanged)"))
        XCTAssertTrue(availability.contains("refreshKeyboard()"))
        XCTAssertTrue(availability.contains("isCurrentFullAccessHandshake"))
        XCTAssertTrue(availability.contains("let status = KeyboardSetupStatus"))
        XCTAssertTrue(availability.contains("let installed = status.keyboardDetected"))
        XCTAssertFalse(availability.contains("AppGroup.defaults.removeObject(forKey: SharedKeys.onboardingFullAccessVerified)"))
        XCTAssertFalse(availability.contains("AppGroup.defaults.removeObject(forKey: SharedKeys.onboardingFullAccessHandshakeDate)"))
        XCTAssertFalse(availability.contains("AppGroup.defaults.set(false, forKey: SharedKeys.onboardingFullAccessVerified)"))
        XCTAssertTrue(availability.contains("ensureFullAccessProbe()"))
        XCTAssertTrue(availability.contains("fullAccessVerified = status.fullAccessVerified"))
        XCTAssertTrue(availability.contains("keyboardInstalled: inputModeInstalled"))
    }

    func testKeyboardSetupPagePassesHandshakeDateForDiagnostics() throws {
        let source = try source("DictusApp/Onboarding/KeyboardSetupPage.swift")

        XCTAssertTrue(source.contains("handshakeDate: fullAccessHandshakeDate > 0 ? Date(timeIntervalSince1970: fullAccessHandshakeDate) : nil"))
        XCTAssertTrue(source.contains("let status = KeyboardSetupStatus("))
        XCTAssertTrue(source.contains("keyboardDetected = status.keyboardDetected"))
        XCTAssertTrue(source.contains("keyboardInstalled: inputModeInstalled"))
        XCTAssertFalse(source.contains("keyboardDetected = inputModeInstalled"))
    }

    func testColorsUseSemanticSystemSourcesWithoutFixedLowContrast() throws {
        let colors = try String(contentsOf: repository.appending(path: "DictusCore/Sources/DictusCore/Design/DictusColors.swift"), encoding: .utf8)

        XCTAssertTrue(colors.contains("static let dictusAccent = Color.accentColor"))
        XCTAssertTrue(colors.contains("Color(.systemRed)"))
        XCTAssertTrue(colors.contains("Color(.systemGreen)"))
        XCTAssertTrue(colors.contains("Color(.secondaryLabel)"))
        XCTAssertFalse(colors.contains("Color.white.opacity(0.5)"))
        XCTAssertFalse(colors.contains("Color(white: 0.15).opacity(0.5)"))
    }

    func testAppExposesOnlyEnglishLocalization() throws {
        let infoData = try Data(contentsOf: repository.appending(path: "DictusApp/Info.plist"))
        let info = try XCTUnwrap(
            try PropertyListSerialization.propertyList(from: infoData, options: [], format: nil) as? [String: Any]
        )
        XCTAssertEqual(info["CFBundleLocalizations"] as? [String], ["en"])

        let catalogData = try Data(contentsOf: repository.appending(path: "DictusApp/Localizable.xcstrings"))
        let catalog = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: catalogData) as? [String: Any]
        )
        XCTAssertEqual(catalog["sourceLanguage"] as? String, "en")

        let strings = try XCTUnwrap(catalog["strings"] as? [String: Any])
        let localizationCodes = Set(strings.values.flatMap { value -> [String] in
            guard let entry = value as? [String: Any],
                  let localizations = entry["localizations"] as? [String: Any] else {
                return []
            }
            return Array(localizations.keys)
        })
        XCTAssertFalse(localizationCodes.contains("fr"))
    }

    func testTypographyUsesDynamicSystemTextStyles() throws {
        let typography = try String(contentsOf: repository.appending(path: "DictusCore/Sources/DictusCore/Design/DictusTypography.swift"), encoding: .utf8)

        XCTAssertTrue(typography.contains(".system(.title, weight: .bold)"))
        XCTAssertTrue(typography.contains(".system(.title3, weight: .semibold)"))
        XCTAssertTrue(typography.contains(".system(.body)"))
        XCTAssertTrue(typography.contains(".system(.caption)"))
        XCTAssertFalse(typography.contains(".system(size:"))
    }

    func testMainShellKeepsNativeTabsAndLetsTabViewOwnBottomSafeArea() throws {
        let mainTabView = try String(contentsOf: repository.appending(path: "DictusApp/Views/MainTabView.swift"), encoding: .utf8)

        XCTAssertTrue(mainTabView.contains("TabView(selection: $selectedTab)"))
        XCTAssertEqual(mainTabView.components(separatedBy: "NavigationStack {").count - 1, 2)
        XCTAssertEqual(mainTabView.components(separatedBy: ".tabItem {").count - 1, 2)
        XCTAssertFalse(mainTabView.contains("safeAreaInset"))
        XCTAssertFalse(mainTabView.contains("frame(height: 96)"))
        XCTAssertFalse(mainTabView.contains("padding(.bottom, 96"))
    }

    func testHomeSettingsActionSelectsTheSettingsTabTag() throws {
        let mainTabView = try source("DictusApp/Views/MainTabView.swift")

        XCTAssertFalse(mainTabView.contains("selectedTab = 1"))
        XCTAssertTrue(mainTabView.contains(".tabItem {\n                        Label(\"Settings\""))
        XCTAssertTrue(mainTabView.contains(".tag(1)"))
        XCTAssertFalse(mainTabView.contains("Label(\"Settings\", systemImage: \"slider.horizontal.3\")\n                    }\n                    .tag(2)"))
    }

    func testModelsAreAccessibleFromSpeakLibraryAndSettings() throws {
        let mainTabView = try source("DictusApp/Views/MainTabView.swift")
        let home = try source("DictusApp/Views/HomeView.swift")
        let settings = try source("DictusApp/Views/SettingsView.swift")

        XCTAssertTrue(mainTabView.contains("HomeView(modelManager:"))
        XCTAssertTrue(home.contains("ModelManagerView(modelManager: modelManager)"))
        XCTAssertFalse(home.contains("onModelsRequested"))
        XCTAssertFalse(home.contains("Open Models"))
        XCTAssertTrue(settings.contains("DefaultKeyboardModePicker()"))
        XCTAssertTrue(settings.contains("NavigationLink { ModelManagerView"))
    }

    func testHomeUsesOneReadinessSummaryAndExplicitCopyFeedback() throws {
        let home = try String(contentsOf: repository.appending(path: "DictusApp/Views/HomeView.swift"), encoding: .utf8)

        XCTAssertTrue(home.contains("readinessPanel"))
        XCTAssertTrue(home.contains("Label(\"Start dictation\""))
        XCTAssertTrue(home.contains("copy(item.text)"))
        XCTAssertTrue(home.contains("showCopiedFeedback"))
        XCTAssertTrue(home.contains("Label(\"Copied\""))
        XCTAssertTrue(home.contains("background(.regularMaterial"))
    }

    func testHomeExposesServiceToggleWhileLiveActivitySharesIt() throws {
        let home = try source("DictusApp/Views/HomeView.swift")
        let attributes = try source("DictusCore/Sources/DictusCore/DictusLiveActivityAttributes.swift")
        let activity = try source("DictusWidgets/DictusLiveActivity.swift")
        let intent = try source("DictusWidgets/StopStandbyIntent.swift")

        XCTAssertTrue(home.contains("Toggle(\"Keyboard dictation\", isOn: $serviceEnabled)"))
        XCTAssertTrue(home.contains("coordinator.enableKeyboardSession()"))
        XCTAssertTrue(home.contains("coordinator.disableKeyboardSession()"))
        XCTAssertTrue(home.contains("coordinator.cancelDictation()"))
        XCTAssertTrue(attributes.contains("serviceEnabled"))
        XCTAssertTrue(activity.contains("context.state.serviceEnabled"))
        XCTAssertTrue(intent.contains("activity.update"))
    }

    func testLiveActivityLockScreenKeepsSemanticForegroundOnSystemBackground() throws {
        let activity = try source("DictusWidgets/DictusLiveActivity.swift")
        guard let lockScreen = activity.components(separatedBy: "private func lockScreenView").last else {
            XCTFail("Missing lock screen Live Activity view")
            return
        }

        XCTAssertFalse(lockScreen.contains("foregroundColor(.white)"))
        XCTAssertTrue(lockScreen.contains("foregroundColor(.primary)"))
        XCTAssertTrue(lockScreen.contains("foregroundColor(.secondary)"))
    }

    func testLiveActivityUsesOwnBrandingWithoutLegacyLogoAssets() throws {
        let activity = try source("DictusWidgets/DictusLiveActivity.swift")
        XCTAssertFalse(activity.contains("Text(\"sAI\")"))
        XCTAssertFalse(activity.contains("MiniLogoBars"))
        XCTAssertFalse(activity.contains("DictusLogo"))
        XCTAssertTrue(activity.contains("private struct SaiityMark"))
        XCTAssertTrue(activity.contains("SaiityMark(size: 20)"))
        XCTAssertTrue(activity.contains("SaiityMark(size: 24)"))
        XCTAssertTrue(activity.contains("SaiityMark(size: 40)"))
        XCTAssertTrue(activity.contains("statusSymbol(for: context.state.phase)"))
    }

    func testRecordingIsModalAndExposesAccessibleRecoveryAndTranscriptStages() throws {
        let recording = try String(contentsOf: repository.appending(path: "DictusApp/Views/RecordingView.swift"), encoding: .utf8)

        XCTAssertTrue(recording.contains(".accessibilityAddTraits(.isModal)"))
        XCTAssertTrue(recording.contains("UIAccessibility.post(notification: .announcement"))
        XCTAssertTrue(recording.contains("Transcript"))
        XCTAssertTrue(recording.contains("textSelection(.enabled)"))
        XCTAssertTrue(recording.contains("Button(\"Try again\""))
        XCTAssertTrue(recording.contains("Button(action: dismissRecording)"))
        XCTAssertTrue(recording.contains("accessibilityLabel(\"Close dictation\")"))
    }

    func testDictationStatusViewUsesTheSameSemanticStateLanguage() throws {
        let dictation = try String(contentsOf: repository.appending(path: "DictusApp/DictationView.swift"), encoding: .utf8)

        XCTAssertTrue(dictation.contains("status.recordingLabel"))
        XCTAssertTrue(dictation.contains(".font(.subheadline)"))
        XCTAssertFalse(dictation.contains(".cornerRadius(12)"))
    }

    func testOnboardingUsesFourSemanticStagesAndOneSetupContainer() throws {
        let onboarding = try String(contentsOf: repository.appending(path: "DictusApp/Onboarding/OnboardingView.swift"), encoding: .utf8)

        XCTAssertTrue(onboarding.contains("enum OnboardingStage"))
        XCTAssertTrue(onboarding.contains("case welcome"))
        XCTAssertTrue(onboarding.contains("case permissions"))
        XCTAssertTrue(onboarding.contains("case availability"))
        XCTAssertTrue(onboarding.contains("case tryIt"))
        XCTAssertTrue(onboarding.contains("AvailabilityPage"))
        XCTAssertTrue(onboarding.contains("NavigationStack"))
        XCTAssertTrue(onboarding.contains("safeAreaInset(edge: .bottom"))
        let stepMarker = "accessibilityValue(Text(\"Step"
        XCTAssertTrue(onboarding.contains(stepMarker))
        XCTAssertFalse(onboarding.contains("@State private var completedSteps"))
        XCTAssertFalse(onboarding.contains("showsPolishPage"))
    }

    func testOnboardingAvailabilityKeepsEveryGateAndTruthfulModelProgress() throws {
        let onboarding = try String(contentsOf: repository.appending(path: "DictusApp/Onboarding/OnboardingView.swift"), encoding: .utf8)

        XCTAssertTrue(onboarding.contains("keyboardInstalled"))
        XCTAssertTrue(onboarding.contains("fullAccessVerified"))
        XCTAssertTrue(onboarding.contains("modelReady"))
        XCTAssertTrue(onboarding.contains("polishEnabled"))
        XCTAssertTrue(onboarding.contains("downloadProgress"))
        XCTAssertTrue(onboarding.contains("downloadByteInfo"))
        XCTAssertTrue(onboarding.contains("ModelLoadingOverlay"))
    }

    func testCleanupDefaultsToEnabledForNewUsers() throws {
        let app = try source("DictusApp/DictusApp.swift")
        let onboarding = try source("DictusApp/Onboarding/OnboardingView.swift")
        let polishPage = try source("DictusApp/Onboarding/PolishTogglePage.swift")
        let settings = try source("DictusApp/Views/SettingsView.swift")

        XCTAssertTrue(app.contains("defaults?.set(true, forKey: SharedKeys.polishEnabled)"))
        XCTAssertTrue(onboarding.contains("private var polishEnabled = true"))
        XCTAssertTrue(polishPage.contains("private var polishEnabled = true"))
        XCTAssertTrue(settings.contains("private var polishEnabled = true"))
    }

    func testCleanupBackendIsUserSelectableAppleIntelligenceOrOllama() throws {
        let coordinator = try source("DictusApp/Polish/PolishCoordinator.swift")
        let manager = try source("DictusApp/Models/ModelManager.swift")
        let models = try source("DictusApp/Views/ModelManagerView.swift")

        XCTAssertTrue(coordinator.contains("PolishSpanPipeline"))
        XCTAssertTrue(coordinator.contains("PolishCleanupBackend.load"))
        XCTAssertTrue(coordinator.contains("PolishCleanupBackend.resolvedEngine"))
        XCTAssertFalse(coordinator.contains("A valid custom Ollama cleanup registration takes precedence"))
        XCTAssertTrue(manager.contains("selectCleanupBackend"))
        XCTAssertTrue(manager.contains("SharedKeys.polishCleanupBackend") || manager.contains("cleanupBackend"))
        XCTAssertTrue(models.contains("dictationCleanupSection"))
        XCTAssertFalse(models.contains("Custom cleanup"))
    }

    func testCleanupMigrationEnablesUpgradeUsersWithoutOverwritingExplicitChoice() throws {
        let app = try source("DictusApp/DictusApp.swift")

        XCTAssertTrue(app.contains("defaults?.object(forKey: SharedKeys.polishEnabled) == nil"))
        XCTAssertTrue(app.contains("defaults?.set(true, forKey: SharedKeys.polishEnabled)"))
    }

    func testCleanupPromptsHandleSpokenSelfCorrections() throws {
        for path in [
            "DictusCore/Sources/DictusCore/Polish/Prompts/PolishAutoPrompt.swift",
            "DictusCore/Sources/DictusCore/Polish/Prompts/PolishNaturalPromptEN.swift",
            "DictusCore/Sources/DictusCore/Polish/Prompts/PolishNaturalPromptFR.swift",
            "DictusCore/Sources/DictusCore/Polish/Prompts/PolishNaturalPromptDE.swift",
            "DictusCore/Sources/DictusCore/Polish/Prompts/PolishNaturalPromptES.swift",
            "DictusCore/Sources/DictusCore/Polish/Prompts/PolishRepairPromptEN.swift",
            "DictusCore/Sources/DictusCore/Polish/Prompts/PolishRepairPromptFR.swift",
            "DictusCore/Sources/DictusCore/Polish/Prompts/PolishRepairPromptDE.swift",
            "DictusCore/Sources/DictusCore/Polish/Prompts/PolishRepairPromptES.swift"
        ] {
            let prompt = try source(path)
            XCTAssertTrue(prompt.contains("self-correction"), "Missing self-correction rule in \(path)")
            XCTAssertTrue(prompt.contains("abandoned fragment"), "Missing abandoned-fragment guard in \(path)")
        }
    }

    func testCleanupPromptsIncludeSpokenRestartAndFillerExample() throws {
        for path in [
            "DictusCore/Sources/DictusCore/Polish/Prompts/PolishAutoPrompt.swift",
            "DictusCore/Sources/DictusCore/Polish/Prompts/PolishNaturalPromptEN.swift"
        ] {
            let prompt = try source(path)
            XCTAssertTrue(prompt.contains("Hey Jack I got like a appointment at 2am"), "Missing restart example in \(path)")
            XCTAssertTrue(prompt.contains("Hey Jack, I got an appointment at 4am. Can you come by please?"), "Missing cleaned restart example in \(path)")
        }
    }

    func testOnboardingAllowsTrialBeforeHandshakeAndOffersFullAccessRecovery() throws {
        let onboarding = try source("DictusApp/Onboarding/OnboardingView.swift")
        let tutorial = try source("DictusApp/Onboarding/GlobeKeyTutorialPage.swift")

        XCTAssertTrue(onboarding.contains("keyboardStatus.keyboardDetected && modelReady"))
        XCTAssertFalse(onboarding.contains("keyboardInstalled && fullAccessVerified && modelReady"))
        XCTAssertTrue(onboarding.contains("switch to the sAiity keyboard and complete Full Access verification"))
        XCTAssertTrue(onboarding.contains("Open Keyboard Settings"))
        XCTAssertTrue(onboarding.contains("Full Access is verified only by the keyboard extension."))
        XCTAssertTrue(tutorial.contains("Return to setup"))
        XCTAssertTrue(tutorial.contains("Full Access required"))
        XCTAssertTrue(tutorial.contains("Open Settings"))
        XCTAssertTrue(tutorial.contains("AppGroup.defaults.bool(forKey: SharedKeys.onboardingFullAccessVerified)"))
        XCTAssertFalse(tutorial.contains("fullAccessVerified = true"))
    }

    func testGlobeTutorialKeepsModifiersInsideItsViewBody() throws {
        let tutorial = try source("DictusApp/Onboarding/GlobeKeyTutorialPage.swift")

        XCTAssertTrue(tutorial.contains(".padding(.vertical, 20)"))
        XCTAssertFalse(tutorial.contains(".padding(.vertical, 20)\n        }\n        }\n        .onAppear"))
    }

    func testOnboardingTrialDoesNotUseHiddenFieldOrArbitraryTextLengthAsSuccess() throws {
        let tutorial = try String(contentsOf: repository.appending(path: "DictusApp/Onboarding/GlobeKeyTutorialPage.swift"), encoding: .utf8)

        XCTAssertTrue(tutorial.contains("firstDictationVerified"))
        XCTAssertTrue(tutorial.contains("transcriptionReady"))
        XCTAssertTrue(tutorial.contains("accessibilityAnnouncement"))
        XCTAssertFalse(tutorial.contains("frame(height: 1)"))
        XCTAssertFalse(tutorial.contains("opacity(0)"))
        XCTAssertFalse(tutorial.contains("minTextLength"))
        XCTAssertFalse(tutorial.contains("skipTutorial"))
    }

    func testOnboardingDistinguishesInstalledAndCurrentlySelectedInputModes() throws {
        let tutorial = try source("DictusApp/Onboarding/GlobeKeyTutorialPage.swift")

        XCTAssertTrue(tutorial.contains("textView.textInputMode"),
                      "the tutorial must inspect the input source currently editing the field")
        XCTAssertTrue(tutorial.contains("UITextInputMode.activeInputModes"),
                      "the diagnostic must retain the installed/enabled input-source context")
        XCTAssertTrue(tutorial.contains("inputModeObserved"),
                      "the current input source must be visible in exported diagnostics")
        XCTAssertTrue(tutorial.contains("KeyboardSetupStatus.isDictusKeyboardIdentifier"),
                      "current-mode classification must use the tested bundle identity rule")
        XCTAssertTrue(tutorial.contains("dictusKeyboardActive = isDictus"),
                      "switching back to the native keyboard must clear the active state")
    }

    func testSettingsTaskFourUsesGroupedNativeSectionsAndShippedDestinations() throws {
        let settings = try source("DictusApp/Views/SettingsView.swift")

        for panel in ["Models", "Dictation", "Keyboard", "More"] {
            XCTAssertTrue(settings.contains("settingsPanel(\"\(panel)\""), "Missing settings panel: \(panel)")
        }
        XCTAssertTrue(settings.contains("Automatic cleanup"))
        XCTAssertTrue(settings.contains("if !validOllamaCleanupModels.isEmpty"))
        XCTAssertTrue(settings.contains("Picker(\"Cleanup model\""))
        XCTAssertTrue(settings.contains("cleanupBackendBinding"))
        XCTAssertTrue(settings.contains("Privacy Policy"))
        XCTAssertTrue(settings.contains("moreGroup(\"Help\")"))
        XCTAssertTrue(settings.contains("moreGroup(\"About\")"))
        XCTAssertTrue(settings.contains("settingsExternalRow"))
        XCTAssertFalse(settings.contains("font(.footnote.weight(.medium))"))
        XCTAssertTrue(settings.contains("NavigationLink { ModelManagerView"))
        XCTAssertFalse(settings.contains("NavigationLink { SoundSettingsView()"))
        XCTAssertTrue(settings.contains("NavigationLink { troubleshootingView }"))
        XCTAssertTrue(settings.contains("NavigationLink(\"Debug Logs\") { DebugLogView() }"))
        XCTAssertTrue(settings.contains("NavigationLink(\"Diagnostics\") { DiagnosticDetailView"))
        XCTAssertTrue(settings.contains("Section(\"On this iPhone\")"))
        XCTAssertTrue(settings.contains("Toggle("))
        XCTAssertFalse(settings.contains("Control order"))
        XCTAssertFalse(settings.contains("Transcript language"))
        XCTAssertFalse(settings.contains("Suggestions after dictation"))
        XCTAssertTrue(settings.contains("KeyPopupPicker()"))
        XCTAssertTrue(settings.contains("KeyboardMaterialPicker()"))
        XCTAssertTrue(settings.contains("DictationPresencePicker()"))
        XCTAssertTrue(settings.contains("Toggle(\"Key containers\""))
        XCTAssertFalse(settings.contains("Toggle(\"Liquid glass\""))
        XCTAssertFalse(settings.contains("Toggle(\"Live Activity\""))
        XCTAssertFalse(settings.contains("transcriptionOutputMode"))
        XCTAssertTrue(settings.contains("Keyboard layout"))
        XCTAssertTrue(settings.contains("TypingLanguagesPanel()"))
        XCTAssertTrue(settings.contains("secondarySystemGroupedBackground"))
        let languagePanel = try source("DictusApp/Views/KeyboardModePicker.swift")
        XCTAssertTrue(languagePanel.contains("ForEach(LayoutType.allCases"))
        XCTAssertTrue(languagePanel.contains("KeyboardLayoutPreference.setGlobalLayout"))
        XCTAssertFalse(languagePanel.contains("SupportedLanguage.activate(entry)"))
    }

    func testSecondaryScreensConfirmDestructiveActionsAndReportCopyOrExport() throws {
        let logs = try source("DictusApp/Views/DebugLogView.swift")
        let polish = try source("DictusApp/Polish/PolishDebugView.swift")
        let sounds = try source("DictusApp/Views/SoundSettingsView.swift")

        XCTAssertTrue(logs.contains("confirmationDialog"))
        XCTAssertTrue(logs.contains("showCopiedFeedback"))
        XCTAssertTrue(logs.contains("Clear logs"))
        XCTAssertTrue(polish.contains("confirmationDialog"))
        XCTAssertTrue(polish.contains("showExportedFeedback"))
        XCTAssertTrue(polish.contains("Clear polish diagnostics"))
        XCTAssertTrue(sounds.contains("Text(soundVolumeLabel"))
        XCTAssertTrue(sounds.contains("Enable sounds to configure"))
        XCTAssertFalse(logs.contains("ant.circle.fill"))
    }

    func testSecondaryContentUsesNativeScrollingAndPaywallKeepsAllPurchaseStates() throws {
        let diagnostic = try source("DictusApp/Views/DiagnosticDetailView.swift")
        let licenses = try source("DictusApp/Views/LicensesView.swift")
        let paywall = try source("DictusApp/Views/PaywallView.swift")
        let presentation = try source("DictusApp/Views/PaywallPresentation.swift")

        XCTAssertTrue(diagnostic.contains("List"))
        XCTAssertFalse(diagnostic.contains(".isModal"), "A pushed diagnostics page must not trap VoiceOver as a modal")
        XCTAssertTrue(diagnostic.contains(".accessibilityValue(passed ? \"OK\" : \"Failed\")"))
        XCTAssertTrue(licenses.contains("List"))
        XCTAssertTrue(licenses.contains("Section("))
        XCTAssertTrue(paywall.contains("purchaseState == .pending"))
        XCTAssertTrue(paywall.contains("Restore purchases"))
        XCTAssertTrue(paywall.contains("Terms of Service"))
        XCTAssertTrue(paywall.contains("Purchase Error"))
        XCTAssertTrue(paywall.contains("Loading plans"))
        XCTAssertFalse(paywall.contains("GlassPressStyle"))
        XCTAssertFalse(paywall.contains("blue glow"))
        XCTAssertTrue(presentation.contains("fullScreenCover"))
        XCTAssertTrue(presentation.contains("NavigationStack"))
    }

    func testModelsUseFullWidthCardsWithReadableMetadataAndActions() throws {
        let manager = try source("DictusApp/Views/ModelManagerView.swift")
        let card = try source("DictusApp/Views/ModelCardView.swift")

        XCTAssertFalse(manager.contains(".safeAreaInset"))
        XCTAssertTrue(manager.contains(".contentMargins(.bottom, 88, for: .scrollContent)"))
        XCTAssertFalse(manager.contains("Add custom model"))
        XCTAssertFalse(manager.contains("showAddModel"))
        XCTAssertFalse(manager.contains("AddCustomModelView"))
        XCTAssertFalse(manager.contains(".swipeActions"))
        XCTAssertFalse(manager.contains(".listRowSeparator(.visible)"))
        XCTAssertTrue(manager.contains(".listRowSeparator(.hidden)"))
        XCTAssertEqual(
            manager.components(separatedBy: ".listSectionSeparator(.hidden)").count - 1,
            3,
            "Installed, Available, and Dictation cleanup should not render section rules"
        )
        XCTAssertTrue(manager.contains("Dictation cleanup"))
        XCTAssertTrue(manager.contains("Apple Intelligence"))
        XCTAssertTrue(manager.contains("selectCleanupBackend(.appleIntelligence)"))
        XCTAssertTrue(manager.contains("On-device Foundation Models"))
        XCTAssertFalse(card.contains("actionColumnWidth"))
        XCTAssertTrue(card.contains("languageSupport.coverage.localizedSummary"))
        XCTAssertTrue(card.contains("cancelCatalogDownload(model.identifier)"))
        XCTAssertTrue(card.contains(".buttonStyle(.borderedProminent)"))
        XCTAssertTrue(card.contains(".font(.subheadline)"))
        XCTAssertTrue(card.contains("GaugeBarView(value: model.accuracyScore, label: \"Accuracy\""))
        XCTAssertTrue(card.contains("GaugeBarView(value: model.speedScore, label: \"Speed\""))
        XCTAssertTrue(card.contains("Text(\"Accuracy \\"))
        XCTAssertTrue(card.contains("Text(\"Speed \\"))
        XCTAssertFalse(card.contains(".opacity(incompatibilityReason == nil ? 1 : 0.55)"))
    }

    func testModelRowsKeepEveryStateAndDeterminateProgressReadable() throws {
        let card = try source("DictusApp/Views/ModelCardView.swift")

        for label in ["Not installed", "Downloading", "Preparing", "Active", "Installed", "Failed", "Unavailable"] {
            XCTAssertTrue(card.contains("\"\(label)"), "Missing model state label: \(label)")
        }
        XCTAssertTrue(card.contains("downloadProgressLabel"))
        XCTAssertTrue(card.contains("downloadByteInfo"))
        XCTAssertTrue(card.contains("accessibilityValue"))
    }

    func testSettingsListKeepsLastSectionAboveFloatingTabBar() throws {
        let settings = try source("DictusApp/Views/SettingsView.swift")

        XCTAssertFalse(settings.contains(".safeAreaInset"))
        XCTAssertTrue(settings.contains(".padding(.bottom, 110)"))
    }

    func testModelDeletionIsVisibleAndStillUsesParentConfirmation() throws {
        let manager = try source("DictusApp/Views/ModelManagerView.swift")
        let card = try source("DictusApp/Views/ModelCardView.swift")

        XCTAssertTrue(card.contains("Label(\"Delete\", systemImage: \"trash\")"))
        XCTAssertFalse(card.contains("private var deletionMenu"))
        XCTAssertTrue(card.contains("onDeleteRequest?()"))
        XCTAssertTrue(manager.contains("Delete \\(model.displayName)?"))
        XCTAssertTrue(manager.contains("Button(\"Delete\", role: .destructive)"))
    }

    func testLanguageDetailUsesScannableNativeRowsAndSemanticQualityLabels() throws {
        let detail = try source("DictusApp/Views/ModelLanguageDetailView.swift")

        XCTAssertTrue(detail.contains("languageRows"))
        XCTAssertTrue(detail.contains("ForEach(languageRows"))
        XCTAssertTrue(detail.contains("Good quality"))
        XCTAssertTrue(detail.contains("Fair quality"))
        XCTAssertTrue(detail.contains("Limited quality"))
        XCTAssertTrue(detail.contains("Quality measured on the large Whisper models"))
        XCTAssertTrue(detail.contains("accessibilityLabel(\"Close language support\")"))
    }

    func testModelLoadingOverlayUsesStableProgressAndSemanticPreparationStages() throws {
        let overlay = try source("DictusApp/Views/ModelLoadingOverlay.swift")

        XCTAssertTrue(overlay.contains("progressLabel"))
        XCTAssertTrue(overlay.contains("downloadByteInfo"))
        XCTAssertTrue(overlay.contains("phaseRow(\"Prepare\""))
        XCTAssertTrue(overlay.contains("Optimizing"))
        XCTAssertTrue(overlay.contains("Loading"))
        XCTAssertTrue(overlay.contains("Return to your app and hold the keyboard microphone to dictate."),
                      "foreground preparation must lead back to direct keyboard holds")
        XCTAssertTrue(overlay.contains("coordinator.keyboardSessionEnabled && coordinator.isEngineRunning"),
                      "model readiness alone must not complete microphone preparation")
        XCTAssertTrue(overlay.contains(".onChange(of: coordinator.status)"),
                      "microphone preparation failures must dismiss the blocking cover")
        XCTAssertTrue(overlay.contains(".onChange(of: coordinator.isPreparingKeyboardSession)"),
                      "warm model preparation must still observe microphone activation")
        XCTAssertFalse(overlay.contains("Return to your app and tap the microphone again."),
                       "idle audio cannot cold-start background dictation")
        XCTAssertTrue(overlay.contains(".accessibilityAddTraits(.isModal)"))
    }

    func testKeyboardLivenessSeparatesAudioReadinessFromRecoveryAction() throws {
        let state = try source("DictusKeyboard/KeyboardState.swift")
        let keys = try source("DictusCore/Sources/DictusCore/SharedKeys.swift")
        let audio = try source("DictusApp/Audio/UnifiedAudioEngine.swift")
        let keyboard = try source("DictusKeyboard/KeyboardViewController.swift")
        let root = try source("DictusKeyboard/KeyboardRootView.swift")

        XCTAssertTrue(keys.contains("keyboardAudioReady"))
        XCTAssertTrue(state.contains("let serviceNeedsRecovery = DictationServiceLivenessPolicy.shouldOfferRecovery("))
        XCTAssertTrue(state.contains("appNeedsServiceRecovery = needsServiceRecovery"))
        XCTAssertTrue(state.contains("appNeedsAppAction = needsModelPreparation || !serviceEnabled || needsServiceRecovery"),
                      "a ready model still needs a recovery action when the audio engine is unavailable")
        XCTAssertTrue(audio.contains("AppGroup.defaults.set(isHealthy, forKey: SharedKeys.keyboardAudioReady)"))
        XCTAssertTrue(keyboard.contains("openDictusForRecovery()"),
                      "the visible recovery target must use the same URL handoff as the Link")
        XCTAssertTrue(root.contains("Link(destination: preparationURL)"),
                      "SwiftUI remains the accessibility/fallback recovery surface")
        XCTAssertTrue(root.contains("SuggestionBarIconButton("))
        XCTAssertTrue(root.contains("action: routeDismiss"))
        let app = try source("DictusApp/DictusApp.swift")
        XCTAssertTrue(app.contains("if serviceEnabled {\n                        coordinator.enableKeyboardSession()"),
                      "enabled keyboard dictation must be re-armed when the app process starts")
    }

    func testAccessoryRelayoutKeepsTheActiveMicFrameAndUsesTheSharedTopLane() throws {
        let controller = try source("DictusKeyboard/KeyboardViewController.swift")
        let root = try source("DictusKeyboard/KeyboardRootView.swift")
        let policy = try source("DictusCore/Sources/DictusCore/VoiceOnlyKeyboardPolicy.swift")

        XCTAssertTrue(controller.contains("micButton?.frame = .zero"),
                      "an unavailable mic frame must not leave a stale touch interceptor behind")
        XCTAssertTrue(controller.contains("topAccessoryHeight: currentSuggestionLaneHeight"))
        XCTAssertTrue(root.contains("topAccessoryHeight: VoiceOnlyKeyboardPolicy.suggestionLaneHeight"))
        XCTAssertTrue(policy.contains("public static let suggestionLaneHeight: Double = 36"))
    }

    func testKeyboardEmojiAndCategoryTargetsUseCompactVisualsAndNativeHitOwners() throws {
        let picker = try source("DictusKeyboard/Views/EmojiPickerView.swift")
        let categories = try source("DictusKeyboard/Views/EmojiCategoryBar.swift")

        XCTAssertTrue(picker.contains("private var rowHeight: CGFloat"))
        XCTAssertTrue(picker.contains("UICollectionView"),
                      "emoji interaction must be owned by native collection cells")
        XCTAssertFalse(picker.contains("TabView("))
        XCTAssertFalse(picker.contains("ScrollView(.vertical"))
        XCTAssertTrue(picker.contains("for row in 0..<4"),
                      "emoji pages must have four rows")
        XCTAssertTrue(picker.contains("private let edgeInset: CGFloat = VoiceOnlyKeyboardPolicy.keyGridInset"))
        XCTAssertTrue(picker.contains("private let rowSpacing: CGFloat"))
        XCTAssertTrue(picker.contains("emojiKeySpacing"))
        XCTAssertFalse(picker.contains("Search Emoji"))
        XCTAssertFalse(categories.contains("keyboardGlass(in:"),
                       "category bookmarks must not add a nested glass well inside the suggestion lane")
        XCTAssertFalse(categories.contains("glassEffect"))
        XCTAssertTrue(categories.contains("EmojiCategoryScrubControl"))
        XCTAssertTrue(categories.contains("emojiCategoryHorizontalInset"))
        XCTAssertTrue(categories.contains("scrubbingEnabled"))
        XCTAssertFalse(categories.contains("magnifyingglass"))
    }

    func testGlobeTutorialRefreshesFullAccessAfterKeyboardHandshake() throws {
        let tutorial = try source("DictusApp/Onboarding/GlobeKeyTutorialPage.swift")

        XCTAssertTrue(tutorial.contains("scenePhase"))
        XCTAssertTrue(tutorial.contains("refreshFullAccess()"))
        XCTAssertTrue(tutorial.contains("DarwinNotificationCenter.addObserver(for: DarwinNotificationName.keyboardFullAccessChanged)"))
        XCTAssertTrue(tutorial.contains("DarwinNotificationCenter.removeObserver(for: DarwinNotificationName.keyboardFullAccessChanged)"))
        XCTAssertTrue(tutorial.contains("DispatchQueue.main.async"))
        XCTAssertTrue(tutorial.contains("AppGroup.defaults.bool(forKey: SharedKeys.onboardingFullAccessVerified)"))
        XCTAssertTrue(tutorial.contains("fullAccessRequired = false"))
        XCTAssertTrue(tutorial.contains("dictationFailed = false"))
        XCTAssertTrue(tutorial.contains("sAiity keyboard is active. Tap the microphone to dictate."))
    }

    func testGlobeTutorialDoesNotStackGenericFailureReturnWithFullAccessRecovery() throws {
        let tutorial = try source("DictusApp/Onboarding/GlobeKeyTutorialPage.swift")

        XCTAssertTrue(tutorial.contains("if fullAccessRequired {"))
        XCTAssertTrue(tutorial.contains("Button(\"Open Settings\", action: openSettings)"))
        XCTAssertTrue(tutorial.contains("if dictationFailed && !fullAccessRequired {"))
    }

    func testOnboardingArmsKeyboardSessionAfterModelInstallAndOnTryIt() throws {
        let availability = try source("DictusApp/Onboarding/OnboardingView.swift")
        let tutorial = try source("DictusApp/Onboarding/GlobeKeyTutorialPage.swift")

        XCTAssertTrue(availability.contains("coordinator.enableKeyboardSession()"))
        XCTAssertTrue(tutorial.contains("coordinator.enableKeyboardSession()"))
    }

    func testSuggestionLaneHasNoBackgroundBarBehindControls() throws {
        let root = try source("DictusKeyboard/KeyboardRootView.swift")

        XCTAssertFalse(root.contains("accessoryLaneBackground"))
        XCTAssertFalse(root.contains("insetGlassPanel"))
        XCTAssertFalse(root.contains("insetPanelFrame"))
        XCTAssertFalse(root.contains("glassEffect(.regular, in: Rectangle())"))
    }

    func testMissingModelErrorDirectsUsersToSettingsModels() throws {
        let speechModelProtocol = try source("DictusApp/Audio/SpeechModelProtocol.swift")

        XCTAssertTrue(speechModelProtocol.contains("Open sAiity and download it in Settings > Models."))
        XCTAssertFalse(speechModelProtocol.contains("in the Models tab"))
    }

    func testKeyPopupPickerOffersOffPopupAndPopout() throws {
        let picker = try source("DictusApp/Views/KeyboardModePicker.swift")
        let mode = try source("DictusCore/Sources/DictusCore/KeyPopupMode.swift")

        XCTAssertTrue(picker.contains("struct KeyPopupPicker: View"))
        XCTAssertTrue(picker.contains("ForEach(KeyPopupMode.allCases"))
        XCTAssertTrue(mode.contains("case off"))
        XCTAssertTrue(mode.contains("case popup"))
        XCTAssertTrue(mode.contains("case popout"))
        XCTAssertTrue(mode.contains("return \"Off\""))
        XCTAssertTrue(mode.contains("return \"Popup\""))
        XCTAssertTrue(mode.contains("return \"Popout\""))
    }

    func testDictationPresenceDoesNotUsePictureInPicture() throws {
        let manager = try source("DictusApp/LiveActivityManager.swift")
        let mode = try source("DictusCore/Sources/DictusCore/DictationPresenceMode.swift")

        XCTAssertFalse(manager.contains("AVPictureInPicture"))
        XCTAssertFalse(manager.contains("DictationPictureInPicture"))
        XCTAssertFalse(mode.contains("case pictureInPicture"))
    }

    private func source(_ path: String) throws -> String {
        try String(contentsOf: repository.appending(path: path), encoding: .utf8)
    }
}
