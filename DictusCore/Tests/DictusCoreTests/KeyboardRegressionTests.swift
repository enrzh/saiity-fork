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
        XCTAssertTrue(root.contains("controller.routeProxyText(emoji)"))
        XCTAssertFalse(root.contains("controller.routeProxyText(emoji)\n                    state.closeArea()"))
    }

    func testSymbolPageDoesNotPlaceACompetingDragGestureAboveTapButtons() throws {
        let root = try source("DictusKeyboard/KeyboardRootView.swift")
        let pageStart = try XCTUnwrap(root.range(of: "private struct LiquidSymbolPageView"))
        let keyStart = try XCTUnwrap(root.range(of: "private struct LiquidSymbolKey"))
        let page = String(root[pageStart.lowerBound..<keyStart.lowerBound])

        XCTAssertFalse(page.contains(".simultaneousGesture(symbolDragGesture(frames: frames))"))
        XCTAssertTrue(page.contains("Button { commitSymbolFromTap(key) } label:"))
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

    func testSurfaceFallbackIsFivePercentTaller() {
        XCTAssertEqual(VoiceOnlyKeyboardPolicy.surfaceHeight,
                       216 * 1.05,
                       accuracy: 0.001)
    }
}
