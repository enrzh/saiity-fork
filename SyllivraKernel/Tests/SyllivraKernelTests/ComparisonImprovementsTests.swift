import Foundation
import XCTest
@testable import SyllivraKernel

final class ComparisonImprovementsTests: XCTestCase {
    func testAutomaticModelResolutionPrefersInstalledRecommendedModel() throws {
        let capabilities = DeviceCapabilities(
            physicalMemoryGB: 8,
            availableMemoryMB: 2_000,
            deviceModelIdentifier: "iPhone16,2",
            thermalState: .nominal
        )
        let resolution = ModelInfo.automaticRuntimeResolution(
            installedIdentifiers: ["openai_whisper-tiny", "openai_whisper-medium"],
            osMajor: 26,
            capabilities: capabilities
        )
        XCTAssertEqual(resolution.resolvedIdentifier, "openai_whisper-medium")
    }

    func testAutomaticModelResolutionFallsBackToInstalledCompatibleModel() {
        let capabilities = DeviceCapabilities(
            physicalMemoryGB: 4,
            availableMemoryMB: 2_000,
            deviceModelIdentifier: "iPhone12,1",
            thermalState: .nominal
        )
        let resolution = ModelInfo.automaticRuntimeResolution(
            installedIdentifiers: ["openai_whisper-tiny"],
            osMajor: 26,
            capabilities: capabilities
        )
        XCTAssertEqual(resolution.resolvedIdentifier, "openai_whisper-tiny")
    }

    func testSnippetStoreUpsertsAndResolvesCaseInsensitively() {
        let defaults = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsName) }

        XCTAssertNotNil(SnippetStore.upsert(
            shortcut: "addr",
            expansion: "123 Main Street",
            in: defaults
        ))
        XCTAssertEqual(
            SnippetStore.expansion(for: "ADDR", from: defaults),
            "123 Main Street"
        )
        XCTAssertEqual(SnippetStore.load(from: defaults).count, 1)
    }

    func testSnippetStoreRejectsWhitespaceShortcut() {
        let defaults = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsName) }

        XCTAssertNil(SnippetStore.upsert(shortcut: "two words", expansion: "x", in: defaults))
        XCTAssertNil(SnippetStore.expansion(for: "two words", from: defaults))
    }

    func testSystemReplacementsSkipContactNamesAndMatchCaseInsensitively() {
        let replacements = SystemTextReplacements(entries: [
            (userInput: "omw", documentText: "On my way!"),
            (userInput: "Anna", documentText: "Anna"),
            (userInput: "two words", documentText: "x"),
            (userInput: "OMW", documentText: "second definition"),
            (userInput: "", documentText: "empty"),
        ])
        XCTAssertEqual(replacements.count, 1)
        XCTAssertEqual(replacements.expansion(for: "OMW"), "On my way!")
        XCTAssertNil(replacements.expansion(for: "Anna"))
        XCTAssertNil(SystemTextReplacements().expansion(for: "omw"))
    }

    func testWritingStyleHasDistinctPromptInstructionsAndPersists() {
        let defaults = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsName) }

        XCTAssertNotEqual(WritingStyle.formal.promptInstruction, WritingStyle.casual.promptInstruction)
        XCTAssertEqual(WritingStyle.active(from: defaults), .balanced)
        WritingStyle.concise.persist(to: defaults)
        XCTAssertEqual(WritingStyle.active(from: defaults), .concise)
        XCTAssertTrue(PolishPromptEnvelope.resolve(raw: "hello", style: .concise).instructions.contains("Be concise"))
    }

    func testPromptRevisionInvalidatesCachedCleanup() {
        let old = PolishResultCache.Key(raw: "hello", engine: "fixture", target: nil, spanAware: false, promptRevision: "old")
        let new = PolishResultCache.Key(raw: "hello", engine: "fixture", target: nil, spanAware: false, promptRevision: "new")
        var cache = PolishResultCache()
        cache.insert("cached", for: old)
        XCTAssertNil(cache.value(for: new))
    }

    func testCleanupCacheKeyIncludesWritingStyle() {
        let balanced = PolishResultCache.Key(
            raw: "hello", engine: "local", target: nil, spanAware: false,
            writingStyle: WritingStyle.balanced.rawValue
        )
        let formal = PolishResultCache.Key(
            raw: "hello", engine: "local", target: nil, spanAware: false,
            writingStyle: WritingStyle.formal.rawValue
        )
        XCTAssertNotEqual(balanced, formal)
    }

    func testUrduIsRegisteredAsTranslationTarget() {
        XCTAssertEqual(TranslationLanguage.urdu.code, "ur")
        XCTAssertTrue(TranslationLanguage.allCases.contains(.urdu))
    }

    private let defaultsName = "comparison-improvements-\(UUID().uuidString)"

    private func isolatedDefaults() -> UserDefaults {
        let defaults = UserDefaults(suiteName: defaultsName)!
        defaults.removePersistentDomain(forName: defaultsName)
        return defaults
    }
}
