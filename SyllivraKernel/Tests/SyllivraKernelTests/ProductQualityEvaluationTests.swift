import XCTest
@testable import SyllivraKernel

final class ProductQualityEvaluationTests: XCTestCase {
    func testFailuresSilenceAndExplicitAcceptanceRemainSeparate() throws {
        let model = try XCTUnwrap(ModelInfo.forIdentifier("openai_whisper-tiny"))
        let fixtures = [
            ASREvaluation.Fixture(id: "fact", languages: ["en"], metric: "wer", reference: "Do not cancel.", mustPreserve: ["not"]),
            ASREvaluation.Fixture(id: "failed", languages: ["en"], metric: "wer", reference: "Hello."),
            ASREvaluation.Fixture(id: "silent", languages: ["en"], metric: "wer", reference: "")
        ]
        var run = ASREvaluation.emptyRun(model: model, fixtures: fixtures, device: "fixture phone", osVersion: "27",
            modelRevision: "fixture", runtimeRevision: "fixture")
        run.audioSHA256 = Dictionary(uniqueKeysWithValues: fixtures.map { ($0.id, String(repeating: "a", count: 64)) })
        run.transcripts = ["fact": "Do not cancel.", "failed": "", "silent": "Hello"]
        run.finalTranscripts = ["fact": "Do cancel."]
        run.outcomes = ["fact": .inserted, "failed": .timedOut, "silent": .noSpeech]
        run.stopToProxyMs = ["fact": 50]; run.cold = ["fact": false]
        let summary = try ASREvaluation.productSummary(run, fixtures: fixtures, model: model)
        XCTAssertEqual(summary.failures, 1)
        XCTAssertEqual(summary.protectedFactFailures, ["fact"])
        XCTAssertEqual(summary.hallucinatedSilence, ["silent"])
        XCTAssertEqual(summary.rated, 0)
        run.acceptedWithoutEdits = ["failed": true]
        XCTAssertThrowsError(try ASREvaluation.productSummary(run, fixtures: fixtures, model: model))
        run.acceptedWithoutEdits = ["fact": false]
        let rated = try ASREvaluation.productSummary(run, fixtures: fixtures, model: model)
        XCTAssertEqual(rated.rated, 1)
        XCTAssertEqual(rated.acceptedUnchanged, 0)
        run.outcomes?["extra"] = .failed
        XCTAssertThrowsError(try ASREvaluation.productSummary(run, fixtures: fixtures, model: model))
        run.outcomes?.removeValue(forKey: "extra")
        run.outcomes?["failed"] = .pending
        XCTAssertThrowsError(try ASREvaluation.productSummary(run, fixtures: fixtures, model: model))
    }

    func testCorpusHasUniqueCasesAndLanguageSafetyCoverage() throws {
        let folder = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures", withExtension: nil))
        let fixtures = try JSONDecoder().decode([ASREvaluation.Fixture].self,
            from: Data(contentsOf: folder.appendingPathComponent("product-quality.json")))
        XCTAssertEqual(fixtures.count, 40)
        XCTAssertEqual(Set(fixtures.map(\.id)).count, 40)
        XCTAssertTrue(fixtures.contains { $0.languages.count == 3 })
        XCTAssertEqual(fixtures.filter { $0.reference.isEmpty }.count, 2)
        XCTAssertTrue(fixtures.contains { $0.mustPreserve?.contains("not") == true })
    }
}
