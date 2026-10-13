import XCTest
@testable import SyllivraKernel

final class SpeechRegionSegmentationTests: XCTestCase {
    private let sampleRate = 16_000
    private let segmenter = SpeechRegionSegmenter()

    func testGermanOnlyStaysOneRegion() {
        let regions = segmenter.regions(in: speech(seconds: 2))
        XCTAssertEqual(regions.count, 1)
        XCTAssertEqual(regions[0].sampleCount, 2 * sampleRate)
    }

    func testEnglishOnlyStaysOneRegion() {
        XCTAssertEqual(segmenter.regions(in: speech(seconds: 1.2)).count, 1)
    }

    func testGermanToEnglishSwitchSeparatedBySilenceCreatesContextualRegions() {
        let samples = speech(seconds: 1.2) + silence(seconds: 0.45) + speech(seconds: 1.2)
        let regions = segmenter.regions(in: samples)

        XCTAssertEqual(regions.count, 2)
        XCTAssertEqual(regions.first?.startSample, 0)
        XCTAssertEqual(regions.last?.endSample, samples.count)
        XCTAssertLessThan(regions[1].startSample, regions[0].endSample)
        XCTAssertGreaterThanOrEqual(regions[0].endSample, regions[1].startSample)
    }

    func testEnglishGermanEnglishCreatesThreeRegions() {
        let samples = speech(seconds: 1) + silence(seconds: 0.4)
            + speech(seconds: 1) + silence(seconds: 0.4) + speech(seconds: 1)
        XCTAssertEqual(segmenter.regions(in: samples).count, 3)
    }

    func testLatinChineseLatinDoesNotChangeSegmentationPolicy() {
        let samples = speech(seconds: 1) + silence(seconds: 0.4)
            + speech(seconds: 1) + silence(seconds: 0.4) + speech(seconds: 1)
        XCTAssertEqual(segmenter.regions(in: samples).count, 3)
    }

    func testNoConvenientSilenceUsesMaximumDurationBoundary() {
        let regions = segmenter.regions(in: speech(seconds: 21))
        XCTAssertEqual(regions.count, 3)
        XCTAssertTrue(regions.allSatisfy { $0.sampleCount <= 10 * sampleRate })
        XCTAssertTrue(regions.dropLast().allSatisfy { $0.sampleCount >= 9 * sampleRate })
    }

    func testHardCutMovesBackToAvoidTinyFinalRegion() {
        let regions = segmenter.regions(in: speech(seconds: 10.1))

        XCTAssertEqual(regions.count, 2)
        XCTAssertGreaterThanOrEqual(regions[0].durationSeconds(), 9.0)
        XCTAssertGreaterThanOrEqual(regions[1].durationSeconds(), 0.8)
    }

    func testHardCutSkipsNaturalBoundaryThatWouldCreateTinyRegion() {
        let samples = speech(seconds: 9.7) + silence(seconds: 0.4) + speech(seconds: 1.0)
        let regions = segmenter.regions(in: samples)

        XCTAssertEqual(regions.count, 2)
        XCTAssertGreaterThanOrEqual(regions[1].durationSeconds(), 0.8)
        XCTAssertLessThanOrEqual(regions[0].endSample, regions[1].endSample)
    }

    func testAllSamplesBetweenSpeechEdgesRemainCovered() {
        let samples = speech(seconds: 1.2) + silence(seconds: 0.45) + speech(seconds: 1.2)
        let regions = segmenter.regions(in: samples)

        XCTAssertEqual(regions.first?.startSample, 0)
        XCTAssertEqual(regions.last?.endSample, samples.count)
        for pair in zip(regions, regions.dropFirst()) {
            XCTAssertLessThanOrEqual(pair.1.startSample, pair.0.endSample)
        }
    }

    func testCoverageReportsOverlapWithoutARealGap() {
        let coverage = SpeechRegionCoverage(
            regions: [
                SpeechRegion(startSample: 0, endSample: 100),
                SpeechRegion(startSample: 80, endSample: 200)
            ],
            totalSampleCount: 240
        )

        XCTAssertEqual(coverage.coveredSampleCount, 200)
        XCTAssertEqual(coverage.overlapSampleCount, 20)
        XCTAssertEqual(coverage.uncoveredWithinSpeechSpan, 0)
        XCTAssertTrue(coverage.hasOverlap)
        XCTAssertFalse(coverage.hasDroppedSpeech)
    }

    func testCoverageReportsARealHoleBetweenRegions() {
        let coverage = SpeechRegionCoverage(
            regions: [
                SpeechRegion(startSample: 20, endSample: 100),
                SpeechRegion(startSample: 120, endSample: 200)
            ],
            totalSampleCount: 240
        )

        XCTAssertEqual(coverage.uncoveredWithinSpeechSpan, 20)
        XCTAssertEqual(coverage.uncoveredSampleCount, 80)
        XCTAssertTrue(coverage.hasDroppedSpeech)
    }

    func testVeryShortDictationIsNotDiscarded() {
        let regions = segmenter.regions(in: speech(seconds: 0.1))
        XCTAssertEqual(regions.count, 1)
        XCTAssertGreaterThan(regions[0].sampleCount, 0)
    }

    func testNoSpeechReturnsNoRegions() {
        XCTAssertTrue(segmenter.regions(in: silence(seconds: 3)).isEmpty)
    }

    func testLongSingleLanguageRecordingUsesHardCutsOnlyWhenNeeded() {
        let regions = segmenter.regions(in: speech(seconds: 9))
        XCTAssertEqual(regions.count, 1)
    }

    func testGermanEnglishGermanTranscriptKeepsEachSpokenLanguage() {
        let regions = [
            SpeechRegionTranscript(
                region: SpeechRegion(startSample: 0, endSample: 10),
                text: "Schick mir bitte",
                detectedLanguage: "de"
            ),
            SpeechRegionTranscript(
                region: SpeechRegion(startSample: 20, endSample: 30),
                text: "the updated invoice",
                detectedLanguage: "en"
            ),
            SpeechRegionTranscript(
                region: SpeechRegion(startSample: 40, endSample: 50),
                text: "morgen bitte",
                detectedLanguage: "de"
            )
        ]
        XCTAssertEqual(
            SpeechTranscriptMerger.merge(regions),
            "Schick mir bitte the updated invoice morgen bitte"
        )
    }

    func testLatinChineseLatinTranscriptKeepsScriptsInPlace() {
        let regions = [
            SpeechRegionTranscript(
                region: SpeechRegion(startSample: 0, endSample: 10),
                text: "Can you send me",
                detectedLanguage: "en"
            ),
            SpeechRegionTranscript(
                region: SpeechRegion(startSample: 20, endSample: 30),
                text: "这份文件",
                detectedLanguage: "zh"
            ),
            SpeechRegionTranscript(
                region: SpeechRegion(startSample: 40, endSample: 50),
                text: "tomorrow please",
                detectedLanguage: "en"
            )
        ]
        XCTAssertEqual(
            SpeechTranscriptMerger.merge(regions),
            "Can you send me这份文件tomorrow please"
        )
    }

    func testOverlapRemovesRepeatedWordWithoutRemovingNormalRepeatedWord() {
        let first = SpeechRegionTranscript(
            region: SpeechRegion(startSample: 0, endSample: 10),
            text: "send the invoice",
            overlapsPreviousRegion: false
        )
        let second = SpeechRegionTranscript(
            region: SpeechRegion(startSample: 5, endSample: 15),
            text: "invoice tomorrow",
            overlapsPreviousRegion: true
        )
        XCTAssertEqual(SpeechTranscriptMerger.merge([first, second]), "send the invoice tomorrow")

        let legitimate = [
            SpeechRegionTranscript(
                region: SpeechRegion(startSample: 0, endSample: 10),
                text: "go go",
                overlapsPreviousRegion: false
            ),
            SpeechRegionTranscript(
                region: SpeechRegion(startSample: 10, endSample: 20),
                text: "go home",
                overlapsPreviousRegion: false
            )
        ]
        XCTAssertEqual(SpeechTranscriptMerger.merge(legitimate), "go go go home")
    }

    func testCJKBoundariesDoNotInsertWesternSpaces() {
        XCTAssertEqual(
            SpeechTranscriptMerger.merge([
                SpeechRegionTranscript(region: SpeechRegion(startSample: 0, endSample: 1), text: "你好，", overlapsPreviousRegion: false),
                SpeechRegionTranscript(region: SpeechRegion(startSample: 0, endSample: 1), text: "can you send me", overlapsPreviousRegion: false),
                SpeechRegionTranscript(region: SpeechRegion(startSample: 0, endSample: 1), text: "的发票。", overlapsPreviousRegion: false)
            ]),
            "你好，can you send me的发票。"
        )
    }

    func testCJKOverlapRemovesRepeatedBoundaryText() {
        let regions = [
            SpeechRegionTranscript(region: SpeechRegion(startSample: 0, endSample: 10), text: "你好世界", overlapsPreviousRegion: false),
            SpeechRegionTranscript(region: SpeechRegion(startSample: 5, endSample: 15), text: "世界，can you", overlapsPreviousRegion: true)
        ]
        XCTAssertEqual(SpeechTranscriptMerger.merge(regions), "你好世界，can you")
    }

    func testSingleCJKCharacterOverlapIsRemoved() {
        let regions = [
            SpeechRegionTranscript(region: SpeechRegion(startSample: 0, endSample: 10), text: "你好", overlapsPreviousRegion: false),
            SpeechRegionTranscript(region: SpeechRegion(startSample: 5, endSample: 15), text: "好，世界", overlapsPreviousRegion: true)
        ]

        XCTAssertEqual(SpeechTranscriptMerger.merge(regions), "你好，世界")
    }

    func testOverlapPreservesPunctuationWithoutDuplicatingIt() {
        let regions = [
            SpeechRegionTranscript(region: SpeechRegion(startSample: 0, endSample: 10), text: "send the invoice.", overlapsPreviousRegion: false),
            SpeechRegionTranscript(region: SpeechRegion(startSample: 5, endSample: 15), text: "invoice. tomorrow", overlapsPreviousRegion: true)
        ]

        XCTAssertEqual(SpeechTranscriptMerger.merge(regions), "send the invoice. tomorrow")
    }

    func testLatinSentenceSpacingSurvivesMerge() {
        XCTAssertEqual(SpeechTranscriptMerger.merge(["hello.", "world"]), "hello. world")
    }

    func testMergePreservesNumbersAndAddresses() {
        let input = "Pay 12.50 or 12,50 at 10:30 to person@example.com via https://example.org/a?x=1&y=2."
        XCTAssertEqual(SpeechTranscriptMerger.merge([input]), input)
    }

    func testOverlapPreservesNumbersAndAddresses() {
        let regions = [
            SpeechRegionTranscript(region: SpeechRegion(startSample: 0, endSample: 10),
                                   text: "Pay 12.50 at 10:30", overlapsPreviousRegion: false),
            SpeechRegionTranscript(region: SpeechRegion(startSample: 5, endSample: 15),
                                   text: "at 10:30 to person@example.com", overlapsPreviousRegion: true)
        ]
        XCTAssertEqual(SpeechTranscriptMerger.merge(regions), "Pay 12.50 at 10:30 to person@example.com")
    }

    func testRegionMetadataSurvivesSequentialRunner() async throws {
        let region = SpeechRegion(startSample: 0, endSample: sampleRate)
        let results = try await SpeechRegionTranscriptionRunner.run(
            audioSamples: speech(seconds: 1),
            regions: [region],
            decode: { _, _, region in
                SpeechRegionTranscript(
                    region: region,
                    text: "hello",
                    detectedLanguage: "en",
                    validatedLanguage: "en",
                    decodeDurationSeconds: 0.25,
                    averageLogProbability: -0.12,
                    fallbackReason: nil
                )
            }
        )

        XCTAssertEqual(results.first?.characterCount, 5)
        XCTAssertEqual(results.first?.decodeDurationSeconds, 0.25)
        XCTAssertEqual(results.first?.averageLogProbability, -0.12)
        XCTAssertNil(results.first?.fallbackReason)
        XCTAssertEqual(results.first?.validatedLanguage, "en")
    }

    func testRunnerDecodesSequentiallyAndHonorsCancellation() async {
        let samples = speech(seconds: 1) + silence(seconds: 0.4) + speech(seconds: 1)
        let callCount = LockedCounter()
        let firstDecodeStarted = DispatchSemaphore(value: 0)
        let task = Task.detached {
            try await SpeechRegionTranscriptionRunner.run(
                audioSamples: samples,
                decode: { _, region in
                    callCount.increment()
                    firstDecodeStarted.signal()
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                    return SpeechRegionTranscript(region: region, text: "piece")
                }
            )
        }
        XCTAssertEqual(
            firstDecodeStarted.wait(timeout: .now() + 2),
            .success,
            "the cancellation test must start a real segment decode"
        )
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Cancellation should stop region decoding")
        } catch is CancellationError {
            XCTAssertEqual(callCount.value, 1)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testRunnerRejectsARegionReturnedAfterCancellation() async {
        let samples = speech(seconds: 1) + silence(seconds: 0.4) + speech(seconds: 1)
        let firstDecodeStarted = DispatchSemaphore(value: 0)
        let task = Task.detached {
            try await SpeechRegionTranscriptionRunner.run(
                audioSamples: samples,
                decode: { _, region in
                    firstDecodeStarted.signal()
                    try? await Task.sleep(nanoseconds: 100_000_000)
                    return SpeechRegionTranscript(region: region, text: "piece")
                }
            )
        }

        XCTAssertEqual(
            firstDecodeStarted.wait(timeout: .now() + 2),
            .success,
            "the post-decode cancellation test must start a real segment decode"
        )
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Cancellation should discard a decode that returned after cancellation")
        } catch is CancellationError {
            // Expected: the runner checks cancellation after the decoder returns.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testRunnerNeverDecodesRegionsConcurrently() async throws {
        let samples = speech(seconds: 1) + silence(seconds: 0.4)
            + speech(seconds: 1) + silence(seconds: 0.4) + speech(seconds: 1)
        let tracker = ConcurrentDecodeTracker()

        let results = try await SpeechRegionTranscriptionRunner.run(
            audioSamples: samples,
            decode: { _, region in
                tracker.enter()
                defer { tracker.leave() }
                try await Task.sleep(nanoseconds: 10_000_000)
                return SpeechRegionTranscript(region: region, text: "piece")
            }
        )

        XCTAssertEqual(results.count, 3)
        XCTAssertEqual(tracker.maximumActive, 1)
    }

    private func speech(seconds: Double) -> [Float] {
        Array(repeating: Float(0.1), count: Int(seconds * Double(sampleRate)))
    }

    private func silence(seconds: Double) -> [Float] {
        Array(repeating: Float.zero, count: Int(seconds * Double(sampleRate)))
    }
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
    }

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }
}

private final class ConcurrentDecodeTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var active = 0
    private var maximum = 0

    func enter() {
        lock.lock()
        active += 1
        maximum = max(maximum, active)
        lock.unlock()
    }

    func leave() {
        lock.lock()
        active -= 1
        lock.unlock()
    }

    var maximumActive: Int {
        lock.lock()
        defer { lock.unlock() }
        return maximum
    }
}
