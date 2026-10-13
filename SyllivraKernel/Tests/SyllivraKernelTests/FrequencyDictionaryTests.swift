// SyllivraKernel/Tests/SyllivraKernelTests/FrequencyDictionaryTests.swift
import XCTest
@testable import SyllivraKernel

final class FrequencyDictionaryTests: XCTestCase {

    func testRankReturnsCorrectValueForKnownWord() {
        var dict = FrequencyDictionary()
        let json = #"{"de": 1, "la": 2, "le": 3, "bonjour": 500}"#
        dict.load(from: json.data(using: .utf8)!)
        XCTAssertEqual(dict.rank(of: "de"), 1)
        XCTAssertEqual(dict.rank(of: "bonjour"), 500)
    }

    func testRankReturnsZeroForUnknownWord() {
        // `rank(of:)` returns the raw frequency count (higher = more common),
        // and 0 when the word is not in the dictionary.
        var dict = FrequencyDictionary()
        let json = #"{"de": 1}"#
        dict.load(from: json.data(using: .utf8)!)
        XCTAssertEqual(dict.rank(of: "xylophone"), 0)
    }

    func testRankIsCaseInsensitive() {
        var dict = FrequencyDictionary()
        let json = #"{"bonjour": 42}"#
        dict.load(from: json.data(using: .utf8)!)
        XCTAssertEqual(dict.rank(of: "Bonjour"), 42)
        XCTAssertEqual(dict.rank(of: "BONJOUR"), 42)
    }

    func testLoadFromInvalidDataProducesEmptyDict() {
        var dict = FrequencyDictionary()
        dict.load(from: "not json".data(using: .utf8)!)
        // Empty dict → unknown words return 0.
        XCTAssertEqual(dict.rank(of: "de"), 0)
    }

    func testCommonWordsRankHigherThanUncommon() {
        var dict = FrequencyDictionary()
        let json = #"{"de": 1, "la": 2, "anticonstitutionnellement": 9999}"#
        dict.load(from: json.data(using: .utf8)!)
        XCTAssertTrue(dict.rank(of: "de") < dict.rank(of: "anticonstitutionnellement"))
    }

    func testRankedCompletionsKeepsOnlyTheRequestedTopK() {
        var dict = FrequencyDictionary()
        let json = #"{"alpha": 1, "beta": 80, "gamma": 40, "delta": 20}"#
        dict.load(from: json.data(using: .utf8)!)

        XCTAssertEqual(
            dict.rankedCompletions(["alpha", "beta", "gamma", "delta"], limit: 2),
            ["beta", "gamma"]
        )
    }

    func testRankedCompletionsPreservesInputOrderForEqualRanks() {
        var dict = FrequencyDictionary()
        let json = #"{"first": 10, "second": 10, "third": 10}"#
        dict.load(from: json.data(using: .utf8)!)

        XCTAssertEqual(
            dict.rankedCompletions(["third", "first", "second"], limit: 3),
            ["third", "first", "second"]
        )
    }

    func testPrefixAndFallbackLookupsKeepUnicodeRankingAndLimits() throws {
        var dict = FrequencyDictionary()
        let words = ["alpha": 500, "alpine": 400, "alphabet": 300, "a": 900,
                     "école": 200, "e\u{301}clair": 100, "über": 80,
                     "👩‍👩‍👧‍👧house": 70, "zebra": 60]
        dict.load(from: try JSONEncoder().encode(words))

        XCTAssertEqual(dict.prefixCompletions(prefix: "AL", limit: 2), ["alpha", "alpine"])
        XCTAssertEqual(dict.prefixCompletions(prefix: "e\u{301}", limit: 3), ["école", "e\u{301}clair"])
        XCTAssertEqual(dict.prefixCompletions(prefix: "Ü", limit: 3), ["über"])
        XCTAssertEqual(dict.prefixCompletions(prefix: "👩", limit: 3), [])
        XCTAssertEqual(dict.prefixCompletions(prefix: "👩‍👩‍👧‍👧", limit: 3), ["👩‍👩‍👧‍👧house"])
        XCTAssertEqual(dict.prefixCompletions(prefix: "alpha", limit: 3), ["alphabet"])
        XCTAssertEqual(dict.prefixCompletions(prefix: "", limit: 3), [])
        XCTAssertEqual(dict.prefixCompletions(prefix: "al", limit: 0), [])
        XCTAssertEqual(dict.topWords(count: 3), ["alpha", "alpine", "alphabet"])
        XCTAssertEqual(dict.topWords(count: 5), ["alpha", "alpine", "alphabet", "école", "e\u{301}clair"])
        XCTAssertEqual(dict.topWords(count: 0), [])
    }

    func testDerivedLookupsFollowReloadsAndCopies() throws {
        var dict = FrequencyDictionary()
        dict.load(from: try JSONEncoder().encode(["alpha": 500, "alpine": 400, "zebra": 300]))
        let retained = dict
        dict.load(from: try JSONEncoder().encode(["bonjour": 900, "bonsoir": 600]))

        XCTAssertEqual(dict.prefixCompletions(prefix: "al", limit: 3), [])
        XCTAssertEqual(dict.prefixCompletions(prefix: "bon", limit: 3), ["bonjour", "bonsoir"])
        XCTAssertEqual(dict.topWords(count: 3), ["bonjour", "bonsoir"])
        XCTAssertEqual(retained.prefixCompletions(prefix: "al", limit: 3), ["alpha", "alpine"])
        XCTAssertEqual(retained.topWords(count: 3), ["alpha", "alpine", "zebra"])

        dict.load(from: Data("not json".utf8))
        XCTAssertEqual(dict.prefixCompletions(prefix: "bon", limit: 3), [])
        XCTAssertEqual(dict.topWords(count: 3), [])
        dict.load(from: try JSONEncoder().encode(["bonjour": 900]))
        dict.load(language: "missing-responsiveness-fixture", bundle: .main)
        XCTAssertEqual(dict.prefixCompletions(prefix: "bon", limit: 3), [])
        XCTAssertEqual(dict.topWords(count: 3), [])
    }

    func testFastLookupsKeepTheSameTiePriorityAsWideRanking() throws {
        var dict = FrequencyDictionary()
        dict.load(from: try JSONEncoder().encode([
            "star": 10, "stack": 10, "stade": 10, "stone": 10,
            "alpha": 20, "école": 10, "e\u{301}clair": 10, "zebra": 10
        ]))
        let all = dict.topWords(count: 20)
        XCTAssertEqual(dict.topWords(count: 3), Array(all.prefix(3)))
        for prefix in ["s", "st", "é", "e\u{301}", "a", "z"] {
            let matches = all.filter { $0.hasPrefix(prefix) && $0.count > prefix.count }
            XCTAssertEqual(dict.prefixCompletions(prefix: prefix, limit: 2), Array(matches.prefix(2)))
        }
    }

    func testLoadFromFixtureFile() {
        guard let url = Bundle.module.url(forResource: "fr_frequency_test", withExtension: "json", subdirectory: "Fixtures"),
              let data = try? Data(contentsOf: url) else {
            XCTFail("Test fixture fr_frequency_test.json not found in test bundle")
            return
        }
        var dict = FrequencyDictionary()
        dict.load(from: data)
        XCTAssertEqual(dict.rank(of: "de"), 1)
        XCTAssertTrue(dict.rank(of: "le") < dict.rank(of: "anticonstitutionnellement"))
    }
}
