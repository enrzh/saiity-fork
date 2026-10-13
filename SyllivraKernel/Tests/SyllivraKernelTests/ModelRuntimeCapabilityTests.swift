import XCTest
@testable import SyllivraKernel

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

    func testUnknownRequestedModelRemainsUnresolvedWithoutInstalledFallback() {
        let resolution = ModelInfo.runtimeResolution(
            for: "removed-speech-engine",
            installedIdentifiers: ["removed-speech-engine"],
            osMajor: 17,
            capabilities: capabilities(ramGB: 8)
        )

        XCTAssertNil(resolution.resolvedIdentifier)
        XCTAssertEqual(resolution.fallbackReason, .unknownModel)
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
