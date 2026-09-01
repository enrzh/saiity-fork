// DictusCore/Tests/DictusCoreTests/ModelInfoTests.swift
import XCTest
@testable import DictusCore

final class ModelInfoTests: XCTestCase {

    func testNewInstallUsesWhisperTinyAndKeepsAnExplicitModelSelection() {
        XCTAssertEqual(ModelInfo.defaultIdentifier, "openai_whisper-tiny")
        XCTAssertEqual(
            ModelInfo.initialModelIdentifier(existingSelection: nil),
            ModelInfo.defaultIdentifier
        )
        XCTAssertEqual(
            ModelInfo.initialModelIdentifier(existingSelection: "  "),
            ModelInfo.defaultIdentifier
        )
        XCTAssertEqual(
            ModelInfo.initialModelIdentifier(existingSelection: " parakeet-tdt-0.6b-v3 "),
            " parakeet-tdt-0.6b-v3 "
        )
    }

    func testCatalogDisplayNamesDoNotExposeInternalRepositoryPrefixes() {
        for model in ModelInfo.allIncludingDeprecated {
            XCTAssertFalse(model.displayName.localizedCaseInsensitiveContains("dictus"))
            XCTAssertFalse(model.displayName.hasPrefix("openai_"))
            XCTAssertFalse(model.displayName.hasPrefix("parakeet-"))
        }
    }

    func testRedesignCatalogContainsExactlySevenApprovedIdentifiers() {
        XCTAssertEqual(Set(ModelInfo.redesignCatalog.map(\.id)), [
            "openai_whisper-tiny", "openai_whisper-base", "openai_whisper-small",
            "openai_whisper-small_216MB", "openai_whisper-medium",
            "parakeet-tdt-0.6b-v3", "openai_whisper-large-v3_turbo_954MB"
        ])
    }

    func testRedesignCatalogPreservesApprovedOrderAndMetadata() {
        struct ExpectedModel {
            let identifier: String
            let sizeLabel: String
            let engine: String
        }

        let expected = [
            ExpectedModel(identifier: "openai_whisper-tiny", sizeLabel: "~40 MB", engine: SpeechEngine.whisperKit.rawValue),
            ExpectedModel(identifier: "openai_whisper-base", sizeLabel: "~75 MB", engine: SpeechEngine.whisperKit.rawValue),
            ExpectedModel(identifier: "openai_whisper-small", sizeLabel: "~250 MB", engine: SpeechEngine.whisperKit.rawValue),
            ExpectedModel(identifier: "openai_whisper-small_216MB", sizeLabel: "~216 MB", engine: SpeechEngine.whisperKit.rawValue),
            ExpectedModel(identifier: "openai_whisper-medium", sizeLabel: "~750 MB", engine: SpeechEngine.whisperKit.rawValue),
            ExpectedModel(identifier: "parakeet-tdt-0.6b-v3", sizeLabel: "~800 MB", engine: SpeechEngine.parakeet.rawValue),
            ExpectedModel(identifier: "openai_whisper-large-v3_turbo_954MB", sizeLabel: "~954 MB", engine: SpeechEngine.whisperKit.rawValue)
        ]

        XCTAssertEqual(ModelInfo.redesignCatalog.count, expected.count)
        for (actual, expected) in zip(ModelInfo.redesignCatalog, expected) {
            XCTAssertEqual(actual.identifier, expected.identifier)
            XCTAssertEqual(actual.sizeLabel, expected.sizeLabel)
            XCTAssertEqual(actual.engine.rawValue, expected.engine)
        }
    }

    func testCatalogHasOneCurrentRowPerIdentifier() {
        XCTAssertEqual(ModelInfo.allIncludingDeprecated.map(\.identifier), ModelInfo.redesignCatalog.map(\.identifier))
        XCTAssertEqual(ModelInfo.allIncludingDeprecated.map(\.identifier).count,
                       Set(ModelInfo.allIncludingDeprecated.map(\.identifier)).count)
        XCTAssertEqual(ModelInfo.redesignCatalog.count, 7)
        XCTAssertEqual(ModelInfo.all.count, Set(ModelInfo.all.map(\.id)).count)
    }

    // MARK: - Catalog visibility

    func testAllContainsOnlyAvailableModels() {
        // ModelInfo.all should contain every integrated model (6 WhisperKit + 1 Parakeet).
        // Phase 37 (issue #104) re-introduced Whisper Turbo to the catalog with per-device
        // gating — it is present here regardless of device; UI filtering happens via
        // `available(on:)` using `isSupported(on:)` in the view layer.
        XCTAssertEqual(ModelInfo.all.count, 7)
        let ids = Set(ModelInfo.all.map(\.identifier))
        XCTAssertTrue(ids.contains("openai_whisper-tiny"))
        XCTAssertTrue(ids.contains("openai_whisper-base"))
        XCTAssertTrue(ids.contains("openai_whisper-small"))
        XCTAssertTrue(ids.contains("openai_whisper-small_216MB"))
        XCTAssertTrue(ids.contains("openai_whisper-medium"))
        XCTAssertTrue(ids.contains("parakeet-tdt-0.6b-v3"))
        XCTAssertTrue(ids.contains("openai_whisper-large-v3_turbo_954MB"))
    }

    func testAllIncludingDeprecatedKeepsCompatibilityAliasForCurrentCatalog() {
        // Compatibility alias: the current catalog has no deprecated entries.
        XCTAssertEqual(ModelInfo.allIncludingDeprecated.count, 7)
        let deprecated = ModelInfo.allIncludingDeprecated.filter { $0.visibility == .deprecated }
        XCTAssertEqual(deprecated.count, 0)
        let available = ModelInfo.allIncludingDeprecated.filter { $0.visibility == .available }
        XCTAssertEqual(available.count, 7)
    }

    func testPreviouslyDownloadedModelsRemainResolvable() {
        XCTAssertNotNil(ModelInfo.forIdentifier("openai_whisper-tiny"))
        XCTAssertNotNil(ModelInfo.forIdentifier("openai_whisper-base"))
        XCTAssertEqual(ModelInfo.forIdentifier("openai_whisper-tiny")?.visibility, .available)
    }

    func testAvailableCatalogHasUniqueDownloadableDeviceCompatibleRows() {
        let device = makeCapabilities(ramGB: 8, model: "iPhone16,2")
        let rows = ModelInfo.available(on: device)

        XCTAssertEqual(rows.map(\.identifier).count, Set(rows.map(\.identifier)).count)
        XCTAssertTrue(rows.allSatisfy { $0.visibility == .available || $0.identifier == ModelInfo.recommendedIdentifier(for: device) })
        XCTAssertTrue(rows.allSatisfy { $0.isSupported(on: device) || $0.identifier == ModelInfo.recommendedIdentifier(for: device) })
    }

    func testInstalledModelsDeduplicateIdentifiersPreferCurrentMetadataAndKeepDeprecatedOnly() {
        let deprecated = makeModel(
            identifier: "shared",
            displayName: "Deprecated shared",
            visibility: .deprecated
        )
        let current = makeModel(
            identifier: "shared",
            displayName: "Current shared",
            visibility: .available
        )
        let deprecatedOnly = makeModel(
            identifier: "legacy",
            displayName: "Legacy",
            visibility: .deprecated
        )

        let rows = ModelInfo.installedRows(from: [deprecated, current, deprecatedOnly])

        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows.map(\.identifier), ["shared", "legacy"])
        XCTAssertEqual(rows.first?.displayName, "Current shared")
        XCTAssertEqual(rows.first?.visibility, .available)
        XCTAssertEqual(rows.last?.displayName, "Legacy")
        XCTAssertEqual(rows.last?.visibility, .deprecated)
    }

    private func makeModel(
        identifier: String,
        displayName: String,
        visibility: CatalogVisibility
    ) -> ModelInfo {
        ModelInfo(
            identifier: identifier,
            displayName: displayName,
            sizeLabel: "~1 MB",
            sizeBytes: 1_000_000,
            engine: .whisperKit,
            accuracyScore: 0.5,
            speedScore: 0.5,
            description: "Test model",
            visibility: visibility
        )
    }

    // MARK: - Gauge scores

    func testGaugeScoresInValidRange() {
        for model in ModelInfo.allIncludingDeprecated {
            XCTAssertTrue((0.0...1.0).contains(model.accuracyScore),
                          "\(model.identifier) accuracyScore \(model.accuracyScore) out of range")
            XCTAssertTrue((0.0...1.0).contains(model.speedScore),
                          "\(model.identifier) speedScore \(model.speedScore) out of range")
        }
    }

    func testAllModelsHaveNonEmptyDescription() {
        for model in ModelInfo.allIncludingDeprecated {
            XCTAssertFalse(model.description.isEmpty, "\(model.identifier) has empty description")
        }
    }

    // MARK: - SpeechEngine

    func testSpeechEngineRawValues() {
        XCTAssertEqual(SpeechEngine.whisperKit.rawValue, "WK")
        XCTAssertEqual(SpeechEngine.parakeet.rawValue, "PK")
    }

    func testSpeechEngineDisplayNames() {
        XCTAssertEqual(SpeechEngine.whisperKit.displayName, "WhisperKit")
        XCTAssertEqual(SpeechEngine.parakeet.displayName, "Parakeet")
    }

    func testEngineAssignment() {
        let whisperKitModels = ModelInfo.allIncludingDeprecated.filter { $0.engine == .whisperKit }
        let parakeetModels = ModelInfo.allIncludingDeprecated.filter { $0.engine == .parakeet }
        XCTAssertEqual(whisperKitModels.count, 6, "Should have six WhisperKit models")
        XCTAssertEqual(parakeetModels.count, 1, "Should have 1 Parakeet model")
        XCTAssertEqual(parakeetModels.first?.identifier, "parakeet-tdt-0.6b-v3")
    }

    // MARK: - Phase 37: per-device gating (issue #104)

    /// Helper to build a synthetic capability snapshot for gating tests.
    /// Values other than `physicalMemoryGB` are not currently consulted by the gating
    /// rule but are supplied with plausible defaults so future rule extensions do not
    /// force this helper to be updated everywhere at once.
    private func makeCapabilities(
        ramGB: Int,
        availableMB: Int = 3000,
        model: String = "iPhoneTest,1",
        thermal: ProcessInfo.ThermalState = .nominal
    ) -> DeviceCapabilities {
        DeviceCapabilities(
            physicalMemoryGB: ramGB,
            availableMemoryMB: availableMB,
            deviceModelIdentifier: model,
            thermalState: thermal
        )
    }

    func testTurboGatedOutOnLowRamDevices() {
        // iPhone 12 / iPhone SE tier: 4 GB RAM — Turbo must not be runnable.
        // Issue #369: it stays LISTED, disabled with a reason, instead of vanishing.
        let iphone12 = makeCapabilities(ramGB: 4, model: "iPhone13,2")
        let turbo = ModelInfo.forIdentifier("openai_whisper-large-v3_turbo_954MB")
        XCTAssertNotNil(turbo)
        XCTAssertFalse(turbo!.isSupported(on: iphone12))
        XCTAssertEqual(turbo!.incompatibilityReason(on: iphone12), .insufficientMemory(requiredGB: 6))
        XCTAssertTrue(ModelInfo.available(on: iphone12).map(\.identifier).contains("openai_whisper-large-v3_turbo_954MB"))
    }

    func testTurboAvailableOnSixGBPlusDevices() {
        // iPhone 14 Pro / iPhone 15 tier: 6 GB — passes the quantized Turbo gate.
        // Argmax lists iPhone14/15/16/17 families as supported for `_954MB`.
        let iphone15 = makeCapabilities(ramGB: 6, model: "iPhone15,4")
        let turbo = ModelInfo.forIdentifier("openai_whisper-large-v3_turbo_954MB")!
        XCTAssertTrue(turbo.isSupported(on: iphone15))
    }

    func testTurboAvailableOnEightGBDevices() {
        // iPhone 15 Pro Max / iPhone 16: 8 GB — well above the bar.
        let iphone15ProMax = makeCapabilities(ramGB: 8, model: "iPhone16,2")
        let turbo = ModelInfo.forIdentifier("openai_whisper-large-v3_turbo_954MB")!
        XCTAssertTrue(turbo.isSupported(on: iphone15ProMax))
        XCTAssertTrue(ModelInfo.available(on: iphone15ProMax).map(\.identifier).contains("openai_whisper-large-v3_turbo_954MB"))

        let iphone17Pro = makeCapabilities(ramGB: 12, model: "iPhone18,1")
        XCTAssertTrue(turbo.isSupported(on: iphone17Pro))
    }

    func testNonTurboModelsNotGated() {
        // Every non-Turbo model must remain visible regardless of RAM tier — Phase 37
        // must not silently shrink the catalog for existing users.
        let lowRam = makeCapabilities(ramGB: 4)
        for model in ModelInfo.all where model.identifier != "openai_whisper-large-v3_turbo_954MB" {
            XCTAssertTrue(model.isSupported(on: lowRam),
                          "\(model.identifier) must not be gated on low-RAM devices")
        }
    }

    func testRecommendedIdentifierNeverReturnsTurbo() {
        // Turbo is intentionally never recommended by default during Phase 37.
        // Verify across the full RAM spectrum to catch any future rule drift.
        for ram in [4, 6, 8, 12, 16] {
            let caps = makeCapabilities(ramGB: ram)
            XCTAssertNotEqual(ModelInfo.recommendedIdentifier(for: caps),
                              "openai_whisper-large-v3_turbo_954MB",
                              "Turbo must not be recommended at \(ram) GB")
        }
    }

    func testRecommendedIdentifierRespectsRamThreshold() {
        XCTAssertEqual(ModelInfo.recommendedIdentifier(for: makeCapabilities(ramGB: 4)),
                       "openai_whisper-small")
        XCTAssertEqual(ModelInfo.recommendedIdentifier(for: makeCapabilities(ramGB: 6)),
                       "parakeet-tdt-0.6b-v3")
        XCTAssertEqual(ModelInfo.recommendedIdentifier(for: makeCapabilities(ramGB: 8)),
                       "parakeet-tdt-0.6b-v3")
    }

    func testRecommendedIdentifierUsesBaseOnA12AndA13IPhones() {
        for identifier in ["iPhone11,2", "iPhone11,8", "iPhone12,1", "iPhone12,8"] {
            let device = makeCapabilities(ramGB: 4, model: identifier)
            XCTAssertEqual(ModelInfo.recommendedIdentifier(for: device),
                           "openai_whisper-base",
                           "\(identifier) must stay within Argmax's A12/A13 support matrix")
        }
    }

    func testRecommendedIdentifierKeepsSmallOnA14FourGBIPhone() {
        let iphone12 = makeCapabilities(ramGB: 4, model: "iPhone13,2")

        XCTAssertEqual(ModelInfo.recommendedIdentifier(for: iphone12),
                       "openai_whisper-small")
    }

    // MARK: - Issue #362: A12/A13 catalog gating

    /// On an iPhone 11 only the Argmax-listed variants may be RUNNABLE. Before the
    /// fix, Small/Medium/Parakeet were all downloadable and picking any of them
    /// reproduced the Core ML optimization hang.
    ///
    /// Issue #369: they must still be LISTED. The row is what tells the user their
    /// phone is the limit; an empty section reads as Dictus being thin.
    func testA12A13IPhonesCanRunOnlyArgmaxSupportedVariants() {
        for identifier in ["iPhone11,2", "iPhone11,8", "iPhone12,1", "iPhone12,8"] {
            let device = makeCapabilities(ramGB: 4, model: identifier)
            let rows = ModelInfo.available(on: device)
            let runnable = Set(rows.filter { $0.isSupported(on: device) }.map(\.identifier))

            XCTAssertTrue(runnable.isSubset(of: ModelInfo.a12a13SupportedIdentifiers),
                          "\(identifier) can run \(runnable.subtracting(ModelInfo.a12a13SupportedIdentifiers))")
            for unsupported in ["openai_whisper-small",
                                "openai_whisper-small_216MB",
                                "openai_whisper-medium",
                                "parakeet-tdt-0.6b-v3",
                                "openai_whisper-large-v3_turbo_954MB"] {
                XCTAssertFalse(runnable.contains(unsupported),
                               "\(identifier) must not be able to run \(unsupported)")
                XCTAssertTrue(rows.map(\.identifier).contains(unsupported),
                              "\(identifier) must still LIST \(unsupported) (issue #369)")
            }
        }
    }

    /// Issue #369's headline: the section an iPhone 11 owner opens is the full
    /// catalogue with one usable entry, not a one-line list.
    func testA12A13AvailableSectionKeepsTheWholeCatalogue() {
        let iphone11 = makeCapabilities(ramGB: 4, model: "iPhone12,1")
        let rows = ModelInfo.available(on: iphone11)
        let identifiers = Set(rows.map(\.identifier))

        // The complete integrated catalogue remains visible.
        XCTAssertEqual(identifiers, Set(ModelInfo.all.map(\.identifier)))
        XCTAssertEqual(rows.filter { $0.isSupported(on: iphone11) }.map(\.identifier),
                       ["openai_whisper-tiny", "openai_whisper-base"])
        XCTAssertTrue(identifiers.contains("openai_whisper-tiny"))
    }

    /// Every disabled row must be able to say why. A row greyed with no sentence is
    /// the failure mode issue #369 exists to remove.
    func testEveryUnrunnableRowCarriesAReason() {
        let devices = [
            makeCapabilities(ramGB: 4, model: "iPhone12,1"),
            makeCapabilities(ramGB: 4, model: "iPhone13,2"),
            makeCapabilities(ramGB: 8, model: "iPhone16,2")
        ]
        for device in devices {
            for model in ModelInfo.available(on: device) {
                XCTAssertEqual(model.incompatibilityReason(on: device) == nil,
                               model.isSupported(on: device),
                               "\(model.identifier) on \(device.deviceModelIdentifier): reason and gate disagree")
            }
        }
    }

    func testIncompatibilityReasonNamesTheRightConstraint() {
        let iphone11 = makeCapabilities(ramGB: 4, model: "iPhone12,1")
        let a14 = makeCapabilities(ramGB: 4, model: "iPhone13,2")
        let small = ModelInfo.forIdentifier("openai_whisper-small")!
        let turbo = ModelInfo.forIdentifier("openai_whisper-large-v3_turbo_954MB")!

        // Old chip, not memory: an iPhone 11 has the RAM, it lacks the generation.
        XCTAssertEqual(small.incompatibilityReason(on: iphone11), .hardwareGeneration)
        XCTAssertEqual(turbo.incompatibilityReason(on: iphone11), .hardwareGeneration)
        // Right generation, not enough memory.
        XCTAssertEqual(turbo.incompatibilityReason(on: a14), .insufficientMemory(requiredGB: 6))
        XCTAssertNil(small.incompatibilityReason(on: a14))
    }

    func testIsSupportedOnA12A13AcceptsOnlyTinyAndBase() {
        let iphone11 = makeCapabilities(ramGB: 4, model: "iPhone12,1")
        for model in ModelInfo.allIncludingDeprecated {
            let expected = ModelInfo.a12a13SupportedIdentifiers.contains(model.identifier)
            XCTAssertEqual(model.isSupported(on: iphone11), expected,
                           "\(model.identifier) gating on iPhone 11")
        }
    }

    /// The recommended model must remain reachable from the available list.
    func testRecommendedModelIsAlwaysOffered() {
        let iphone11 = makeCapabilities(ramGB: 4, model: "iPhone12,1")

        XCTAssertEqual(ModelInfo.recommendedIdentifier(for: iphone11), "openai_whisper-base")
        XCTAssertEqual(ModelInfo.forIdentifier("openai_whisper-base")?.visibility, .available)
        XCTAssertTrue(ModelInfo.all.map(\.identifier).contains("openai_whisper-base"))
        XCTAssertTrue(ModelInfo.available(on: iphone11).map(\.identifier).contains("openai_whisper-base"))
    }

    /// The same invariant stated once for every tier: whatever the app tells a device
    /// to install must be reachable from the Settings "Available" list on that device.
    func testEveryTierCanReachItsOwnRecommendation() {
        let devices = [
            makeCapabilities(ramGB: 4, model: "iPhone11,2"),
            makeCapabilities(ramGB: 4, model: "iPhone12,1"),
            makeCapabilities(ramGB: 4, model: "iPhone13,2"),
            makeCapabilities(ramGB: 6, model: "iPhone15,4"),
            makeCapabilities(ramGB: 8, model: "iPhone16,2"),
            makeCapabilities(ramGB: 12, model: "iPhone18,1")
        ]
        for device in devices {
            let recommended = ModelInfo.recommendedIdentifier(for: device)
            XCTAssertTrue(ModelInfo.available(on: device).map(\.identifier).contains(recommended),
                          "\(device.deviceModelIdentifier) recommends \(recommended) but cannot install it")
        }
    }

    /// The deprecation exception must not leak: an A14 iPhone still sees Small, and
    /// Base stays hidden there because Small is the better model on that hardware.
    func testDeprecationExceptionDoesNotLeakToA14Devices() {
        let iphone12 = makeCapabilities(ramGB: 4, model: "iPhone13,2")
        let offered = ModelInfo.available(on: iphone12).map(\.identifier)

        XCTAssertTrue(offered.contains("openai_whisper-small"))
        XCTAssertTrue(offered.contains("openai_whisper-base"))
        XCTAssertTrue(offered.contains("openai_whisper-tiny"))
        // Issue #369: Turbo is present but disabled here, not absent.
        XCTAssertTrue(offered.contains("openai_whisper-large-v3_turbo_954MB"))
    }

    /// Guards the >= 6 GB path against collateral damage from the A12/A13 branch.
    func testSixGBDeviceCatalogUnchanged() {
        let iphone15 = makeCapabilities(ramGB: 6, model: "iPhone15,4")
        let offered = Set(ModelInfo.available(on: iphone15).map(\.identifier))

        XCTAssertEqual(offered, Set(ModelInfo.all.map(\.identifier)))
        XCTAssertTrue(offered.contains("parakeet-tdt-0.6b-v3"))
        XCTAssertTrue(offered.contains("openai_whisper-large-v3_turbo_954MB"))
    }

    /// Issue #369 criterion: on a 8 GB+ device nothing is disabled and the section
    /// looks exactly as it does today.
    func testNothingIsDisabledOnEightGBDevices() {
        let iphone15ProMax = makeCapabilities(ramGB: 8, model: "iPhone16,2")
        let rows = ModelInfo.available(on: iphone15ProMax)

        XCTAssertEqual(rows.map(\.identifier), ModelInfo.all.map(\.identifier))
        XCTAssertTrue(rows.allSatisfy { $0.isSupported(on: iphone15ProMax) })
    }

    // MARK: - Supported identifiers

    func testSupportedIdentifiersMatchesAllIncludingDeprecated() {
        let ids = ModelInfo.supportedIdentifiers
        XCTAssertEqual(ids.count, 7)
        for model in ModelInfo.allIncludingDeprecated {
            XCTAssertTrue(ids.contains(model.identifier))
        }
    }

    // MARK: - Labels backward compat

    func testEachModelHasNonEmptyLabels() {
        for model in ModelInfo.allIncludingDeprecated {
            XCTAssertFalse(model.displayName.isEmpty, "\(model.identifier) has empty displayName")
            XCTAssertFalse(model.sizeLabel.isEmpty, "\(model.identifier) has empty sizeLabel")
        }
    }
}
