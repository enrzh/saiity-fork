import XCTest
@testable import DictusCore

final class ModelRuntimeCapabilityTests: XCTestCase {
    func testEnglishOnlyModelsDoNotAdvertiseAutomaticDetection() throws {
        let model = try XCTUnwrap(ModelInfo.forIdentifier("openai_whisper-small.en"))
        XCTAssertFalse(model.runtimeCapability.supportsAutomaticLanguageDetection)
        XCTAssertEqual(model.languageSupport.highlights.map(\.code), ["en"])
    }

    func testParakeetMetadataDoesNotClaimChineseSupport() throws {
        let model = try XCTUnwrap(ModelInfo.forIdentifier("parakeet-tdt-0.6b-v3"))
        XCTAssertEqual(model.runtimeCapability.minimumOSMajorVersion, 17)
        XCTAssertFalse(model.languageSupport.highlights.map(\.code).contains("zh"))
        XCTAssertFalse(model.languageSupport.additionalCodes.contains("zh"))
    }

    func testQwenFallsBackOnlyToAnInstalledCompatibleWhisperModelOnOlderOS() {
        let resolution = ModelInfo.runtimeResolution(
            for: "qwen3-asr-0.6b-f32",
            installedIdentifiers: ["qwen3-asr-0.6b-f32", "openai_whisper-small"],
            osMajor: 17,
            capabilities: capabilities(ramGB: 8)
        )

        XCTAssertEqual(resolution.resolvedIdentifier, "openai_whisper-small")
        XCTAssertEqual(resolution.fallbackReason, .unavailableOnOS)
        XCTAssertTrue(resolution.usedFallback)
    }

    func testUnsupportedRequestedModelRemainsUnresolvedWithoutInstalledFallback() {
        let resolution = ModelInfo.runtimeResolution(
            for: "qwen3-asr-0.6b-f32",
            installedIdentifiers: ["qwen3-asr-0.6b-f32"],
            osMajor: 17,
            capabilities: capabilities(ramGB: 8)
        )

        XCTAssertNil(resolution.resolvedIdentifier)
        XCTAssertEqual(resolution.fallbackReason, .unavailableOnOS)
    }

    private func capabilities(ramGB: Int) -> DeviceCapabilities {
        DeviceCapabilities(
            physicalMemoryGB: ramGB,
            availableMemoryMB: 3000,
            deviceModelIdentifier: "iPhone16,2",
            thermalState: .nominal
        )
    }
}
