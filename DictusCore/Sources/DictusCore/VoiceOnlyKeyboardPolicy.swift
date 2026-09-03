import Foundation
import CoreGraphics

public enum VoiceOnlyKeyboardPolicy {
    public enum SymbolPage: Equatable {
        case symbols1
        case symbols2
    }

    public enum SymbolPageTransition: Equatable {
        case symbols1ToSymbols2
        case symbols2ToSymbols1

        public static func forToggle(from page: SymbolPage) -> Self {
            switch page {
            case .symbols1: return .symbols1ToSymbols2
            case .symbols2: return .symbols2ToSymbols1
            }
        }
    }

    public struct SymbolGrid {
        public static func frames(
            for rows: [[CGFloat]],
            in size: CGSize,
            spacing: CGFloat,
            inset: CGFloat,
            rowSpacing: CGFloat? = nil
        ) -> [[CGRect]] {
            guard !rows.isEmpty else { return [] }
            let resolvedRowSpacing = rowSpacing ?? spacing
            let rowHeight = max(1, (size.height - resolvedRowSpacing * CGFloat(rows.count - 1)) / CGFloat(rows.count))
            return rows.enumerated().map { rowIndex, row in
                guard !row.isEmpty,
                      row.allSatisfy({ $0 >= 0 }) else { return [] }
                let usableWidth = size.width - inset * 2
                guard usableWidth > 0 else { return [] }
                let totalUnits = max(1, row.reduce(CGFloat.zero, +))
                let gaps = spacing * CGFloat(max(0, row.count - 1))
                let unitWidth = (usableWidth - gaps) / totalUnits
                guard unitWidth > 0 else { return [] }
                var x = inset
                return row.map { width in
                    let frame = CGRect(x: x,
                                       y: CGFloat(rowIndex) * (rowHeight + resolvedRowSpacing),
                                       width: unitWidth * width,
                                       height: rowHeight)
                    x = frame.maxX + spacing
                    return frame
                }
            }
        }
    }

    public static let usesLegacyKeyGrid = false
    /// Native compact iPhone portrait height before the sAiity scale.
    public static let nativePortraitReferenceHeight: Double = 216
    /// Extra dictation-board height on top of the native keyboard.
    public static let surfaceHeightScale: Double = 1.10
    /// Shared portrait fallback and the scale applied to device-native heights
    /// at runtime by the keyboard extension.
    public static let surfaceHeight: Double = nativePortraitReferenceHeight * surfaceHeightScale

    /// Chooses the height reported by the laid-out input view, falling back to
    /// the device provider while UIKit is still resolving the input surface.
    /// The controller view is used only to reject a full-screen inputView
    /// candidate while UIKit is still resolving the keyboard surface.
    public struct SurfaceHeightResolution: Equatable {
        public let height: Double
        public let observedInputViewHeight: Double?
        public let stableInputViewPasses: Int
        public let usesInputViewHeight: Bool
    }

    public static func resolvedSurfaceHeight(
        inputViewHeight: Double?,
        controllerViewHeight: Double?,
        fallbackHeight: Double,
        previousInputViewHeight: Double? = nil,
        stableInputViewPasses: Int = 0
    ) -> SurfaceHeightResolution {
        let fallback = fallbackHeight.isFinite && fallbackHeight > 0 ? fallbackHeight : 1
        guard let inputViewHeight, inputViewHeight.isFinite, inputViewHeight > 0 else {
            return SurfaceHeightResolution(height: fallback,
                                           observedInputViewHeight: nil,
                                           stableInputViewPasses: 0,
                                           usesInputViewHeight: false)
        }

        // During keyboard entry UIKit can temporarily give inputView the same
        // full-screen height as the controller. Never turn that transient
        // container geometry into the keyboard's declared height.
        if let controllerViewHeight,
           controllerViewHeight.isFinite,
           controllerViewHeight > 0,
           inputViewHeight >= controllerViewHeight - 0.5 {
            return SurfaceHeightResolution(height: fallback,
                                           observedInputViewHeight: nil,
                                           stableInputViewPasses: 0,
                                           usesInputViewHeight: false)
        }

        let isSameAsPrevious = previousInputViewHeight.map {
            abs($0 - inputViewHeight) <= 0.5
        } ?? false
        let stablePasses = isSameAsPrevious
            ? max(0, stableInputViewPasses) + 1
            : 1
        let isStable = stablePasses >= 2
        return SurfaceHeightResolution(
            height: isStable ? inputViewHeight : fallback,
            observedInputViewHeight: inputViewHeight,
            stableInputViewPasses: stablePasses,
            usesInputViewHeight: isStable
        )
    }

    public static let controlSize: Double = 44
    public static let symbolControlGap: Double = 4
    /// The auxiliary page keeps Emoji and microphone in one native-height bottom row.
    /// The page toggle belongs to the first key of the third symbol row, so it does not
    /// consume a second vertical control lane and compress the symbol keys.
    public static let symbolBottomControlLaneHeight: Double = controlSize
    public static let symbolBottomControlBottomInset: Double = 4
    public static let symbolBottomControlBudget: Double = symbolBottomControlLaneHeight + symbolBottomControlBottomInset
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
    /// Alternate symbol pages use three real rows. SwiftUI owns the lower control lane
    /// inside the shared surface; there is no legacy accessory row.
    public static let contentHeight: Double = surfaceHeight
    public static let symbolsMinimumContentHeight: Double = controlSize * 3
    /// Auxiliary pages need three symbol rows plus one native-height SwiftUI control row.
    public static let alternateMinimumHeight: Double = verticalPadding * 2 + controlSize + symbolsMinimumContentHeight
    public static let titleHeight: Double = 17
    /// Reserve a real text line for failures even at the standard 216pt
    /// keyboard height. This lane stays outside the mic capsule.
    public static let statusHeight: Double = 20
    public static let contentSpacing: Double = 6
    public static let topInset: Double = 8

    public static func primaryControlWidth(availableWidth: Double, centerAreaWidth: Double) -> Double {
        let clusterVisible = availableWidth - horizontalPadding * 2 >= controlSize * 2 + 124
        let globalWidthLimit = clusterVisible
            ? availableWidth - horizontalPadding * 2 - commandClusterSize * 2
            : availableWidth
        return max(44, min(max(132, availableWidth * 0.39), centerAreaWidth - 16, globalWidthLimit))
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
        public let controlOrder: KeyboardAccessoryOrder

        public var surfaceInset: Double { horizontalInset }

        public var surfaceFrame: CGRect {
            CGRect(x: horizontalInset, y: verticalPadding,
                   width: max(0, surfaceWidth - horizontalInset * 2),
                   height: max(0, surfaceHeight - verticalPadding * 2))
        }

        public var bottomAuxiliaryControlFrame: CGRect {
            CGRect(x: surfaceFrame.minX, y: surfaceFrame.maxY - visibleControlGap - controlSize,
                   width: surfaceFrame.width, height: controlSize)
        }

        public var auxiliaryContentFrame: CGRect {
            let maxY = bottomAuxiliaryControlFrame.minY - visibleControlGap
            guard maxY > surfaceFrame.minY else { return .zero }
            return CGRect(x: surfaceFrame.minX, y: surfaceFrame.minY, width: surfaceFrame.width,
                          height: maxY - surfaceFrame.minY)
        }

        public var auxiliaryControlFrames: [CGRect] {
            switch controlOrder {
            case .emojiFirst: return [leftUtilityFrames.emoji, leftUtilityFrames.number]
            case .numberFirst: return [leftUtilityFrames.number, leftUtilityFrames.emoji]
            }
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
            let emojiFrame = CGRect(x: x, y: surfaceFrame.maxY - visibleControlGap - size.height, width: size.width, height: size.height)
            let numberFrame = CGRect(x: x + size.width + railSpacing, y: surfaceFrame.maxY - visibleControlGap - size.height, width: size.width, height: size.height)
            return (
                CGRect(x: x, y: emojiFrame.minY - railSpacing - size.height, width: size.width, height: size.height),
                controlOrder == .emojiFirst ? emojiFrame : numberFrame,
                controlOrder == .emojiFirst ? numberFrame : emojiFrame
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

        /// The failure message gets its own non-interactive lane below the mic.
        /// Keeping it in the center region prevents it from colliding with the
        /// left and right utility rails while leaving the capsule's content stable.
        public var dictationErrorFrame: CGRect {
            let mic = dictateFrame
            guard !mic.isEmpty else { return .zero }

            let frame = CGRect(
                x: micCenterArea.minX,
                y: mic.maxY + visibleControlGap,
                width: micCenterArea.width,
                height: statusHeight
            )
            guard surfaceFrame.contains(frame), !frame.intersects(mic) else { return .zero }
            return frame
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
        surfaceHeight: Double = VoiceOnlyKeyboardPolicy.surfaceHeight,
        controlOrder: KeyboardAccessoryOrder = .emojiFirst
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
            showsLanguageIndicator: hasRails,
            controlOrder: controlOrder
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
