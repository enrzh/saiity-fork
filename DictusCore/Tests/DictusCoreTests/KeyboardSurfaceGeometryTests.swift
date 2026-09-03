import XCTest
@testable import DictusCore

final class KeyboardSurfaceGeometryTests: XCTestCase {
    private var repository: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    func testResolvedSurfaceHeightUsesFallbackForFirstObservationThenStableNativeHeight() {
        let first = VoiceOnlyKeyboardPolicy.resolvedSurfaceHeight(
            inputViewHeight: 228, controllerViewHeight: 844, fallbackHeight: 216)
        let stable = VoiceOnlyKeyboardPolicy.resolvedSurfaceHeight(
            inputViewHeight: 228, controllerViewHeight: 844, fallbackHeight: 216,
            previousInputViewHeight: first.observedInputViewHeight,
            stableInputViewPasses: first.stableInputViewPasses)

        XCTAssertEqual(first.height, 216)
        XCTAssertFalse(first.usesInputViewHeight)
        XCTAssertEqual(stable.height, 228)
        XCTAssertTrue(stable.usesInputViewHeight)
        XCTAssertEqual(stable.stableInputViewPasses, 2)
    }

    func testResolvedSurfaceHeightResetsStabilityWhenNativeHeightChanges() {
        let changed = VoiceOnlyKeyboardPolicy.resolvedSurfaceHeight(
            inputViewHeight: 240, controllerViewHeight: 844, fallbackHeight: 216,
            previousInputViewHeight: 228, stableInputViewPasses: 4)

        XCTAssertEqual(changed.height, 216)
        XCTAssertEqual(changed.observedInputViewHeight, 240)
        XCTAssertEqual(changed.stableInputViewPasses, 1)
        XCTAssertFalse(changed.usesInputViewHeight)
    }

    func testResolvedSurfaceHeightRejectsTemporaryFullscreenAndInvalidValues() {
        let fullscreen = VoiceOnlyKeyboardPolicy.resolvedSurfaceHeight(
            inputViewHeight: 844, controllerViewHeight: 844, fallbackHeight: 216,
            previousInputViewHeight: 228, stableInputViewPasses: 4)
        let invalid = VoiceOnlyKeyboardPolicy.resolvedSurfaceHeight(
            inputViewHeight: .nan, controllerViewHeight: 844, fallbackHeight: .infinity)

        XCTAssertEqual(fullscreen.height, 216)
        XCTAssertNil(fullscreen.observedInputViewHeight)
        XCTAssertEqual(fullscreen.stableInputViewPasses, 0)
        XCTAssertEqual(invalid.height, 1)
        XCTAssertNil(invalid.observedInputViewHeight)
    }

    func testSymbolGridKeepsFourUsableRowsAtStandardHeights() {
        let spacing: CGFloat = 5
        let inset: CGFloat = 4
        let surfaceVerticalInset = CGFloat(VoiceOnlyKeyboardPolicy.verticalPadding)

        for height in [CGFloat(216), CGFloat(228)] {
            let surfaceHeight = height - surfaceVerticalInset * 2
            for page in [KeyboardSymbolsLayout.numbers, KeyboardSymbolsLayout.symbols] {
                let rows = page.map { $0.map { CGFloat($0.width) } }
                let frames = VoiceOnlyKeyboardPolicy.SymbolGrid.frames(
                    for: rows, in: CGSize(width: 390, height: surfaceHeight),
                    spacing: spacing,
                    inset: inset,
                    rowSpacing: 6
                )

                XCTAssertEqual(frames.count, 3)
                XCTAssertTrue(frames.flatMap { $0 }.allSatisfy { $0.maxY <= surfaceHeight }, "height=\(height), page=\(page)")
                XCTAssertTrue(frames.flatMap { $0 }.allSatisfy { $0.height >= 40 }, "height=\(height), page=\(page)")
            }
        }

    }

    func testSymbolGridRowsHaveAtLeastFortyPointsAt216PointSurfaceHeight() {
        let surfaceHeight = CGFloat(VoiceOnlyKeyboardPolicy.surfaceHeight)
            - CGFloat(VoiceOnlyKeyboardPolicy.verticalPadding * 2)
        let frames = VoiceOnlyKeyboardPolicy.SymbolGrid.frames(
            for: KeyboardSymbolsLayout.symbols.map { $0.map { CGFloat($0.width) } },
            in: CGSize(width: 390, height: surfaceHeight),
            spacing: 5,
            inset: 4,
            rowSpacing: 6
        )

        XCTAssertEqual(frames.count, 3)
        XCTAssertTrue(frames.allSatisfy { row in
            row.allSatisfy { $0.height >= 40 }
        })
    }

    func testSymbolGridHeightReservesVisibleControlGapInProductionLayout() throws {
        let root = try String(
            contentsOf: repository.appending(path: "DictusKeyboard/KeyboardRootView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(root.contains("KeyboardSymbolsLayout"))
        XCTAssertFalse(root.contains("symbolBottomControlBudget"))
    }

    func testSymbolGridReservesLeadingLanePerRow() {
        let frames = VoiceOnlyKeyboardPolicy.SymbolGrid.frames(
            for: [[1, 1], [1, 1]],
            in: CGSize(width: 200, height: 100),
            spacing: 4, inset: 8
        )

        XCTAssertEqual(frames[0][0].minX, 8, accuracy: 0.001)
        XCTAssertEqual(frames[1][0].minX, 8, accuracy: 0.001)
        XCTAssertTrue(frames.flatMap { $0 }.allSatisfy { $0.maxX <= 192 })
    }

    func testSymbolGridUsesZeroForMissingReservedRows() {
        let frames = VoiceOnlyKeyboardPolicy.SymbolGrid.frames(
            for: [[1], [1]],
            in: CGSize(width: 100, height: 100),
            spacing: 4, inset: 8
        )

        XCTAssertEqual(frames[0][0].minX, 8, accuracy: 0.001)
        XCTAssertEqual(frames[1][0].minX, 8, accuracy: 0.001)
    }

    func testSymbolGridFailsClosedForEmptyRowsNegativeValuesAndNoWidth() {
        let frames = VoiceOnlyKeyboardPolicy.SymbolGrid.frames(
            for: [[], [-1], [1]],
            in: CGSize(width: 20, height: 100),
            spacing: 4, inset: 8
        )

        XCTAssertEqual(frames.map(\.count), [0, 0, 1])
    }

    func testSymbolPagesKeepThreeContentRowsAndPageToggle() {
        for page in [KeyboardSymbolsLayout.numbers, KeyboardSymbolsLayout.symbols] {
            XCTAssertEqual(page.count, 3)
            XCTAssertEqual(page[2].first?.kind, .pageToggle)
        }
    }

    func testPageToggleRoutesInBothDirectionsWithoutClosingVoiceSurface() {
        XCTAssertEqual(VoiceOnlyKeyboardPolicy.SymbolPageTransition.forToggle(from: .symbols1), .symbols1ToSymbols2)
        XCTAssertEqual(VoiceOnlyKeyboardPolicy.SymbolPageTransition.forToggle(from: .symbols2), .symbols2ToSymbols1)
    }

    func testSymbolPageDoesNotOverlayAuxiliaryControls() throws {
        let root = try String(
            contentsOf: repository.appending(path: "DictusKeyboard/KeyboardRootView.swift"),
            encoding: .utf8
        )

        XCTAssertFalse(root.contains("HStack(alignment: .center, spacing: CGFloat(VoiceOnlyKeyboardPolicy.symbolControlGap))"))
        XCTAssertTrue(root.contains("case .emoji:"))
        XCTAssertTrue(root.contains("AuxiliaryBottomBar("))
    }

    func testActionFramesStayInsideTheSharedSurfaceAtNativeHeights() {
        for height in [216.0, 228.0] {
            let layout = VoiceOnlyKeyboardPolicy.layout(for: 390, surfaceHeight: height)
            let surface = CGRect(x: 0, y: 0, width: 390, height: height)

            XCTAssertTrue(layout.actionRectangles.allSatisfy(surface.contains))
        }
    }

    func testActionFramesDoNotMoveWhenSurfaceHeightChanges() {
        let standard = VoiceOnlyKeyboardPolicy.layout(for: 390, surfaceHeight: 216)
        let refined = VoiceOnlyKeyboardPolicy.layout(for: 390, surfaceHeight: 228)

        XCTAssertEqual(standard.leftUtilityFrames.at.minX, refined.leftUtilityFrames.at.minX, accuracy: 0.001)
        XCTAssertEqual(standard.leftUtilityFrames.emoji.minX, refined.leftUtilityFrames.emoji.minX, accuracy: 0.001)
        XCTAssertEqual(standard.leftUtilityFrames.number.minX, refined.leftUtilityFrames.number.minX, accuracy: 0.001)
        XCTAssertEqual(standard.deleteFrame.minX, refined.deleteFrame.minX, accuracy: 0.001)
        XCTAssertEqual(standard.returnFrame.minX, refined.returnFrame.minX, accuracy: 0.001)
    }
}
