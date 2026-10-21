import XCTest
@testable import SyllivraKernel

final class ModelRuntimeCapabilityTests: XCTestCase {
    func testEnglishOnlyModelsDoNotAdvertiseAutomaticDetection() throws {
        let model = try XCTUnwrap(ModelInfo.forIdentifier("openai_whisper-small.en"))
        XCTAssertFalse(model.runtimeCapability.supportsAutomaticLanguageDetection)
        XCTAssertEqual(model.languageSupport.highlights.map(\.code), ["en"])
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
