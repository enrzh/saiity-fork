import Foundation

public enum VoiceOnlyKeyboardPolicy {
    public static let usesLegacyKeyGrid = false
    public static let surfaceHeight: Double = 220
    public static let controlSize: Double = 44
    public static let railSpacing: Double = 4
    public static let verticalPadding: Double = 8
    public static let rightRailHeight: Double = controlSize * 4 + railSpacing * 3 + verticalPadding * 2

    public struct Layout: Equatable {
        public let surfaceWidth: Double
        public let leftRailWidth: Double
        public let rightRailWidth: Double
        public let centerX: Double
    }

    public static func layout(for availableWidth: Double) -> Layout {
        Layout(
            surfaceWidth: availableWidth,
            leftRailWidth: controlSize,
            rightRailWidth: controlSize,
            centerX: availableWidth / 2
        )
    }
}
