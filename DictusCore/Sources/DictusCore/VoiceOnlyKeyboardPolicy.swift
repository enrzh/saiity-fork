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
    public static let railSpacing: Double = 4
    public static let horizontalPadding: Double = 6
    public static let controlEdgeInset: Double = 12
    public static let visibleControlGap: Double = 8
    /// The right rail spans the voice surface with the same breathing room as
    /// Apple's compact keyboard controls.
    public static let verticalPadding: Double = 4
    /// The language indicator sits slightly closer to
    /// the lower edge, matching the asymmetric system keyboard balance.
    public static let leftRailVerticalPadding: Double = 4
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
        return layout(for: Double(width), surfaceHeight: Double(surfaceHeight)).rightRailFrames
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
        return layout(for: Double(width), surfaceHeight: Double(surfaceHeight)).dismissFrame
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

        public var surfaceInset: Double { horizontalInset }

        public var surfaceFrame: CGRect {
            CGRect(x: horizontalInset, y: verticalPadding,
                   width: max(0, surfaceWidth - horizontalInset * 2),
                   height: max(0, surfaceHeight - verticalPadding * 2))
        }

        public var rightCommandFrame: CGRect {
            CGRect(x: surfaceFrame.maxX - visibleControlGap - rightRailWidth, y: rightRailTop,
                   width: rightRailWidth, height: rightRailHeight)
        }

        public var languageFrame: CGRect {
            CGRect(x: surfaceFrame.minX + visibleControlGap,
                   y: surfaceFrame.minY + VoiceOnlyKeyboardPolicy.topInset,
                   width: VoiceOnlyKeyboardPolicy.languageVisualWidth,
                   height: VoiceOnlyKeyboardPolicy.controlSize)
        }

        public var leftUtilityFrames: (at: CGRect, emoji: CGRect, number: CGRect) {
            guard leftRailWidth > 0 else { return (.zero, .zero, .zero) }
            let x = surfaceFrame.minX + visibleControlGap
            let size = CGSize(width: VoiceOnlyKeyboardPolicy.controlSize, height: VoiceOnlyKeyboardPolicy.controlSize)
            return (
                CGRect(x: x, y: surfaceFrame.maxY - visibleControlGap - size.height * 2, width: size.width, height: size.height),
                CGRect(x: x, y: surfaceFrame.maxY - visibleControlGap - size.height, width: size.width, height: size.height),
                CGRect(x: x + size.width + railSpacing, y: surfaceFrame.maxY - visibleControlGap - size.height, width: size.width, height: size.height)
            )
        }

        public var deleteFrame: CGRect { rightRailFrames.delete }

        public var returnFrame: CGRect { rightRailFrames.returnKey }

        public var rightRailFrames: (delete: CGRect, returnKey: CGRect) {
            let x = surfaceFrame.maxX - visibleControlGap - rightRailWidth
            return (delete: CGRect(x: x, y: surfaceFrame.minY + visibleControlGap, width: rightRailWidth, height: controlSize),
                    returnKey: CGRect(x: x, y: surfaceFrame.minY + visibleControlGap + controlSize, width: rightRailWidth, height: controlSize))
        }

        public var dismissFrame: CGRect {
            guard rightRailWidth > 0 else { return .zero }
            return CGRect(x: surfaceFrame.maxX - visibleControlGap - rightRailWidth,
                          y: surfaceFrame.maxY - visibleControlGap - bottomActionHitHeight,
                          width: rightRailWidth, height: bottomActionHitHeight)
        }

        public var micCenterArea: CGRect {
            CGRect(x: centerX - centerAreaWidth / 2,
                   y: surfaceFrame.minY,
                   width: centerAreaWidth, height: surfaceFrame.height)
        }

        /// Alternate pages cover the complete embedded surface. The upper
        /// action rails are drawn on top by the owning controls overlay.
        public var alternateContentFrame: CGRect {
            surfaceFrame
        }

        public var alternateAccessoryRowFrame: CGRect {
            CGRect(x: surfaceFrame.minX, y: surfaceFrame.minY,
                   width: surfaceFrame.width,
                   height: min(VoiceOnlyKeyboardPolicy.controlSize, surfaceFrame.height))
        }

        public var alternateContentBelowAccessoryFrame: CGRect {
            let row = alternateAccessoryRowFrame
            return CGRect(x: surfaceFrame.minX, y: row.maxY,
                          width: surfaceFrame.width,
                          height: max(0, surfaceFrame.maxY - row.maxY))
        }

        /// The symbols pages reserve their bottom row for the UIKit-owned ABC control.
        /// This row stays inside the inset surface so the control is not clipped.
        public var symbolsReservedRowFrame: CGRect {
            CGRect(x: surfaceFrame.minX,
                   y: surfaceFrame.maxY - VoiceOnlyKeyboardPolicy.controlSize,
                   width: surfaceFrame.width,
                   height: VoiceOnlyKeyboardPolicy.controlSize)
        }

        /// The hold-to-dictate capsule keeps one frame while its content changes.
        public var dictateFrame: CGRect {
            guard surfaceFrame.height >= VoiceOnlyKeyboardPolicy.primaryControlSize + visibleControlGap else { return .zero }
            let width = VoiceOnlyKeyboardPolicy.primaryControlWidth(
                availableWidth: surfaceWidth,
                centerAreaWidth: centerAreaWidth
            )
            return CGRect(
                x: centerX - width / 2,
                y: surfaceFrame.minY + (surfaceFrame.height - VoiceOnlyKeyboardPolicy.primaryControlSize) / 2,
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
                let x = rightRailFrames.delete.minX + (rightRailWidth - controlSize) / 2
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
        let leftWidth = CGFloat(controlSize * Double(leftRailControlCount) + railSpacing * Double(leftRailControlCount - 1))
        let rightWidth = actionHitSize.width
        let minimumRailHeight = verticalPadding * 2 + visibleControlGap * 2 + rightRailHeight + bottomActionHitHeight
        let hasRails = availableWidth >= Double(leftWidth + rightWidth) + minimumCenterAreaWidth + horizontalPadding * 2
            && resolvedSurfaceHeight >= minimumRailHeight
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
            rightRailTop: verticalPadding + visibleControlGap,
            rightRailBottom: verticalPadding + visibleControlGap + rightRailHeight,
            dismissTop: resolvedSurfaceHeight - verticalPadding - visibleControlGap - bottomActionHitHeight,
            dismissBottom: resolvedSurfaceHeight - verticalPadding - visibleControlGap,
            contentHeight: resolvedSurfaceHeight,
            surfaceHeight: resolvedSurfaceHeight,
            centerX: horizontalInset + (availableWidth - horizontalInset * 2) / 2,
            leftBottomCenterX: resolvedLeftRailWidth > 0
                ? horizontalInset + visibleControlGap + controlSize / 2
                : 0,
            rightBottomCenterX: railWidth > 0
                ? horizontalInset + (availableWidth - horizontalInset * 2)
                    - visibleControlGap - railWidth / 2
                : 0,
            leftBottomCenterY: hasRails
                ? resolvedSurfaceHeight - verticalPadding - visibleControlGap - bottomActionHitHeight / 2
                : 0,
            rightBottomCenterY: hasRails
                ? resolvedSurfaceHeight - verticalPadding - visibleControlGap - bottomActionHitHeight / 2
                : 0,
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
