import XCTest
@testable import SyllivraKernel

final class ProductCompletionTests: XCTestCase {
    func testGermanChineseEnglishChoicesRejectFrenchWithoutBlockingMixedSpeechAndNames() {
        let languages = ["de", "zh-Hant", "EN_us"]
        XCTAssertEqual(SpokenLanguagePreferences.bestLanguage(scores: ["fr": 10, "de": 2, "en": 1, "zh": 0], among: languages), "de")
        XCTAssertNil(SpokenLanguagePreferences.bestLanguage(scores: ["fr": 10], among: languages))
        XCTAssertNil(SpokenLanguagePreferences.bestLanguage(scores: ["de": .nan], among: languages))
        XCTAssertEqual(SpokenLanguagePreferences.unexpectedLanguage(in: "Bonjour, je voudrais réserver une table pour demain soir.", languages: languages), "fr")
        XCTAssertNil(SpokenLanguagePreferences.unexpectedLanguage(in: "Bitte schick mir die Rechnung morgen. Please send the invoice tomorrow. 我们明天需要确认这个付款计划。", languages: languages))
        XCTAssertNil(SpokenLanguagePreferences.unexpectedLanguage(in: "Please send François the café address at https://bonjour.fr.", languages: languages))
        XCTAssertNil(SpokenLanguagePreferences.unexpectedLanguage(in: "Bonjour", languages: languages))
        XCTAssertNil(SpokenLanguagePreferences.unexpectedLanguage(in: "François Dupont", languages: languages))
        XCTAssertNil(SpokenLanguagePreferences.unexpectedLanguage(in: "Bonjour, je voudrais réserver une table pour demain soir.", languages: []))
        XCTAssertEqual(languages.map(SpokenLanguagePreferences.recognitionName), ["German", "Chinese", "English"])
        XCTAssertEqual(DictationProblem("Recognition returned French outside your selected spoken languages. Try again.").message,
                       "Recognition returned French outside your selected spoken languages. Try again.")
        XCTAssertEqual(DictationProblem("This voice model does not cover your selected spoken languages.").action, .models)
    }

    func testRecognitionChoicesAreTaskLocalAndCannotLeakIntoTheNextDictation() async {
        XCTAssertTrue(SpokenLanguagePreferences.recognitionLanguages.isEmpty)
        await SpokenLanguagePreferences.$recognitionLanguages.withValue(["de", "en", "zh"]) {
            let inherited = await Task { SpokenLanguagePreferences.recognitionLanguages }.value
            XCTAssertEqual(inherited, ["de", "en", "zh"])
        }
        XCTAssertTrue(SpokenLanguagePreferences.recognitionLanguages.isEmpty)
    }

    private let phone = DeviceCapabilities(physicalMemoryGB: 8, availableMemoryMB: 3000,
        deviceModelIdentifier: "iPhone18,4", thermalState: .nominal)

    func testLanguageCoverageAndNormalization() throws {
        XCTAssertEqual(SpokenLanguagePreferences.normalized(["zh-Hant", "EN_us", "fil", "tl", "jw", "jv", ""]), ["en", "jv", "tl", "zh"])
        XCTAssertFalse(SpokenLanguagePreferences.availableCodes.contains("fil"))
        let multilingual = try XCTUnwrap(ModelInfo.forIdentifier("openai_whisper-small"))
        XCTAssertTrue(SpokenLanguagePreferences.accepts(multilingual, languages: ["de", "fr", "en"]))
        XCTAssertTrue(SpokenLanguagePreferences.accepts(multilingual, languages: []))
        XCTAssertNil(ModelInfo.forIdentifier("parakeet-tdt-0.6b-v3"), "retired engines no longer resolve")
        let english = try XCTUnwrap(ModelInfo.forIdentifier("openai_whisper-small.en"))
        XCTAssertFalse(SpokenLanguagePreferences.accepts(english, languages: ["en", "zh"]))
        XCTAssertFalse(SpokenLanguagePreferences.accepts(english, languages: []))
        XCTAssertTrue(SpokenLanguagePreferences.accepts(english, languages: ["en"]))
    }

    func testRecommendationsHonorLanguagesAndQualityWithoutInventingSupport() {
        let models: Set<String> = ["openai_whisper-small.en", "openai_whisper-small", "openai_whisper-medium", "openai_whisper-large-v3_947MB"]
        func resolve(_ languages: [String], installed: Set<String> = models) -> String? {
            ModelSelectionProfile.balanced.resolvedIdentifier(installed: installed, osMajor: 27,
                capabilities: phone, requiredLanguages: languages)
        }
        XCTAssertEqual(resolve(["zh-Hant", "en"]), "openai_whisper-large-v3_947MB")
        XCTAssertNil(resolve(["unsupported"]))
        XCTAssertNil(resolve(["yue"], installed: ["openai_whisper-small", "openai_whisper-medium"]))
        XCTAssertEqual(resolve(["yue"]), "openai_whisper-large-v3_947MB")
        XCTAssertEqual(resolve(["zh"], installed: ["openai_whisper-small"]), "openai_whisper-small")
        XCTAssertEqual(resolve([], installed: ["parakeet-tdt-0.6b-v3", "openai_whisper-small"]), "openai_whisper-small",
                       "a stale identifier from a retired engine is ignored")
    }

    func testConstrainedHardwareCannotBypassCoverage() {
        let oldPhone = DeviceCapabilities(physicalMemoryGB: 3, availableMemoryMB: 700,
            deviceModelIdentifier: "iPhone12,1", thermalState: .serious)
        XCTAssertEqual(ModelSelectionProfile.precise.resolvedIdentifier(installed: ["openai_whisper-base", "openai_whisper-large-v3_947MB"],
            osMajor: 17, capabilities: oldPhone, requiredLanguages: ["zh"]), "openai_whisper-base")
        XCTAssertNil(ModelSelectionProfile.balanced.resolvedIdentifier(installed: ["openai_whisper-small.en"],
            osMajor: 27, capabilities: phone, requiredLanguages: ["sw"]))
    }

    func testManualChoicesSurviveLanguageChangesAndAutomaticReadinessStaysIndependent() throws {
        let name = "dictus.product-completion-tests"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(["zh", "en"], forKey: SharedKeys.spokenLanguages)
        defaults.set("manual", forKey: SharedKeys.modelSelectionMode)
        defaults.set("openai_whisper-large-v3_947MB", forKey: SharedKeys.dictationWhisperModel)
        XCTAssertNil(DictationModelPreferences.resolveAppModel(in: defaults,
            installed: ["openai_whisper-small"], osMajor: 27, capabilities: phone))
        defaults.set("openai_whisper-small.en", forKey: SharedKeys.keyboardDictationModel)
        XCTAssertEqual(DictationModelPreferences.resolveKeyboardModel(in: defaults, installed: ["openai_whisper-small.en"],
            osMajor: 27, capabilities: phone), "openai_whisper-small.en", "explicit choices remain user controlled")
        defaults.removeObject(forKey: SharedKeys.keyboardDictationModel)
        XCTAssertNil(DictationModelPreferences.resolveKeyboardModel(in: defaults, installed: ["openai_whisper-small.en"],
            osMajor: 27, capabilities: phone))
        XCTAssertEqual(defaults.string(forKey: SharedKeys.dictationWhisperModel), "openai_whisper-large-v3_947MB")
        XCTAssertNil(defaults.object(forKey: SharedKeys.transcriptionLanguage))
        XCTAssertNil(defaults.object(forKey: SharedKeys.language))
    }

    func testRuntimeFallbackCannotSilentlyDropAChosenLanguage() {
        let fallback = ModelInfo.runtimeResolution(for: "openai_whisper-medium", installedIdentifiers: ["openai_whisper-small"],
            osMajor: 27, capabilities: phone, fallbackLanguages: ["yue"])
        XCTAssertNil(fallback.resolvedIdentifier)
        XCTAssertEqual(fallback.fallbackReason, .notInstalled)
        let manual = ModelInfo.runtimeResolution(for: "openai_whisper-small.en", installedIdentifiers: ["openai_whisper-small.en"],
            osMajor: 27, capabilities: phone, fallbackLanguages: ["zh"])
        XCTAssertNil(manual.resolvedIdentifier, "A manual model cannot ignore a selected language it does not support")
        let compatible = ModelInfo.runtimeResolution(for: "openai_whisper-small.en",
            installedIdentifiers: ["openai_whisper-small.en", "openai_whisper-small"],
            osMajor: 27, capabilities: phone, fallbackLanguages: ["de", "zh", "en"])
        XCTAssertEqual(compatible.resolvedIdentifier, "openai_whisper-small")
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
}
