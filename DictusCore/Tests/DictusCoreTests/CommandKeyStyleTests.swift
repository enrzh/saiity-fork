// DictusCore/Tests/DictusCoreTests/CommandKeyStyleTests.swift
//
// The press treatment is shared by two renderers that cannot both be right on their
// own: SwiftUI can fade a whole layer, Core Graphics can only wash inside a plate it
// draws. These tests hold the numbers they agree on, so the two cannot drift apart
// again without something failing.

import XCTest
@testable import DictusCore

final class CommandKeyStyleTests: XCTestCase {

    /// A held key shrinks about its own centre.
    ///
    /// Scaling from the top-left instead is the mistake this guards: it reads as the
    /// key sliding away rather than being pressed.
    func testPressedPlateScalesAboutItsCentre() {
        let rect = CGRect(x: 7, y: 128, width: 45.4, height: 43)
        let pressed = CommandKeyStyle.pressedPlate(rect, pressed: true)

        XCTAssertEqual(pressed.midX, rect.midX, accuracy: 0.001)
        XCTAssertEqual(pressed.midY, rect.midY, accuracy: 0.001)
        XCTAssertEqual(pressed.width, rect.width * CommandKeyStyle.pressScale, accuracy: 0.001)
        XCTAssertEqual(pressed.height, rect.height * CommandKeyStyle.pressScale, accuracy: 0.001)
    }

    /// An unheld plate is returned untouched, not a copy of a scaled one.
    func testUnpressedPlateIsUnchanged() {
        let rect = CGRect(x: 7, y: 128, width: 45.4, height: 43)
        XCTAssertEqual(CommandKeyStyle.pressedPlate(rect, pressed: false), rect)
    }

    /// The scale has to leave a visible margin, and not so much that the key reads
    /// as a different key. Both ends of that are arbitrary; these are the bounds that
    /// were checked against the rendered system keyboard.
    func testPressScaleIsVisibleButSubtle() {
        XCTAssertGreaterThan(CommandKeyStyle.pressScale, 0.90)
        XCTAssertLessThan(CommandKeyStyle.pressScale, 0.98)
    }

    /// A degenerate plate must not divide by zero or produce NaN geometry.
    ///
    /// A key can be laid out at zero width mid-animation, and a NaN in a drawing
    /// context silently blanks the whole key rather than failing.
    func testPressedPlateSurvivesDegenerateRects() {
        for rect in [CGRect.zero, CGRect(x: 3, y: 4, width: 0, height: 43),
                     CGRect(x: 3, y: 4, width: 45, height: 0)] {
            let pressed = CommandKeyStyle.pressedPlate(rect, pressed: true)
            XCTAssertTrue(pressed.minX.isFinite, "\(rect) produced \(pressed)")
            XCTAssertTrue(pressed.width.isFinite, "\(rect) produced \(pressed)")
            XCTAssertTrue(pressed.height.isFinite, "\(rect) produced \(pressed)")
        }
    }

    /// The corner radius makes a command key read as a control, not a letter key.
    ///
    /// What has to hold is that it is clearly rounder than a letter plate, that it
    /// never exceeds half the tallest plate (past that the corners clip), and that it
    /// is not silently changed to something squarer. The exact value is the product's
    /// choice, not a measurement: a crop of the platform's own key suggested a
    /// smaller radius, but calibrating that measurement showed it cannot tell 11 from
    /// 18, so the shape was not moved on the strength of it.
    func testCommandRadiusIsRounderThanALetterAndDoesNotClip() {
        let tallestPlate = KeyGridPlacement.maximumRowHeight
        XCTAssertGreaterThan(CommandKeyStyle.cornerRadius, KeyGridPlacement.keyCornerRadius)
        XCTAssertLessThan(CommandKeyStyle.cornerRadius, tallestPlate / 2)
        XCTAssertEqual(CommandKeyStyle.cornerRadius, 18, accuracy: 0.01)
    }

    /// The space bar is the one key that is a pill rather than a rounded command
    /// shape, and it asks for that radius explicitly.
    ///
    /// It is wide, so a full pill costs it nothing visually, and it must not drift
    /// onto the command radius: that is the shape that reads as squared.
    func testSpaceBarKeepsItsPillRadius() {
        XCTAssertEqual(CommandKeyStyle.pillRadius(forHeight: 40), 20, accuracy: 0.01)
        XCTAssertEqual(CommandKeyStyle.pillRadius(forHeight: 43), 21.5, accuracy: 0.01)
        // Wider than the command radius, so the two shapes stay distinguishable.
        XCTAssertGreaterThan(
            CommandKeyStyle.pillRadius(forHeight: 40),
            CommandKeyStyle.cornerRadius
        )
        XCTAssertEqual(CommandKeyStyle.pillRadius(forHeight: -5), 0, accuracy: 0.01)
    }

    /// The grid's copy of the radius is the same number, not a second literal.
    ///
    /// `KeyGridPlacement.commandCornerRadius` and `CommandKeyStyle.cornerRadius` are
    /// both public, so a future edit could easily leave them disagreeing — and then
    /// the shift key and the delete key on the same row would have different shapes.
    func testGridAndCommandStyleAgreeOnTheRadius() {
        XCTAssertEqual(KeyGridPlacement.commandCornerRadius, CommandKeyStyle.cornerRadius)
    }

    /// The wash has to read as a press on glass, which is brighter than the keyboard
    /// behind it, so it lightens rather than darkens.
    func testWashIsLighteningAndSubtle() {
        XCTAssertGreaterThan(CommandKeyStyle.pressWashAlpha, 0.10)
        XCTAssertLessThan(CommandKeyStyle.pressWashAlpha, 0.30)
    }
}
