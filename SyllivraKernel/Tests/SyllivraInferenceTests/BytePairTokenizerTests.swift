import XCTest
import CryptoKit
@testable import SyllivraInference

final class BytePairTokenizerTests: XCTestCase {
    private struct Golden: Decodable {
        struct Case: Decodable { let name: String; let text: String; let ids: [Int32]; let decoded: String }
        let revision: String
        let tokenizerSHA256: String
        let cases: [Case]
    }

    private var fixture: URL {
        get throws { try XCTUnwrap(Bundle.module.resourceURL).appendingPathComponent("Fixtures/qwen2.5") }
    }

    private func changedTokenizer(_ change: (inout [String: Any]) -> Void) throws -> BytePairTokenizer {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var document = try XCTUnwrap(JSONSerialization.jsonObject(
            with: Data(contentsOf: fixture.appendingPathComponent("tokenizer.json"))) as? [String: Any])
        change(&document)
        try JSONSerialization.data(withJSONObject: document).write(to: directory.appendingPathComponent("tokenizer.json"))
        return try BytePairTokenizer(directory: directory)
    }

    func testExactTokenIDsMatchPinnedIndependentReference() throws {
        let data = try Data(contentsOf: fixture.appendingPathComponent("tokenizer.json"))
        let golden = try JSONDecoder().decode(Golden.self, from: Data(contentsOf: fixture.appendingPathComponent("golden.json")))
        XCTAssertEqual(golden.revision, "7ae557604adf67be50417f59c2c2f167def9a775")
        XCTAssertEqual(golden.cases.count, 78)
        XCTAssertEqual(SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(), golden.tokenizerSHA256)
        let tokenizer = try BytePairTokenizer(directory: fixture)
        for item in golden.cases {
            XCTAssertEqual(try tokenizer.encode(item.text), item.ids, item.name)
            XCTAssertEqual(try tokenizer.decode(item.ids), item.decoded, item.name)
        }
    }

    func testDecodingRetainsSplitUTF8UntilBytesAreJoined() throws {
        let tokenizer = try BytePairTokenizer(directory: fixture)
        // U+200D is split into E2 80 and 8D by the real Qwen vocabulary.
        XCTAssertEqual(try tokenizer.tokenBytes(for: 378), [0xe2, 0x80])
        XCTAssertEqual(try tokenizer.tokenBytes(for: 235), [0x8d])
        XCTAssertEqual(try tokenizer.decode([378, 235]), "\u{200d}")
        XCTAssertEqual(try tokenizer.decode([378]), "\u{fffd}")
    }

    func testUnknownTokenIDsFailWithoutDroppingOutput() throws {
        let tokenizer = try BytePairTokenizer(directory: fixture)
        XCTAssertThrowsError(try tokenizer.decode([-1]))
        XCTAssertThrowsError(try tokenizer.decode([Int32.max]))
        XCTAssertThrowsError(try tokenizer.tokenBytes(for: 151665))
    }

    func testUnsupportedNormalizationAndPretokenizationFailClosed() throws {
        XCTAssertThrowsError(try changedTokenizer { $0["normalizer"] = ["type": "Lowercase"] })
        XCTAssertThrowsError(try changedTokenizer { $0["pre_tokenizer"] = ["type": "Whitespace"] })
        XCTAssertThrowsError(try changedTokenizer { document in
            var sequence = document["pre_tokenizer"] as! [String: Any]
            var steps = sequence["pretokenizers"] as! [[String: Any]]
            steps[0]["pattern"] = ["Regex": "\\S+"]
            sequence["pretokenizers"] = steps
            document["pre_tokenizer"] = sequence
        })
    }

    func testImplicitPaddingTruncationAndPostprocessingFailClosed() throws {
        XCTAssertThrowsError(try changedTokenizer { $0["truncation"] = ["max_length": 10] })
        XCTAssertThrowsError(try changedTokenizer { $0["padding"] = ["strategy": "BatchLongest"] })
        XCTAssertThrowsError(try changedTokenizer { $0["post_processor"] = ["type": "TemplateProcessing"] })
        XCTAssertThrowsError(try changedTokenizer { $0["decoder"] = ["type": "WordPiece"] })
    }

    func testUnsupportedBPEOptionsFailClosed() throws {
        for (key, value) in [("dropout", 0.1 as Any), ("byte_fallback", true), ("ignore_merges", true),
                             ("unk_token", "unknown"), ("fuse_unk", true), ("continuing_subword_prefix", "##")] {
            XCTAssertThrowsError(try changedTokenizer { document in
                var model = document["model"] as! [String: Any]
                model[key] = value
                document["model"] = model
            }, key)
        }
    }

    func testMalformedVocabularyAndMergeRulesFailClosed() throws {
        XCTAssertThrowsError(try changedTokenizer { document in
            var model = document["model"] as! [String: Any]
            var vocabulary = model["vocab"] as! [String: Int]
            vocabulary["!"] = nil
            model["vocab"] = vocabulary
            document["model"] = model
        })
        for merges in [["missing missing"], ["Ġ Ġ", "Ġ Ġ"], ["one"], ["a b"]] {
            XCTAssertThrowsError(try changedTokenizer { document in
                var model = document["model"] as! [String: Any]
                model["merges"] = merges
                document["model"] = model
            }, "\(merges)")
        }
        XCTAssertThrowsError(try changedTokenizer { document in
            var model = document["model"] as! [String: Any]
            var vocabulary = model["vocab"] as! [String: Int]
            vocabulary["\""] = vocabulary["!"]
            model["vocab"] = vocabulary
            document["model"] = model
        })
    }

    func testUnsupportedAddedTokenMatchingFailsClosed() throws {
        for key in ["lstrip", "rstrip", "single_word", "normalized"] {
            XCTAssertThrowsError(try changedTokenizer { document in
                var tokens = document["added_tokens"] as! [[String: Any]]
                tokens[0][key] = true
                document["added_tokens"] = tokens
            }, key)
        }
        XCTAssertThrowsError(try changedTokenizer { document in
            var tokens = document["added_tokens"] as! [[String: Any]]
            tokens[1]["id"] = tokens[0]["id"]
            document["added_tokens"] = tokens
        })
    }

    func testMergeOperandsMustBeDefinedBeforeTheirResult() throws {
        XCTAssertThrowsError(try changedTokenizer { document in
            var model = document["model"] as! [String: Any]
            var merges = model["merges"] as! [String]
            merges.swapAt(0, 1)
            model["merges"] = merges
            document["model"] = model
        })
    }

    func testCancelledEncodingDoesNotReturnPartialTokens() async throws {
        let tokenizer = try BytePairTokenizer(directory: fixture)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try tokenizer.encode("A cancelled request")
        }
        do { _ = try await task.value; XCTFail("Cancelled encoding must throw") }
        catch is CancellationError { }
    }
}
