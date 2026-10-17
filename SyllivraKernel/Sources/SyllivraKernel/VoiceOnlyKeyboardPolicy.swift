import Foundation
import CoreGraphics

public enum VoiceOnlyKeyboardPolicy {
    public struct LeftUtilityFrames: Equatable {
        public let at: CGRect
        public let emoji: CGRect
        public let number: CGRect

        public init(at: CGRect, emoji: CGRect, number: CGRect) {
            self.at = at
            self.emoji = emoji
            self.number = number
        }
    }

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
            rowSpacing: CGFloat? = nil,
            maxRowHeight: CGFloat? = nil
        ) -> [[CGRect]] {
            guard !rows.isEmpty else { return [] }
            let resolvedRowSpacing = rowSpacing ?? spacing
            let natural = max(1, (size.height - resolvedRowSpacing * CGFloat(rows.count - 1)) / CGFloat(rows.count))
            let rowHeight = min(natural, maxRowHeight ?? natural)
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

        /// Last-row height of ABC / 123 / #+=. Caps, #+= and Delete pin to the
        /// dictation-board delete hit height whenever the remaining letter rows
        /// still have a usable target.
        public static func letterAlignedLastRowHeight(
            in height: CGFloat,
            rowSpacing: CGFloat
        ) -> CGFloat {
            let commandHeight = VoiceOnlyKeyboardPolicy.bottomBarVisualHeight
            let minimumUpperRows = CGFloat(36 * 2)
            let maxPinned = max(1, height - rowSpacing * 2 - minimumUpperRows)
            return min(commandHeight, maxPinned)
        }

        /// Pins the last character row (shift/delete) to a shared height so ABC,
        /// 123 and #+= do not resize the delete key.
        public static func framesWithPinnedLastRow(
            for rows: [[CGFloat]],
            in size: CGSize,
            spacing: CGFloat,
            inset: CGFloat,
            rowSpacing: CGFloat? = nil,
            lastRowHeight: CGFloat,
            maxRowHeight: CGFloat? = nil
        ) -> [[CGRect]] {
            guard !rows.isEmpty else { return [] }
            let resolvedRowSpacing = rowSpacing ?? spacing
            let pinnedHeight = min(max(1, lastRowHeight), max(1, size.height))
            if rows.count == 1 {
                let frames = frames(
                    for: rows,
                    in: CGSize(width: size.width, height: pinnedHeight),
                    spacing: spacing,
                    inset: inset,
                    rowSpacing: resolvedRowSpacing,
                    maxRowHeight: maxRowHeight
                )
                let y = max(0, size.height - pinnedHeight)
                return frames.map { row in
                    row.map { CGRect(x: $0.minX, y: y, width: $0.width, height: pinnedHeight) }
                }
            }

            let upperRows = Array(rows.dropLast())
            let upperCount = max(1, upperRows.count)
            let naturalUpper = max(
                1,
                (size.height - pinnedHeight - resolvedRowSpacing * CGFloat(upperCount))
                    / CGFloat(upperCount)
            )
            let upperRowHeight = min(naturalUpper, maxRowHeight ?? naturalUpper)
            let packedUpper = upperRowHeight * CGFloat(upperRows.count)
                + resolvedRowSpacing * CGFloat(max(0, upperRows.count - 1))
            let originY = max(0, size.height - pinnedHeight - resolvedRowSpacing - packedUpper)
            let upperFrames = frames(
                for: upperRows,
                in: CGSize(width: size.width, height: packedUpper),
                spacing: spacing,
                inset: inset,
                rowSpacing: resolvedRowSpacing,
                maxRowHeight: upperRowHeight
            ).map { row in
                row.map { CGRect(x: $0.minX, y: $0.minY + originY, width: $0.width, height: $0.height) }
            }
            let lastY = originY + packedUpper + resolvedRowSpacing
            let lastFrames = frames(
                for: [rows[rows.count - 1]],
                in: CGSize(width: size.width, height: pinnedHeight),
                spacing: spacing,
                inset: inset,
                rowSpacing: resolvedRowSpacing
            ).map { row in
                row.map { CGRect(x: $0.minX, y: lastY, width: $0.width, height: pinnedHeight) }
            }
            return upperFrames + lastFrames
        }

        /// Builds a symbol row whose first and last commands keep a native-sized
        /// hit target while the punctuation keys share the remaining width.
        ///
        /// The row is intentionally rectangular: rounded visual surfaces are
        /// rendered inside these frames, but the whole frame remains tappable at
        /// the screen edge.
        public static func fixedEdgeCommandRowFrames(
            itemCount: Int,
            rowFrame: CGRect,
            spacing: CGFloat,
            commandWidth: CGFloat
        ) -> [CGRect] {
            guard itemCount >= 2,
                  rowFrame.minX.isFinite,
                  rowFrame.minY.isFinite,
                  rowFrame.width.isFinite,
                  rowFrame.height.isFinite,
                  spacing >= 0,
                  rowFrame.width > 0,
                  rowFrame.height > 0,
                  commandWidth > 0 else { return [] }

            let gapCount = CGFloat(itemCount - 1)
            let widthAfterGaps = rowFrame.width - spacing * gapCount
            guard widthAfterGaps > 0 else { return [] }

            let edgeWidth = min(commandWidth, widthAfterGaps / 2)
            let middleCount = itemCount - 2
            let middleWidth = middleCount > 0
                ? max(0, (widthAfterGaps - edgeWidth * 2) / CGFloat(middleCount))
                : 0
            guard edgeWidth > 0,
                  middleCount == 0 || middleWidth > 0 else { return [] }

            var x = rowFrame.minX
            return (0..<itemCount).map { index in
                let width = index == 0 || index == itemCount - 1 ? edgeWidth : middleWidth
                let frame = CGRect(x: x, y: rowFrame.minY, width: width, height: rowFrame.height)
                x = frame.maxX + spacing
                return frame
            }
        }
    }

    public static let usesLegacyKeyGrid = false
    /// Native compact iPhone portrait height before width expansion scaling.
    public static let nativePortraitReferenceHeight: Double = 216
    /// Reference keyboard width on a standard compact iPhone (logical points).
    public static let nativePortraitReferenceWidth: Double = 390
    /// Inset glass content width at the reference width before full-bleed expansion.
    public static var insetSurfaceContentWidthAtReference: Double {
        nativePortraitReferenceWidth - horizontalPadding * 2
    }
    /// Small breathing-room extension above the native keyboard height.
    /// Keep the suggestion lane separate; this scales only the Liquid Glass surface.
    public static let surfaceHeightScale: Double = 1.0
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
        // Never shrink below the requested native fallback height.
        let resolvedHeight = isStable ? max(inputViewHeight, fallback) : fallback
        return SurfaceHeightResolution(
            height: resolvedHeight,
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
    public static let symbolBottomControlLaneHeight: Double = spacebarHeight
    public static let symbolBottomControlBottomInset: Double = 4
    public static let symbolBottomControlBudget: Double = symbolBottomControlLaneHeight + symbolBottomControlBottomInset
    public static let actionHitSize = CGSize(width: 88, height: 44)
    public static let bottomActionHitHeight: CGFloat = 44
    /// Inset for compact accessory faces and vertical bottom-bar breathing room.
    public static let commandVisualInset: CGFloat = 8
    /// Inner padding of the emoji category well inside the compact suggestion lane.
    public static let emojiCategoryHorizontalInset: CGFloat = 4
    public static let emojiCategoryVerticalInset: CGFloat = 2
    /// Letter and symbol key plates use the compact system-keyboard radius.
    public static let keyCornerRadius: CGFloat = 8
    /// ABC, 123, emoji, shift, delete, space, and return.
    public static let commandKeyCornerRadius: CGFloat = CommandKeyStyle.cornerRadius
    /// Pressed emoji cell. Letter keys use their own highlight radius.
    public static let emojiHighlightCornerRadius: CGFloat = 13
    /// Number-pad plates are much wider than letter keys, so the same 8pt
    /// radius reads as a square slab. This keeps them key-shaped.
    public static let numberPadKeyCornerRadius: CGFloat = 14
    /// Keeps the whole pad off the glass rim. Per-key insets made the keys short.
    public static let numberPadEdgeInset: CGFloat = 14
    public static let numberPadKeySpacing: CGFloat = 10
    public static let numberPadRowSpacing: CGFloat = 8
    /// Period fills its bottom-row target so its visible gaps match Space/Return.
    public static let periodKeyPlateWidth: CGFloat = CGFloat(controlSize)
    public static let utilityVisualSize: Double = 40
    /// Compact accessory face inside its hit target.
    public static func commandVisualSize(for hit: CGSize) -> CGSize {
        CGSize(
            width: max(0, hit.width - commandVisualInset),
            height: max(0, hit.height - commandVisualInset)
        )
    }
    public static let languageVisualWidth: Double = 46
    public static let rightRailControlCount: Int = 2
    public static let leftRailControlCount: Int = 3
    public static let minimumCenterAreaWidth: Double = 76
    public static let commandClusterSize: Double = controlSize
    /// The primary voice action is larger than utility controls so it remains
    /// easy to press without turning the keyboard into a key grid.
    public static let primaryControlSize: Double = 54
    /// On/off control at the top left of the dictation board.
    public static let dictationToggleWidth: Double = 58
    public static let dictationToggleHeight: Double = 28
    /// Bottom-row faces retain the 45pt character height inside a 54pt row lane.
    public static let bottomBarVisualHeight: Double = Double(letterKeyHeight)
    public static let spacebarHeight: Double = 54
    /// Circular compact faces fill their horizontal targets; the taller lane
    /// keeps vertical breathing room and the shared Space/Return alignment.
    public static let bottomBarControlWidth: Double = bottomBarVisualHeight
    public static let bottomBarSpacing: Double = 2
    public static func bottomBarVisualSize(for hit: CGSize) -> CGSize {
        CGSize(width: max(0, hit.width), height: bottomBarVisualHeight)
    }
    public static let railSpacing: Double = 4
    public static let horizontalPadding: Double = 8
    public static let controlEdgeInset: Double = 12
    public static let visibleControlGap: Double = 8
    /// Padding between the bottom chrome row and the glass surface edge (native keyboard breathing room).
    public static let chromeBottomInset: Double = 2
    /// Native portrait reference geometry shared by letter, number and symbol
    /// pages. Keeping these values in one place prevents an older compact grid
    /// from reappearing through a secondary layout path.
    public static let keyGridInset: CGFloat = 6.5
    public static let keySpacing: CGFloat = 6
    public static let keyRowSpacing: CGFloat = 11
    public static let letterKeyHeight: CGFloat = 45
    /// The letter keyboard keeps a compact action header above its four key rows.
    /// This leaves the dictation action visible without covering the top letter row.
    public static let letterKeyboardHeaderHeight: Double = 44
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
    /// Visual height of the compact suggestion / accessory lane.
    public static let suggestionLaneHeight: Double = 32
    /// Hit size of dismiss, paste, and dictation-board controls in that lane.
    public static let accessoryControlSize: Double = 48
    public static let accessoryEdgeInset: Double = 8
    /// Inset for circular suggestion-lane icons inside the 36pt lane.
    public static let suggestionLaneControlInset: CGFloat = 4
    /// The emoji category control floats above the bottom spacebar instead of
    /// competing with the keyboard host's suggestion lane.
    public static let floatingEmojiCategoryBarHeight: Double = 22
    public static let floatingEmojiCategoryBarGap: Double = 4
    /// Maximum visible width of the expanded category handle. The hit track is
    /// wider so the handle can follow a drag without enlarging the keyboard.
    public static let floatingEmojiCategoryBarMaxWidth: Double = 176
    /// Same as `railSpacing` so ABC, 123, and emoji delete share `boardDeleteFrame`.
    public static let chromeCommandRowGap: Double = railSpacing
    /// Extra height added to the native keyboard window. Larger than the visual
    /// lane so shrinking the bar enlarges the glass surface and the keys inside it.
    public static let keyboardWindowAccessoryHeight: Double = 44

    /// Horizontal growth from full-bleed width vs the previous inset glass surface at the same width.
    public static func horizontalExpansionScale(for availableWidth: Double) -> Double {
        let width = max(1, availableWidth)
        let railsFit = width >= Double(leftRailControlCount) * controlSize
            + actionHitSize.width + controlSize
        let centerMinimumFitsWithInset = width >= Double(leftRailControlCount) * controlSize
            + actionHitSize.width + controlSize + horizontalPadding * 2
        guard railsFit, centerMinimumFitsWithInset else { return 1 }
        let previousSurface = width - horizontalPadding * 2
        guard previousSurface > 0 else { return 1 }
        return width / previousSurface
    }

    /// Applies the same expansion factor to the reference portrait keyboard height.
    public static func scaledSurfaceHeight(for availableWidth: Double) -> Double {
        nativePortraitReferenceHeight
            * horizontalExpansionScale(for: availableWidth)
            * surfaceHeightScale
    }

    public struct ScaledKeyGeometry: Equatable {
        public let keyGridInset: CGFloat
        public let keySpacing: CGFloat
        public let keyRowSpacing: CGFloat
        public let letterKeyHeight: CGFloat
    }

    public static func scaledKeyGeometry(for availableWidth: Double) -> ScaledKeyGeometry {
        // Match the supplied native portrait reference: approximately 35pt
        // faces at 420pt width, 6pt horizontal and 11pt vertical gaps. Width
        // adapts through the row weights; spacing must not grow with it.
        // Keep compact landscape surfaces usable without stretching the keys.
        return ScaledKeyGeometry(
            keyGridInset: keyGridInset,
            keySpacing: keySpacing,
            keyRowSpacing: keyRowSpacing,
            letterKeyHeight: letterKeyHeight
        )
    }

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
        public let topAccessoryHeight: Double
        public let centerX: Double
        public let leftBottomCenterX: Double
        public let rightBottomCenterX: Double
        public let leftBottomCenterY: Double
        public let rightBottomCenterY: Double
        public let showsLanguageIndicator: Bool
        public let controlOrder: KeyboardAccessoryOrder

        public var surfaceInset: Double { horizontalInset }

        /// UIKit controls are mounted in the input view, while SwiftUI draws in
        /// a taller, bottom-anchored host. Keep their frames in the same space.
        public func inputFrame(_ hostedFrame: CGRect, inputViewHeight: CGFloat) -> CGRect {
            hostedFrame.offsetBy(dx: 0, dy: inputViewHeight - CGFloat(surfaceHeight))
        }

        public var surfaceFrame: CGRect {
            CGRect(x: horizontalInset, y: verticalPadding + topAccessoryHeight,
                   width: max(0, surfaceWidth - horizontalInset * 2),
                   height: max(0, surfaceHeight - verticalPadding * 2 - topAccessoryHeight))
        }

        public var bottomAuxiliaryControlFrame: CGRect {
            CGRect(x: surfaceFrame.minX, y: spaceLaneMinY,
                   width: surfaceFrame.width, height: spacebarHeight)
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

        /// The microphone keeps the same physical accessory slot on the emoji
        /// and symbols pages. `leftUtilityFrames.number` is the second slot for
        /// the default order and the first slot for the reversed order.
        public var auxiliaryMicrophoneFrame: CGRect {
            leftUtilityFrames.number
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

        public var accessoryMicrophoneFrame: CGRect {
            CGRect(x: max(0, surfaceWidth - 72), y: 0, width: 64,
                   height: VoiceOnlyKeyboardPolicy.suggestionLaneHeight)
        }

        public var accessoryMoreFrame: CGRect {
            CGRect(x: accessoryEdgeInset, y: 0, width: languageVisualWidth,
                   height: VoiceOnlyKeyboardPolicy.suggestionLaneHeight)
        }

        public var accessoryDismissFrame: CGRect {
            CGRect(
                x: max(0, surfaceWidth - accessoryEdgeInset - accessoryControlSize),
                y: 0,
                width: accessoryControlSize,
                height: VoiceOnlyKeyboardPolicy.suggestionLaneHeight
            )
        }

        /// Voice navigation occupies the trailing slot; More owns keyboard dismissal.
        public var accessoryDictationBoardFrame: CGRect {
            CGRect(
                x: accessoryDismissFrame.minX,
                y: 0,
                width: accessoryControlSize,
                height: VoiceOnlyKeyboardPolicy.suggestionLaneHeight
            )
        }

        public var accessoryServiceToggleFrame: CGRect {
            CGRect(x: max(0, accessoryDictationBoardFrame.minX - railSpacing - accessoryControlSize),
                   y: 0, width: accessoryControlSize, height: VoiceOnlyKeyboardPolicy.suggestionLaneHeight)
        }

        /// Emoji category scrubber in the suggestion lane, between the language
        /// chip and the service control. UIKit owns this hit target
        /// because keyboard hosts often drop SwiftUI taps in the top lane.
        public var accessoryEmojiCategoryFrame: CGRect {
            let minX = accessoryEdgeInset + languageVisualWidth + railSpacing
            let maxX = accessoryServiceToggleFrame.minX - railSpacing
            let width = max(0, maxX - minX)
            return CGRect(
                x: minX,
                y: 0,
                width: width,
                height: VoiceOnlyKeyboardPolicy.suggestionLaneHeight
            )
        }

        /// Invisible drag track immediately above the shared spacebar. It spans
        /// the inset surface so the compact moving handle can follow the full
        /// horizontal gesture without moving up into the emoji grid.
        public var floatingEmojiCategoryFrame: CGRect {
            let height = floatingEmojiCategoryBarHeight
            let space = chromeWideSpaceFrame
            let width = max(0, 2 * min(space.midX - surfaceFrame.minX - visibleControlGap,
                                      boardDeleteFrame.minX - visibleControlGap - space.midX))
            let bottomY = spaceLaneMinY - floatingEmojiCategoryBarGap
            guard width > 0, height > 0, bottomY - height >= surfaceFrame.minY else { return .zero }
            // The collapsed marker uses this track's centre, so centre the
            // track on Space and trim both ends equally to clear Delete.
            let frame = CGRect(
                x: space.midX - width / 2,
                y: bottomY - height,
                width: width,
                height: height
            )
            return surfaceFrame.intersection(frame)
        }

        /// The board's keyboard glyph occupies the top slot of the same left rail
        /// as Emoji and 123. Keeping all three frames on one x-axis makes the
        /// accessory controls stable when the board changes state.
        public var boardKeyboardFrame: CGRect {
            CGRect(
                x: surfaceFrame.minX + visibleControlGap,
                y: surfaceFrame.minY + visibleControlGap,
                width: controlSize,
                height: controlSize
            )
        }

        public var boardReturnFrame: CGRect { dismissFrame }

        /// Delete shares the grid renderer's inner gap and fixed outer edge.
        public var commandKeyVisualFrame: CGRect {
            let hit = boardDeleteFrame
            let width = max(0, hit.width - KeyGridPlacement.keySpacing)
            return CGRect(x: hit.maxX - width, y: hit.minY, width: width, height: hit.height)
        }

        public var commandKeyVisualSize: CGSize {
            commandKeyVisualFrame.size
        }

        public var boardDeleteFrame: CGRect {
            // Keep delete directly above the bottom-right Enter action. The
            // previous calculation derived its height from the whole surface,
            // which made the button grow to 52pt on the extended board and
            // overlap Enter.
            let width = max(0, surfaceFrame.width - horizontalPadding * 2) * 0.15
            let returnFrame = boardReturnFrame
            let height = VoiceOnlyKeyboardPolicy.bottomBarVisualHeight
            // Grow around the existing centre so the character rows stay put.
            let centerY = returnFrame.minY - railSpacing - bottomActionHitHeight / 2
            return CGRect(x: returnFrame.maxX - width,
                          y: centerY - height / 2,
                          width: width, height: height)
        }

        /// Explicit clipboard insertion sits beside the language menu and keeps
        /// its own stable hit target without changing the action-rectangle API.
        public var pasteFrame: CGRect {
            let frame = CGRect(
                x: languageFrame.maxX + visibleControlGap,
                y: languageFrame.minY,
                width: VoiceOnlyKeyboardPolicy.controlSize,
                height: VoiceOnlyKeyboardPolicy.controlSize
            )
            return surfaceFrame.contains(frame) ? frame : .zero
        }

        public var leftUtilityFrames: LeftUtilityFrames {
            guard leftRailWidth > 0 else { return LeftUtilityFrames(at: .zero, emoji: .zero, number: .zero) }
            let x = surfaceFrame.minX + visibleControlGap
            let size = CGSize(width: VoiceOnlyKeyboardPolicy.controlSize, height: VoiceOnlyKeyboardPolicy.controlSize)
            let emojiFrame = CGRect(x: x, y: spaceLaneMinY, width: size.width, height: spacebarHeight)
            let numberFrame = CGRect(x: x + size.width + railSpacing, y: spaceLaneMinY, width: size.width, height: spacebarHeight)
            return LeftUtilityFrames(
                at: CGRect(x: x, y: emojiFrame.minY - railSpacing - size.height, width: size.width, height: size.height),
                emoji: controlOrder == .emojiFirst ? emojiFrame : numberFrame,
                number: controlOrder == .emojiFirst ? numberFrame : emojiFrame
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
                          y: spaceLaneMinY,
                          width: rightRailWidth, height: spacebarHeight)
        }

        /// The letter keyboard keeps the back-to-dictation control immediately
        /// left of Enter in the native-style bottom row.
        public var letterDismissFrame: CGRect {
            guard rightRailWidth > 0 else { return .zero }
            let returnFrame = CGRect(
                x: surfaceFrame.maxX - visibleControlGap - actionHitSize.width,
                y: spaceLaneMinY,
                width: actionHitSize.width,
                height: spacebarHeight
            )
            let frame = CGRect(
                x: returnFrame.minX - bottomBarSpacing - controlSize,
                y: returnFrame.minY,
                width: controlSize,
                height: spacebarHeight
            )
            return surfaceFrame.contains(frame) ? frame : .zero
        }

        /// The letter keyboard's punctuation slot reuses the compact command
        /// slot immediately left of Return. Keeping it in the shared geometry
        /// contract prevents the period key from drifting when the surface
        /// height or accessory lane changes.
        public var letterPeriodFrame: CGRect {
            let right = chromeReturnFrame
            guard !right.isEmpty, leftRailWidth > 0 else { return .zero }
            return CGRect(x: right.minX - bottomBarSpacing - controlSize,
                          y: right.minY, width: controlSize, height: right.height)
        }

        /// Letter pages reserve the period slot without changing the auxiliary
        /// pages' wider spacebar.
        public var letterSpaceFrame: CGRect {
            let space = chromeWideSpaceFrame
            let period = letterPeriodFrame
            guard !space.isEmpty, !period.isEmpty else { return space }

            let frame = CGRect(
                x: space.minX,
                y: space.minY,
                width: max(0, period.minX - bottomBarSpacing - space.minX),
                height: space.height
            )
            guard frame.width >= 44, surfaceFrame.contains(frame) else { return space }
            return frame
        }

        public var letterReturnFrame: CGRect {
            guard !letterDismissFrame.isEmpty else { return .zero }
            let frame = CGRect(
                x: surfaceFrame.maxX - visibleControlGap - actionHitSize.width,
                y: spaceLaneMinY,
                width: actionHitSize.width,
                height: spacebarHeight
            )
            return surfaceFrame.contains(frame) ? frame : .zero
        }

        /// Unified native-style chrome on the voice board: 123, ABC, space, emoji, return.
        /// ABC and 123 pages reuse the compact 123/ABC slot, then emoji, space, and return.
        public var chromeNumbersFrame: CGRect {
            guard leftRailWidth > 0 else { return .zero }
            let frame = CGRect(
                x: surfaceFrame.minX + visibleControlGap,
                y: spaceLaneMinY,
                width: bottomBarControlWidth,
                height: spacebarHeight
            )
            return surfaceFrame.contains(frame) ? frame : .zero
        }

        public var chromeLettersFrame: CGRect {
            let numbers = chromeNumbersFrame
            guard !numbers.isEmpty else { return .zero }
            let frame = CGRect(
                x: numbers.maxX + bottomBarSpacing,
                y: numbers.minY,
                width: bottomBarControlWidth,
                height: spacebarHeight
            )
            return surfaceFrame.contains(frame) ? frame : .zero
        }

        /// Union of the two compact left slots. Voice keeps 123 and ABC there;
        /// ABC/123 pages put compact 123/ABC in the first slot and emoji in the second.
        public var chromeWideLettersFrame: CGRect {
            let numbers = chromeNumbersFrame
            let letters = chromeLettersFrame
            guard !numbers.isEmpty, !letters.isEmpty else { return letters }
            return numbers.union(letters)
        }

        /// Voice page places emoji immediately left of return.
        public var chromeEmojiFrame: CGRect {
            let right = chromeReturnFrame
            guard !right.isEmpty, leftRailWidth > 0 else { return .zero }
            let frame = CGRect(
                x: right.minX - bottomBarSpacing - bottomBarControlWidth,
                y: spaceLaneMinY,
                width: bottomBarControlWidth,
                height: spacebarHeight
            )
            return surfaceFrame.contains(frame) ? frame : .zero
        }

        public var chromeReturnFrame: CGRect { letterReturnFrame.isEmpty ? dismissFrame : letterReturnFrame }

        public var chromeSpaceFrame: CGRect {
            let left = chromeLettersFrame
            let right = chromeEmojiFrame
            guard !left.isEmpty, !right.isEmpty else { return .zero }
            let x = left.maxX + bottomBarSpacing
            let width = right.minX - bottomBarSpacing - x
            guard width >= 44 else { return .zero }
            let frame = CGRect(x: x, y: spaceLaneMinY, width: width, height: spacebarHeight)
            return surfaceFrame.contains(frame) ? frame : .zero
        }

        /// ABC/123 and emoji pages hide the right-of-space emoji control and give
        /// that width to the spacebar.
        public var chromeWideSpaceFrame: CGRect {
            let space = chromeSpaceFrame
            let emoji = chromeEmojiFrame
            guard !space.isEmpty, !emoji.isEmpty else { return space }
            return CGRect(
                x: space.minX,
                y: space.minY,
                width: emoji.maxX - space.minX,
                height: space.height
            )
        }

        /// The symbols page puts its return-to-dictation control between the
        /// spacebar and the wide Enter key, matching the ABC page's right-side
        /// control slot.
        public var symbolDictationFrame: CGRect {
            guard rightRailWidth > 0 else { return .zero }
            let frame = CGRect(
                x: dismissFrame.minX - railSpacing - controlSize,
                y: dismissFrame.minY,
                width: controlSize,
                height: spacebarHeight
            )
            return surfaceFrame.contains(frame) ? frame : .zero
        }

        /// Reserve the symbol-page dictation slot without changing the shared
        /// voice/letter spacebar geometry.
        public var symbolSpaceFrame: CGRect {
            let voiceFrame = symbolDictationFrame
            guard !spaceFrame.isEmpty, !voiceFrame.isEmpty else { return spaceFrame }
            let maxX = voiceFrame.minX - railSpacing
            let frame = CGRect(
                x: spaceFrame.minX,
                y: spaceFrame.minY,
                width: max(0, maxX - spaceFrame.minX),
                height: spaceFrame.height
            )
            guard frame.width >= 44, surfaceFrame.contains(frame) else { return spaceFrame }
            return frame
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

        /// Full-width UIKit letter grid, below the compact dictation header.
        public var letterKeyboardFrame: CGRect {
            let frame = CGRect(
                x: surfaceFrame.minX,
                y: surfaceFrame.minY + letterKeyboardHeaderHeight,
                width: surfaceFrame.width,
                height: max(0, surfaceFrame.height - letterKeyboardHeaderHeight)
            )
            return surfaceFrame.contains(frame) ? frame : .zero
        }

        /// Bottom-bar Y shared with emoji / 123 / dismiss so the voice space key
        /// lines up with the auxiliary pages.
        var spaceLaneMinY: Double {
            surfaceFrame.maxY - VoiceOnlyKeyboardPolicy.chromeBottomInset - VoiceOnlyKeyboardPolicy.spacebarHeight
        }

        /// Origin of the auxiliary SwiftUI bottom bar inside the surface.
        public var chromeBottomBarOriginY: Double { spaceLaneMinY }

        /// The hold-to-dictate capsule keeps one frame while its content changes.
        /// It is vertically centered in the board above the shared bottom space bar.
        public var dictateFrame: CGRect {
            guard surfaceFrame.height >= VoiceOnlyKeyboardPolicy.primaryControlSize + visibleControlGap else { return .zero }
            let width = VoiceOnlyKeyboardPolicy.primaryControlWidth(
                availableWidth: surfaceWidth,
                centerAreaWidth: centerAreaWidth
            )
            let clusterHeight = VoiceOnlyKeyboardPolicy.primaryControlSize
                + visibleControlGap
                + VoiceOnlyKeyboardPolicy.spacebarHeight
            guard surfaceFrame.height >= clusterHeight else { return .zero }
            let available = spaceLaneMinY - surfaceFrame.minY
            guard available >= VoiceOnlyKeyboardPolicy.primaryControlSize else { return .zero }
            return CGRect(
                x: centerX - width / 2,
                y: surfaceFrame.minY + (available - VoiceOnlyKeyboardPolicy.primaryControlSize) / 2,
                width: width,
                height: VoiceOnlyKeyboardPolicy.primaryControlSize
            )
        }

        /// Power mirrors More in the top-right corner with a full touch target.
        public var dictationServiceToggleFrame: CGRect {
            let more = dictationMoreFrame
            let frame = CGRect(
                x: surfaceWidth - accessoryEdgeInset - more.width,
                y: more.minY,
                width: more.width,
                height: more.height
            )
            guard CGRect(x: 0, y: 0, width: surfaceWidth, height: surfaceHeight).contains(frame),
                  !frame.intersects(dictateFrame), !frame.intersects(boardDeleteFrame),
                  !frame.intersects(chromeReturnFrame) else { return .zero }
            return frame
        }

        /// Keep More top-left with its whole tap target inside the input view.
        public var dictationMoreFrame: CGRect {
            let frame = CGRect(x: accessoryEdgeInset, y: verticalPadding,
                               width: languageVisualWidth, height: 44)
            guard CGRect(x: 0, y: 0, width: surfaceWidth, height: surfaceHeight).contains(frame),
                  !frame.intersects(dictateFrame),
                  !frame.intersects(boardDeleteFrame) else { return accessoryMoreFrame }
            return frame
        }

        public var spaceFrame: CGRect {
            let clusterHeight = VoiceOnlyKeyboardPolicy.primaryControlSize
                + visibleControlGap
                + VoiceOnlyKeyboardPolicy.spacebarHeight
            guard surfaceFrame.height >= clusterHeight else { return .zero }
            if leftRailWidth > 0 && rightRailWidth > 0 {
                return chromeSpaceFrame
            }
            let width = VoiceOnlyKeyboardPolicy.primaryControlWidth(
                availableWidth: surfaceWidth,
                centerAreaWidth: centerAreaWidth
            )
            let frame = CGRect(
                x: centerX - width / 2,
                y: spaceLaneMinY,
                width: width,
                height: VoiceOnlyKeyboardPolicy.spacebarHeight
            )
            guard surfaceFrame.contains(frame) else { return .zero }
            return frame
        }

        /// The failure message gets its own non-interactive lane below the mic
        /// and above the shared bottom space bar.
        public var dictationErrorFrame: CGRect {
            let mic = dictateFrame
            guard !mic.isEmpty else { return .zero }

            let frame = CGRect(
                x: micCenterArea.minX,
                y: mic.maxY + visibleControlGap,
                width: micCenterArea.width,
                height: statusHeight
            )
            guard surfaceFrame.contains(frame), !frame.intersects(mic),
                  spaceFrame.isEmpty || !frame.intersects(spaceFrame) else { return .zero }
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
            let spaceRects = spaceFrame.isEmpty ? [] : [spaceFrame]
            return utilities + commandRects + (rightRailWidth > 0 ? [dismissFrame] : []) + [dictateFrame] + spaceRects
        }
    }

    public static func layout(
        for availableWidth: Double,
        surfaceHeight: Double = VoiceOnlyKeyboardPolicy.surfaceHeight,
        controlOrder: KeyboardAccessoryOrder = .emojiFirst,
        topAccessoryHeight: Double = 0,
        compactChrome: Bool = false
    ) -> Layout {
        let resolvedSurfaceHeight = max(0, surfaceHeight)
        let leftWidth = CGFloat(controlSize * Double(leftRailControlCount) + railSpacing * Double(leftRailControlCount - 1))
        let rightWidth = actionHitSize.width
        // Compact keyboards use a single bottom row, not the legacy two-row rail.
        let minimumRailHeight = compactChrome
            ? verticalPadding * 2 + primaryControlSize + visibleControlGap + spacebarHeight
            : verticalPadding * 2 + visibleControlGap * 2 + rightRailHeight + spacebarHeight
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
            dismissTop: resolvedSurfaceHeight - verticalPadding - chromeBottomInset - spacebarHeight,
            dismissBottom: resolvedSurfaceHeight - verticalPadding - chromeBottomInset,
            contentHeight: resolvedSurfaceHeight,
            surfaceHeight: resolvedSurfaceHeight,
            topAccessoryHeight: max(0, topAccessoryHeight),
            centerX: horizontalInset + (availableWidth - horizontalInset * 2) / 2,
            leftBottomCenterX: resolvedLeftRailWidth > 0
                ? horizontalInset + visibleControlGap + controlSize / 2
                : 0,
            rightBottomCenterX: railWidth > 0
                ? horizontalInset + (availableWidth - horizontalInset * 2)
                    - visibleControlGap - railWidth / 2
                : 0,
            leftBottomCenterY: hasRails
                ? resolvedSurfaceHeight - verticalPadding - chromeBottomInset - spacebarHeight / 2
                : 0,
            rightBottomCenterY: hasRails
                ? resolvedSurfaceHeight - verticalPadding - chromeBottomInset - spacebarHeight / 2
                : 0,
            showsLanguageIndicator: hasRails,
            controlOrder: controlOrder
        )
    }

    private static func horizontalInset(for availableWidth: Double) -> Double {
        let railsFit = availableWidth >= Double(leftRailControlCount) * controlSize
            + actionHitSize.width + controlSize
        guard railsFit else { return min(horizontalPadding, availableWidth / 2) }

        return 0
    }
}
