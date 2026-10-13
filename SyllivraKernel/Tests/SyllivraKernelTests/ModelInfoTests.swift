// SyllivraKernel/Tests/SyllivraKernelTests/ModelInfoTests.swift
import XCTest
@testable import SyllivraKernel

final class ModelInfoTests: XCTestCase {
    func testPreviewExportsHaveConservativeDeviceGatesAndTruthfulLanguageSupport() throws {
        let compactEnglish = try XCTUnwrap(ModelInfo.forIdentifier("openai_whisper-small.en_217MB"))
        let mediumEnglish = try XCTUnwrap(ModelInfo.forIdentifier("openai_whisper-medium.en"))
        let compactTurbo = try XCTUnwrap(ModelInfo.forIdentifier("openai_whisper-large-v3-v20240930_547MB"))
        let older = makeCapabilities(ramGB: 4, model: "iPhone12,1")
        let fourGB = makeCapabilities(ramGB: 4, model: "iPhone13,2")
        let eightGB = makeCapabilities(ramGB: 8, model: "iPhone16,2")
        for model in [compactEnglish, mediumEnglish, compactTurbo] {
            XCTAssertTrue(model.isExperimental)
            XCTAssertEqual(model.visibility, .available)
            XCTAssertTrue(ModelInfo.supportedIdentifiers.contains(model.identifier))
            XCTAssertFalse(ModelInfo.available(on: eightGB).contains { $0.id == model.id })
            XCTAssertTrue(ModelInfo.installedRows(from: ModelInfo.redesignCatalog).contains { $0.id == model.id })
            let resolution = ModelInfo.runtimeResolution(for: model.identifier,
                installedIdentifiers: [model.identifier], osMajor: 26, capabilities: eightGB)
            XCTAssertEqual(resolution.resolvedIdentifier, model.identifier)
            XCTAssertFalse(model.isSupported(on: older))
            XCTAssertTrue(model.isSupported(on: eightGB))
            XCTAssertNotEqual(ModelInfo.recommendedIdentifier(for: eightGB), model.identifier)
        }
        XCTAssertTrue(compactEnglish.isSupported(on: fourGB))
        XCTAssertFalse(mediumEnglish.isSupported(on: fourGB))
        XCTAssertFalse(compactTurbo.isSupported(on: fourGB))
        XCTAssertFalse(compactEnglish.runtimeCapability.supportsAutomaticLanguageDetection)
        XCTAssertFalse(mediumEnglish.runtimeCapability.supportsAutomaticLanguageDetection)
        XCTAssertTrue(compactTurbo.runtimeCapability.supportsAutomaticLanguageDetection)
        XCTAssertLessThan(compactEnglish.sizeBytes, 220_000_000)
        XCTAssertLessThan(compactTurbo.sizeBytes, 550_000_000)
    }

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

    func testRedesignCatalogContainsApprovedIdentifiers() {
        XCTAssertEqual(Set(ModelInfo.redesignCatalog.map(\.id)), [
            "openai_whisper-tiny", "openai_whisper-tiny.en", "openai_whisper-base", "openai_whisper-base.en",
            "openai_whisper-small", "openai_whisper-small.en",
            "openai_whisper-small_216MB", "openai_whisper-medium",
            "parakeet-tdt-0.6b-v2", "parakeet-tdt-0.6b-v3",
            "openai_whisper-large-v3_turbo_954MB",
            "openai_whisper-large-v2_949MB", "openai_whisper-large-v2_turbo_955MB",
            "openai_whisper-large-v3_947MB", "distil-whisper_distil-large-v3_594MB",
            "distil-whisper_distil-large-v3_turbo_600MB",
            "openai_whisper-large-v3-v20240930_626MB",
            "openai_whisper-large-v3-v20240930_turbo_632MB",
            "openai_whisper-small.en_217MB", "openai_whisper-medium.en", "openai_whisper-large-v3-v20240930_547MB",
            QwenASRModel.small.rawValue, QwenASRModel.large.rawValue
        ])
    }

    func testRedesignCatalogPreservesApprovedOrderAndMetadata() {
        struct ExpectedModel {
            let identifier: String
            let sizeLabel: String
            let engine: String
        }

        let expected = [
            ExpectedModel(identifier: "openai_whisper-tiny", sizeLabel: "~77 MB", engine: SpeechEngine.whisperKit.rawValue),
            ExpectedModel(identifier: "openai_whisper-tiny.en", sizeLabel: "~153 MB", engine: SpeechEngine.whisperKit.rawValue),
            ExpectedModel(identifier: "openai_whisper-base", sizeLabel: "~147 MB", engine: SpeechEngine.whisperKit.rawValue),
            ExpectedModel(identifier: "openai_whisper-base.en", sizeLabel: "~147 MB", engine: SpeechEngine.whisperKit.rawValue),
            ExpectedModel(identifier: "openai_whisper-small", sizeLabel: "~487 MB", engine: SpeechEngine.whisperKit.rawValue),
            ExpectedModel(identifier: "openai_whisper-small.en", sizeLabel: "~487 MB", engine: SpeechEngine.whisperKit.rawValue),
            ExpectedModel(identifier: "openai_whisper-small_216MB", sizeLabel: "~216 MB", engine: SpeechEngine.whisperKit.rawValue),
            ExpectedModel(identifier: "openai_whisper-medium", sizeLabel: "~1.53 GB", engine: SpeechEngine.whisperKit.rawValue),
            ExpectedModel(identifier: "parakeet-tdt-0.6b-v2", sizeLabel: "~800 MB", engine: SpeechEngine.parakeet.rawValue),
            ExpectedModel(identifier: "parakeet-tdt-0.6b-v3", sizeLabel: "~800 MB", engine: SpeechEngine.parakeet.rawValue),
            ExpectedModel(identifier: "openai_whisper-large-v3_turbo_954MB", sizeLabel: "~954 MB", engine: SpeechEngine.whisperKit.rawValue),
            ExpectedModel(identifier: "openai_whisper-large-v2_949MB", sizeLabel: "~949 MB", engine: SpeechEngine.whisperKit.rawValue),
            ExpectedModel(identifier: "openai_whisper-large-v2_turbo_955MB", sizeLabel: "~955 MB", engine: SpeechEngine.whisperKit.rawValue),
            ExpectedModel(identifier: "openai_whisper-large-v3_947MB", sizeLabel: "~947 MB", engine: SpeechEngine.whisperKit.rawValue),
            ExpectedModel(identifier: "distil-whisper_distil-large-v3_594MB", sizeLabel: "~594 MB", engine: SpeechEngine.whisperKit.rawValue),
            ExpectedModel(identifier: "distil-whisper_distil-large-v3_turbo_600MB", sizeLabel: "~600 MB", engine: SpeechEngine.whisperKit.rawValue),
            ExpectedModel(identifier: "openai_whisper-large-v3-v20240930_626MB", sizeLabel: "~626 MB", engine: SpeechEngine.whisperKit.rawValue),
            ExpectedModel(identifier: "openai_whisper-large-v3-v20240930_turbo_632MB", sizeLabel: "~632 MB", engine: SpeechEngine.whisperKit.rawValue),
            ExpectedModel(identifier: "openai_whisper-small.en_217MB", sizeLabel: "~218 MB", engine: SpeechEngine.whisperKit.rawValue),
            ExpectedModel(identifier: "openai_whisper-medium.en", sizeLabel: "~1.53 GB", engine: SpeechEngine.whisperKit.rawValue),
            ExpectedModel(identifier: "openai_whisper-large-v3-v20240930_547MB", sizeLabel: "~550 MB", engine: SpeechEngine.whisperKit.rawValue),
            ExpectedModel(identifier: QwenASRModel.small.rawValue, sizeLabel: "~700 MB", engine: SpeechEngine.qwenASR.rawValue),
            ExpectedModel(identifier: QwenASRModel.large.rawValue, sizeLabel: "~2.1 GB", engine: SpeechEngine.qwenASR.rawValue)
        ]

        XCTAssertEqual(ModelInfo.redesignCatalog.count, expected.count)
        for (actual, expected) in zip(ModelInfo.redesignCatalog, expected) {
            XCTAssertEqual(actual.identifier, expected.identifier)
            XCTAssertEqual(actual.sizeLabel, expected.sizeLabel)
            XCTAssertEqual(actual.engine.rawValue, expected.engine)
        }
    }

    func testCatalogHasOneCurrentRowPerIdentifier() {
        XCTAssertEqual(ModelInfo.allIncludingDeprecated.map(\.identifier), ModelInfo.redesignCatalog.filter { $0.visibility != .evaluationOnly }.map(\.identifier))
        XCTAssertEqual(ModelInfo.allIncludingDeprecated.map(\.identifier).count,
                       Set(ModelInfo.allIncludingDeprecated.map(\.identifier)).count)
        XCTAssertEqual(ModelInfo.redesignCatalog.count, 23)
        XCTAssertEqual(ModelInfo.all.count, Set(ModelInfo.all.map(\.id)).count)
    }

    // MARK: - Catalog visibility

    func testAllContainsOnlyAvailableModels() {
        XCTAssertEqual(ModelInfo.all.map(\.identifier), [
            "openai_whisper-tiny",
            "openai_whisper-base",
            "openai_whisper-medium",
            "openai_whisper-large-v3_turbo_954MB",
            "openai_whisper-large-v3_947MB",
            QwenASRModel.small.rawValue, QwenASRModel.large.rawValue
        ])
        let ids = Set(ModelInfo.all.map(\.identifier))
        XCTAssertEqual(ids, ModelInfo.downloadableIdentifiers)
        XCTAssertFalse(ids.contains("openai_whisper-small"))
        XCTAssertFalse(ids.contains("parakeet-tdt-0.6b-v3"))
        XCTAssertTrue(ids.contains("openai_whisper-large-v3_turbo_954MB"))
        XCTAssertTrue(ids.contains("openai_whisper-large-v3_947MB"))
    }

    func testAllIncludingDeprecatedKeepsCompatibilityAliasForCurrentCatalog() {
        // Compatibility alias: the current catalog has no deprecated entries.
        XCTAssertEqual(ModelInfo.allIncludingDeprecated.count, 23)
        let deprecated = ModelInfo.allIncludingDeprecated.filter { $0.visibility == .deprecated }
        XCTAssertEqual(deprecated.count, 0)
        let available = ModelInfo.allIncludingDeprecated.filter { $0.visibility == .available }
        XCTAssertEqual(available.count, 23)
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
        XCTAssertEqual(whisperKitModels.count, 19, "Compact preview exports are runtime catalog rows")
        XCTAssertEqual(parakeetModels.count, 2, "Should have two Parakeet models")
        XCTAssertEqual(parakeetModels.map(\.identifier), ["parakeet-tdt-0.6b-v2", "parakeet-tdt-0.6b-v3"])
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

    func testMemoryHeavyModelsAreGatedOnLowRamDevices() {
        let lowRam = makeCapabilities(ramGB: 4)
        let heavyIdentifiers = [
            "openai_whisper-large-v3_turbo_954MB",
            "openai_whisper-large-v2_949MB",
            "openai_whisper-large-v2_turbo_955MB",
            "openai_whisper-large-v3_947MB",
            "distil-whisper_distil-large-v3_594MB",
            "distil-whisper_distil-large-v3_turbo_600MB",
            "openai_whisper-large-v3-v20240930_626MB",
            "openai_whisper-large-v3-v20240930_turbo_632MB",
        ]
        for identifier in heavyIdentifiers {
            let model = ModelInfo.forIdentifier(identifier)
            XCTAssertNotNil(model)
            XCTAssertEqual(model?.incompatibilityReason(on: lowRam), .insufficientMemory(requiredGB: 6))
        }
        for identifier in ["openai_whisper-tiny", "openai_whisper-base", "openai_whisper-small",
                            "openai_whisper-small_216MB", "openai_whisper-medium", "parakeet-tdt-0.6b-v3"] {
            XCTAssertTrue(ModelInfo.forIdentifier(identifier)?.isSupported(on: lowRam) == true,
                          "\(identifier) should remain supported on a 4 GB A14 device")
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
                       "openai_whisper-base")
        XCTAssertEqual(ModelInfo.recommendedIdentifier(for: makeCapabilities(ramGB: 6)),
                       "openai_whisper-medium")
        XCTAssertEqual(ModelInfo.recommendedIdentifier(for: makeCapabilities(ramGB: 8)),
                       "openai_whisper-medium")
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
                       "openai_whisper-base")
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
            XCTAssertTrue(rows.map(\.identifier).contains("openai_whisper-medium"))
            XCTAssertFalse(runnable.contains("openai_whisper-medium"))
            for hidden in ["openai_whisper-small",
                           "openai_whisper-small_216MB",
                           "parakeet-tdt-0.6b-v2",
                           "parakeet-tdt-0.6b-v3",
                           "parakeet-tdt-0.6b-v3"] {
                XCTAssertFalse(rows.map(\.identifier).contains(hidden),
                               "\(identifier) must not offer \(hidden) for new downloads")
            }
            XCTAssertTrue(rows.map(\.identifier).contains("openai_whisper-large-v3_turbo_954MB"))
            XCTAssertFalse(runnable.contains("openai_whisper-large-v3_turbo_954MB"))
            XCTAssertTrue(rows.map(\.identifier).contains("openai_whisper-large-v3_947MB"))
            XCTAssertFalse(runnable.contains("openai_whisper-large-v3_947MB"))
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

        XCTAssertTrue(offered.contains("openai_whisper-medium"))
        XCTAssertTrue(offered.contains("openai_whisper-base"))
        XCTAssertTrue(offered.contains("openai_whisper-tiny"))
        XCTAssertFalse(offered.contains("openai_whisper-small"))
        XCTAssertTrue(offered.contains("openai_whisper-large-v3_turbo_954MB"))
        XCTAssertTrue(offered.contains("openai_whisper-large-v3_947MB"))
    }

    /// Guards the >= 6 GB path against collateral damage from the A12/A13 branch.
    func testSixGBDeviceCatalogUnchanged() {
        let iphone15 = makeCapabilities(ramGB: 6, model: "iPhone15,4")
        let offered = Set(ModelInfo.available(on: iphone15).map(\.identifier))

        XCTAssertEqual(offered, Set(ModelInfo.all.map(\.identifier)))
        XCTAssertTrue(offered.contains("openai_whisper-medium"))
        XCTAssertFalse(offered.contains("parakeet-tdt-0.6b-v3"))
        XCTAssertTrue(offered.contains("openai_whisper-large-v3_turbo_954MB"))
        XCTAssertTrue(offered.contains("openai_whisper-large-v3_947MB"))
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
        XCTAssertEqual(ids.count, 23)
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
