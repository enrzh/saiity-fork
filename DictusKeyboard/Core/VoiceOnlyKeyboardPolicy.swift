import Foundation
import CoreGraphics
import UIKit

/// Central geometry and layout authority for the voice-only keyboard.
///
/// All dimensions, frames, scaling, and tiling are defined here so that both
/// the SwiftUI chrome and the UIKit touch surfaces derive from the same source.
/// Changing a value here updates the entire keyboard consistently.
public enum VoiceOnlyKeyboardPolicy {
    // MARK: - Constants

    /// Visual control size (mic capsule, 123/ABC buttons).
    public static let controlSize: CGFloat = 44
    /// Primary control size (dictate capsule on voice board).
    public static let primaryControlSize: CGFloat = 54
    /// Height of the bottom action bar (space, delete, return, etc.).
    public static let bottomActionHitHeight: CGFloat = 44
    /// Height of the suggestion/accessory lane at the top.
    public static let suggestionLaneHeight: CGFloat = 36
    /// Gap between visible controls on the voice board.
    public static let visibleControlGap: CGFloat = 8
    /// Padding between bottom chrome row and glass surface edge.
    public static let chromeBottomInset: CGFloat = 6
    /// Horizontal inset for the key grid on the letter page.
    public static let keyGridInset: CGFloat = 6.5
    /// Horizontal gap between keys in a row.
    public static let keySpacing: CGFloat = 6
    /// Vertical gap between key rows.
    public static let keyRowSpacing: CGFloat = 11
    /// Height of a letter key (fixed; only row count/spacing adapts).
    public static let letterKeyHeight: CGFloat = 45
    /// Height of the compact action header above the letter grid.
    public static let letterKeyboardHeaderHeight: Double = 44
    /// Corner radius for letter/number/symbol keys.
    public static let keyCornerRadius: CGFloat = 8
    /// Corner radius for command keys (shift, delete, return, 123, ABC, emoji).
    public static let commandKeyCornerRadius: CGFloat = 18
    /// Maximum number of key rows on the letter page (including optional digit row).
    public static let maxKeyRows: Int = 5
    /// Maximum number of key rows on the symbol/number pages.
    public static let maxSymbolRows: Int = 4
    /// Rail spacing between left/right utility buttons.
    public static let railSpacing: CGFloat = 4
    /// Language indicator visual width in the accessory lane.
    public static let languageVisualWidth: CGFloat = 52
    /// Accessory lane edge inset.
    public static let accessoryEdgeInset: CGFloat = 12
    /// Dictation toggle width/height (bare UISwitch).
    public static let dictationToggleWidth: CGFloat = 52
    public static let dictationToggleHeight: CGFloat = 32
    /// Visual inset from hit frame to glass plate for command keys.
    public static let commandVisualInset: CGFloat = 2

    // MARK: - Derived Visual Sizes

    /// Visual size of a command key plate (inset inside its hit frame).
    public static let commandKeyVisualSize: CGSize = CGSize(
        width: controlSize - 2 * commandVisualInset,
        height: bottomActionHitHeight - 2 * commandVisualInset
    )

    /// Visual size of the dictate capsule on the voice board.
    public static let primaryControlVisualSize: CGSize = CGSize(
        width: primaryControlSize - 2 * commandVisualInset,
        height: primaryControlSize - 2 * commandVisualInset
    )

    /// Returns the visual plate size for a command key given its hit frame.
    public static func commandKeyVisualSize(for hit: CGSize) -> CGSize {
        CGSize(
            width: max(0, hit.width - 2 * commandVisualInset),
            height: max(0, hit.height - 2 * commandVisualInset)
        )
    }

    // MARK: - Scaling

    /// Reference keyboard width (iPhone 14 portrait).
    private static let referenceWidth: CGFloat = 390
    /// Reference surface height (letters page).
    private static let referenceSurfaceHeight: CGFloat = 216

    /// Horizontal expansion scale: full-bleed on wide screens, inset on narrow.
    public static func horizontalExpansionScale(for width: CGFloat) -> CGFloat {
        min(max(width / referenceWidth, 0.85), 1.15)
    }

    /// Scales the reference surface height to the current width.
    public static func scaledSurfaceHeight(for width: CGFloat) -> CGFloat {
        referenceSurfaceHeight * horizontalExpansionScale(for: width)
    }

    /// Key geometry that stays fixed; only row count and spacing adapt.
    public struct ScaledKeyGeometry {
        public let keyGridInset: CGFloat
        public let keySpacing: CGFloat
        public let keyRowSpacing: CGFloat
        public let letterKeyHeight: CGFloat

        public init(
            keyGridInset: CGFloat = keyGridInset,
            keySpacing: CGFloat = keySpacing,
            keyRowSpacing: CGFloat = keyRowSpacing,
            letterKeyHeight: CGFloat = letterKeyHeight
        ) {
            self.keyGridInset = keyGridInset
            self.keySpacing = keySpacing
            self.keyRowSpacing = keyRowSpacing
            self.letterKeyHeight = letterKeyHeight
        }
    }

    /// Scaled key geometry for a given keyboard width.
    public static func scaledKeyGeometry(for width: Double) -> ScaledKeyGeometry {
        let scale = horizontalExpansionScale(for: CGFloat(width))
        return ScaledKeyGeometry(
            keyGridInset: keyGridInset * scale,
            keySpacing: keySpacing * scale,
            keyRowSpacing: keyRowSpacing * scale,
            letterKeyHeight: letterKeyHeight
        )
    }

    // MARK: - Symbol Grid Geometry

    public enum SymbolGrid {
        /// Height of the last (command) row, pinned to the bottom of the grid.
        public static func letterAlignedLastRowHeight(
            in gridHeight: CGFloat,
            rowSpacing: CGFloat
        ) -> CGFloat {
            let upperRows = maxKeyRows - 1
            let upperSpacing = rowSpacing * CGFloat(max(0, upperRows - 1))
            let upperHeight = letterKeyHeight * CGFloat(upperRows)
            let available = gridHeight - upperHeight - upperSpacing - rowSpacing
            return max(letterKeyHeight, available)
        }

        /// Solves frames for a weighted grid with a pinned last row.
        ///
        /// - Parameters:
        ///   - weights: Per-key width weights (1.0 = standard letter key).
        ///   - size: Total grid size.
        ///   - spacing: Horizontal spacing between keys.
        ///   - inset: Horizontal inset from grid edges.
        ///   - rowSpacing: Vertical spacing between rows.
        ///   - lastRowHeight: Fixed height of the last (command) row.
        ///   - maxRowHeight: Cap on upper row height.
        /// - Returns: Rectangles for each key, in the grid's coordinate space.
        public static func framesWithPinnedLastRow(
            for weights: [[CGFloat]],
            in size: CGSize,
            spacing: CGFloat,
            inset: CGFloat,
            rowSpacing: CGFloat,
            lastRowHeight: CGFloat,
            maxRowHeight: CGFloat? = nil
        ) -> [[CGRect]] {
            guard !weights.isEmpty else { return [] }
            let resolvedRowSpacing = rowSpacing
            let pinnedHeight = min(max(1, lastRowHeight), max(1, size.height))
            if weights.count == 1 {
                let frames = frames(
                    for: weights,
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

            let upperRows = Array(weights.dropLast())
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
                for: [weights.last!],
                in: CGSize(width: size.width, height: pinnedHeight),
                spacing: spacing,
                inset: inset,
                rowSpacing: 0,
                maxRowHeight: nil
            ).map { row in
                row.map { CGRect(x: $0.minX, y: lastY, width: $0.width, height: pinnedHeight) }
            }
            return upperFrames + lastFrames
        }

        /// Standard row frames without pinning.
        public static func frames(
            for weights: [[CGFloat]],
            in size: CGSize,
            spacing: CGFloat,
            inset: CGFloat,
            rowSpacing: CGFloat,
            maxRowHeight: CGFloat? = nil
        ) -> [[CGRect]] {
            guard !weights.isEmpty else { return [] }
            let rowCount = weights.count
            let availableHeight = size.height - spacing * CGFloat(rowCount - 1)
            let naturalHeight = availableHeight / CGFloat(rowCount)
            let rowHeight = min(naturalHeight, maxRowHeight ?? naturalHeight)
            let totalHeight = rowHeight * CGFloat(rowCount) + spacing * CGFloat(rowCount - 1)
            let originY = (size.height - totalHeight) / 2

            return weights.enumerated().map { rowIndex, rowWeights in
                let totalWeight = rowWeights.reduce(0, +)
                let availableWidth = size.width - inset * 2 - spacing * CGFloat(max(0, rowWeights.count - 1))
                var x = inset
                let y = originY + (rowHeight + spacing) * CGFloat(rowIndex)
                return rowWeights.enumerated().map { _, weight in
                    let width = availableWidth * weight / totalWeight
                    let frame = CGRect(x: x, y: y, width: width, height: rowHeight)
                    x += width + spacing
                    return frame
                }
            }
        }

        /// Pins the last (command) row edge-to-edge so shift and delete keep
        /// the same frames as every other surface.
        public static func fixedEdgeCommandRowFrames(
            itemCount: Int,
            rowFrame: CGRect,
            spacing: CGFloat,
            commandWidth: CGFloat
        ) -> [CGRect] {
            guard itemCount >= 2 else { return [] }
            let commandCount = 2 // shift + delete
            let letterCount = max(0, itemCount - commandCount)
            let letterWidth = max(0, (rowFrame.width - spacing * CGFloat(itemCount - 1) - commandWidth * CGFloat(commandCount)) / CGFloat(max(1, letterCount)))
            var frames: [CGRect] = []
            var x = rowFrame.minX
            if letterCount > 0 {
                for _ in 0..<letterCount {
                    frames.append(CGRect(x: x, y: rowFrame.minY, width: letterWidth, height: rowFrame.height))
                    x += letterWidth + spacing
                }
            }
            frames.append(CGRect(x: x, y: rowFrame.minY, width: commandWidth, height: rowFrame.height))
            x += commandWidth + spacing
            frames.append(CGRect(x: x, y: rowFrame.minY, width: commandWidth, height: rowFrame.height))
            return frames
        }
    }

    // MARK: - Layout

    public struct Layout {
        public let surfaceFrame: CGRect
        public let leftRailWidth: CGFloat
        public let rightRailWidth: CGFloat
        public let dictateFrame: CGRect
        public let spaceFrame: CGRect
        public let chromeNumbersFrame: CGRect
        public let chromeLettersFrame: CGRect
        public let chromeEmojiFrame: CGRect
        public let chromeReturnFrame: CGRect
        public let chromeSpaceFrame: CGRect
        public let chromeWideSpaceFrame: CGRect
        public let boardDeleteFrame: CGRect
        public let accessoryDictationBoardFrame: CGRect
        public let accessoryDismissFrame: CGRect
        public let accessoryEmojiCategoryFrame: CGRect
        public let floatingEmojiCategoryFrame: CGRect
        public let pasteFrame: CGRect
        public let dictationServiceToggleFrame: CGRect
        public let letterSpaceFrame: CGRect
        public let letterReturnFrame: CGRect
        public let letterPeriodFrame: CGRect
        public let dictationErrorFrame: CGRect
        public let commandKeyVisualSize: CGSize
        public let primaryControlVisualSize: CGSize
        public let suggestionLaneHeight: CGFloat

        public init(
            surfaceFrame: CGRect,
            leftRailWidth: CGFloat,
            rightRailWidth: CGFloat,
            dictateFrame: CGRect,
            spaceFrame: CGRect,
            chromeNumbersFrame: CGRect,
            chromeLettersFrame: CGRect,
            chromeEmojiFrame: CGRect,
            chromeReturnFrame: CGRect,
            chromeSpaceFrame: CGRect,
            chromeWideSpaceFrame: CGRect,
            boardDeleteFrame: CGRect,
            accessoryDictationBoardFrame: CGRect,
            accessoryDismissFrame: CGRect,
            accessoryEmojiCategoryFrame: CGRect,
            floatingEmojiCategoryFrame: CGRect,
            pasteFrame: CGRect,
            dictationServiceToggleFrame: CGRect,
            letterSpaceFrame: CGRect,
            letterReturnFrame: CGRect,
            letterPeriodFrame: CGRect,
            dictationErrorFrame: CGRect,
            commandKeyVisualSize: CGSize,
            primaryControlVisualSize: CGSize,
            suggestionLaneHeight: CGFloat
        ) {
            self.surfaceFrame = surfaceFrame
            self.leftRailWidth = leftRailWidth
            self.rightRailWidth = rightRailWidth
            self.dictateFrame = dictateFrame
            self.spaceFrame = spaceFrame
            self.chromeNumbersFrame = chromeNumbersFrame
            self.chromeLettersFrame = chromeLettersFrame
            self.chromeEmojiFrame = chromeEmojiFrame
            self.chromeReturnFrame = chromeReturnFrame
            self.chromeSpaceFrame = chromeSpaceFrame
            self.chromeWideSpaceFrame = chromeWideSpaceFrame
            self.boardDeleteFrame = boardDeleteFrame
            self.accessoryDictationBoardFrame = accessoryDictationBoardFrame
            self.accessoryDismissFrame = accessoryDismissFrame
            self.accessoryEmojiCategoryFrame = accessoryEmojiCategoryFrame
            self.floatingEmojiCategoryFrame = floatingEmojiCategoryFrame
            self.pasteFrame = pasteFrame
            self.dictationServiceToggleFrame = dictationServiceToggleFrame
            self.letterSpaceFrame = letterSpaceFrame
            self.letterReturnFrame = letterReturnFrame
            self.letterPeriodFrame = letterPeriodFrame
            self.dictationErrorFrame = dictationErrorFrame
            self.commandKeyVisualSize = commandKeyVisualSize
            self.primaryControlVisualSize = primaryControlVisualSize
            self.suggestionLaneHeight = suggestionLaneHeight
        }
    }

    public static func layout(
        for width: Double,
        surfaceHeight: Double,
        controlOrder: KeyboardAccessoryOrder = .emojiFirst,
        topAccessoryHeight: Double = 36
    ) -> Layout {
        let w = CGFloat(width)
        let h = CGFloat(surfaceHeight)
        let suggestionLaneHeight = CGFloat(topAccessoryHeight)
        let availableHeight = h - suggestionLaneHeight
        let surfaceFrame = CGRect(x: 0, y: suggestionLaneHeight, width: w, height: availableHeight)

        let geometry = scaledKeyGeometry(for: width)
        let centerX = w / 2

        // --- Dictate capsule ---
        let primaryWidth = primaryControlWidth(availableWidth: w, centerAreaWidth: w * 0.6)
        let primaryHeight = primaryControlSize
        let primaryY = (availableHeight - primaryHeight - visibleControlGap - bottomActionHitHeight) / 2 + suggestionLaneHeight
        let dictateFrame = CGRect(x: centerX - primaryWidth / 2, y: primaryY, width: primaryWidth, height: primaryHeight)

        // --- Bottom bar ---
        let bottomY = h - chromeBottomInset - bottomActionHitHeight
        let leftInset = accessoryEdgeInset
        let rightInset = w - accessoryEdgeInset
        let dictationBoardWidth = primaryWidth // reuse dictate width
        let dictationBoardFrame = CGRect(
            x: centerX - dictationBoardWidth / 2,
            y: bottomY,
            width: dictationBoardWidth,
            height: bottomActionHitHeight
        )
        let dismissFrame = CGRect(
            x: rightInset - commandKeyVisualSize.width,
            y: bottomY,
            width: commandKeyVisualSize.width,
            height: bottomActionHitHeight
        )

        // --- Space / Return / Emoji ---
        let returnWidth = commandKeyVisualSize.width
        let returnFrame = CGRect(
            x: rightInset - returnWidth,
            y: bottomY,
            width: returnWidth,
            height: bottomActionHitHeight
        )
        let emojiFrame = CGRect(
            x: leftInset,
            y: bottomY,
            width: commandKeyVisualSize.width,
            height: bottomActionHitHeight
        )
        let numbersFrame = CGRect(
            x: leftInset + commandKeyVisualSize.width + railSpacing,
            y: bottomY,
            width: commandKeyVisualSize.width,
            height: bottomActionHitHeight
        )
        let spaceX = emojiFrame.maxX + railSpacing
        let spaceWidth = max(44, returnFrame.minX - railSpacing - spaceX)
        let spaceFrame = CGRect(x: spaceX, y: bottomY, width: spaceWidth, height: bottomActionHitHeight)

        // --- Delete (shared across all pages) ---
        let deleteFrame = CGRect(
            x: leftInset,
            y: bottomY - railSpacing - commandKeyVisualSize.height,
            width: commandKeyVisualSize.width,
            height: commandKeyVisualSize.height
        )

        // --- 123 / ABC toggle ---
        let chromeNumbersFrame = CGRect(
            x: leftInset,
            y: bottomY - railSpacing * 2 - commandKeyVisualSize.height * 2,
            width: commandKeyVisualSize.width,
            height: commandKeyVisualSize.height
        )
        let chromeLettersFrame = CGRect(
            x: numbersFrame.maxX + railSpacing,
            y: chromeNumbersFrame.minY,
            width: commandKeyVisualSize.width,
            height: commandKeyVisualSize.height
        )
        let chromeEmojiFrame = CGRect(
            x: returnFrame.minX - railSpacing - commandKeyVisualSize.width,
            y: bottomY,
            width: commandKeyVisualSize.width,
            height: bottomActionHitHeight
        )
        let chromeReturnFrame = returnFrame
        let chromeSpaceFrame = spaceFrame
        let chromeWideSpaceFrame = CGRect(
            x: spaceFrame.minX,
            y: spaceFrame.minY,
            width: emojiFrame.maxX - spaceFrame.minX,
            height: spaceFrame.height
        )

        // --- Paste / Service Toggle ---
        let pasteWidth = languageVisualWidth
        let pasteFrame = CGRect(
            x: rightInset - pasteWidth,
            y: suggestionLaneHeight,
            width: pasteWidth,
            height: suggestionLaneHeight
        )
        let toggleFrame = CGRect(
            x: leftInset + visibleControlGap + commandVisualInset,
            y: suggestionLaneHeight + visibleControlGap + commandVisualInset,
            width: dictationToggleWidth,
            height: dictationToggleHeight
        )

        // --- Letter page specific ---
        let letterSpaceFrame = spaceFrame
        let letterReturnFrame = returnFrame
        let letterPeriodFrame = CGRect(
            x: rightInset - commandKeyVisualSize.width * 2 - railSpacing,
            y: bottomY,
            width: commandKeyVisualSize.width,
            height: bottomActionHitHeight
        )

        // --- Error lane ---
        let errorFrame = CGRect(
            x: 0,
            y: dictateFrame.maxY + visibleControlGap,
            width: w,
            height: 44
        )

        // --- Emoji category scrubber ---
        let categoryBarHeight: CGFloat = 36
        let categoryBarY = bottomY - categoryBarHeight - railSpacing
        let floatingCategoryFrame = CGRect(
            x: leftInset,
            y: categoryBarY,
            width: w - leftInset * 2,
            height: categoryBarHeight
        )

        // --- Accessory lane frames ---
        let accessoryDictationBoardFrame = dictationBoardFrame
        let accessoryDismissFrame = dismissFrame
        let accessoryEmojiCategoryFrame = floatingCategoryFrame

        // --- Rail widths ---
        let leftRailWidth = controlOrder == .emojiFirst ? 0 : commandKeyVisualSize.width * 2 + railSpacing
        let rightRailWidth = commandKeyVisualSize.width * 2 + railSpacing

        return Layout(
            surfaceFrame: surfaceFrame,
            leftRailWidth: leftRailWidth,
            rightRailWidth: rightRailWidth,
            dictateFrame: dictateFrame,
            spaceFrame: spaceFrame,
            chromeNumbersFrame: chromeNumbersFrame,
            chromeLettersFrame: chromeLettersFrame,
            chromeEmojiFrame: chromeEmojiFrame,
            chromeReturnFrame: chromeReturnFrame,
            chromeSpaceFrame: chromeSpaceFrame,
            chromeWideSpaceFrame: chromeWideSpaceFrame,
            boardDeleteFrame: deleteFrame,
            accessoryDictationBoardFrame: accessoryDictationBoardFrame,
            accessoryDismissFrame: accessoryDismissFrame,
            accessoryEmojiCategoryFrame: accessoryEmojiCategoryFrame,
            floatingEmojiCategoryFrame: floatingCategoryFrame,
            pasteFrame: pasteFrame,
            dictationServiceToggleFrame: toggleFrame,
            letterSpaceFrame: letterSpaceFrame,
            letterReturnFrame: letterReturnFrame,
            letterPeriodFrame: letterPeriodFrame,
            dictationErrorFrame: errorFrame,
            commandKeyVisualSize: commandKeyVisualSize,
            primaryControlVisualSize: primaryControlVisualSize,
            suggestionLaneHeight: suggestionLaneHeight
        )
    }

    private static func primaryControlWidth(availableWidth: CGFloat, centerAreaWidth: CGFloat) -> CGFloat {
        min(availableWidth * 0.7, centerAreaWidth)
    }
}

// MARK: - Layout Persistence Keys

public enum KeyboardAccessoryOrder: String, Codable, CaseIterable, Sendable {
    case emojiFirst
    case numberFirst

    public static var current: KeyboardAccessoryOrder {
        let defaults = UserDefaults(suiteName: "group.de.aiity.saiity.ios.beta")
        if let raw = defaults?.string(forKey: "dictus.keyboardAccessoryOrder"),
           let order = KeyboardAccessoryOrder(rawValue: raw) {
            return order
        }
        return .emojiFirst
    }
}