import XCTest

final class AudioLifecycleContractTests: XCTestCase {
    private var repository: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func source(_ path: String) throws -> String {
        try String(contentsOf: repository.appending(path: path), encoding: .utf8)
    }

    func testMicrophoneSessionPreservesKeyboardHapticsWithoutVoiceChatProcessing() throws {
        let audio = try source("DictusApp/Audio/UnifiedAudioEngine.swift")
        let start = try XCTUnwrap(audio.range(of: "func configureAudioSession()"))
        let end = try XCTUnwrap(audio.range(of: "// MARK: - System Haptics Allowance"))
        let configuration = String(audio[start.lowerBound..<end.lowerBound])
        let allowance = try XCTUnwrap(configuration.range(of: "applyHapticsAllowance("))
        let activation = try XCTUnwrap(configuration.range(of: "session.setActive(true)"))

        XCTAssertTrue(configuration.contains("mode: .default"))
        XCTAssertLessThan(allowance.lowerBound, activation.lowerBound,
                          "Request haptics before the microphone session becomes active")
        XCTAssertFalse(audio.contains("setMode(.voiceChat)"),
                       "Voice-chat routing must not suppress typing feedback during standby or capture")
        XCTAssertFalse(audio.contains("setVoiceProcessingEnabled(true)"),
                       "Changing only the session mode leaves the voice-processing input unit enabled")
        XCTAssertFalse(audio.contains("restoreIdleAudioProcessing()"),
                       "Keep one stable input mode instead of changing routes while the engine runs")
    }

    func testCoordinatorPreloadsModelsWithoutActivatingAudioAtStartup() throws {
        let coordinator = try source("DictusApp/DictationCoordinator.swift")
        let initStart = try XCTUnwrap(coordinator.range(of: "private init()"))
        let observerStart = try XCTUnwrap(coordinator.range(of: "// Stop audio engine when user taps Power button"))
        let startup = String(coordinator[initStart.lowerBound..<observerStart.lowerBound])

        XCTAssertTrue(startup.contains("try await ensureEngineReady()"))
        XCTAssertFalse(startup.contains("audioEngine.configureAudioSession()"))
        XCTAssertFalse(startup.contains("audioEngine.warmUp()"))
    }

    func testForegroundRecoveryPreloadsOnlyTheModel() throws {
        let coordinator = try source("DictusApp/DictationCoordinator.swift")
        let foregroundStart = try XCTUnwrap(
            coordinator.range(of: "forName: UIApplication.didBecomeActiveNotification")
        )
        let foregroundEnd = try XCTUnwrap(
            coordinator.range(of: "// Schedule a prewarm of the Apple FM polish model")
        )
        let foreground = String(coordinator[foregroundStart.lowerBound..<foregroundEnd.lowerBound])

        XCTAssertTrue(foreground.contains("ensureEngineReady()"))
        XCTAssertFalse(foreground.contains("audioEngine.configureAudioSession()"))
        XCTAssertFalse(foreground.contains("audioEngine.warmUp()"))
    }

    func testCaptureCompletionRetainsAudioOnlyForExplicitKeyboardSession() throws {
        let coordinator = try source("DictusApp/DictationCoordinator.swift")
        let stopStart = try XCTUnwrap(coordinator.range(of: "func stopDictation()"))
        let nextMethod = try XCTUnwrap(coordinator.range(of: "func processAuthoritativeFinalTranscript("))
        let stop = String(coordinator[stopStart.lowerBound..<nextMethod.lowerBound])

        XCTAssertTrue(stop.contains("let samples = collectCompletedRecording()"))
        let start = try XCTUnwrap(coordinator.range(of: "private func collectCompletedRecording()"))
        let end = try XCTUnwrap(coordinator.range(of: "func deactivateAudioIfIdle()"))
        let collection = String(coordinator[start.lowerBound..<end.lowerBound])
        XCTAssertTrue(collection.contains("if keyboardSessionEnabled"))
        XCTAssertTrue(collection.contains("return audioEngine.collectSamples()"))
        XCTAssertTrue(collection.contains("return audioEngine.collectSamplesAndDeactivate()"))
    }

    func testCancelAndErrorPathsReleaseConfiguredAudio() throws {
        let coordinator = try source("DictusApp/DictationCoordinator.swift")

        XCTAssertTrue(coordinator.contains("_ = audioEngine.collectSamplesAndDeactivate()"))
        XCTAssertTrue(coordinator.contains("audioEngine.deactivateIfIdle()"))

        let errorStart = try XCTUnwrap(coordinator.range(of: "private func handleError("))
        let modelSection = try XCTUnwrap(coordinator.range(of: "// MARK: - Model load orchestration"))
        let errorPath = String(coordinator[errorStart.lowerBound..<modelSection.lowerBound])
        XCTAssertTrue(errorPath.contains("audioEngine.deactivateSession()"))
        XCTAssertTrue(errorPath.contains("audioEngine.deactivateIfIdle()"))
    }

    func testBackgroundPathReleasesOnlyIdleAudio() throws {
        let app = try source("DictusApp/DictusApp.swift")
        let backgroundStart = try XCTUnwrap(app.range(of: "case .background:"))
        let coldStartResolution = try XCTUnwrap(
            app.range(of: "let resumedColdStart = coordinator.resolvePendingColdStartOnBackground()")
        )
        let background = String(app[backgroundStart.lowerBound..<coldStartResolution.lowerBound])

        XCTAssertTrue(background.contains("coordinator.deactivateAudioIfIdle()"))
        XCTAssertFalse(background.contains("coordinator.isEngineRunning"))
        let coordinator = try source("DictusApp/DictationCoordinator.swift")
        XCTAssertTrue(coordinator.contains("guard !keyboardSessionEnabled else { return }"))
    }

    func testKeyboardSessionRequiresExplicitForegroundPreparation() throws {
        let coordinator = try source("DictusApp/DictationCoordinator.swift")
        let start = try XCTUnwrap(coordinator.range(of: "func enableKeyboardSession()"))
        let end = try XCTUnwrap(coordinator.range(of: "func disableKeyboardSession()"))
        let prepare = String(coordinator[start.lowerBound..<end.lowerBound])
        XCTAssertTrue(coordinator.contains("keyboardSessionEnabled = false"))
        XCTAssertTrue(prepare.contains("guard UIApplication.shared.applicationState == .active else { return }"))
        XCTAssertTrue(prepare.contains("guard !Task.isCancelled, self.keyboardSessionEnabled,"))
        XCTAssertTrue(prepare.contains("try self.audioEngine.warmUp()"))
        let audio = try source("DictusApp/Audio/UnifiedAudioEngine.swift")
        XCTAssertTrue(audio.contains("captureBuffer.capture {"), "standby must use the synchronized session gate")
        XCTAssertTrue(audio.contains("scheduleIdleRelease(after: Self.idleReleaseInterval)"))
    }

    func testServiceDisableCancelsEveryActiveDictationStatus() throws {
        let coordinator = try source("DictusApp/DictationCoordinator.swift")
        let serviceStart = try XCTUnwrap(
            coordinator.range(of: "forName: Notification.Name(\"DictusServiceToggleRequested\")")
        )
        let interruptionStart = try XCTUnwrap(
            coordinator.range(of: "// Cancel any in-flight dictation when the audio session is interrupted")
        )
        let service = String(coordinator[serviceStart.lowerBound..<interruptionStart.lowerBound])

        XCTAssertTrue(service.contains("self.setKeyboardDictationEnabled(enabled)"))
        let changeStart = try XCTUnwrap(coordinator.range(of: "func setKeyboardDictationEnabled("))
        let changeEnd = try XCTUnwrap(coordinator.range(of: "func enableKeyboardSession()"))
        let change = String(coordinator[changeStart.lowerBound..<changeEnd.lowerBound])
        XCTAssertTrue(change.contains("DictationSessionLivenessPolicy.isActive(status) { cancelDictation() }"))
        XCTAssertTrue(change.contains("disableKeyboardSession()"))
        let disableStart = try XCTUnwrap(coordinator.range(of: "func disableKeyboardSession()"))
        let disableEnd = try XCTUnwrap(coordinator.range(of: "private func collectCompletedRecording()"))
        XCTAssertTrue(coordinator[disableStart.lowerBound..<disableEnd.lowerBound].contains("audioEngine.deactivateIfIdle()"))
    }
}
