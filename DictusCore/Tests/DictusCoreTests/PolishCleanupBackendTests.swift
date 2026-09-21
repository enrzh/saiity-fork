import XCTest
@testable import DictusCore

final class PolishCleanupBackendTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "dictus.polish-cleanup-backend-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testDefaultIsAppleIntelligenceAndPersistsOnFirstLoad() {
        XCTAssertEqual(PolishCleanupBackend.load(from: defaults, customModels: []), .appleIntelligence)
        XCTAssertEqual(
            defaults.string(forKey: SharedKeys.polishCleanupBackend),
            PolishCleanupBackend.appleIntelligenceStorageValue
        )
    }

    func testMissingKeyMigratesExistingValidOllamaCleanup() {
        let model = validOllamaModel(name: "Local cleanup")
        CustomModel.save([model], to: defaults)

        XCTAssertEqual(
            PolishCleanupBackend.load(from: defaults),
            .ollama(model.id)
        )
        XCTAssertEqual(
            defaults.string(forKey: SharedKeys.polishCleanupBackend),
            PolishCleanupBackend.ollama(model.id).storageValue
        )
    }

    func testExplicitAppleIntelligenceWinsOverRegisteredOllama() {
        let model = validOllamaModel(name: "Local cleanup")
        PolishCleanupBackend.appleIntelligence.persist(to: defaults)

        let loaded = PolishCleanupBackend.load(from: defaults, customModels: [model])
        XCTAssertEqual(loaded, .appleIntelligence)
        XCTAssertEqual(
            PolishCleanupBackend.resolvedEngine(
                preference: loaded,
                appleFMAvailable: true,
                validOllamaIDs: [model.id]
            ),
            .appleIntelligence
        )
    }

    func testLaterOllamaRegistrationDoesNotStealPersistedAppleIntelligence() {
        XCTAssertEqual(PolishCleanupBackend.load(from: defaults, customModels: []), .appleIntelligence)
        let model = validOllamaModel(name: "Late cleanup")
        XCTAssertEqual(
            PolishCleanupBackend.load(from: defaults, customModels: [model]),
            .appleIntelligence
        )
    }

    func testSelectedOllamaIsUsedWhenValid() {
        let model = validOllamaModel(name: "Local cleanup")
        PolishCleanupBackend.ollama(model.id).persist(to: defaults)

        XCTAssertEqual(
            PolishCleanupBackend.load(from: defaults, customModels: [model]),
            .ollama(model.id)
        )
        XCTAssertEqual(
            PolishCleanupBackend.resolvedEngine(
                preference: .ollama(model.id),
                appleFMAvailable: true,
                validOllamaIDs: [model.id]
            ),
            .ollama(model.id)
        )
    }

    func testDeletedOllamaFallsBackToRemainingThenAppleIntelligence() {
        let first = validOllamaModel(name: "One")
        let second = validOllamaModel(name: "Two")
        PolishCleanupBackend.ollama(first.id).persist(to: defaults)

        PolishCleanupBackend.handleDeletedModel(first, remaining: [second], defaults: defaults)
        XCTAssertEqual(PolishCleanupBackend.load(from: defaults, customModels: [second]), .ollama(second.id))

        PolishCleanupBackend.handleDeletedModel(second, remaining: [], defaults: defaults)
        XCTAssertEqual(PolishCleanupBackend.load(from: defaults, customModels: []), .appleIntelligence)
    }

    func testUnavailableAppleIntelligenceFallsThroughToPassthrough() {
        XCTAssertEqual(
            PolishCleanupBackend.resolvedEngine(
                preference: .appleIntelligence,
                appleFMAvailable: false,
                validOllamaIDs: []
            ),
            .passthrough
        )
    }

    func testInvalidOllamaFallsBackToAppleIntelligenceWhenAvailable() {
        let missing = UUID()
        XCTAssertEqual(
            PolishCleanupBackend.resolvedEngine(
                preference: .ollama(missing),
                appleFMAvailable: true,
                validOllamaIDs: []
            ),
            .appleIntelligence
        )
    }

    func testParseRoundTrip() {
        let id = UUID()
        XCTAssertEqual(PolishCleanupBackend.parse("appleIntelligence"), .appleIntelligence)
        XCTAssertEqual(PolishCleanupBackend.parse("ollama:\(id.uuidString)"), .ollama(id))
        XCTAssertNil(PolishCleanupBackend.parse("ollama"))
        XCTAssertNil(PolishCleanupBackend.parse("whisper"))
    }

    private func validOllamaModel(name: String) -> CustomModel {
        CustomModel(
            name: name,
            repositoryURL: "http://127.0.0.1:11434",
            role: .cleanup,
            source: .ollama,
            modelName: "llama3.2:3b"
        )
    }
}
