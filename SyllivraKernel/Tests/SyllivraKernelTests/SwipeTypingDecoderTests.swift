import CoreGraphics
import XCTest
@testable import SyllivraKernel

final class SwipeTypingDecoderTests: XCTestCase {
    func testSamplesCollapseConsecutiveDuplicatesAndIgnoreNonLetters() {
        XCTAssertEqual(SwipeTypingDecoder.sampledLetters(from: "hhjjkllo"), "hjklo")
        XCTAssertEqual(SwipeTypingDecoder.sampledLetters(from: "h-e-l-l-o"), "helo")
        XCTAssertEqual(SwipeTypingDecoder.sampledLetters(from: Array("HhEeLlLo")), "helo")
    }

    func testMatchesRequiresFirstLastAndSubsequence() {
        XCTAssertTrue(SwipeTypingDecoder.matches("hello", path: "hjelelo"))
        XCTAssertTrue(SwipeTypingDecoder.matches("the", path: "tghe"))
        XCTAssertFalse(SwipeTypingDecoder.matches("hello", path: "hjklo"))
        XCTAssertFalse(SwipeTypingDecoder.matches("hello", path: "world"))
        XCTAssertFalse(SwipeTypingDecoder.matches("hello", path: "h"))
        XCTAssertFalse(SwipeTypingDecoder.shouldCommit(path: "h"))
    }

    func testFrequencyRanksSwipeCandidates() {
        var dictionary = FrequencyDictionary()
        dictionary.load(from: Data(#"{"hello":90,"help":40,"hero":10,"world":80}"#.utf8))
        XCTAssertEqual(dictionary.swipeCandidates(path: "hjelelo", limit: 3), ["hello"])
        XCTAssertEqual(dictionary.swipeCandidates(path: "hjerto", limit: 3), ["hero"])
    }

    func testDwellOnLProducesRepeatedLetter() {
        let keys = qwertyKeys()
        let path = letterPath(["h", "e", "l", "o"], dwell: "l")
        XCTAssertEqual(SwipeTypingDecoder.sampledLetters(from: path, keys: keys), "hello")
        XCTAssertTrue(SwipeTypingDecoder.matches("hello", path: "hello"))
    }

    func testPassingThroughLDoesNotInventADoubleLetter() {
        let keys = qwertyKeys()
        let path = letterPath(["h", "e", "l", "o"], dwell: nil)
        XCTAssertEqual(SwipeTypingDecoder.sampledLetters(from: path, keys: keys), "helo")
        XCTAssertFalse(SwipeTypingDecoder.matches("hello", path: "helo"))
    }

    func testSpatialScorePrefersTheWordThatStaysOnL() throws {
        var dictionary = FrequencyDictionary()
        dictionary.load(from: Data(#"{"hello":10,"hero":90}"#.utf8))
        let keys = qwertyKeys()
        let path = letterPath(["h", "e", "r", "l", "o"], dwell: "l")
        let ranked = dictionary.swipeCandidates(touches: path, keys: keys, limit: 2)
        XCTAssertEqual(Set(ranked), Set(["hello", "hero"]))
        XCTAssertEqual(ranked.first, "hello")

        let heroScore = try XCTUnwrap(SwipeTypingDecoder.spatialScore(word: "hero", touches: path, keys: keys))
        let helloScore = try XCTUnwrap(SwipeTypingDecoder.spatialScore(word: "hello", touches: path, keys: keys))
        XCTAssertLessThan(helloScore, heroScore)
    }

    func testNoisyTapIsNotASwipe() {
        let keys = qwertyKeys()
        let tap = [SwipeTypingDecoder.Touch(x: keyX("h"), y: keyY("h"), time: 0)]
        XCTAssertFalse(SwipeTypingDecoder.shouldCommit(path: SwipeTypingDecoder.sampledLetters(from: tap, keys: keys)))
    }

    private func qwertyKeys() -> [SwipeTypingDecoder.Key] {
        let rows = ["qwertyuiop", "asdfghjkl", "zxcvbnm"]
        return rows.enumerated().flatMap { row, letters in
            letters.enumerated().map { column, letter in
                SwipeTypingDecoder.Key(
                    letter: letter,
                    frame: CGRect(x: Double(column) * 30, y: Double(row) * 40, width: 30, height: 40)
                )
            }
        }
    }

    private func keyX(_ letter: Character) -> Double {
        let rows = ["qwertyuiop", "asdfghjkl", "zxcvbnm"]
        for letters in rows {
            if let column = letters.firstIndex(of: letter) {
                let offset = letters.distance(from: letters.startIndex, to: column)
                return Double(offset) * 30 + 15
            }
        }
        return 0
    }

    private func keyY(_ letter: Character) -> Double {
        let rows = ["qwertyuiop", "asdfghjkl", "zxcvbnm"]
        for (row, letters) in rows.enumerated() where letters.contains(letter) {
            return Double(row) * 40 + 20
        }
        return 0
    }

    private func letterPath(_ letters: [Character], dwell: Character?) -> [SwipeTypingDecoder.Touch] {
        var time: TimeInterval = 0
        var touches: [SwipeTypingDecoder.Touch] = []
        for letter in letters {
            let pause: TimeInterval = (dwell == letter) ? 0.22 : 0.04
            let samples = (dwell == letter) ? 6 : 2
            for _ in 0..<samples {
                touches.append(SwipeTypingDecoder.Touch(x: keyX(letter), y: keyY(letter), time: time))
                time += pause / Double(samples)
            }
            time += 0.02
        }
        return touches
    }
}
