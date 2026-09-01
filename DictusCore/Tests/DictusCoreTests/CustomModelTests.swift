import XCTest
@testable import DictusCore

final class CustomModelTests: XCTestCase {
    func testOnlyEnglishAndGermanAreSelectable() {
        XCTAssertEqual(SupportedLanguage.allCases, [.english, .german])
        XCTAssertEqual(TranscriptionLanguageMode(storedValue: "fr"), .explicit(.english))
        XCTAssertEqual(TranscriptionLanguageMode(storedValue: "es"), .explicit(.english))
    }

    func testASRRejectsOllamaAndCleanupRejectsNvidia() {
        let asr = CustomModel(name: "Local", repositoryURL: "https://ollama.com", role: .asr, source: .ollama)
        let cleanup = CustomModel(name: "NVIDIA", repositoryURL: "https://developer.nvidia.com/model", role: .cleanup, source: .nvidia)
        XCTAssertNotNil(asr.validationError)
        XCTAssertNotNil(cleanup.validationError)
    }

    func testASRURLsNeedSpeechRecognitionEvidence() {
        let nonASR = CustomModel(
            name: "Image model",
            repositoryURL: "https://huggingface.co/example/image-model",
            role: .asr,
            source: .huggingFace
        )
        let speechModel = CustomModel(
            name: "Whisper tiny",
            repositoryURL: "https://huggingface.co/openai/whisper-tiny",
            role: .asr,
            source: .huggingFace
        )

        XCTAssertNil(nonASR.validationError)
        XCTAssertNil(speechModel.validationError)
        XCTAssertNotNil(speechModel.runtimeSupportError)
    }

    func testHuggingFaceMetadataMustDeclareSpeechRecognition() {
        let asrMetadata = Data(#"{"pipeline_tag":"automatic-speech-recognition","tags":["audio"]}"#.utf8)
        let textMetadata = Data(#"{"pipeline_tag":"text-generation","tags":["text"]}"#.utf8)

        XCTAssertTrue(CustomModel.metadataIndicatesASR(asrMetadata))
        XCTAssertFalse(CustomModel.metadataIndicatesASR(textMetadata))
    }

    func testOllamaCleanupRequiresModelNameAndAllowsLocalHTTP() {
        let missingName = CustomModel(
            name: "Cleanup",
            repositoryURL: "http://127.0.0.1:11434",
            role: .cleanup,
            source: .ollama
        )
        let localModel = CustomModel(
            name: "Cleanup",
            repositoryURL: "http://127.0.0.1:11434",
            role: .cleanup,
            source: .ollama,
            modelName: "qwen2.5:3b"
        )

        XCTAssertNotNil(missingName.validationError)
        XCTAssertNil(localModel.validationError)
    }

    func testCustomASRRejectsNonWhisperKitSourcesAndRepositories() {
        let nvidia = CustomModel(name: "Nemotron", repositoryURL: "https://huggingface.co/nvidia/model", role: .asr, source: .nvidia, modelName: "model")
        let arbitraryHF = CustomModel(name: "Checkpoint", repositoryURL: "https://huggingface.co/example/whisper", role: .asr, source: .huggingFace, modelName: "whisper")

        XCTAssertNotNil(nvidia.runtimeSupportError)
        XCTAssertNotNil(arbitraryHF.runtimeSupportError)
    }

    func testOnlyKnownWhisperKitCoreMLVariantPassesCustomASRContract() {
        let model = CustomModel(
            name: "Whisper tiny",
            repositoryURL: "https://huggingface.co/argmaxinc/whisperkit-coreml",
            role: .asr,
            source: .huggingFace,
            modelName: "openai_whisper-tiny"
        )

        XCTAssertNil(model.runtimeSupportError)
    }

    func testDuplicateCustomModelsUseStableIdentity() {
        let first = CustomModel(
            name: "Whisper",
            repositoryURL: "https://huggingface.co/openai/whisper-tiny/",
            role: .asr,
            source: .huggingFace
        )
        let second = CustomModel(
            name: "Whisper revised",
            repositoryURL: "https://huggingface.co/openai/whisper-tiny",
            role: .asr,
            source: .huggingFace
        )

        XCTAssertEqual(first.identityKey, second.identityKey)
    }

    func testCustomModelsRoundTripInAppGroupDefaults() {
        let defaults = UserDefaults(suiteName: "saiity.custom-model-tests")!
        defaults.removePersistentDomain(forName: "saiity.custom-model-tests")
        defer { defaults.removePersistentDomain(forName: "saiity.custom-model-tests") }
        let model = CustomModel(name: "Whisper", repositoryURL: "https://huggingface.co/openai/whisper-tiny", role: .asr, source: .huggingFace)
        CustomModel.save([model], to: defaults)
        XCTAssertEqual(CustomModel.load(from: defaults), [model])
    }

    func testProviderURLsRequireRepositoryPaths() {
        let hfCollection = CustomModel(name: "Speech", repositoryURL: "https://huggingface.co/models/whisper", role: .asr, source: .huggingFace)
        let nvidiaDeveloperPage = CustomModel(name: "Speech", repositoryURL: "https://developer.nvidia.com/", role: .asr, source: .nvidia)
        let nvidiaModel = CustomModel(name: "Nemotron ASR", repositoryURL: "https://developer.nvidia.com/nemo/automatic-speech-recognition/nemotron", role: .asr, source: .nvidia)
        let nvidiaWrongPath = CustomModel(name: "Developer page", repositoryURL: "https://developer.nvidia.com/foo/whisper", role: .asr, source: .nvidia)

        XCTAssertNotNil(hfCollection.validationError)
        XCTAssertNotNil(nvidiaDeveloperPage.validationError)
        XCTAssertNil(nvidiaModel.validationError)
        XCTAssertNotNil(nvidiaWrongPath.validationError)
    }

    func testRuntimeSupportStatusContract() {
        let runnable = CustomModel(name: "Tiny", repositoryURL: "https://huggingface.co/argmaxinc/whisperkit-coreml", role: .asr, source: .huggingFace, modelName: "openai_whisper-tiny")
        let hfUnsupported = CustomModel(name: "Whisper", repositoryURL: "https://huggingface.co/openai/whisper-tiny", role: .asr, source: .huggingFace, modelName: "whisper")
        let nvidiaUnsupported = CustomModel(name: "Nemotron", repositoryURL: "https://developer.nvidia.com/nemo/automatic-speech-recognition/nemotron", role: .asr, source: .nvidia, modelName: "nemotron")
        let malformed = CustomModel(name: "Broken", repositoryURL: "not a url", role: .asr, source: .huggingFace)

        XCTAssertNil(runnable.validationError)
        XCTAssertNil(runnable.runtimeSupportError)
        XCTAssertNil(hfUnsupported.validationError)
        XCTAssertNotNil(hfUnsupported.runtimeSupportError)
        XCTAssertNil(nvidiaUnsupported.validationError)
        XCTAssertNotNil(nvidiaUnsupported.runtimeSupportError)
        XCTAssertNotNil(malformed.validationError)
        XCTAssertNotNil(malformed.runtimeSupportError)
    }

    func testSaveDeduplicatesByIdentityAndKeepsLastRegistration() {
        let defaults = UserDefaults(suiteName: "saiity.custom-model-dedupe-tests")!
        defaults.removePersistentDomain(forName: "saiity.custom-model-dedupe-tests")
        defer { defaults.removePersistentDomain(forName: "saiity.custom-model-dedupe-tests") }
        let first = CustomModel(name: "First", repositoryURL: "https://huggingface.co/openai/whisper-tiny", role: .asr, source: .huggingFace)
        let last = CustomModel(name: "Last", repositoryURL: "https://huggingface.co/openai/whisper-tiny/", role: .asr, source: .huggingFace)

        CustomModel.save([first, last], to: defaults)

        XCTAssertEqual(CustomModel.load(from: defaults), [last])
    }

    func testLoadDropsMalformedRecordsWithoutDroppingValidRecords() throws {
        let defaults = UserDefaults(suiteName: "saiity.custom-model-safe-load-tests")!
        defaults.removePersistentDomain(forName: "saiity.custom-model-safe-load-tests")
        defer { defaults.removePersistentDomain(forName: "saiity.custom-model-safe-load-tests") }
        let valid = CustomModel(name: "Cleanup", repositoryURL: "http://127.0.0.1:11434", role: .cleanup, source: .ollama, modelName: "llama3")
        let validJSON = try JSONEncoder().encode(valid)
        let malformed = Data(#"{"id":"bad","name":12}"#.utf8)
        let array = try JSONSerialization.data(withJSONObject: [
            try JSONSerialization.jsonObject(with: validJSON),
            try JSONSerialization.jsonObject(with: malformed)
        ])
        defaults.set(array, forKey: SharedKeys.customModels)

        XCTAssertEqual(CustomModel.load(from: defaults), [valid])
    }
}
