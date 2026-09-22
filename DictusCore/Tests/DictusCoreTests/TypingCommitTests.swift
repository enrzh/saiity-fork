import XCTest
@testable import DictusCore

final class TypingCommitTests: XCTestCase {
    func testSmallSlipsAccentsApostrophesAndSplitsCanCommit() {
        XCTAssertTrue(TypingCommit.accepts(typed: "teh", correction: "the"))
        XCTAssertTrue(TypingCommit.accepts(typed: "tres", correction: "très"))
        XCTAssertTrue(TypingCommit.accepts(typed: "cest", correction: "c'est"))
        XCTAssertTrue(TypingCommit.accepts(typed: "pasnmal", correction: "pas mal"))
    }

    func testDistantRewritesAndFactsStayTyped() {
        XCTAssertFalse(TypingCommit.accepts(typed: "Peter", correction: "Paul"))
        XCTAssertFalse(TypingCommit.accepts(typed: "AB-120", correction: "AB120"))
        XCTAssertFalse(TypingCommit.accepts(typed: "125.50", correction: "125"))
        XCTAssertFalse(TypingCommit.accepts(typed: "hello", correction: "world"))
        XCTAssertFalse(TypingCommit.accepts(typed: "the", correction: "the"))
    }
}
