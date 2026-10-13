import XCTest
@testable import SyllivraKernel

final class DictationModelPreferencesTests: XCTestCase {
    private let phone = DeviceCapabilities(physicalMemoryGB: 8, availableMemoryMB: 3000,
        deviceModelIdentifier: "iPhone18,4", thermalState: .nominal)

    func testPendingManualChoiceSurvivesDownloadDiscoveryAndReopeningSettings() throws {
        let name = "dictus.pending-model-tests"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.removePersistentDomain(forName: name)
        defaults.set("manual", forKey: SharedKeys.modelSelectionMode)
        defaults.set(QwenASRModel.large.rawValue, forKey: SharedKeys.dictationStreamingModel)
        let installed: Set<String> = [QwenASRModel.small.rawValue, "openai_whisper-tiny"]
        for _ in 0..<3 {
            XCTAssertNil(DictationModelPreferences.resolveAppModel(in: defaults, recognizer: .streaming,
                installed: installed, osMajor: 27, capabilities: phone))
            XCTAssertEqual(DictationModelPreferences.requestedAppModel(in: defaults, recognizer: .streaming), QwenASRModel.large.rawValue)
        }
        XCTAssertEqual(DictationModelPreferences.resolveAppModel(in: defaults, recognizer: .streaming,
            installed: installed.union([QwenASRModel.large.rawValue]), osMajor: 27, capabilities: phone), QwenASRModel.large.rawValue)
    }

    func testAppQwenAndKeyboardWhisperAreIndependentAndMigrateOnce() throws {
        let name = "dictus.scope-model-tests"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.removePersistentDomain(forName: name)
        defaults.set(QwenASRModel.small.rawValue, forKey: SharedKeys.activeModel)
        defaults.set(true, forKey: SharedKeys.modelReady)
        DictationModelPreferences.migrate(in: defaults)
        let keyboard = DictationModelPreferences.resolveKeyboardModel(in: defaults,
            installed: [QwenASRModel.small.rawValue, "openai_whisper-base"], osMajor: 27, capabilities: phone)
        XCTAssertEqual(keyboard, "openai_whisper-base")
        defaults.set(keyboard, forKey: SharedKeys.activeModel)
        DictationModelPreferences.migrate(in: defaults)
        let appRequest = DictationLanguageRequest(mode: .autoDetect, translationTarget: nil)
            .bound(sessionID: "app-session", generation: 1, clientIdentifier: "app-test")
        XCTAssertEqual(DictationModelPreferences.requestedModel(for: appRequest, in: defaults), QwenASRModel.small.rawValue)
        let keyboardRequest = appRequest.bound(sessionID: "keyboard-session", generation: 2, clientIdentifier: "keyboard-test")
        XCTAssertEqual(DictationModelPreferences.requestedModel(for: keyboardRequest, in: defaults), "openai_whisper-base")
    }

    func testAllActiveStagesAndFinalizationDeferRuntimeChanges() {
        for status in [DictationStatus.requested, .recording, .transcribing, .processing] {
            XCTAssertFalse(DictationModelPreferences.canChangeRuntime(status: status, finalizing: false))
        }
        XCTAssertFalse(DictationModelPreferences.canChangeRuntime(status: .ready, finalizing: true))
        XCTAssertTrue(DictationModelPreferences.canChangeRuntime(status: .ready, finalizing: false))
        XCTAssertTrue(DictationModelPreferences.canChangeRuntime(status: .idle, finalizing: false))
    }

    func testAQueuedPreloadCannotSwapTheModelAfterARecordingBegins() {
        for status in [DictationStatus.requested, .recording, .transcribing, .processing, .ready] {
            XCTAssertFalse(DictationModelPreferences.canPrepareModel(QwenASRModel.large.rawValue,
                sessionModel: QwenASRModel.small.rawValue, status: status, finalizing: true))
            XCTAssertTrue(DictationModelPreferences.canPrepareModel(QwenASRModel.small.rawValue,
                sessionModel: QwenASRModel.small.rawValue, status: status, finalizing: true))
        }
        XCTAssertTrue(DictationModelPreferences.canPrepareModel(QwenASRModel.large.rawValue,
            sessionModel: QwenASRModel.small.rawValue, status: .idle, finalizing: false))
    }

    func testPreviewReadsHaveABoundAndPreserveAllSamplesForStop() {
        let buffer = AudioCaptureBuffer()
        let audio = (0..<25_000).map(Float.init)
        buffer.start(sessionID: 1)
        _ = buffer.capture { audio }
        var copied: [Float] = []
        while let chunk = buffer.read(after: copied.count, maximumSamples: 8_000) {
            XCTAssertLessThanOrEqual(chunk.samples.count, 8_000)
            copied += chunk.samples
        }
        XCTAssertEqual(copied, audio)
        XCTAssertEqual(buffer.stop(), audio)
        XCTAssertNil(buffer.read(after: 0, maximumSamples: 0))
    }

    func testCancellationSignalIsStickyAndVisibleAcrossThreads() async throws {
        let control = InferenceCancellation()
        try control.check()
        await Task.detached { control.cancel() }.value
        XCTAssertTrue(control.isCancelled)
        XCTAssertThrowsError(try control.check())
    }
}
