// DictusCore/Sources/DictusCore/KeyboardCursorJoystick.swift
// Spacebar hold uses native-style trackpad deltas. A held finger only moves the
// caret when it travels; a stationary finger never generates synthetic motion.
import CoreGraphics
import Foundation

/// Converts a held spacebar offset into caret steps.
public enum KeyboardCursorJoystick {
    /// Neutral area around the press. Finger jitter inside this radius does
    /// not cruise the caret. Follow still maps real travel inside it.
    public static let deadZone: CGFloat = 8
    /// Retained for source compatibility with older keyboard hosts. Delta
    /// tracking does not schedule repeat events.
    public static let tickInterval: TimeInterval = 0.04
    public static let pointsPerCharacter: CGFloat = 16
    public static let pointsPerLine: CGFloat = 24
    public static let maxCharactersPerTick: Int = 4
    public static let maxLinesPerTick: Int = 2
    /// Ignore sub-pixel jitter so a resting finger does not look like travel.
    public static let movementEpsilon: CGFloat = 0.35
    public static let maxFollowCharactersPerTick: Int = 32
    public static let maxFollowLinesPerTick: Int = 8

    public static func step(from origin: CGPoint, to point: CGPoint) -> KeyboardCursorStep {
        KeyboardCursorStep(
            characters: units(
                displacement: point.x - origin.x,
                pointsPerUnit: pointsPerCharacter,
                maxUnits: maxCharactersPerTick
            ),
            lines: units(
                displacement: point.y - origin.y,
                pointsPerUnit: pointsPerLine,
                maxUnits: maxLinesPerTick
            )
        )
    }

    public static func units(
        displacement: CGFloat,
        pointsPerUnit: CGFloat,
        maxUnits: Int
    ) -> Int {
        let magnitude = abs(displacement)
        guard magnitude > deadZone else { return 0 }
        let extra = magnitude - deadZone
        let count = 1 + Int(extra / pointsPerUnit)
        return (displacement > 0 ? 1 : -1) * min(maxUnits, count)
    }
}

/// Tracks one spacebar press using only movement deltas.
public struct KeyboardCursorJoystickSampler: Equatable {
    public var origin: CGPoint
    public var lastPoint: CGPoint
    public var remainderX: CGFloat
    public var remainderY: CGFloat

    public init(origin: CGPoint) {
        self.origin = origin
        self.lastPoint = origin
        self.remainderX = 0
        self.remainderY = 0
    }

    /// Consume only the distance travelled since the last sample. `now` and
    /// `force` remain in the signature so UIKit and SwiftUI hosts can share the
    /// sampler without a second compatibility layer.
    public mutating func tick(
        to point: CGPoint,
        now: TimeInterval,
        force: Bool = false
    ) -> KeyboardCursorStep {
        let dx = point.x - lastPoint.x
        let dy = point.y - lastPoint.y
        lastPoint = point

        guard abs(dx) >= KeyboardCursorJoystick.movementEpsilon
            || abs(dy) >= KeyboardCursorJoystick.movementEpsilon else {
            return KeyboardCursorStep()
        }
        return consumeFollow(dx: dx, dy: dy)
    }

    private mutating func consumeFollow(dx: CGFloat, dy: CGFloat) -> KeyboardCursorStep {
        remainderX += dx
        remainderY += dy
        let characters = quantize(
            remainder: &remainderX,
            pointsPerUnit: KeyboardCursorTrackpad.pointsPerCharacter,
            maxUnits: KeyboardCursorJoystick.maxFollowCharactersPerTick
        )
        let lines = quantize(
            remainder: &remainderY,
            pointsPerUnit: KeyboardCursorTrackpad.pointsPerLine,
            maxUnits: KeyboardCursorJoystick.maxFollowLinesPerTick
        )
        return KeyboardCursorStep(characters: characters, lines: lines)
    }

    private func quantize(
        remainder: inout CGFloat,
        pointsPerUnit: CGFloat,
        maxUnits: Int
    ) -> Int {
        guard pointsPerUnit > 0 else { return 0 }
        let raw = Int(remainder / pointsPerUnit)
        let clamped = max(-maxUnits, min(maxUnits, raw))
        remainder -= CGFloat(clamped) * pointsPerUnit
        if abs(raw) > maxUnits {
            remainder = 0
        }
        return clamped
    }
}
