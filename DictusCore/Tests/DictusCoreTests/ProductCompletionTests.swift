import XCTest
@testable import DictusCore

final class ProductCompletionTests: XCTestCase {
    private let phone = DeviceCapabilities(physicalMemoryGB: 8, availableMemoryMB: 3000,
        deviceModelIdentifier: "iPhone18,4", thermalState: .nominal)

    func testLanguageCoverageAndNormalization() throws {
        XCTAssertEqual(SpokenLanguagePreferences.normalized(["zh-Hant", "EN_us", "fil", "tl", "jw", "jv", ""]), ["en", "jv", "tl", "zh"])
        XCTAssertFalse(SpokenLanguagePreferences.availableCodes.contains("fil"))
        let parakeet = try XCTUnwrap(ModelInfo.forIdentifier("parakeet-tdt-0.6b-v3"))
        XCTAssertTrue(SpokenLanguagePreferences.accepts(parakeet, languages: ["de", "fr", "en"]))
        XCTAssertFalse(SpokenLanguagePreferences.accepts(parakeet, languages: ["zh", "en"]))
        XCTAssertFalse(SpokenLanguagePreferences.accepts(parakeet, languages: []))
        let english = try XCTUnwrap(ModelInfo.forIdentifier("openai_whisper-small.en"))
        XCTAssertFalse(SpokenLanguagePreferences.accepts(english, languages: ["en", "zh"]))
        XCTAssertFalse(SpokenLanguagePreferences.accepts(english, languages: []))
        XCTAssertTrue(SpokenLanguagePreferences.accepts(english, languages: ["en"]))
    }

    func testRecommendationsHonorLanguagesAndQualityWithoutInventingSupport() {
        let models: Set<String> = ["parakeet-tdt-0.6b-v3", "openai_whisper-small.en", "openai_whisper-small", "openai_whisper-medium", "openai_whisper-large-v3_947MB"]
        func resolve(_ languages: [String], installed: Set<String> = models) -> String? {
            ModelSelectionProfile.balanced.resolvedIdentifier(installed: installed, osMajor: 27,
                capabilities: phone, recognizer: .whisper, requiredLanguages: languages)
        }
        XCTAssertEqual(resolve(["zh-Hant", "en"]), "openai_whisper-large-v3_947MB")
        XCTAssertNil(resolve(["unsupported"]))
        XCTAssertNil(resolve(["yue"], installed: ["openai_whisper-small", "openai_whisper-medium"]))
        XCTAssertEqual(resolve(["yue"]), "openai_whisper-large-v3_947MB")
        XCTAssertEqual(resolve(["zh"], installed: ["openai_whisper-small"]), "openai_whisper-small")
        XCTAssertEqual(resolve([], installed: ["parakeet-tdt-0.6b-v3", "openai_whisper-small"]), "openai_whisper-small")
    }

    func testConstrainedHardwareAndForegroundEngineCannotBypassCoverage() {
        let oldPhone = DeviceCapabilities(physicalMemoryGB: 3, availableMemoryMB: 700,
            deviceModelIdentifier: "iPhone12,1", thermalState: .serious)
        XCTAssertEqual(ModelSelectionProfile.precise.resolvedIdentifier(installed: ["openai_whisper-base", "openai_whisper-large-v3_947MB"],
            osMajor: 17, capabilities: oldPhone, recognizer: .whisper, requiredLanguages: ["zh"]), "openai_whisper-base")
        XCTAssertNil(ModelSelectionProfile.balanced.resolvedIdentifier(installed: [QwenASRModel.small.rawValue],
            osMajor: 27, capabilities: phone, recognizer: .streaming, requiredLanguages: ["sw"]))
        XCTAssertNil(ModelSelectionProfile.balanced.resolvedIdentifier(installed: [QwenASRModel.small.rawValue],
            osMajor: 17, capabilities: phone, recognizer: .streaming, requiredLanguages: ["zh"]))
    }

    func testManualChoicesSurviveLanguageChangesAndAutomaticReadinessStaysIndependent() throws {
        let name = "dictus.product-completion-tests"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(["zh", "en"], forKey: SharedKeys.spokenLanguages)
        defaults.set("manual", forKey: SharedKeys.modelSelectionMode)
        defaults.set(QwenASRModel.large.rawValue, forKey: SharedKeys.dictationStreamingModel)
        XCTAssertNil(DictationModelPreferences.resolveAppModel(in: defaults, recognizer: .streaming,
            installed: [QwenASRModel.small.rawValue], osMajor: 27, capabilities: phone))
        defaults.set("parakeet-tdt-0.6b-v3", forKey: SharedKeys.keyboardDictationModel)
        XCTAssertEqual(DictationModelPreferences.resolveKeyboardModel(in: defaults, installed: ["parakeet-tdt-0.6b-v3"],
            osMajor: 27, capabilities: phone), "parakeet-tdt-0.6b-v3", "explicit choices remain user controlled")
        defaults.removeObject(forKey: SharedKeys.keyboardDictationModel)
        XCTAssertNil(DictationModelPreferences.resolveKeyboardModel(in: defaults, installed: ["parakeet-tdt-0.6b-v3"],
            osMajor: 27, capabilities: phone))
        XCTAssertEqual(defaults.string(forKey: SharedKeys.dictationStreamingModel), QwenASRModel.large.rawValue)
        XCTAssertNil(defaults.object(forKey: SharedKeys.transcriptionLanguage))
        XCTAssertNil(defaults.object(forKey: SharedKeys.language))
    }

    func testRuntimeFallbackCannotSilentlyDropAChosenLanguage() {
        let fallback = ModelInfo.runtimeResolution(for: "parakeet-tdt-0.6b-v3", installedIdentifiers: ["openai_whisper-small"],
            osMajor: 27, capabilities: phone, fallbackLanguages: ["yue"])
        XCTAssertNil(fallback.resolvedIdentifier)
        XCTAssertEqual(fallback.fallbackReason, .notInstalled)
        let manual = ModelInfo.runtimeResolution(for: "parakeet-tdt-0.6b-v3", installedIdentifiers: ["parakeet-tdt-0.6b-v3"],
            osMajor: 27, capabilities: phone, fallbackLanguages: ["zh"])
        XCTAssertEqual(manual.resolvedIdentifier, "parakeet-tdt-0.6b-v3")
    }

    func testAppOnlySetupDoesNotRequireKeyboardAndLegacySetupKeepsItsGate() throws {
        XCTAssertTrue(OnboardingUsage.appOnly.canContinue(keyboardInstalled: false, modelReady: true))
        XCTAssertFalse(OnboardingUsage.appOnly.canContinue(keyboardInstalled: true, modelReady: false))
        XCTAssertFalse(OnboardingUsage.keyboard.canContinue(keyboardInstalled: false, modelReady: true))
        XCTAssertTrue(OnboardingUsage.keyboard.canContinue(keyboardInstalled: true, modelReady: true))
        let name = "dictus.onboarding-usage-tests"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        XCTAssertEqual(OnboardingUsage.active(from: defaults), .keyboard)
        defaults.set("appOnly", forKey: SharedKeys.onboardingUsage)
        XCTAssertFalse(OnboardingUsage.active(from: defaults).usesKeyboard)
    }

    func testProblemsOfferRelevantRecoveryWithoutRawDiagnostics() {
        XCTAssertEqual(DictationProblem("Microphone permission denied").action, .openSettings)
        XCTAssertEqual(DictationProblem("Microphone permission not yet requested").action, .retry)
        XCTAssertEqual(DictationProblem("File permission denied").action, .retry)
        XCTAssertEqual(DictationProblem("Qwen out of memory").action, .models)
        XCTAssertFalse(DictationProblem("Qwen out of memory").message.contains("stay open"))
        XCTAssertTrue(DictationProblem("Qwen left foreground").message.contains("stay open"))
        XCTAssertEqual(DictationProblem("Invalid checksum in download receipt").action, .repairDownload)
        XCTAssertEqual(DictationProblem("Network connection lost", downloading: true).message, "The download couldn’t finish. Check your connection and try again.")
        XCTAssertEqual(DictationProblem("No model downloaded").action, .models)
        XCTAssertTrue(DictationProblem("Recording too short").message.contains("Speak a little longer"))
        XCTAssertTrue(DictationProblem("Not enough space").message.contains("storage"))
        XCTAssertTrue(DictationProblem("No space left on device").message.contains("storage"))
        XCTAssertTrue(DictationProblem("There isn’t enough space to save this file.").message.contains("storage"))
        XCTAssertEqual(DictationProblem("The model server is busy. Please try again in a few minutes.", downloading: true).action, .retry)
        XCTAssertFalse(DictationProblem("namespace failure").message.contains("storage"))
    }

    func testReplayIsOptInBoundedAndExpiresAtTheBoundary() throws {
        var replay = RecordingReplayBuffer()
        replay.retain([0.5], session: 1, enabled: false, now: 10)
        XCTAssertFalse(replay.isAvailable(now: 10))
        replay.retain([], session: 1, enabled: true, now: 10)
        XCTAssertNil(replay.session)
        let limit = RecordingReplayBuffer.sampleRate * RecordingReplayBuffer.maximumSeconds
        replay.retain([1] + Array(repeating: 0.5, count: limit), session: 2, enabled: true, now: 10)
        XCTAssertTrue(replay.trimmed)
        let wav = try XCTUnwrap(replay.wavData(now: 11))
        XCTAssertEqual(wav.count, 44 + limit * 2)
        XCTAssertEqual(Array(wav[44..<46]), [0xff, 0x3f], "retains the tail rather than the first sample")
        XCTAssertTrue(replay.isAvailable(now: 309.999))
        XCTAssertFalse(replay.isAvailable(now: 310))
        XCTAssertFalse(replay.isAvailable(now: 9))
        XCTAssertNil(replay.wavData(now: 310))
        replay.retain([0], session: 3, enabled: true, now: 20)
        XCTAssertEqual(replay.session, 3)
        XCTAssertFalse(replay.trimmed)
        replay.clear()
        XCTAssertNil(replay.session)
        XCTAssertFalse(replay.isAvailable(now: 20))
    }

    func testReplayWAVHeaderPCMAndCancellation() throws {
        var replay = RecordingReplayBuffer()
        replay.retain([-2, 2, .nan, .infinity, 0], session: 1, enabled: true, now: 0)
        let wav = try XCTUnwrap(replay.wavData(now: 0))
        XCTAssertEqual(String(decoding: wav[0..<4], as: UTF8.self), "RIFF")
        XCTAssertEqual(String(decoding: wav[8..<16], as: UTF8.self), "WAVEfmt ")
        XCTAssertEqual(Array(wav[22..<36]), [1, 0, 0x80, 0x3e, 0, 0, 0, 0x7d, 0, 0, 2, 0, 16, 0])
        XCTAssertEqual(String(decoding: wav[36..<40], as: UTF8.self), "data")
        XCTAssertEqual(Array(wav[44...]), [1, 128, 255, 127, 0, 0, 0, 0, 0, 0])
        XCTAssertNil(replay.wavData(now: 0, isCancelled: { true }))
        replay.retain(Array(repeating: 0, count: 4096), session: 2, enabled: true, now: 0)
        var checks = 0
        XCTAssertNil(replay.wavData(now: 0, isCancelled: { checks += 1; return checks == 2 }))
        XCTAssertEqual(checks, 2)
    }
}
