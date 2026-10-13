import XCTest
@testable import SyllivraKernel

final class NativeKeyGeometryTests: XCTestCase {
    func testNativeReferenceKeepsStableGapsAndKeyFaces() {
        for width: CGFloat in [320, 375, 390, 402, 420, 440] {
            let metrics = VoiceOnlyKeyboardPolicy.scaledKeyGeometry(for: Double(width))
            let frames = VoiceOnlyKeyboardPolicy.SymbolGrid.framesWithPinnedLastRow(
                for: Array(repeating: Array(repeating: 1, count: 10), count: 3),
                in: CGSize(width: width, height: 162),
                spacing: metrics.keySpacing,
                inset: metrics.keyGridInset,
                rowSpacing: metrics.keyRowSpacing,
                lastRowHeight: 44,
                maxRowHeight: metrics.letterKeyHeight
            )
            XCTAssertEqual(frames[0][0].minX, 6.5, accuracy: 0.01)
            XCTAssertEqual(frames[0][9].maxX, width - 6.5, accuracy: 0.01)
            XCTAssertEqual(frames[0][1].minX - frames[0][0].maxX, 6, accuracy: 0.01)
            XCTAssertEqual(frames[1][0].minY - frames[0][0].maxY, 11, accuracy: 0.01)
            XCTAssertEqual(frames[0][0].height, 45, accuracy: 0.01)
            XCTAssertLessThanOrEqual(frames[2][0].maxY, 162)
            if width == 420 {
                XCTAssertEqual(frames[0][0].width, 35.3, accuracy: 0.01)
            }
        }
    }

    func testCompactAndOptionalDigitRowsFitWithoutOverlap() {
        for rowCount in [3, 4] {
            for height: CGFloat in [118, 162, 216] {
                let frames = VoiceOnlyKeyboardPolicy.SymbolGrid.framesWithPinnedLastRow(
                    for: Array(repeating: Array(repeating: 1, count: 10), count: rowCount),
                    in: CGSize(width: 375, height: height),
                    spacing: 6, inset: 6.5, rowSpacing: 11,
                    lastRowHeight: 44, maxRowHeight: 45
                )
                XCTAssertEqual(frames.count, rowCount)
                for index in frames.indices {
                    XCTAssertGreaterThan(frames[index][0].height, 0)
                    XCTAssertLessThanOrEqual(frames[index][0].maxY, height + 0.01)
                    if index > 0 {
                        XCTAssertEqual(frames[index][0].minY - frames[index - 1][0].maxY, 11, accuracy: 0.01)
                    }
                }
            }
        }
    }
}
