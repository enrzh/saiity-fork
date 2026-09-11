import XCTest
@testable import DictusCore

final class KeyboardAccessoryLaneTests: XCTestCase {
    func testEveryLayoutKeepsThe44PointTopLaneOutsideTheSurface() {
        for width in [320.0, 375, 390, 430] {
            let layout = VoiceOnlyKeyboardPolicy.layout(
                for: width,
                surfaceHeight: 280,
                topAccessoryHeight: VoiceOnlyKeyboardPolicy.suggestionLaneHeight
            )

            XCTAssertEqual(VoiceOnlyKeyboardPolicy.suggestionLaneHeight, 44)
            XCTAssertEqual(layout.topAccessoryHeight, 44)
            XCTAssertEqual(layout.surfaceFrame.minY, 48)
            XCTAssertEqual(layout.surfaceFrame.maxY, 276)
        }
    }

    func testBoardFramesAre44PointHitTargetsInsideTheSurface() {
        let layout = VoiceOnlyKeyboardPolicy.layout(for: 390, surfaceHeight: 280, topAccessoryHeight: 44)

        for frame in [layout.boardKeyboardFrame, layout.boardDeleteFrame, layout.boardReturnFrame] {
            XCTAssertEqual(frame.size, CGSize(width: frame.width, height: 44))
            XCTAssertTrue(layout.surfaceFrame.contains(frame), "frame=\(frame)")
        }
        XCTAssertEqual(layout.boardDeleteFrame.maxY + VoiceOnlyKeyboardPolicy.railSpacing,
                       layout.boardReturnFrame.minY,
                       accuracy: 0.001)
    }

    func testPolicyCallsDefaultToNoTopAccessoryLane() {
        let layout = VoiceOnlyKeyboardPolicy.layout(for: 390, surfaceHeight: 280)
        XCTAssertEqual(layout.topAccessoryHeight, 0)
        XCTAssertEqual(layout.surfaceFrame.minY, VoiceOnlyKeyboardPolicy.verticalPadding)
    }
}
