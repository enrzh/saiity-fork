import XCTest

final class KeyboardInteractionLayerContractTests: XCTestCase {
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

    func testEverySurfaceUsesSharedKeyGeometryAndMaterialIsDecorative() throws {
        let root = try source("DictusKeyboard/KeyboardRootView.swift")
        let letter = try source("DictusKeyboard/LetterKeyboardSurface.swift")
        let number = try source("DictusKeyboard/NumberKeyboardSurface.swift")
        let symbol = try source("DictusKeyboard/SymbolKeyboardSurface.swift")
        let plates = try source("DictusKeyboard/Views/AuxiliaryBottomBar.swift")
        let style = try source("DictusKeyboard/KeyboardKeyStyle.swift")
        let chrome = try source("DictusKeyboard/KeyboardChrome.swift")
        let input = try source("DictusKeyboard/KeyboardKeyInput.swift")
        let controller = try source("DictusKeyboard/KeyboardViewController.swift")

        XCTAssertTrue(root.contains("LetterKeyboardSurface("))
        XCTAssertTrue(root.contains("NumberKeyboardSurface("))
        XCTAssertTrue(root.contains("SymbolKeyboardSurface("))
        XCTAssertTrue(letter.contains("KeyboardKeyHitGeometry.frames("))
        XCTAssertTrue(number.contains("KeyboardKeyHitGeometry.frames("))
        XCTAssertTrue(symbol.contains("KeyboardKeyHitGeometry.frames("))
        XCTAssertTrue(input.contains("final class KeyboardKeyTouchControl"))
        XCTAssertTrue(input.contains("bounds.contains(point)"))
        XCTAssertFalse(controller.contains("interactiveTarget(in:"))
        XCTAssertFalse(plates.contains("keyHitFrames"))
        XCTAssertFalse(letter.contains("LetterInteractionSurface"))
        XCTAssertTrue(style.contains("opacity(KeyboardInteractionPreferences.keyContainersEnabled ? 1 : 0)"))
        XCTAssertTrue(style.contains(".allowsHitTesting(false)"))
        XCTAssertTrue(chrome.contains(".allowsHitTesting(!voiceBoardUsesUIKitHits)"))
        // The number and symbol grids are owned by the one shared UIKit component, so
        // neither installs a control per key. Per-key controls were recreated by
        // SwiftUI on ordinary state changes, and a control missing at release time
        // silently dropped the character.
        for (name, surface) in [("number", number), ("symbol", symbol)] {
            XCTAssertTrue(surface.contains(".keyGridInput("),
                          "\(name) must publish its grid to the shared UIKit touch owner")
            XCTAssertTrue(surface.contains("refreshedGridHandlers("),
                          "\(name) must supply press/move/release callbacks")
        }
        // The letter grid went further: it is one UIKit view that draws the keys and
        // hit-tests them from the same rectangles, with no SwiftUI key faces at all.
        // Drawing and hit testing in two systems is what let a visible key have no
        // target, and a target have no visible key.
        let grid = try source("DictusKeyboard/Next/KeyGridView.swift")
        XCTAssertTrue(grid.contains("final class KeyGridView: UIView"))
        XCTAssertTrue(grid.contains("override func touchesBegan("),
                      "the key grid must own its own touches")
        XCTAssertTrue(grid.contains("KeyGridPlacement.solve("),
                      "hit targets must come from the shared geometry, which tiles the grid contiguously")
        XCTAssertFalse(letter.contains(".keyGridInput("),
                       "the letter surface must not publish a separate hit geometry")
        XCTAssertFalse(letter.contains("ForEach(frames)"),
                       "the letter surface must not draw key faces; the UIKit grid does")
        XCTAssertTrue(controller.contains("NextKeyboardHost()"),
                      "the controller must host the key grid on the input view")
        XCTAssertFalse(controller.contains("LetterKeyGridView"),
                       "the legacy letter grid is deleted; the controller must not name it at all")
        XCTAssertFalse(number.contains("NumberInteractionOverlay"))
        XCTAssertFalse(symbol.contains("SymbolInteractionOverlay"))
        XCTAssertFalse(root.contains("GiellaKeyboardView("))
    }

    func testLegacyGiellaKeyboardViewIsNotInstalledAtRuntime() throws {
        let controller = try source("DictusKeyboard/KeyboardViewController.swift")

        XCTAssertFalse(controller.contains("GiellaKeyboardView("))
        XCTAssertFalse(controller.contains("installLetterKeyboard("))
        XCTAssertFalse(controller.contains("giellaKeyboard"))
        XCTAssertFalse(controller.contains("GiellaKeyboardViewDelegate"))
    }

    func testKeyboardInteractionLayerKeepsVoiceOnlyPolicyAsGeometrySource() throws {
        let root = try source("DictusKeyboard/KeyboardRootView.swift")
        let controller = try source("DictusKeyboard/KeyboardViewController.swift")
        let surfaces = try [
            source("DictusKeyboard/LetterKeyboardSurface.swift"),
            source("DictusKeyboard/NumberKeyboardSurface.swift"),
            source("DictusKeyboard/SymbolKeyboardSurface.swift"),
            source("DictusKeyboard/VoiceBoardSurface.swift")
        ]

        XCTAssertTrue(root.contains("VoiceOnlyKeyboardPolicy.layout("))
        XCTAssertTrue(controller.contains("VoiceOnlyKeyboardPolicy.resolvedSurfaceHeight("))
        XCTAssertTrue(controller.contains("VoiceOnlyKeyboardPolicy.layout("))
        for surface in surfaces {
            XCTAssertTrue(surface.contains("VoiceOnlyKeyboardPolicy."))
        }
    }
}
