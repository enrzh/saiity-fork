import XCTest
@testable import DictusCore

/// Scores captured raw ASR outputs; does not load models or certify device execution.
final class ASREvaluationTests: XCTestCase {
    private func fixtures() throws -> [ASREvaluation.Fixture] {
        let url = try XCTUnwrap(Bundle.module.url(
            forResource: "asr-evaluation", withExtension: "json", subdirectory: "Fixtures"
        ))
        return try JSONDecoder().decode([ASREvaluation.Fixture].self, from: Data(contentsOf: url))
    }

    func testFixtureAndScorerContract() throws {
        let fixtures = try fixtures()
        XCTAssertEqual(Set(fixtures.map(\.id)).count, fixtures.count)
        XCTAssertEqual(Set(fixtures.flatMap(\.languages)), ["en", "de", "fr", "es", "zh", "ja"])
        for fixture in fixtures {
            XCTAssertTrue(["wer", "cer"].contains(fixture.metric))
            XCTAssertFalse(ASREvaluation.tokens(fixture.reference, metric: fixture.metric).isEmpty)
        }
        XCTAssertEqual(ASREvaluation.editDistance(["a", "b"], ["a", "c"]), 1)
        XCTAssertEqual(ASREvaluation.editDistance(["a"], []), 1)
        XCTAssertEqual(ASREvaluation.editDistance([], ["a", "b"]), 2)
        XCTAssertEqual(ASREvaluation.editDistance(["a", "b"], ["a", "x", "b"]), 1)
        XCTAssertEqual(ASREvaluation.editDistance(["a", "b"], ["a", "b"]), 0)
        XCTAssertEqual(ASREvaluation.tokens("Bonjour, été!", metric: "wer"), ["bonjour", "été"])
        XCTAssertEqual(ASREvaluation.tokens("你 好。", metric: "cer"), ["你", "好"])
        XCTAssertEqual(ASREvaluation.tokens("e\u{301}", metric: "cer"), ["é"])
    }

    func testEmptyRunTemplateMatchesEligibleLanguages() throws {
        let englishOnly = try XCTUnwrap(ModelInfo.forIdentifier("openai_whisper-tiny.en"))
        let parakeet = try XCTUnwrap(ModelInfo.forIdentifier("parakeet-tdt-0.6b-v3"))
        let fixtures = try fixtures()

        let englishRun = ASREvaluation.emptyRun(
            model: englishOnly, fixtures: fixtures, device: "iPhone", osVersion: "26.0",
            modelRevision: "rev", runtimeRevision: "rt"
        )
        XCTAssertEqual(Set(englishRun.transcripts.keys), ["en-reminder"])

        let parakeetRun = ASREvaluation.emptyRun(
            model: parakeet, fixtures: fixtures, device: "iPhone", osVersion: "26.0",
            modelRevision: "rev", runtimeRevision: "rt"
        )
        XCTAssertTrue(parakeetRun.transcripts.keys.contains("de-en-switch"))
        XCTAssertFalse(parakeetRun.transcripts.keys.contains("zh-reminder"),
                       "Parakeet v3 must not be scored as supporting Chinese")
        XCTAssertFalse(parakeetRun.transcripts.keys.contains("en-zh-switch"))

    }

    func testValidateRejectsMissingHashesAndEmptyMetadata() throws {
        let tiny = try XCTUnwrap(ModelInfo.forIdentifier("openai_whisper-tiny"))
        let fixtures = try fixtures()
        var run = ASREvaluation.emptyRun(
            model: tiny, fixtures: fixtures, device: " ", osVersion: "26.0",
            modelRevision: "rev", runtimeRevision: "rt"
        )
        XCTAssertThrowsError(try ASREvaluation.validate(run, fixtures: fixtures, model: tiny))

        run.device = "iPhone16,2"
        run.audioSHA256["en-reminder"] = "not-a-hash"
        XCTAssertThrowsError(try ASREvaluation.validate(run, fixtures: fixtures, model: tiny))
    }

    func testScoreCapturedRun() throws {
        guard let path = ProcessInfo.processInfo.environment["DICTUS_ASR_RESULTS"] else {
            throw XCTSkip("Set DICTUS_ASR_RESULTS to captured-run JSON; no ASR benchmark was run")
        }
        let run = try JSONDecoder().decode(
            ASREvaluation.CapturedRun.self,
            from: Data(contentsOf: URL(fileURLWithPath: path))
        )
        let model = try XCTUnwrap(ModelInfo.forIdentifier(run.modelIdentifier))
        let scores = try ASREvaluation.score(run, fixtures: try fixtures(), model: model)
        for score in scores {
            print("ASR \(model.identifier) \(score.id) \(score.metric)=\(score.rate) errors=\(score.errors) units=\(score.units)")
        }
    }
}
