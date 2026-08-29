import Foundation

public enum VoiceOnlyKeyboardPolicy {
    public static let usesLegacyKeyGrid = false
    public static let surfaceHeight: Double = 220
    public static let controlSize: Double = 44
    public static let railSpacing: Double = 4
    public static let horizontalPadding: Double = 10
    /// The right rail spans the voice surface with the same breathing room as
    /// Apple's compact keyboard controls.
    public static let verticalPadding: Double = 16
    /// The language indicator and next-keyboard control sit slightly closer to
    /// the lower edge, matching the asymmetric system keyboard balance.
    public static let leftRailVerticalPadding: Double = 8
    public static let rightRailHeight: Double = controlSize * 4 + railSpacing * 3 + verticalPadding * 2

    public struct Layout: Equatable {
        public let surfaceWidth: Double
        public let leftRailWidth: Double
        public let rightRailWidth: Double
        public let centerX: Double
    }

    public static func layout(for availableWidth: Double) -> Layout {
        let centerAreaWidth = availableWidth
            - horizontalPadding * 2
            - controlSize
            - controlSize

        return Layout(
            surfaceWidth: availableWidth,
            leftRailWidth: controlSize,
            rightRailWidth: controlSize,
            centerX: horizontalPadding + controlSize + centerAreaWidth / 2
        )
    }
}
