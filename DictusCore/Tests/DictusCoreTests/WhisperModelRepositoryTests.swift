// DictusCore/Tests/DictusCoreTests/WhisperModelRepositoryTests.swift
// Tests for the local WhisperKit model repository resolution (issue #249).
import XCTest
@testable import DictusCore

final class WhisperModelRepositoryTests: XCTestCase {

    /// Stand-in for the app's Documents directory so tests never touch the real one.
    private var documents: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        documents = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("WhisperModelRepositoryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let documents {
            try? FileManager.default.removeItem(at: documents)
        }
        documents = nil
        try super.tearDownWithError()
    }

    // MARK: - Helpers

    /// Creates `<documents>/huggingface/models/argmaxinc/whisperkit-coreml/<identifier>`
    /// and returns it, optionally populated with the compiled Core ML bundles a real
    /// download leaves behind.
    @discardableResult
    private func makeModelFolder(_ identifier: String, withCompiledModels: Bool) throws -> URL {
        let folder = documents
            .appendingPathComponent(WhisperModelRepository.relativeRepositoryPath, isDirectory: true)
            .appendingPathComponent(identifier, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // config.json ships with every variant and is present even in a partial download.
        try Data("{}".utf8).write(to: folder.appendingPathComponent("config.json"))
        if withCompiledModels {
            for bundle in ["MelSpectrogram.mlmodelc", "AudioEncoder.mlmodelc", "TextDecoder.mlmodelc"] {
                try FileManager.default.createDirectory(
                    at: folder.appendingPathComponent(bundle, isDirectory: true),
                    withIntermediateDirectories: true
                )
                try Data("compiled".utf8).write(to: folder.appendingPathComponent(bundle + "/coremldata.bin"))
                try Data("program".utf8).write(to: folder.appendingPathComponent(bundle + "/model.mil"))
                if bundle != "MelSpectrogram.mlmodelc" {
                    try FileManager.default.createDirectory(at: folder.appendingPathComponent(bundle + "/weights"), withIntermediateDirectories: true)
                    try Data("weights".utf8).write(to: folder.appendingPathComponent(bundle + "/weights/weight.bin"))
                }
            }
        }
        return folder
    }

    // MARK: - Path construction

    func testRepositoryURLMatchesTheHubApiLayout() {
        let repository = WhisperModelRepository.repositoryURL(documentsDirectory: documents)
        XCTAssertEqual(
            repository?.path,
            documents.appendingPathComponent("huggingface/models/argmaxinc/whisperkit-coreml").path
        )
    }

    func testModelFolderURLIsReturnedEvenWhenNothingIsOnDisk() {
        // Delete and cleanup need the path before checking whether it exists.
        let folder = WhisperModelRepository.modelFolderURL(
            for: "openai_whisper-small",
            documentsDirectory: documents
        )
        XCTAssertEqual(folder?.lastPathComponent, "openai_whisper-small")
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder?.path ?? ""))
    }

    func testModelFolderURLUsesTheIdentifierVerbatim() {
        // Quantized variants keep the suffix in both the catalog and the repo folder.
        let folder = WhisperModelRepository.modelFolderURL(
            for: "openai_whisper-small_216MB",
            documentsDirectory: documents
        )
        XCTAssertEqual(folder?.lastPathComponent, "openai_whisper-small_216MB")
    }

    // MARK: - Installed detection

    func testInstalledModelFolderIsResolvedForACompleteDownload() throws {
        let expected = try makeModelFolder("openai_whisper-medium", withCompiledModels: true)

        let resolved = WhisperModelRepository.installedModelFolderURL(
            for: "openai_whisper-medium",
            documentsDirectory: documents
        )

        XCTAssertEqual(resolved?.path, expected.path)
        XCTAssertTrue(
            WhisperModelRepository.isModelInstalled("openai_whisper-medium", documentsDirectory: documents)
        )
    }

    func testInstalledModelFolderIsNilWhenTheModelWasNeverDownloaded() {
        XCTAssertNil(
            WhisperModelRepository.installedModelFolderURL(
                for: "openai_whisper-small",
                documentsDirectory: documents
            )
        )
        XCTAssertFalse(
            WhisperModelRepository.isModelInstalled("openai_whisper-small", documentsDirectory: documents)
        )
    }

    func testInstalledModelFolderIsNilForAPartialDownload() throws {
        // A folder with metadata but no compiled bundle must never be handed to
        // WhisperKit — the user has to re-download it from the model manager.
        try makeModelFolder("openai_whisper-small", withCompiledModels: false)

        XCTAssertNil(
            WhisperModelRepository.installedModelFolderURL(
                for: "openai_whisper-small",
                documentsDirectory: documents
            )
        )
    }

    func testEmptyOrTruncatedCompiledBundleIsNotInstalled() throws {
        let folder = try makeModelFolder("openai_whisper-small", withCompiledModels: true)
        let marker = folder.appendingPathComponent("AudioEncoder.mlmodelc/coremldata.bin")
        try FileManager.default.removeItem(at: marker)
        XCTAssertFalse(WhisperModelRepository.isModelInstalled("openai_whisper-small", documentsDirectory: documents))
        try Data().write(to: marker)
        XCTAssertFalse(WhisperModelRepository.isModelInstalled("openai_whisper-small", documentsDirectory: documents))
    }

    func testLegacyBundleMissingWeightsOrWithInvalidConfigIsNotInstalled() throws {
        let folder = try makeModelFolder("openai_whisper-small", withCompiledModels: true)
        let weights = folder.appendingPathComponent("AudioEncoder.mlmodelc/weights/weight.bin")
        try FileManager.default.removeItem(at: weights)
        XCTAssertFalse(WhisperModelRepository.isModelInstalled("openai_whisper-small", documentsDirectory: documents))
        try Data("weights".utf8).write(to: weights)
        try Data("not json".utf8).write(to: folder.appendingPathComponent("config.json"))
        XCTAssertFalse(WhisperModelRepository.isModelInstalled("openai_whisper-small", documentsDirectory: documents))
    }

    func testVariantReceiptsKeepIndependentOfflineReadiness() throws {
        for identifier in ["openai_whisper-small", "openai_whisper-medium"] {
            let folder = try makeModelFolder(identifier, withCompiledModels: true)
            let paths = ["config.json", "MelSpectrogram.mlmodelc/coremldata.bin",
                         "AudioEncoder.mlmodelc/coremldata.bin", "TextDecoder.mlmodelc/coremldata.bin"]
            let files = paths.map { ["path": identifier + "/" + $0, "size": $0 == "config.json" ? 2 : 8] as [String: Any] }
            let data = try JSONSerialization.data(withJSONObject: ["version": 1, "files": files])
            try data.write(to: folder.appendingPathComponent(".dictus-download-receipt.json"))
        }
        XCTAssertTrue(WhisperModelRepository.isModelInstalled("openai_whisper-small", documentsDirectory: documents))
        XCTAssertTrue(WhisperModelRepository.isModelInstalled("openai_whisper-medium", documentsDirectory: documents))
        let small = try XCTUnwrap(WhisperModelRepository.modelFolderURL(for: "openai_whisper-small", documentsDirectory: documents))
        try Data("cut".utf8).write(to: small.appendingPathComponent("AudioEncoder.mlmodelc/coremldata.bin"))
        XCTAssertFalse(WhisperModelRepository.isModelInstalled("openai_whisper-small", documentsDirectory: documents))
        XCTAssertTrue(WhisperModelRepository.isModelInstalled("openai_whisper-medium", documentsDirectory: documents))
    }

    func testDeletingTheModelFolderMakesItReportAsMissing() throws {
        let folder = try makeModelFolder("openai_whisper-small_216MB", withCompiledModels: true)
        XCTAssertNotNil(
            WhisperModelRepository.installedModelFolderURL(
                for: "openai_whisper-small_216MB",
                documentsDirectory: documents
            )
        )

        // Mirrors what ModelManager.deleteModel removes.
        try FileManager.default.removeItem(at: folder)

        XCTAssertNil(
            WhisperModelRepository.installedModelFolderURL(
                for: "openai_whisper-small_216MB",
                documentsDirectory: documents
            )
        )
    }

    func testDeletingOneModelLeavesTheOthersInstalled() throws {
        try makeModelFolder("openai_whisper-small", withCompiledModels: true)
        let medium = try makeModelFolder("openai_whisper-medium", withCompiledModels: true)

        try FileManager.default.removeItem(at: medium)

        XCTAssertTrue(
            WhisperModelRepository.isModelInstalled("openai_whisper-small", documentsDirectory: documents)
        )
        XCTAssertFalse(
            WhisperModelRepository.isModelInstalled("openai_whisper-medium", documentsDirectory: documents)
        )
    }

    // MARK: - Tokenizer cache diagnostics

    func testCachedTokenizerRepositoryNamesIsEmptyWhenNothingWasEverLoaded() {
        XCTAssertTrue(
            WhisperModelRepository.cachedTokenizerRepositoryNames(documentsDirectory: documents).isEmpty
        )
    }

    func testCachedTokenizerRepositoryNamesListsTheOpenAIRepos() throws {
        // WhisperKit caches tokenizers under huggingface/models/openai/<repo>,
        // separately from the variant folder.
        let openAI = documents.appendingPathComponent("huggingface/models/openai", isDirectory: true)
        for repo in ["whisper-small", "whisper-medium"] {
            try FileManager.default.createDirectory(
                at: openAI.appendingPathComponent(repo, isDirectory: true),
                withIntermediateDirectories: true
            )
        }

        XCTAssertEqual(
            WhisperModelRepository.cachedTokenizerRepositoryNames(documentsDirectory: documents),
            ["whisper-medium", "whisper-small"]
        )
    }
}
