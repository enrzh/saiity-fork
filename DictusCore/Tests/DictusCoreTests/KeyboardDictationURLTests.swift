// DictusCore/Tests/DictusCoreTests/KeyboardDictationURLTests.swift
// Unit tests pinning the single rule that recognises keyboard dictation URLs (issue #264).
import XCTest
@testable import DictusCore

final class KeyboardDictationURLTests: XCTestCase {

    func testKeyboardCommandMappingPreservesLiteralActions() {
        XCTAssertEqual(KeyboardCommand.delete.proxyAction, .deleteBackward)
        XCTAssertEqual(KeyboardCommand.returnKey.proxyAction, .insertText("\n"))
        XCTAssertEqual(KeyboardCommand.at.proxyAction, .insertText("@"))
    }

    /// The URL the keyboard opens on a microphone tap (KeyboardState).
    func testRecordURLFromKeyboard() {
        let url = URL(string: "saiity://dictate?source=keyboard")!
        XCTAssertEqual(KeyboardDictationURL.intent(from: url), .record)
    }

    /// The prepare-only URL from issue #262 must never be read as a recording request:
    /// it loads the model and shows the loading overlay, nothing else.
    func testPrepareURLFromKeyboard() {
        let url = URL(string: "saiity://dictate?source=keyboard&intent=prepare")!
        XCTAssertEqual(KeyboardDictationURL.intent(from: url), .prepare)
    }

    /// Query item order must not matter — the rule is a lookup, not a prefix match.
    func testPrepareURLWithReversedQueryOrder() {
        let url = URL(string: "saiity://dictate?intent=prepare&source=keyboard")!
        XCTAssertEqual(KeyboardDictationURL.intent(from: url), .prepare)
    }

    /// An unknown intent value is still a recording request: only `prepare` diverts.
    func testUnknownIntentFallsBackToRecord() {
        let url = URL(string: "saiity://dictate?source=keyboard&intent=whatever")!
        XCTAssertEqual(KeyboardDictationURL.intent(from: url), .record)
    }

    /// The Live Activity deep link opens the same host without a source, and must not
    /// be mistaken for a keyboard cold start (it would show the swipe-back overlay).
    func testWidgetDictateURLIsNotAKeyboardRequest() {
        let url = URL(string: "saiity://dictate")!
        XCTAssertNil(KeyboardDictationURL.intent(from: url))
    }

    /// Another source value is not the keyboard.
    func testOtherSourceIsNotAKeyboardRequest() {
        let url = URL(string: "saiity://dictate?source=widget")!
        XCTAssertNil(KeyboardDictationURL.intent(from: url))
    }

    /// `saiity://stop` and `saiity://open` share the scheme but not the host.
    func testOtherHostsAreNotKeyboardRequests() {
        XCTAssertNil(KeyboardDictationURL.intent(from: URL(string: "saiity://stop")!))
        XCTAssertNil(KeyboardDictationURL.intent(from: URL(string: "saiity://open?source=keyboard")!))
    }

    /// A foreign scheme never matches, even with an identical host and query.
    func testForeignSchemeIsNotAKeyboardRequest() {
        let url = URL(string: "whatsapp://dictate?source=keyboard")!
        XCTAssertNil(KeyboardDictationURL.intent(from: url))
    }

    /// iOS normalises schemes and hosts to lower case, but URLs handed to the app can
    /// carry any casing. Matching must not depend on it.
    func testSchemeAndHostMatchingIsCaseInsensitive() {
        let url = URL(string: "SAIITY://Dictate?source=keyboard")!
        XCTAssertEqual(KeyboardDictationURL.intent(from: url), .record)
    }
}
