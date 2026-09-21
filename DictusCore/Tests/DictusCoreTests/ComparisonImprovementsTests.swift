import Foundation
import XCTest
@testable import DictusCore

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

    func testWritingStyleHasDistinctPromptInstructionsAndPersists() {
        let defaults = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsName) }

        XCTAssertNotEqual(WritingStyle.formal.promptInstruction, WritingStyle.casual.promptInstruction)
        XCTAssertEqual(WritingStyle.active(from: defaults), .balanced)
        WritingStyle.concise.persist(to: defaults)
        XCTAssertEqual(WritingStyle.active(from: defaults), .concise)
        XCTAssertTrue(PolishPromptEnvelope.userTurn(raw: "hello", style: .concise).contains("Be concise"))
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
