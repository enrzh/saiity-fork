import XCTest
@testable import DictusCore

final class KeyboardRegressionTests: XCTestCase {
    private var repository: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func source(_ path: String) throws -> String {
        try String(contentsOf: repository.appending(path: path), encoding: .utf8)
    }

    func testEmojiSelectionDoesNotCloseThePicker() throws {
        let root = try source("DictusKeyboard/KeyboardRootView.swift")
        XCTAssertTrue(root.contains("routeText(emoji)"))
        XCTAssertFalse(root.contains("routeText(emoji)\n                    state.closeArea()"))
    }

    func testSymbolPageDoesNotPlaceACompetingDragGestureAboveTapButtons() throws {
        let root = try source("DictusKeyboard/KeyboardRootView.swift")
        let pageStart = try XCTUnwrap(root.range(of: "private struct LiquidSymbolPageView"))
        let keyStart = try XCTUnwrap(root.range(of: "private struct LiquidSymbolKey"))
        let page = String(root[pageStart.lowerBound..<keyStart.lowerBound])

        XCTAssertFalse(page.contains(".simultaneousGesture(symbolDragGesture(frames: frames))"))
        XCTAssertTrue(page.contains("Button { commitSymbolFromTap(key) } label:"))
    }

    func testSymbolButtonsUseAStableNativeTapSurface() throws {
        let root = try source("DictusKeyboard/KeyboardRootView.swift")
        let start = try XCTUnwrap(root.range(of: "private func symbolKey"))
        let end = try XCTUnwrap(root.range(of: "private func commitSymbolFromTap"))
        let body = String(root[start.lowerBound..<end.lowerBound])

        XCTAssertTrue(body.contains("Button { commitSymbolFromTap(key) } label:"))
        XCTAssertTrue(body.contains(".contentShape(RoundedRectangle"))
        XCTAssertTrue(body.contains(".frame(maxWidth: .infinity, maxHeight: .infinity)"))
        XCTAssertFalse(body.contains("LongPressGesture"),
                      "a symbol key must not need a hold gesture to reach its tap action")
    }

    func testEmojiTapCannotBeRejectedByAStaleDragAxis() throws {
        let picker = try source("DictusKeyboard/Views/EmojiPickerView.swift")
        let start = try XCTUnwrap(picker.range(of: "private func commitEmojiFromTap"))
        let end = try XCTUnwrap(picker.range(of: "private func resetEmojiGestureLock"))
        let body = String(picker[start.lowerBound..<end.lowerBound])

        XCTAssertFalse(body.contains("guard emojiDragAxis == nil"),
                      "a normal emoji tap must still commit if a prior drag left transient state")
        XCTAssertTrue(body.contains("guard !emojiCommitLocked else"))
        XCTAssertTrue(body.contains("insertEmoji(emoji)"))
    }

    func testLeftUtilityGapsUseOneSharedSpacingValue() {
        let layout = VoiceOnlyKeyboardPolicy.layout(for: 390, controlOrder: .emojiFirst)
        let frames = layout.leftUtilityFrames

        XCTAssertEqual(frames.emoji.minY - frames.at.maxY,
                       VoiceOnlyKeyboardPolicy.railSpacing,
                       accuracy: 0.001)
        XCTAssertEqual(frames.number.minX - frames.emoji.maxX,
                       VoiceOnlyKeyboardPolicy.railSpacing,
                       accuracy: 0.001)
    }

    func testSurfaceFallbackIsTenPercentTaller() {
        XCTAssertEqual(VoiceOnlyKeyboardPolicy.surfaceHeight,
                       216 * 1.10,
                       accuracy: 0.001)
    }
}
