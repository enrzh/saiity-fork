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

    func testCaptureCompletionReleasesAudioBeforeTranscription() throws {
        let coordinator = try source("DictusApp/DictationCoordinator.swift")
        let stopStart = try XCTUnwrap(coordinator.range(of: "func stopDictation()"))
        let nextMethod = try XCTUnwrap(coordinator.range(of: "func processAuthoritativeFinalTranscript("))
        let stop = String(coordinator[stopStart.lowerBound..<nextMethod.lowerBound])

        XCTAssertTrue(stop.contains("audioEngine.collectSamplesAndDeactivate()"))
        XCTAssertFalse(stop.contains("let samples = audioEngine.collectSamples()"))
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

        XCTAssertTrue(service.contains("DictationSessionLivenessPolicy.isActive(self.status)"))
        XCTAssertTrue(service.contains("self.audioEngine.deactivateIfIdle()"))
    }
}
