import XCTest
@testable import DictusCore

final class KeyboardCursorJoystickTests: XCTestCase {
    func testOriginAreaDoesNotMoveTheCaret() {
        let origin = CGPoint(x: 40, y: 20)
        XCTAssertTrue(KeyboardCursorJoystick.step(from: origin, to: origin).isEmpty)
        XCTAssertTrue(
            KeyboardCursorJoystick.step(
                from: origin,
                to: CGPoint(x: origin.x + KeyboardCursorJoystick.deadZone, y: origin.y)
            ).isEmpty
        )
        XCTAssertTrue(
            KeyboardCursorJoystick.step(
                from: origin,
                to: CGPoint(x: origin.x, y: origin.y - KeyboardCursorJoystick.deadZone)
            ).isEmpty
        )
    }

    func testDisplacementPastTheDeadZoneStepsOncePerAxis() {
        let origin = CGPoint(x: 40, y: 20)
        let justRight = CGPoint(x: origin.x + KeyboardCursorJoystick.deadZone + 1, y: origin.y)
        XCTAssertEqual(
            KeyboardCursorJoystick.step(from: origin, to: justRight),
            KeyboardCursorStep(characters: 1)
        )
        let justUp = CGPoint(x: origin.x, y: origin.y - KeyboardCursorJoystick.deadZone - 1)
        XCTAssertEqual(
            KeyboardCursorJoystick.step(from: origin, to: justUp),
            KeyboardCursorStep(lines: -1)
        )
    }

    func testFartherDisplacementStepsFasterAndClamps() {
        let origin = CGPoint.zero
        let farRight = CGPoint(
            x: KeyboardCursorJoystick.deadZone + KeyboardCursorJoystick.pointsPerCharacter * 8,
            y: 0
        )
        XCTAssertEqual(
            KeyboardCursorJoystick.step(from: origin, to: farRight).characters,
            KeyboardCursorJoystick.maxCharactersPerTick
        )
        let farDown = CGPoint(
            x: 0,
            y: KeyboardCursorJoystick.deadZone + KeyboardCursorJoystick.pointsPerLine * 8
        )
        XCTAssertEqual(
            KeyboardCursorJoystick.step(from: origin, to: farDown).lines,
            KeyboardCursorJoystick.maxLinesPerTick
        )
    }

    func testAxesAreIndependentInsideTheOriginArea() {
        let origin = CGPoint.zero
        let rightAndJitter = CGPoint(
            x: KeyboardCursorJoystick.deadZone + 1,
            y: KeyboardCursorJoystick.deadZone
        )
        XCTAssertEqual(
            KeyboardCursorJoystick.step(from: origin, to: rightAndJitter),
            KeyboardCursorStep(characters: 1)
        )
    }

    func testTheSameOffsetKeepsProducingTheSameStep() {
        let origin = CGPoint(x: 10, y: 10)
        let held = CGPoint(x: 10 + KeyboardCursorJoystick.deadZone + 4, y: 10)
        let first = KeyboardCursorJoystick.step(from: origin, to: held)
        let second = KeyboardCursorJoystick.step(from: origin, to: held)
        XCTAssertEqual(first, second)
        XCTAssertEqual(first, KeyboardCursorStep(characters: 1))
    }

    func testReturningToTheOriginStopsTheDirection() {
        let origin = CGPoint(x: 50, y: 40)
        let heldLeft = CGPoint(x: origin.x - KeyboardCursorJoystick.deadZone - 8, y: origin.y)
        XCTAssertEqual(
            KeyboardCursorJoystick.step(from: origin, to: heldLeft),
            KeyboardCursorStep(characters: -1)
        )
        XCTAssertTrue(KeyboardCursorJoystick.step(from: origin, to: origin).isEmpty)
    }

    func testFingerTravelFollowsNativeCharacterDensity() {
        var sampler = KeyboardCursorJoystickSampler(origin: .zero)
        XCTAssertEqual(
            sampler.tick(to: CGPoint(x: KeyboardCursorTrackpad.pointsPerCharacter, y: 0), now: 1),
            KeyboardCursorStep(characters: 1)
        )
        XCTAssertEqual(
            sampler.tick(to: CGPoint(x: KeyboardCursorTrackpad.pointsPerCharacter * 3, y: 0), now: 1.01),
            KeyboardCursorStep(characters: 2)
        )
    }

    func testFractionalTravelCarriesOverUntilTheNextCharacter() {
        var sampler = KeyboardCursorJoystickSampler(origin: .zero)
        XCTAssertTrue(
            sampler.tick(to: CGPoint(x: KeyboardCursorTrackpad.pointsPerCharacter - 1, y: 0), now: 1).isEmpty
        )
        XCTAssertEqual(
            sampler.tick(to: CGPoint(x: KeyboardCursorTrackpad.pointsPerCharacter, y: 0), now: 1.01),
            KeyboardCursorStep(characters: 1)
        )
    }

    func testAStillFingerOutsideTheOriginDoesNotGenerateSyntheticMovement() {
        let origin = CGPoint(x: 10, y: 10)
        let held = CGPoint(x: 10 + KeyboardCursorJoystick.deadZone + 4, y: 10)
        var sampler = KeyboardCursorJoystickSampler(origin: origin)
        XCTAssertEqual(
            sampler.tick(to: held, now: 1),
            KeyboardCursorStep(characters: 1)
        )
        XCTAssertTrue(sampler.tick(to: held, now: 1.01).isEmpty)
    }

    func testReversalUsesTheNewTravelDelta() {
        var sampler = KeyboardCursorJoystickSampler(origin: CGPoint(x: 50, y: 40))
        XCTAssertEqual(
            sampler.tick(to: CGPoint(x: 18, y: 40), now: 1),
            KeyboardCursorStep(characters: -4)
        )
        XCTAssertEqual(
            sampler.tick(to: CGPoint(x: 50, y: 40), now: 1.2),
            KeyboardCursorStep(characters: 4)
        )
        XCTAssertTrue(sampler.tick(to: CGPoint(x: 50, y: 40), now: 1.4).isEmpty)
    }

    func testTravelBeyondTheVisibleSpacebarKeepsFollowingTheFinger() {
        var sampler = KeyboardCursorJoystickSampler(origin: CGPoint(x: 100, y: 20))
        XCTAssertEqual(
            sampler.tick(to: CGPoint(x: 1000, y: 20), now: 1),
            KeyboardCursorStep(characters: 32)
        )
        XCTAssertEqual(
            sampler.tick(to: CGPoint(x: 900, y: 20), now: 1.1),
            KeyboardCursorStep(characters: -12)
        )
    }
}
