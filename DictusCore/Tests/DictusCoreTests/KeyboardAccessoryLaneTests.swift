import XCTest
@testable import DictusCore

final class KeyboardAccessoryLaneTests: XCTestCase {
    func testEveryLayoutKeepsTheCompactTopLaneOutsideTheSurface() {
        for width in [320.0, 375, 390, 430] {
            let layout = VoiceOnlyKeyboardPolicy.layout(
                for: width,
                surfaceHeight: 280,
                topAccessoryHeight: VoiceOnlyKeyboardPolicy.suggestionLaneHeight
            )

            XCTAssertEqual(VoiceOnlyKeyboardPolicy.suggestionLaneHeight, 36)
            XCTAssertEqual(layout.topAccessoryHeight, 36)
            XCTAssertEqual(layout.surfaceFrame.minY, 40)
            XCTAssertEqual(layout.surfaceFrame.maxY, 276)
            XCTAssertEqual(layout.surfaceFrame.minY - layout.topAccessoryHeight, 4)
            XCTAssertEqual(280 - layout.surfaceFrame.maxY, 4)
        }
    }

    /// The selected-category marker must sit on the horizontal centre above the
    /// spacebar on every device. Shortening the bar to dodge the delete key
    /// silently moved that marker off-centre, so the frame stays symmetric and
    /// the delete corner is resolved by hit-test order instead.
    func testEmojiCategoryBarStaysHorizontallyCentredOnEveryDevice() {
        for width in [320.0, 375, 390, 402, 430] {
            for surfaceHeight in [260.0, 280, 300] {
                let layout = VoiceOnlyKeyboardPolicy.layout(
                    for: width,
                    surfaceHeight: surfaceHeight,
                    topAccessoryHeight: VoiceOnlyKeyboardPolicy.suggestionLaneHeight
                )
                let bar = layout.floatingEmojiCategoryFrame
                XCTAssertFalse(bar.isEmpty, "width=\(width) height=\(surfaceHeight)")
                XCTAssertEqual(bar.midX, layout.surfaceFrame.midX, accuracy: 0.001,
                               "category bar must be centred, width=\(width) height=\(surfaceHeight)")
                XCTAssertEqual(bar.minX,
                               layout.surfaceFrame.minX + VoiceOnlyKeyboardPolicy.visibleControlGap,
                               accuracy: 0.001)
                XCTAssertEqual(bar.maxX,
                               layout.surfaceFrame.maxX - VoiceOnlyKeyboardPolicy.visibleControlGap,
                               accuracy: 0.001)
                XCTAssertTrue(layout.surfaceFrame.contains(bar))
            }
        }
    }

    func testBoardFramesAre44PointHitTargetsInsideTheSurface() {
        let layout = VoiceOnlyKeyboardPolicy.layout(for: 390, surfaceHeight: 280, topAccessoryHeight: 44)

        for frame in [layout.chromeLettersFrame, layout.boardDeleteFrame, layout.chromeReturnFrame] {
            XCTAssertEqual(frame.size.height, 44)
            XCTAssertTrue(layout.surfaceFrame.contains(frame), "frame=\(frame)")
        }
        XCTAssertEqual(layout.boardDeleteFrame.maxY + VoiceOnlyKeyboardPolicy.railSpacing,
                       layout.chromeReturnFrame.minY,
                       accuracy: 0.001)
    }

    func testNativeModeButtonsSitOnTheBottomChromeLane() {
        let layout = VoiceOnlyKeyboardPolicy.layout(
            for: 390,
            surfaceHeight: 280,
            controlOrder: .numberFirst,
            topAccessoryHeight: 44
        )

        XCTAssertEqual(layout.chromeNumbersFrame.minX,
                       layout.surfaceFrame.minX + VoiceOnlyKeyboardPolicy.visibleControlGap,
                       accuracy: 0.001)
        XCTAssertEqual(layout.chromeNumbersFrame.minY, layout.chromeSpaceFrame.minY, accuracy: 0.001)
        XCTAssertEqual(layout.chromeLettersFrame.minX,
                       layout.chromeNumbersFrame.maxX + VoiceOnlyKeyboardPolicy.railSpacing,
                       accuracy: 0.001)
        XCTAssertEqual(layout.chromeWideLettersFrame.minX, layout.chromeNumbersFrame.minX, accuracy: 0.001)
        XCTAssertEqual(layout.chromeWideLettersFrame.maxX, layout.chromeLettersFrame.maxX, accuracy: 0.001)
        XCTAssertEqual(layout.chromeWideLettersFrame.height, VoiceOnlyKeyboardPolicy.spacebarHeight, accuracy: 0.001)
        XCTAssertEqual(layout.chromeWideSpaceFrame.minX, layout.chromeSpaceFrame.minX, accuracy: 0.001)
        XCTAssertEqual(layout.chromeWideSpaceFrame.maxX, layout.chromeEmojiFrame.maxX, accuracy: 0.001)
        XCTAssertEqual(layout.chromeWideSpaceFrame.height, layout.chromeSpaceFrame.height, accuracy: 0.001)
        XCTAssertGreaterThan(layout.chromeWideSpaceFrame.width, layout.chromeSpaceFrame.width)
        XCTAssertEqual(layout.chromeEmojiFrame.maxX + VoiceOnlyKeyboardPolicy.railSpacing,
                       layout.chromeReturnFrame.minX,
                       accuracy: 0.001)
        XCTAssertNotEqual(layout.chromeEmojiFrame, layout.chromeLettersFrame)
        XCTAssertEqual(layout.chromeSpaceFrame.minX,
                       layout.chromeLettersFrame.maxX + VoiceOnlyKeyboardPolicy.railSpacing,
                       accuracy: 0.001)
        XCTAssertTrue(layout.surfaceFrame.contains(layout.floatingEmojiCategoryFrame))
        XCTAssertEqual(layout.floatingEmojiCategoryFrame.height,
                       VoiceOnlyKeyboardPolicy.floatingEmojiCategoryBarHeight,
                       accuracy: 0.001)
        XCTAssertEqual(layout.floatingEmojiCategoryFrame.maxY
                        + VoiceOnlyKeyboardPolicy.floatingEmojiCategoryBarGap,
                       layout.chromeSpaceFrame.minY,
                       accuracy: 0.001)
        XCTAssertEqual(layout.floatingEmojiCategoryFrame.minX,
                       layout.surfaceFrame.minX + VoiceOnlyKeyboardPolicy.visibleControlGap,
                       accuracy: 0.001)
        // The bar keeps a symmetric inset so the selected marker stays centred;
        // delete keeps the shared corner by winning the hit test, not by the bar
        // being shortened.
        XCTAssertEqual(layout.floatingEmojiCategoryFrame.maxX,
                       layout.surfaceFrame.maxX - VoiceOnlyKeyboardPolicy.visibleControlGap,
                       accuracy: 0.001)
        XCTAssertGreaterThan(layout.floatingEmojiCategoryFrame.width,
                             VoiceOnlyKeyboardPolicy.floatingEmojiCategoryBarMaxWidth,
                             "the invisible track must be wider than the moving handle")
        XCTAssertEqual(layout.accessoryDictationBoardFrame.maxX + VoiceOnlyKeyboardPolicy.railSpacing,
                       layout.accessoryDismissFrame.minX, accuracy: 0.001)
        XCTAssertEqual(layout.accessoryDismissFrame.width, 36, accuracy: 0.001)
        XCTAssertEqual(layout.accessoryEmojiCategoryFrame.minX,
                       VoiceOnlyKeyboardPolicy.accessoryEdgeInset
                        + VoiceOnlyKeyboardPolicy.languageVisualWidth
                        + VoiceOnlyKeyboardPolicy.railSpacing,
                       accuracy: 0.001)
        XCTAssertEqual(layout.accessoryEmojiCategoryFrame.maxX + VoiceOnlyKeyboardPolicy.railSpacing,
                       layout.accessoryDictationBoardFrame.minX, accuracy: 0.001)
        XCTAssertEqual(layout.accessoryEmojiCategoryFrame.height, 36, accuracy: 0.001)
        XCTAssertGreaterThan(layout.accessoryEmojiCategoryFrame.width, 80)
        XCTAssertEqual(VoiceOnlyKeyboardPolicy.accessoryControlSize, 36)
        XCTAssertEqual(VoiceOnlyKeyboardPolicy.keyboardWindowAccessoryHeight, 44)
        XCTAssertGreaterThan(
            VoiceOnlyKeyboardPolicy.keyboardWindowAccessoryHeight,
            VoiceOnlyKeyboardPolicy.suggestionLaneHeight
        )
    }

    func testPolicyCallsDefaultToNoTopAccessoryLane() {
        let layout = VoiceOnlyKeyboardPolicy.layout(for: 390, surfaceHeight: 280)
        XCTAssertEqual(layout.topAccessoryHeight, 0)
        XCTAssertEqual(layout.surfaceFrame.minY, VoiceOnlyKeyboardPolicy.verticalPadding)
    }

    func testLastRowCommandHitMatchesDictationBoardDelete() {
        for width in [320.0, 375, 390, 430] {
            let layout = VoiceOnlyKeyboardPolicy.layout(for: width, surfaceHeight: 280, topAccessoryHeight: 44)
            let gridHeight: CGFloat = 168
            let lastRowHeight = VoiceOnlyKeyboardPolicy.SymbolGrid.letterAlignedLastRowHeight(
                in: gridHeight,
                rowSpacing: 5
            )
            XCTAssertEqual(lastRowHeight, layout.boardDeleteFrame.height, accuracy: 0.001)
            let frames = VoiceOnlyKeyboardPolicy.SymbolGrid.fixedEdgeCommandRowFrames(
                itemCount: 9,
                rowFrame: CGRect(x: 8, y: 0, width: layout.surfaceFrame.width - 16, height: lastRowHeight),
                spacing: CGFloat(VoiceOnlyKeyboardPolicy.railSpacing),
                commandWidth: layout.boardDeleteFrame.width
            )
            XCTAssertEqual(frames.first?.size, CGSize(width: layout.boardDeleteFrame.width, height: layout.boardDeleteFrame.height))
            XCTAssertEqual(frames.last?.size, CGSize(width: layout.boardDeleteFrame.width, height: layout.boardDeleteFrame.height))
            XCTAssertEqual(
                VoiceOnlyKeyboardPolicy.commandVisualSize(for: frames.last?.size ?? .zero),
                layout.commandKeyVisualSize
            )
        }
    }

    func testLetterGridHeightPinsDeleteToTheBoardDeleteFrame() {
        for width in [320.0, 375, 390, 430] {
            let layout = VoiceOnlyKeyboardPolicy.layout(
                for: width,
                surfaceHeight: 280,
                topAccessoryHeight: 44
            )
            let gridHeight = layout.surfaceFrame.height
                - VoiceOnlyKeyboardPolicy.chromeCommandRowGap
                - 44
                - VoiceOnlyKeyboardPolicy.chromeBottomInset
            XCTAssertEqual(
                gridHeight,
                layout.boardDeleteFrame.maxY - layout.surfaceFrame.minY,
                accuracy: 0.001
            )
            XCTAssertEqual(
                layout.floatingEmojiCategoryFrame.maxY + VoiceOnlyKeyboardPolicy.floatingEmojiCategoryBarGap,
                layout.chromeSpaceFrame.minY,
                accuracy: 0.001
            )
        }
    }

    func testWideEmojiBarFitsItsCompactCategoryContent() {
        let layout = VoiceOnlyKeyboardPolicy.layout(
            for: 1024,
            surfaceHeight: 280,
            controlOrder: .numberFirst,
            topAccessoryHeight: VoiceOnlyKeyboardPolicy.suggestionLaneHeight
        )

        XCTAssertGreaterThan(
            layout.floatingEmojiCategoryFrame.width,
            VoiceOnlyKeyboardPolicy.floatingEmojiCategoryBarMaxWidth
        )
    }

    func testCommandVisualSizeStaysPinnedToDictationDelete() {
        for width in [320.0, 375, 390, 430, 768] {
            let short = VoiceOnlyKeyboardPolicy.layout(for: width, surfaceHeight: 260, topAccessoryHeight: 44)
            let tall = VoiceOnlyKeyboardPolicy.layout(for: width, surfaceHeight: 340, topAccessoryHeight: 44)
            XCTAssertEqual(short.commandKeyVisualSize, tall.commandKeyVisualSize)
            XCTAssertEqual(tall.commandKeyVisualSize.height, 36)
            XCTAssertEqual(Double(tall.commandKeyVisualSize.width) + 8, tall.boardDeleteFrame.width, accuracy: 0.001)
            XCTAssertEqual(
                Double(tall.boardDeleteFrame.maxX),
                tall.surfaceFrame.maxX - VoiceOnlyKeyboardPolicy.visibleControlGap,
                accuracy: 0.001
            )
            XCTAssertEqual(
                Double(tall.boardDeleteFrame.maxY) + VoiceOnlyKeyboardPolicy.railSpacing,
                Double(tall.chromeReturnFrame.minY),
                accuracy: 0.001
            )
            for height in [44.0, 60, 80] {
                let frames = VoiceOnlyKeyboardPolicy.SymbolGrid.fixedEdgeCommandRowFrames(
                    itemCount: 9,
                    rowFrame: CGRect(
                        x: VoiceOnlyKeyboardPolicy.visibleControlGap,
                        y: 0,
                        width: tall.surfaceFrame.width - VoiceOnlyKeyboardPolicy.visibleControlGap * 2,
                        height: height
                    ),
                    spacing: VoiceOnlyKeyboardPolicy.railSpacing,
                    commandWidth: tall.boardDeleteFrame.width
                )
                XCTAssertEqual(frames.first?.width, tall.boardDeleteFrame.width)
                XCTAssertEqual(frames.last?.width, tall.boardDeleteFrame.width)
                XCTAssertEqual(
                    Double(frames.last?.maxX ?? -1),
                    tall.surfaceFrame.width - VoiceOnlyKeyboardPolicy.visibleControlGap,
                    accuracy: 0.001
                )
                for pair in zip(frames, frames.dropFirst()) {
                    XCTAssertLessThanOrEqual(pair.0.maxX, pair.1.minX)
                }
            }
        }
    }
}
