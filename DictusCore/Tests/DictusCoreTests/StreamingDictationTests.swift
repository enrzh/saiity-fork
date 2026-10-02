import XCTest
@testable import DictusCore

final class StreamingDictationTests: XCTestCase {
    func testCutsAndStopFlushConserveEverySpeechSampleWithoutDuplicates() {
        var buffer = StreamingSpeechBuffer()
        let speech = (0..<352_000).map(Float.init)
        var slices = buffer.append(speech, events: [.started(0)])
        slices += buffer.append([], events: [], flush: true)
        XCTAssertTrue(slices.allSatisfy { $0.samples.count <= 160_000 })
        XCTAssertEqual(slices.flatMap(\.samples), speech)
        XCTAssertEqual(slices.last?.region.endSample, speech.count)
        XCTAssertTrue(buffer.append([], events: [], flush: true).isEmpty)
    }

    func testSilenceIsBoundedAndDoesNotLoseTheNextOnset() {
        var buffer = StreamingSpeechBuffer()
        for _ in 0..<30 {
            XCTAssertTrue(buffer.append(Array(repeating: 0, count: 16_000), events: []).isEmpty)
            XCTAssertLessThanOrEqual(buffer.retainedSampleCount, 16_000)
        }
        let speech = Array(repeating: Float(0.5), count: 16_000)
        let slices = buffer.append(speech, events: [.started(480_000), .ended(492_800)])
        XCTAssertEqual(slices.flatMap(\.samples).filter { $0 == 0.5 }, speech)
    }

    func testPreviewReadsLeaveStopBufferIntactAndSessionBound() {
        let capture = AudioCaptureBuffer()
        capture.start(sessionID: 1)
        _ = capture.capture { [1, 2, 3] }
        XCTAssertEqual(capture.read(after: 1)?.samples, [2, 3])
        XCTAssertNil(capture.read(after: -1))
        XCTAssertEqual(capture.stop(), [1, 2, 3])
        XCTAssertNil(capture.read(after: 0))
        capture.start(sessionID: 2)
        _ = capture.capture { [4] }
        XCTAssertEqual(capture.read(after: 0)?.sessionID, 2)
    }

    func testRecognizerMigrationAndCoverageStaySeparateFromCleanup() throws {
        let name = "dictus.recognizer-tests"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        defer { defaults.removePersistentDomain(forName: name) }
        XCTAssertEqual(DictationRecognizer.load(from: defaults), .whisper)
        defaults.set(QwenASRModel.small.rawValue, forKey: SharedKeys.activeModel)
        XCTAssertEqual(DictationRecognizer.load(from: defaults), .streaming)
        defaults.set("whisper", forKey: SharedKeys.dictationRecognizer)
        XCTAssertEqual(DictationRecognizer.load(from: defaults), .whisper)
        let model = try XCTUnwrap(ModelInfo.forIdentifier(QwenASRModel.small.rawValue))
        XCTAssertEqual(model.engine, .qwenASR)
        XCTAssertEqual(model.runtimeCapability.minimumOSMajorVersion, 18)
        XCTAssertTrue(ASREvaluation.documentedLanguages(for: model).contains("zh"))
        XCTAssertFalse(ASREvaluation.documentedLanguages(for: model).contains("is"))
    }

    func testAutomaticSelectionStaysWithinRecognizerAndDoesNotMaskUnavailableQwen() {
        let phone = DeviceCapabilities(physicalMemoryGB: 8, availableMemoryMB: 3000,
            deviceModelIdentifier: "iPhone18,4", thermalState: .nominal)
        let installed: Set<String> = [QwenASRModel.small.rawValue, QwenASRModel.large.rawValue, "openai_whisper-tiny"]
        XCTAssertEqual(ModelSelectionProfile.balanced.resolvedIdentifier(installed: installed, osMajor: 27,
            capabilities: phone, recognizer: .streaming), QwenASRModel.small.rawValue)
        XCTAssertEqual(ModelSelectionProfile.precise.resolvedIdentifier(installed: installed, osMajor: 27,
            capabilities: phone, recognizer: .streaming), QwenASRModel.large.rawValue)
        XCTAssertEqual(ModelSelectionProfile.balanced.resolvedIdentifier(installed: installed, osMajor: 27,
            capabilities: phone, recognizer: .whisper), "openai_whisper-tiny")
        XCTAssertNil(ModelSelectionProfile.balanced.resolvedIdentifier(installed: installed, osMajor: 17,
            capabilities: phone, recognizer: .streaming))
        XCTAssertNil(ModelInfo.runtimeResolution(for: QwenASRModel.small.rawValue,
            installedIdentifiers: ["openai_whisper-tiny"], osMajor: 27, capabilities: phone).resolvedIdentifier)
    }
}
