import XCTest
@testable import DictusCore

final class SuggestionRequestGateTests: XCTestCase {
    func testOnlyNewestRequestRemainsCurrent() {
        var gate = SuggestionRequestGate()
        let first = gate.begin()
        let second = gate.begin()

        XCTAssertFalse(gate.isCurrent(first))
        XCTAssertTrue(gate.isCurrent(second))
    }

    func testTokenRemainsCurrentUntilNextRequest() {
        var gate = SuggestionRequestGate()
        let token = gate.begin()

        XCTAssertTrue(gate.isCurrent(token))
    }
}
