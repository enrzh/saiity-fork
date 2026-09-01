import Foundation
import CoreGraphics

public enum VoiceOnlyKeyboardPolicy {
    public static let usesLegacyKeyGrid = false
    /// The standard portrait iPhone keyboard grid height. The extension's UIKit
    /// height provider remains the source of truth at runtime; this is the
    /// shared fallback used by policy tests and the initial SwiftUI layout.
    public static let surfaceHeight: Double = 216
    public static let controlSize: Double = 44
    public static let actionHitSize = CGSize(width: 88, height: 44)
    public static let bottomActionHitHeight: CGFloat = 44
    public static let utilityVisualSize: Double = 36
    public static let languageVisualWidth: Double = 58
    public static let rightRailControlCount: Int = 2
    public static let leftRailControlCount: Int = 3
    public static let minimumCenterAreaWidth: Double = 76
    public static let commandClusterSize: Double = controlSize
    /// The primary voice action is larger than utility controls so it remains
    /// easy to press without turning the keyboard into a key grid.
    public static let primaryControlSize: Double = 54
    public static let railSpacing: Double = 0
    public static let horizontalPadding: Double = 10
    /// The right rail spans the voice surface with the same breathing room as
    /// Apple's compact keyboard controls.
    public static let verticalPadding: Double = 8
    /// The language indicator sits slightly closer to
    /// the lower edge, matching the asymmetric system keyboard balance.
    public static let leftRailVerticalPadding: Double = 8
    public static let rightRailHeight: Double = actionHitSize.height * 2
    /// Alternate symbol pages use four rows of at least 44pt. The center region
    /// may occupy the full fixed surface because the outer rails own its sides.
    public static let contentHeight: Double = surfaceHeight
    public static let titleHeight: Double = 17
    public static let statusHeight: Double = 16
    public static let contentSpacing: Double = 6
    public static let topInset: Double = 8

    public static func primaryControlWidth(availableWidth: Double, centerAreaWidth: Double) -> Double {
        let clusterVisible = availableWidth - horizontalPadding * 2 >= controlSize * 2 + 124
        let globalWidthLimit = clusterVisible
            ? availableWidth - horizontalPadding * 2 - commandClusterSize * 2
            : availableWidth
        return max(44, min(max(132, availableWidth * 0.39), centerAreaWidth - 16, globalWidthLimit))
    }

    public static func rightRailFrames(
        for width: CGFloat,
        surfaceHeight: CGFloat = CGFloat(VoiceOnlyKeyboardPolicy.surfaceHeight)
    ) -> (delete: CGRect, returnKey: CGRect) {
        guard layout(for: Double(width), surfaceHeight: Double(surfaceHeight)).rightRailWidth > 0 else {
            return (.zero, .zero)
        }
        let inset = horizontalInset(for: Double(width))
        let x = max(0, width - CGFloat(inset) - actionHitSize.width)
        return (
            CGRect(x: x, y: CGFloat(topInset), width: actionHitSize.width, height: actionHitSize.height),
            CGRect(x: x, y: CGFloat(topInset) + actionHitSize.height, width: actionHitSize.width, height: actionHitSize.height)
        )
    }

    public static func leftUtilityFrames(
        for width: CGFloat,
        surfaceHeight: CGFloat = CGFloat(VoiceOnlyKeyboardPolicy.surfaceHeight)
    ) -> (at: CGRect, emoji: CGRect, number: CGRect) {
        let layout = layout(for: Double(width), surfaceHeight: Double(surfaceHeight))
        return layout.leftUtilityFrames
    }

    public static func dismissFrame(
        for width: CGFloat,
        surfaceHeight: CGFloat = CGFloat(VoiceOnlyKeyboardPolicy.surfaceHeight)
    ) -> CGRect {
        guard layout(for: Double(width), surfaceHeight: Double(surfaceHeight)).rightRailWidth > 0 else {
            return .zero
        }
        let inset = horizontalInset(for: Double(width))
        let x = max(0, width - CGFloat(inset) - actionHitSize.width)
        return CGRect(x: x, y: surfaceHeight - bottomActionHitHeight,
                      width: actionHitSize.width, height: bottomActionHitHeight)
    }

    public struct Layout: Equatable {
        public let surfaceWidth: Double
        public let horizontalInset: Double
        public let leftRailWidth: Double
        public let rightRailWidth: Double
        public let centerAreaWidth: Double
        public let rightRailHeight: Double
        public let rightRailTop: Double
        public let rightRailBottom: Double
        public let dismissTop: Double
        public let dismissBottom: Double
        public let contentHeight: Double
        public let surfaceHeight: Double
        public let centerX: Double
        public let leftBottomCenterX: Double
        public let rightBottomCenterX: Double
        public let leftBottomCenterY: Double
        public let rightBottomCenterY: Double
        public let showsLanguageIndicator: Bool

        public var rightCommandFrame: CGRect {
            CGRect(x: surfaceWidth - horizontalInset - rightRailWidth, y: rightRailTop,
                   width: rightRailWidth, height: rightRailHeight)
        }

        public var languageFrame: CGRect {
            CGRect(x: horizontalInset, y: VoiceOnlyKeyboardPolicy.topInset,
                   width: VoiceOnlyKeyboardPolicy.languageVisualWidth,
                   height: VoiceOnlyKeyboardPolicy.controlSize)
        }

        public var leftUtilityFrames: (at: CGRect, emoji: CGRect, number: CGRect) {
            guard leftRailWidth > 0 else { return (.zero, .zero, .zero) }
            let x = horizontalInset
            let y = surfaceHeight - VoiceOnlyKeyboardPolicy.controlSize
            let size = CGSize(width: VoiceOnlyKeyboardPolicy.controlSize, height: VoiceOnlyKeyboardPolicy.controlSize)
            return (
                CGRect(x: x, y: y, width: size.width, height: size.height),
                CGRect(x: x + size.width, y: y, width: size.width, height: size.height),
                CGRect(x: x + size.width * 2, y: y, width: size.width, height: size.height)
            )
        }

        public var deleteFrame: CGRect { rightRailFrames.delete }

        public var returnFrame: CGRect { rightRailFrames.returnKey }

        public var rightRailFrames: (delete: CGRect, returnKey: CGRect) {
            VoiceOnlyKeyboardPolicy.rightRailFrames(
                for: surfaceWidth,
                surfaceHeight: CGFloat(surfaceHeight)
            )
        }

        public var dismissFrame: CGRect {
            guard rightRailWidth > 0 else { return .zero }
            return VoiceOnlyKeyboardPolicy.dismissFrame(
                for: surfaceWidth,
                surfaceHeight: CGFloat(surfaceHeight)
            )
        }

        public var micCenterArea: CGRect {
            CGRect(x: centerX - centerAreaWidth / 2,
                   y: (surfaceHeight - contentHeight) / 2,
                   width: centerAreaWidth, height: contentHeight)
        }

        /// The full-height content region for alternate pages. Rails remain
        /// outside its right edge; the bottom blank symbols row leaves the
        /// left utility rail available for controls.
        public var alternateContentFrame: CGRect {
            let x = horizontalInset
            let right = surfaceWidth - horizontalInset - rightRailWidth
            return CGRect(x: x, y: 0, width: max(0, right - x), height: surfaceHeight)
        }

        /// The hold-to-dictate capsule keeps one frame while its content changes.
        public var dictateFrame: CGRect {
            guard surfaceHeight >= VoiceOnlyKeyboardPolicy.primaryControlSize else { return .zero }
            let width = VoiceOnlyKeyboardPolicy.primaryControlWidth(
                availableWidth: surfaceWidth,
                centerAreaWidth: centerAreaWidth
            )
            return CGRect(
                x: centerX - width / 2,
                y: (surfaceHeight - VoiceOnlyKeyboardPolicy.primaryControlSize) / 2,
                width: width,
                height: VoiceOnlyKeyboardPolicy.primaryControlSize
            )
        }

        public var actionRectangles: [CGRect] {
            let utilities = leftRailWidth > 0
                ? [leftUtilityFrames.at, leftUtilityFrames.emoji, leftUtilityFrames.number]
                : []
            let commandRects: [CGRect]
            if rightRailWidth > 0 {
                let x = surfaceWidth - horizontalInset - rightRailWidth + (rightRailWidth - controlSize) / 2
                commandRects = (0..<rightRailControlCount).map { index in
                    CGRect(x: x, y: rightRailTop + Double(index) * controlSize,
                           width: controlSize, height: controlSize)
                }
            } else {
                commandRects = []
            }
            return utilities + commandRects + (rightRailWidth > 0 ? [dismissFrame] : []) + [dictateFrame]
        }
    }

    public static func layout(
        for availableWidth: Double,
        surfaceHeight: Double = VoiceOnlyKeyboardPolicy.surfaceHeight
    ) -> Layout {
        let resolvedSurfaceHeight = max(0, surfaceHeight)
        let leftWidth = CGFloat(controlSize * Double(leftRailControlCount))
        let rightWidth = actionHitSize.width
        let hasRails = availableWidth >= Double(leftWidth + rightWidth) + minimumCenterAreaWidth + horizontalPadding * 2
            && resolvedSurfaceHeight >= topInset + rightRailHeight + bottomActionHitHeight
        // Keep the same outer inset on both the visual center region and the UIKit
        // action rail. At the narrowest supported width, dropping the inset keeps
        // the center region at the 44pt minimum instead of compressing it below a
        // usable touch target.
        let horizontalInset = horizontalInset(for: availableWidth)
        let railWidth = hasRails ? rightWidth : 0
        let resolvedLeftRailWidth = hasRails ? Double(leftWidth) : 0
        let centerAreaWidth = max(0, availableWidth
            - horizontalInset * 2
            - resolvedLeftRailWidth
            - Double(railWidth))

        return Layout(
            surfaceWidth: availableWidth,
            horizontalInset: horizontalInset,
            leftRailWidth: resolvedLeftRailWidth,
            rightRailWidth: Double(railWidth),
            centerAreaWidth: centerAreaWidth,
            rightRailHeight: rightRailHeight,
            rightRailTop: topInset,
            rightRailBottom: topInset + rightRailHeight,
            dismissTop: resolvedSurfaceHeight - controlSize,
            dismissBottom: resolvedSurfaceHeight,
            contentHeight: resolvedSurfaceHeight,
            surfaceHeight: resolvedSurfaceHeight,
            centerX: horizontalInset + resolvedLeftRailWidth + centerAreaWidth / 2,
            leftBottomCenterX: horizontalInset,
            rightBottomCenterX: availableWidth - horizontalInset - (railWidth > 0 ? railWidth / 2 : controlSize / 2),
            leftBottomCenterY: resolvedSurfaceHeight - controlSize / 2,
            rightBottomCenterY: resolvedSurfaceHeight - controlSize / 2,
            showsLanguageIndicator: hasRails
        )
    }

    private static func horizontalInset(for availableWidth: Double) -> Double {
        let railsFit = availableWidth >= Double(leftRailControlCount) * controlSize
            + actionHitSize.width + controlSize
        guard railsFit else { return min(horizontalPadding, availableWidth / 2) }

        let centerMinimumFitsWithInset = availableWidth >= Double(leftRailControlCount) * controlSize
            + actionHitSize.width + controlSize + horizontalPadding * 2
        return centerMinimumFitsWithInset ? horizontalPadding : 0
    }
}
