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
        XCTAssertTrue(keyboard.contains("DarwinNotificationCenter.post(DarwinNotificationName.keyboardFullAccessChanged)"))
        XCTAssertTrue(availability.contains("DarwinNotificationCenter.addObserver(for: DarwinNotificationName.keyboardFullAccessChanged)"))
        XCTAssertTrue(availability.contains("DarwinNotificationCenter.removeObserver(for: DarwinNotificationName.keyboardFullAccessChanged)"))
        XCTAssertTrue(availability.contains("refreshKeyboard()"))
        XCTAssertTrue(availability.contains("let handshake = installed"))
        XCTAssertTrue(availability.contains("AppGroup.defaults.set(false, forKey: SharedKeys.onboardingFullAccessVerified)"))
        XCTAssertTrue(availability.contains("fullAccessVerified = handshake"))
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
        XCTAssertEqual(mainTabView.components(separatedBy: "NavigationStack {").count - 1, 3)
        XCTAssertEqual(mainTabView.components(separatedBy: ".tabItem {").count - 1, 3)
        XCTAssertFalse(mainTabView.contains("safeAreaInset"))
        XCTAssertFalse(mainTabView.contains("frame(height: 96)"))
        XCTAssertFalse(mainTabView.contains("padding(.bottom, 96"))
    }

    func testHomeUsesOneReadinessSummaryAndExplicitCopyFeedback() throws {
        let home = try String(contentsOf: repository.appending(path: "DictusApp/Views/HomeView.swift"), encoding: .utf8)

        XCTAssertTrue(home.contains("Section(\"Readiness\")"))
        XCTAssertTrue(home.contains("Label(\"Start dictation\""))
        XCTAssertTrue(home.contains("Button(\"Copy\""))
        XCTAssertTrue(home.contains("Text(showCopiedFeedback ? \"Copied\""))
        XCTAssertFalse(home.contains("RoundedRectangle(cornerRadius: 12)"))
    }

    func testServiceToggleUsesSharedServiceStateAndLiveActivityCarriesDetectionState() throws {
        let home = try source("DictusApp/Views/HomeView.swift")
        let attributes = try source("DictusCore/Sources/DictusCore/DictusLiveActivityAttributes.swift")
        let activity = try source("DictusWidgets/DictusLiveActivity.swift")
        let intent = try source("DictusWidgets/StopStandbyIntent.swift")

        XCTAssertTrue(home.contains("SharedKeys.serviceEnabled"))
        XCTAssertTrue(home.contains("onChange(of: serviceEnabled)"))
        XCTAssertTrue(attributes.contains("detectionMuted"))
        XCTAssertTrue(activity.contains("context.state.detectionMuted"))
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

    func testRecordingIsModalAndExposesAccessibleRecoveryAndTranscriptStages() throws {
        let recording = try String(contentsOf: repository.appending(path: "DictusApp/Views/RecordingView.swift"), encoding: .utf8)

        XCTAssertTrue(recording.contains(".accessibilityAddTraits(.isModal)"))
        XCTAssertTrue(recording.contains("UIAccessibility.post(notification: .announcement"))
        XCTAssertTrue(recording.contains("Text(\"Live transcript\")"))
        XCTAssertTrue(recording.contains("Text(\"Processed result\")"))
        XCTAssertTrue(recording.contains("Button(\"Try again\""))
        XCTAssertTrue(recording.contains("Button(\"Close\""))
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

    func testOnboardingAllowsTrialBeforeHandshakeAndOffersFullAccessRecovery() throws {
        let onboarding = try source("DictusApp/Onboarding/OnboardingView.swift")
        let tutorial = try source("DictusApp/Onboarding/GlobeKeyTutorialPage.swift")

        XCTAssertTrue(onboarding.contains("keyboardInstalled && modelReady"))
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

    func testSettingsTaskFourUsesGroupedNativeSectionsAndShippedDestinations() throws {
        let settings = try source("DictusApp/Views/SettingsView.swift")

        let sections = ["Dictation", "Keyboard", "Translation & Cleanup", "Feedback", "Privacy", "Support"]
        XCTAssertEqual(sections.filter { settings.contains("Section(\"\($0)\")") }, sections)
        XCTAssertTrue(settings.contains("NavigationLink { ModelManagerView"))
        XCTAssertFalse(settings.contains("NavigationLink { SoundSettingsView()"))
        XCTAssertTrue(settings.contains("NavigationLink { DebugLogView()"))
        XCTAssertTrue(settings.contains("NavigationLink { DiagnosticDetailView"))
        XCTAssertTrue(settings.contains("Toggle("))
        XCTAssertTrue(settings.contains("Picker("))
        XCTAssertFalse(settings.contains("Keyboard layout"))
        XCTAssertFalse(settings.contains("RoundedRectangle"))
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
        XCTAssertTrue(diagnostic.contains("accessibilityAddTraits"))
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

    func testModelsUseCompactRowsWithOneStableActionColumn() throws {
        let manager = try source("DictusApp/Views/ModelManagerView.swift")
        let card = try source("DictusApp/Views/ModelCardView.swift")

        XCTAssertFalse(manager.contains(".safeAreaInset"))
        XCTAssertTrue(manager.contains(".contentMargins(.bottom, 88, for: .scrollContent)"))
        XCTAssertFalse(manager.contains(".swipeActions"))
        XCTAssertFalse(manager.contains(".listRowSeparator(.visible)"))
        XCTAssertTrue(manager.contains(".listRowSeparator(.hidden)"))
        XCTAssertEqual(
            manager.components(separatedBy: ".listSectionSeparator(.hidden)").count - 1,
            2,
            "Installed and Available should not render section rules"
        )
        XCTAssertTrue(card.contains("actionColumnWidth"))
        XCTAssertTrue(card.contains(".frame(width: actionColumnWidth"))
        XCTAssertTrue(card.contains("private let actionColumnWidth: CGFloat = 128"))
        XCTAssertTrue(card.contains(".fixedSize(horizontal: true, vertical: false)"))
        XCTAssertTrue(card.contains(".font(.subheadline)"))
        XCTAssertFalse(card.contains("Label(\"Accuracy"))
        XCTAssertFalse(card.contains("Label(\"Speed"))
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
        XCTAssertTrue(settings.contains(".contentMargins(.bottom, 88, for: .scrollContent)"))
    }

    func testModelDeletionIsOnlyExposedThroughConfirmedMenu() throws {
        let manager = try source("DictusApp/Views/ModelManagerView.swift")
        let card = try source("DictusApp/Views/ModelCardView.swift")

        XCTAssertTrue(card.contains("Menu"))
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
        XCTAssertTrue(overlay.contains("Preparing"))
        XCTAssertTrue(overlay.contains("Optimizing"))
        XCTAssertTrue(overlay.contains("Loading"))
        XCTAssertTrue(overlay.contains(".accessibilityAddTraits(.isModal)"))
    }

    func testKeyboardEmojiAndSearchTargetsKeepFortyFourPointHitAreas() throws {
        let picker = try source("DictusKeyboard/Views/EmojiPickerView.swift")
        let categories = try source("DictusKeyboard/Views/EmojiCategoryBar.swift")

        XCTAssertTrue(picker.contains("private var rowHeight: CGFloat { 44 }"))
        XCTAssertTrue(picker.contains("frame(width: emojiCellWidth, height: rowHeight)"))
        XCTAssertTrue(picker.contains("frame(width: emojiCellWidth, height: 44)"))
        XCTAssertTrue(picker.contains("private let keyHeight: CGFloat = 44"))
        XCTAssertTrue(categories.contains(".frame(height: 44)"))
        XCTAssertTrue(categories.contains(".frame(width: 44, height: 44)"))
    }

    private func source(_ path: String) throws -> String {
        try String(contentsOf: repository.appending(path: path), encoding: .utf8)
    }
}
