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
        let notifications = try source("SyllivraKernel/Sources/SyllivraKernel/DarwinNotifications.swift")
        let keyboard = try source("DictusKeyboard/KeyboardViewController.swift")
        let availability = try source("DictusApp/Onboarding/KeyboardSetupPage.swift")

        XCTAssertTrue(notifications.contains("keyboardFullAccessChanged"))
        XCTAssertTrue(keyboard.contains("publishFullAccessHandshake()"))
        XCTAssertTrue(keyboard.contains("let granted = hasFullAccess"))
        XCTAssertTrue(keyboard.contains("guard isAttached, isOnScreen"))
        XCTAssertTrue(keyboard.contains("SharedKeys.onboardingFullAccessHandshakeDate"))
        XCTAssertTrue(keyboard.contains("DarwinNotificationCenter.post(DarwinNotificationName.keyboardFullAccessChanged)"))
        XCTAssertTrue(availability.contains("DarwinNotificationCenter.addObserver(for: DarwinNotificationName.keyboardFullAccessChanged)"))
        XCTAssertTrue(availability.contains("static let shared = KeyboardSetupModel()"))
        XCTAssertTrue(availability.contains("DarwinNotificationName.keyboardFullAccessDenied"))
        XCTAssertTrue(availability.contains("Self.shared.refresh()"))
        XCTAssertTrue(availability.contains("isCurrentFullAccessHandshake"))
        XCTAssertTrue(availability.contains("keyboardInstalled = installed || verified"))
        XCTAssertFalse(availability.contains("AppGroup.defaults.removeObject(forKey: SharedKeys.onboardingFullAccessVerified)"))
        XCTAssertFalse(availability.contains("AppGroup.defaults.removeObject(forKey: SharedKeys.onboardingFullAccessHandshakeDate)"))
        XCTAssertTrue(availability.contains("AppGroup.defaults.set(false, forKey: SharedKeys.onboardingFullAccessVerified)"), "an explicit denied event must clear the old permission result")
        XCTAssertTrue(availability.contains("func beginVerification()"))
        XCTAssertTrue(availability.contains("fullAccessVerified = verified"))
        XCTAssertTrue(availability.contains("AppGroup.defaults.synchronize()"))
    }

    func testKeyboardSetupPagePassesHandshakeDateForDiagnostics() throws {
        let source = try source("DictusApp/Onboarding/KeyboardSetupPage.swift")

        let keyboard = try self.source("DictusKeyboard/KeyboardViewController.swift")
        XCTAssertTrue(keyboard.contains("SharedKeys.onboardingFullAccessHandshakeDate"))
        XCTAssertTrue(source.contains("isCurrentFullAccessHandshake"))
        XCTAssertTrue(source.contains("while !Task.isCancelled && !setup.fullAccessVerified"))
        XCTAssertTrue(source.contains("setup.requestProbe()"))
        XCTAssertTrue(source.contains(".task(id: checkingKeyboard && scenePhase == .active)"))
    }

    func testVisibleOnboardingAvailabilityPageRefreshesAfterReturningFromSettings() throws {
        let source = try source("DictusApp/Onboarding/KeyboardSetupPage.swift")

        XCTAssertTrue(source.contains("KeyboardSetupModel: ObservableObject"))
        XCTAssertTrue(source.contains("DarwinNotificationCenter.addObserver(for: DarwinNotificationName.keyboardFullAccessChanged)"))
        XCTAssertTrue(source.contains("if returningFromSettings { checkingKeyboard = true"))
        XCTAssertTrue(source.contains(".onChange(of: scenePhase)"))
        XCTAssertTrue(source.contains("Task.sleep(for: .seconds(1))"))
        XCTAssertTrue(source.contains("!setup.fullAccessVerified"))
    }

    func testColorsUseSemanticSystemSourcesWithoutFixedLowContrast() throws {
        let colors = try String(contentsOf: repository.appending(path: "SyllivraKernel/Sources/SyllivraKernel/Design/DictusColors.swift"), encoding: .utf8)

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
        let typography = try String(contentsOf: repository.appending(path: "SyllivraKernel/Sources/SyllivraKernel/Design/DictusTypography.swift"), encoding: .utf8)

        XCTAssertTrue(typography.contains(".system(.title, weight: .bold)"))
        XCTAssertTrue(typography.contains(".system(.title3, weight: .semibold)"))
        XCTAssertTrue(typography.contains(".system(.body)"))
        XCTAssertTrue(typography.contains(".system(.caption)"))
        XCTAssertFalse(typography.contains(".system(size:"))
    }

    func testRootIsOneNavigationStackWithoutTabs() throws {
        let root = try source("DictusApp/Views/RootView.swift")

        XCTAssertEqual(root.components(separatedBy: "NavigationStack {").count - 1, 1)
        XCTAssertTrue(root.contains("HomeView(modelManager: modelManager)"))
        XCTAssertFalse(root.contains("TabView"))
        XCTAssertFalse(root.contains("safeAreaInset"))
    }

    func testHomeReachesEverySettingsPage() throws {
        let home = try source("DictusApp/Views/HomeView.swift")
        let settings = try source("DictusApp/Views/SettingsView.swift")

        for destination in ["ModelManagerView(modelManager: modelManager)", "DictationSettingsView(modelManager: modelManager)",
                            "KeyboardSettingsView()", "DictationHistoryView()", "HelpView()", "AboutView()"] {
            XCTAssertTrue(home.contains(destination), "Home must reach \(destination)")
        }
        XCTAssertFalse(home.contains("VoiceOptionsView"), "Voice models are chosen in one place, Models")
        XCTAssertFalse(home.contains("onModelsRequested"))
        XCTAssertTrue(settings.contains("DefaultKeyboardModePicker()"))
    }

    func testHomeUsesOneReadinessSummaryAndExplicitCopyFeedback() throws {
        let home = try String(contentsOf: repository.appending(path: "DictusApp/Views/HomeView.swift"), encoding: .utf8)

        let workspace = String(home.components(separatedBy: "#Preview").first ?? "")
        XCTAssertTrue(workspace.contains("List {"))
        XCTAssertFalse(workspace.contains(".safeAreaInset(edge: .bottom"),
                       "Keyboard power and settings must scroll on short screens")
        XCTAssertFalse(workspace.contains("DictationModelQuickPicker("), "Model choice belongs in Models")
        XCTAssertTrue(home.contains("if currentReadiness.action != .start"), "A ready app shows no status card")
        XCTAssertTrue(home.contains("Text(readiness.title)"), "Readiness and recovery titles must come from the shared policy")
        XCTAssertFalse(home.contains("Text(\"Ready when you are\")"))
        XCTAssertTrue(home.contains("accessibilityIdentifier(\"home.newDictation\")"))
        XCTAssertTrue(home.contains(".disabled(currentReadiness.action != .start)"))
        XCTAssertTrue(home.contains("copy(item)"))
        XCTAssertTrue(home.contains("UIAccessibility.post(notification: .announcement, argument: \"Copied\")"))
        XCTAssertTrue(home.contains("Array(RecentDictations.load(from: AppGroup.defaults).prefix(3))"),
                      "the home list must stay compact and leave full history to its dedicated screen")
        XCTAssertTrue(home.contains(".lineLimit(2)"),
                      "recent dictations must use bounded previews")
        XCTAssertTrue(home.contains("DictationHistoryEditView(item: item)"),
                      "a recent row opens the transcript it names")
        let settings = try source("DictusApp/Views/SettingsView.swift")
        XCTAssertFalse(settings.contains("Toggle(\"Autocorrection\""), "the keyboard has no autocorrection")
        XCTAssertTrue(settings.contains("KeyboardInteractionPreferences.notifyChanged()"))
        let overlay = try source("DictusApp/Views/SwipeBackOverlayView.swift")
        XCTAssertTrue(overlay.contains("Ready to dictate"))
        XCTAssertFalse(overlay.contains("Ready when you are"))
        XCTAssertFalse(home.contains("style: .relative"),
                       "Saved dictation timestamps must not tick or shift every second")
        XCTAssertTrue(home.contains("date.formatted(date: .omitted, time: .shortened)"),
                      "Recent rows show the saved time, or the day for older entries")
        XCTAssertFalse(home.contains("SaiityDashboardCard"))
        XCTAssertFalse(home.contains("background(.regularMaterial"))
    }

    func testHomeExposesServiceToggleWhileLiveActivitySharesIt() throws {
        let home = try source("DictusApp/Views/HomeView.swift")
        let attributes = try source("SyllivraKernel/Sources/SyllivraKernel/DictusLiveActivityAttributes.swift")
        let activity = try source("DictusWidgets/DictusLiveActivity.swift")
        let intent = try source("DictusWidgets/StopStandbyIntent.swift")

        XCTAssertTrue(home.contains("coordinator.setKeyboardDictationEnabled(enabled)"))
        XCTAssertTrue(home.contains("Toggle(\"Keyboard Dictation\""))
        XCTAssertTrue(home.contains("home.keyboardDictationToggle"))
        XCTAssertTrue(intent.contains("KeyboardDictationService.setEnabled"))
        XCTAssertTrue(attributes.contains("serviceEnabled"))
        XCTAssertTrue(activity.contains("state.serviceEnabled"))
        XCTAssertTrue(intent.contains("activity.update"))
        XCTAssertTrue(intent.contains("opensIntent: OpenURLIntent(url)"),
                      "Enabling a cold microphone must request foreground preparation")
    }

    func testLiveActivityLockScreenKeepsSemanticForegroundOnSystemBackground() throws {
        let activity = try source("DictusWidgets/DictusLiveActivity.swift")
        guard let lockScreen = activity.components(separatedBy: "struct DictationActivityCard: View").last else {
            XCTFail("Missing lock screen Live Activity view")
            return
        }

        XCTAssertFalse(lockScreen.contains("foregroundColor(.white)"))
        XCTAssertTrue(lockScreen.contains(".white : .primary"))
        XCTAssertTrue(lockScreen.contains("foregroundStyle(.secondary)"))
    }

    func testLiveActivityUsesOwnBrandingWithoutLegacyLogoAssets() throws {
        let activity = try source("DictusWidgets/DictusLiveActivity.swift")
        XCTAssertFalse(activity.contains("Text(\"sAI\")"))
        XCTAssertFalse(activity.contains("MiniLogoBars"))
        XCTAssertTrue(activity.contains("DictusLogo(height: 20)"))
        XCTAssertTrue(activity.contains("DictusLogo(height: 24)"))
        XCTAssertTrue(activity.contains("ActivitySignal(state: context.state, compact: true)"))
    }

    func testRecordingIsModalAndExposesAccessibleRecoveryAndTranscriptStages() throws {
        let recording = try String(contentsOf: repository.appending(path: "DictusApp/Views/RecordingView.swift"), encoding: .utf8)

        XCTAssertTrue(recording.contains(".accessibilityAddTraits(.isModal)"))
        XCTAssertTrue(recording.contains("UIAccessibility.post(notification: .announcement"))
        XCTAssertTrue(recording.contains("Transcript"))
        let sharedResult = try String(contentsOf: repository.appending(path: "DictusApp/Views/HomeView.swift"), encoding: .utf8)
        XCTAssertTrue(recording.contains("DictationTranscriptResult(result:"))
        XCTAssertTrue(sharedResult.contains("textSelection(.enabled)"))
        XCTAssertTrue(sharedResult.contains("dictation.resultVariant"))
        XCTAssertTrue(recording.contains("DictationProblem(errorMessage).action"))
        XCTAssertTrue(recording.contains("case .models, .repairDownload: showRecoveryModels = true"))
        XCTAssertTrue(recording.contains("Button(action: dismissRecording)"))
        XCTAssertTrue(recording.contains("accessibilityLabel(\"Close dictation\")"))
    }

    func testRecordingCancellationUsesLiveCoordinatorStatus() throws {
        let recording = try String(contentsOf: repository.appending(path: "DictusApp/Views/RecordingView.swift"), encoding: .utf8)

        XCTAssertTrue(recording.contains("switch coordinator.status"))
        XCTAssertTrue(recording.contains("coordinator.status == .transcribing"))
        XCTAssertTrue(recording.contains("coordinator.status == .processing"))
        XCTAssertTrue(recording.contains("accessibilityIdentifier(isCancellationStage ? \"dictation.cancel\""))
    }

    func testCoordinatorCancellationStopsCleanupBeforeTheTaskCanReport() throws {
        let coordinator = try source("DictusApp/DictationCoordinator.swift")
        let cancellation = try XCTUnwrap(coordinator.range(of: "func cancelDictation()"))
        let body = String(coordinator[cancellation.lowerBound...])

        XCTAssertTrue(body.contains("PolishCoordinator.shared.cancelInflight()"))
        XCTAssertTrue(body.contains("dictationTask?.cancel()"))
    }

    func testRecognitionAndProcessingKeepTheSelectedLanguageSnapshot() throws {
        let coordinator = try source("DictusApp/DictationCoordinator.swift")
        let service = try source("DictusApp/Audio/TranscriptionService.swift")
        XCTAssertTrue(service.contains("$recognitionLanguages.withValue(languagePolicy.spokenLanguages)"))
        XCTAssertTrue(coordinator.contains("spokenLanguages: currentLanguagePolicy.spokenLanguages"))
        let guardPosition = try XCTUnwrap(coordinator.range(of: "unexpectedLanguage(in: rawText"))
        let deliveryPosition = try XCTUnwrap(coordinator.range(of: "let decision = DictationFinalizationDecision.make("))
        XCTAssertLessThan(guardPosition.lowerBound, deliveryPosition.lowerBound)
        XCTAssertTrue(coordinator.contains("cleaned = translatedRawText"))
        XCTAssertTrue(try source("DictusApp/Views/RecordingView.swift").contains("Unverified recognition"))
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
        XCTAssertTrue(onboarding.contains("KeyboardSetupCard()"))
        XCTAssertTrue(onboarding.contains("modelReady"))
        XCTAssertTrue(onboarding.contains("polishEnabled"))
        XCTAssertTrue(onboarding.contains("downloadProgress"))
        XCTAssertTrue(onboarding.contains("downloadByteInfo"))
        XCTAssertTrue(onboarding.contains("cancelCatalogDownload"), "Inline preparation must retain a cancel action")
    }

    func testCleanupDefaultsToEnabledForNewUsers() throws {
        let app = try source("DictusApp/DictusApp.swift")
        let onboarding = try source("DictusApp/Onboarding/OnboardingView.swift")
        let settings = try source("DictusApp/Views/SettingsView.swift")

        XCTAssertTrue(app.contains("defaults?.set(true, forKey: SharedKeys.polishEnabled)"))
        XCTAssertTrue(onboarding.contains("private var polishEnabled = true"))
        XCTAssertTrue(settings.contains("private var polishEnabled = true"))
    }

    func testCleanupRunsOnAppleIntelligenceOrPassesTextThrough() throws {
        let coordinator = try source("DictusApp/Polish/PolishCoordinator.swift")
        let manager = try source("DictusApp/Models/ModelManager.swift")

        XCTAssertTrue(coordinator.contains("PolishSpanPipeline"))
        XCTAssertTrue(coordinator.contains("guard let appleFMEngine, PolishAvailability.isAppleFMAvailable else { return passthroughEngine }"))
        XCTAssertFalse(coordinator.contains("Ollama"), "Dictated text never leaves the iPhone for cleanup")
        XCTAssertFalse(manager.contains("cleanupBackend"))
    }

    func testCleanupMigrationEnablesUpgradeUsersWithoutOverwritingExplicitChoice() throws {
        let app = try source("DictusApp/DictusApp.swift")

        XCTAssertTrue(app.contains("defaults?.object(forKey: SharedKeys.polishEnabled) == nil"))
        XCTAssertTrue(app.contains("defaults?.set(true, forKey: SharedKeys.polishEnabled)"))
    }

    func testCleanupPromptsHandleSpokenSelfCorrections() throws {
        for path in [
            "SyllivraKernel/Sources/SyllivraKernel/Polish/Prompts/PolishAutoPrompt.swift",
            "SyllivraKernel/Sources/SyllivraKernel/Polish/Prompts/PolishNaturalPromptEN.swift",
            "SyllivraKernel/Sources/SyllivraKernel/Polish/Prompts/PolishNaturalPromptFR.swift",
            "SyllivraKernel/Sources/SyllivraKernel/Polish/Prompts/PolishNaturalPromptDE.swift",
            "SyllivraKernel/Sources/SyllivraKernel/Polish/Prompts/PolishNaturalPromptES.swift"
        ] {
            let prompt = try source(path)
            XCTAssertTrue(prompt.contains("self-correction"), "Missing self-correction rule in \(path)")
            XCTAssertTrue(prompt.contains("abandoned fragment"), "Missing abandoned-fragment guard in \(path)")
        }
    }

    func testCleanupPromptsIncludeSpokenRestartAndFillerExample() throws {
        for path in [
            "SyllivraKernel/Sources/SyllivraKernel/Polish/Prompts/PolishAutoPrompt.swift",
            "SyllivraKernel/Sources/SyllivraKernel/Polish/Prompts/PolishNaturalPromptEN.swift"
        ] {
            let prompt = try source(path)
            XCTAssertTrue(prompt.contains("Hey Jack I got like a appointment at 2am"), "Missing restart example in \(path)")
            XCTAssertTrue(prompt.contains("Hey Jack, I got an appointment at 4am. I got a poem at 4am. Can you come by please?"), "Distinct statements must survive the cleanup example in \(path)")
        }
    }

    func testOnboardingAllowsTrialBeforeHandshakeAndOffersFullAccessRecovery() throws {
        let onboarding = try source("DictusApp/Onboarding/OnboardingView.swift")
        let tutorial = try source("DictusApp/Onboarding/GlobeKeyTutorialPage.swift")

        let setup = try source("DictusApp/Onboarding/KeyboardSetupPage.swift")
        XCTAssertTrue(onboarding.contains("canContinue(keyboardInstalled: setup.keyboardInstalled, modelReady: modelReady)"))
        XCTAssertTrue(onboarding.contains("if usesKeyboard { KeyboardSetupCard() }"))
        XCTAssertFalse(onboarding.contains("keyboardInstalled && fullAccessVerified && modelReady"))
        XCTAssertTrue(onboarding.contains("then switch to it to verify Full Access"))
        XCTAssertTrue(setup.contains("Button(\"Open Settings\")"))
        XCTAssertTrue(setup.contains("The keyboard confirms Full Access itself."))
        XCTAssertTrue(tutorial.contains("Return to setup"))
        XCTAssertTrue(tutorial.contains("Full Access required"))
        XCTAssertTrue(tutorial.contains("Open Settings"))
        XCTAssertTrue(tutorial.contains("KeyboardSetupModel.shared"))
        XCTAssertTrue(tutorial.contains("setup.requestProbe()"))
        XCTAssertFalse(tutorial.contains("fullAccessVerified = status.fullAccessVerified"))
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

        for page in ["DictationSettingsView", "KeyboardSettingsView", "HelpView", "AboutView"] {
            XCTAssertTrue(settings.contains("struct \(page): View"), "Missing settings page: \(page)")
        }
        XCTAssertTrue(settings.contains("List {"))
        XCTAssertFalse(settings.contains("settingsPanel("))
        XCTAssertTrue(settings.contains("Clean Up Text"))
        XCTAssertFalse(settings.contains("CleanupSettingsView"))
        XCTAssertFalse(settings.contains("Cleanup options"))
        let modelManagerView = try source("DictusApp/Views/ModelManagerView.swift")
        XCTAssertFalse(modelManagerView.contains("CleanupModelPicker"), "Cleanup has no model choice")
        XCTAssertTrue(settings.contains("Privacy Policy"))
        XCTAssertFalse(settings.contains("moreGroup("))
        XCTAssertFalse(settings.contains("settingsExternalRow"))
        XCTAssertFalse(settings.contains("SoundSettingsView"))
        XCTAssertTrue(settings.contains("NavigationLink(\"Debug Logs\") { DebugLogView() }"))
        XCTAssertTrue(settings.contains("NavigationLink(\"Diagnostics\") { DiagnosticDetailView"))
        XCTAssertTrue(settings.contains("Section(\"This iPhone\")"))
        XCTAssertFalse(settings.contains("Control order"))
        XCTAssertFalse(settings.contains("Transcript language"))
        XCTAssertFalse(settings.contains("Offer continuation after dictation"))
        XCTAssertTrue(settings.contains("Toggle(\"Show Top Bar\""))
        XCTAssertTrue(settings.contains("DictationPresencePicker()"))
        XCTAssertTrue(settings.contains("KeyPopupPicker()"))
        for removed in ["KeyboardMaterialPicker()", "Toggle(\"Key Containers\"",
                        "KeyboardHoldSpeedPicker()", "Toggle(\"Adaptive Touch\"", "KeyboardHoldOptionsView()"] {
            XCTAssertFalse(settings.contains(removed), removed)
        }
        XCTAssertFalse(settings.contains("Toggle(\"Liquid glass\""))
        XCTAssertTrue(settings.contains("transcriptionOutputMode"))
        XCTAssertTrue(settings.contains("TypingLanguagesPanel()"))
        XCTAssertTrue(settings.contains("Toggle(\"Save History\""), "History saving stays reachable without saved entries")
        let languagePanel = try source("DictusApp/Views/KeyboardModePicker.swift")
        XCTAssertTrue(languagePanel.contains("ForEach(LayoutType.allCases"))
        XCTAssertTrue(languagePanel.contains("KeyboardLayoutPreference.setGlobalLayout"))
        XCTAssertFalse(languagePanel.contains("SupportedLanguage.activate(entry)"))
    }

    func testSecondaryScreensConfirmDestructiveActionsAndReportCopyOrExport() throws {
        let logs = try source("DictusApp/Views/DebugLogView.swift")
        let polish = try source("DictusApp/Polish/PolishDebugView.swift")

        XCTAssertTrue(logs.contains("confirmationDialog"))
        XCTAssertTrue(logs.contains("showCopiedFeedback"))
        XCTAssertTrue(logs.contains("Clear logs"))
        XCTAssertTrue(polish.contains("confirmationDialog"))
        XCTAssertTrue(polish.contains("showExportedFeedback"))
        XCTAssertTrue(polish.contains("Clear polish diagnostics"))
        XCTAssertFalse(logs.contains("ant.circle.fill"))
    }

    func testSecondaryContentUsesNativeScrolling() throws {
        let diagnostic = try source("DictusApp/Views/DiagnosticDetailView.swift")
        let licenses = try source("DictusApp/Views/LicensesView.swift")

        XCTAssertTrue(diagnostic.contains("List"))
        XCTAssertFalse(diagnostic.contains(".isModal"), "A pushed diagnostics page must not trap VoiceOver as a modal")
        XCTAssertTrue(diagnostic.contains(".accessibilityValue(passed ? \"OK\" : \"Failed\")"))
        XCTAssertTrue(licenses.contains("List"))
        XCTAssertTrue(licenses.contains("Section {"))
    }

    func testShippedNoticesPreserveInheritedSourceLicensesAndApacheNotices() throws {
        let data = try Data(contentsOf: repository.appending(path: "DictusApp/Resources/OpenSourceNotices.json"))
        let notices = try JSONDecoder().decode([[String: String]].self, from: data)
        XCTAssertEqual(Set(notices.compactMap { $0["name"] }).count, notices.count)
        for (name, path) in [
            ("Dictus", "LICENSE"),
            ("giellakbd-ios", "DictusKeyboard/Vendored/LICENSE-MIT")
        ] {
            let notice = try XCTUnwrap(notices.first { $0["name"] == name })
            XCTAssertEqual(notice["text"], try source(path), "Preserve the source license for \(name)")
        }
        let crypto = try XCTUnwrap(notices.first { $0["name"] == "Swift Crypto" }?["text"])
        XCTAssertTrue(crypto.contains("Copyright 2019 The SwiftCrypto Project"))
        let asn1 = try XCTUnwrap(notices.first { $0["name"] == "Swift ASN.1" }?["text"])
        XCTAssertTrue(asn1.contains("Copyright 2022 The SwiftASN1 Project"))
    }

    func testModelsUseNativeSectionsWithReadableMetadataAndActions() throws {
        let manager = try source("DictusApp/Views/ModelManagerView.swift")
        let card = try source("DictusApp/Views/ModelCardView.swift")

        XCTAssertFalse(manager.contains(".safeAreaInset"))
        XCTAssertFalse(manager.contains(".contentMargins(.bottom, 88, for: .scrollContent)"), "Without a tab bar no extra bottom margin is needed")
        XCTAssertFalse(manager.contains("Add custom model"))
        XCTAssertFalse(manager.contains("showAddModel"))
        XCTAssertFalse(manager.contains("AddCustomModelView"))
        XCTAssertFalse(manager.contains(".swipeActions"))
        XCTAssertFalse(manager.contains("modelSectionHeader"))
        XCTAssertFalse(manager.contains(".listRowSeparator(.hidden)"))
        XCTAssertFalse(manager.contains("Processing"), "Cleanup has no model choice; Apple Intelligence runs it")
        XCTAssertTrue(manager.contains("Picker(\"Voice Model\""), "One voice model choice covers the app and keyboard")
        XCTAssertFalse(card.contains("actionColumnWidth"))
        XCTAssertTrue(card.contains("languageSupport.coverage.localizedSummary"))
        XCTAssertTrue(card.contains("cancelCatalogDownload(model.identifier)"))
        XCTAssertTrue(card.contains(".buttonStyle(.borderless)"))
        XCTAssertTrue(card.contains(".font(.subheadline)"))
        XCTAssertFalse(card.contains("GaugeBarView("), "Catalog estimates must not appear as measured scores")
        XCTAssertFalse(manager.contains("DictationSettingsAdvisor(modelManager: modelManager)"))
        XCTAssertFalse(manager.contains("VoiceOptionsView(modelManager: modelManager)"))
        XCTAssertTrue(manager.contains("modelManager.useRecommendedSettings()"), "Automatic restores the recommended models")
        XCTAssertFalse(manager.contains("Realtime"), "Live text existed only for the retired Qwen engine")
        XCTAssertFalse(manager.contains("ModelSelectionProfilePicker"))
        XCTAssertFalse(manager.contains("ModelSelectionModePicker"))
        XCTAssertFalse(manager.contains(".fullScreenCover("), "Model preparation should leave navigation available")
        XCTAssertFalse(card.contains(".opacity(incompatibilityReason == nil ? 1 : 0.55)"))
    }

    func testModelRowsKeepEveryStateAndDeterminateProgressReadable() throws {
        let card = try source("DictusApp/Views/ModelCardView.swift")

        for label in ["Downloading", "Preparing", "In app", "Keyboard", "App & keyboard", "Failed", "Unavailable"] {
            XCTAssertTrue(card.contains("\"\(label)"), "Missing model state label: \(label)")
        }
        XCTAssertTrue(card.contains("downloadProgressLabel"))
        XCTAssertTrue(card.contains("downloadByteInfo"))
        XCTAssertTrue(card.contains("accessibilityValue"))
    }

    func testSettingsPagesUseNativeFormsWithoutTabBarMargins() throws {
        let settings = try source("DictusApp/Views/SettingsView.swift")

        XCTAssertFalse(settings.contains(".safeAreaInset"))
        XCTAssertTrue(settings.contains("Form {"))
        XCTAssertFalse(settings.contains(".contentMargins(.bottom, 88, for: .scrollContent)"))
        XCTAssertFalse(settings.contains("DisclosureGroup("), "Settings use plain sections, not hidden advanced groups")
    }

    func testModelDeletionStillUsesParentConfirmationAndGuards() throws {
        let manager = try source("DictusApp/Views/ModelManagerView.swift")
        let card = try source("DictusApp/Views/ModelCardView.swift")

        XCTAssertTrue(card.contains("Label(\"Delete\", systemImage: \"trash\")"))
        XCTAssertTrue(card.contains("onDeleteRequest?()"))
        XCTAssertTrue(card.contains("onDeletePartialRequest?()"))
        XCTAssertTrue(card.contains("!isActive && modelManager.downloadedModels.count > 1"))
        XCTAssertTrue(card.contains(".disabled(!isFailed && !canDeleteModel)"))
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
        XCTAssertTrue(detail.contains("Upstream large-v3 FLEURS reference"))
        XCTAssertTrue(detail.contains("not measurements of this model export or this phone"))
        XCTAssertTrue(detail.contains("No published reference measurement"))
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
        let keys = try source("SyllivraKernel/Sources/SyllivraKernel/SharedKeys.swift")
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
        XCTAssertTrue((try relocatedKeyboardSource()).contains("ImmediateKeyButton("))
        XCTAssertTrue((try relocatedKeyboardSource()).contains("highlightSize: frame.size"))
        XCTAssertFalse(root.contains("Link(destination: preparationURL)"))
        XCTAssertFalse(root.contains("SuggestionBarIconButton("))
        XCTAssertFalse(root.contains("private func accessoryBar("))
        XCTAssertTrue(keyboard.contains("UIAction(title: \"Dismiss keyboard\""))
        XCTAssertTrue(keyboard.contains("identifier: \"open-saiity-button\""))
        let app = try source("DictusApp/DictusApp.swift")
        XCTAssertTrue(app.contains("AudioLifecyclePolicy.shouldRestoreStandby(serviceEnabled: serviceEnabled"))
        XCTAssertTrue(app.contains("onboardingComplete: hasCompletedOnboarding"))
        XCTAssertTrue(app.contains("recordPermission == .granted"),
                      "automatic restoration must not ask for microphone permission on Welcome")
    }

    func testAccessoryRelayoutKeepsTheActiveMicFrameAndUsesTheSharedTopLane() throws {
        let controller = try source("DictusKeyboard/KeyboardViewController.swift")
        let root = try source("DictusKeyboard/KeyboardRootView.swift")
        let policy = try source("SyllivraKernel/Sources/SyllivraKernel/VoiceOnlyKeyboardPolicy.swift")

        XCTAssertFalse(controller.contains("micButton?.frame = .zero"),
                       "relayout must not clear an active mic before restoring the same frame")
        XCTAssertTrue(controller.contains("micButton?.isHidden = !dictateVisible"))
        XCTAssertTrue(controller.contains("topAccessoryHeight: currentSuggestionLaneHeight"))
        XCTAssertTrue(root.contains("topAccessoryHeight: KeyboardInteractionPreferences.topBarHeight(for: state.areaMode)"))
        XCTAssertTrue(policy.contains("public static let suggestionLaneHeight: Double = 32"))
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
        XCTAssertFalse(categories.contains("keyboardGlass(in: Capsule())"),
                       "the minimal category strip is unboxed")
        XCTAssertFalse(categories.contains("contentOffset"), "The full category rail remains stationary")
        XCTAssertTrue(categories.contains("EmojiCategoryScrubControl"))
        XCTAssertTrue(categories.contains("EmojiCategoryBarMetrics.railInset"))
        XCTAssertFalse(categories.contains("isExpanded"))
        XCTAssertFalse(categories.contains("magnifyingglass"))
    }

    func testGlobeTutorialRefreshesFullAccessAfterKeyboardHandshake() throws {
        let tutorial = try source("DictusApp/Onboarding/GlobeKeyTutorialPage.swift")

        XCTAssertTrue(tutorial.contains("scenePhase"))
        XCTAssertTrue(tutorial.contains("refreshFullAccess()"))
        XCTAssertTrue(tutorial.contains("KeyboardSetupModel.shared"))
        XCTAssertTrue(tutorial.contains(".onChange(of: setup.fullAccessVerified)"))
        XCTAssertTrue(tutorial.contains("DispatchQueue.main.async"))
        XCTAssertTrue(tutorial.contains("setup.fullAccessVerified"))
        XCTAssertTrue(tutorial.contains("fullAccessRequired = false"))
        XCTAssertTrue(tutorial.contains("dictationFailed = false"))
        XCTAssertTrue(tutorial.contains("Syllivra keyboard is active. Tap the microphone to dictate."))
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

        XCTAssertFalse(availability.contains("coordinator.enableKeyboardSession()"), "setup verification and video playback must not arm the microphone")
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

        XCTAssertTrue(speechModelProtocol.contains("Open Syllivra and download it in Settings > Models."))
        XCTAssertFalse(speechModelProtocol.contains("in the Models tab"))
    }

    func testKeyboardKeepsOneLookWithoutAppearanceSettings() throws {
        let picker = try source("DictusApp/Views/KeyboardModePicker.swift")
        let kernel = try source("SyllivraKernel/Sources/SyllivraKernel/KeyboardInteractionPreferences.swift")
        let mode = try source("SyllivraKernel/Sources/SyllivraKernel/KeyPopupMode.swift")
        XCTAssertTrue(picker.contains("struct KeyPopupPicker: View"))
        XCTAssertTrue(picker.contains("ForEach(KeyPopupMode.allCases"))
        for option in ["return \"Off\"", "return \"Popup\"", "return \"Popout\"", "return \"Key flash\""] {
            XCTAssertTrue(mode.contains(option), option)
        }
        XCTAssertFalse(picker.contains("Picker(\"Material\""))
        XCTAssertFalse(picker.contains("Toggle(\"Background\""))
        XCTAssertFalse(kernel.contains("liquidGlassEnabled"))
        XCTAssertFalse(kernel.contains("keyContainersEnabled"))
    }

    func testDictationPresenceDoesNotUsePictureInPicture() throws {
        let manager = try source("DictusApp/LiveActivityManager.swift")
        let mode = try source("SyllivraKernel/Sources/SyllivraKernel/DictationPresenceMode.swift")

        XCTAssertFalse(manager.contains("AVPictureInPicture"))
        XCTAssertFalse(manager.contains("DictationPictureInPicture"))
        XCTAssertFalse(mode.contains("case pictureInPicture"))
    }


    private func relocatedKeyboardSource() throws -> String {
        let paths = [
            "DictusKeyboard/KeyboardRootView.swift",
            "DictusKeyboard/KeyboardChrome.swift",
            "DictusKeyboard/KeyboardKeyStyle.swift",
            "DictusKeyboard/KeyboardKeyInput.swift",
            "DictusKeyboard/VoiceBoardSurface.swift",
            "DictusKeyboard/KeyboardState.swift",
            "DictusKeyboard/Views/EmojiPickerView.swift",
            "DictusKeyboard/Views/EmojiGestureCoordinator.swift",
            "DictusKeyboard/Views/EmojiCategoryBar.swift",
            "DictusKeyboard/Views/EmojiCategoryControl.swift",
            "SyllivraKernel/Sources/SyllivraKernel/KeyboardSurfaceState.swift",
            "SyllivraKernel/Sources/SyllivraKernel/EmojiSurfaceModel.swift",
        ]
        return try paths.map { try source($0) }.joined(separator: "\n")
    }

    private func source(_ path: String) throws -> String {
        try String(contentsOf: repository.appending(path: path), encoding: .utf8)
    }
}
