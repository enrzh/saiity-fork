// DictusCore/Sources/DictusCore/NextKeyGridPlacement.swift
//
// Turns a page of keys into rectangles. This is the only place in the new keyboard
// that decides where a key is, and the only place that decides how large its
// pressable area is.
//
// Two properties are non-negotiable, and both are tested:
//
//  1. A target never shrinks below the plate the user can see. A key you can see
//     is always a key you can press.
//  2. No point inside the grid is dead. The targets tile the whole grid, edge to
//     edge, so there is no band of keyboard that swallows a tap.
//
// The second one is the lesson from giellakbd-ios, this project's own Apache-2.0
// ancestor: its `UICollectionView` uses zero inter-item and line spacing, so every
// cell is contiguous and every point lands on a key. Deriving targets from the
// plates instead — "plate plus half of each gap" — leaves the outer margin outside
// every target, and those margins then need a separate rescue path. We had that
// bug and it cost four builds.

import CoreGraphics
import Foundation

public enum KeyGridPlacement {

    /// Spacing between plates, and the margin at the left and right edges.
    public static let keySpacing: CGFloat = 6
    /// Spacing between rows of plates.
    public static let rowSpacing: CGFloat = 11
    /// Margin between the grid and the left/right edges of its container.
    public static let edgeInset: CGFloat = 6.5
    /// Height of a letter plate. Rows are allowed to be shorter when the container
    /// is cramped; this is the height they get when there is room.
    public static let preferredRowHeight: CGFloat = 45
    public static let keyCornerRadius: CGFloat = 8
    public static let commandCornerRadius: CGFloat = 18

    /// Solves `page` for a container of `size`.
    ///
    /// The last row is treated specially: it holds shift and delete, which are
    /// pinned to the edges so they occupy the same place on every page. A keyboard
    /// where delete shifts sideways when you switch pages is disorienting in a way
    /// that is hard to articulate and easy to feel.
    public static func solve(_ page: KeyGridPage, in size: CGSize) -> KeyGridLayout {
        var layout = KeyGridLayout()
        guard !page.isEmpty, isUsable(size, for: page) else { return layout }

        // Every row is the same height and the block is bottom-aligned.
        //
        // The first version gave the last row "whatever height was left over", which
        // on a 216pt keyboard with three rows handed it 194pt and squeezed the
        // letter rows into 1pt each. The visible symptom would have been a keyboard
        // that drew three hairlines and ignored 87% of every tap.
        let rowCount = CGFloat(page.rows.count)
        let gaps = rowSpacing * (rowCount - 1)
        let rowHeight = max(1, min((size.height - gaps) / rowCount, preferredRowHeight))
        let blockHeight = rowHeight * rowCount + gaps
        let originY = max(0, size.height - blockHeight)

        var placed: [PlacedKey] = []
        for (rowIndex, row) in page.rows.enumerated() {
            guard !row.isEmpty else { continue }
            let rowTop = originY + CGFloat(rowIndex) * (rowHeight + rowSpacing)
            let plates = (rowIndex == page.rows.count - 1 && page.pinnedLastRow)
                ? edgePinnedPlates(for: row, width: size.width, top: rowTop, height: rowHeight)
                : weightedPlates(for: row, width: size.width, top: rowTop, height: rowHeight)
            for (column, plate) in plates.enumerated() {
                placed.append(
                    PlacedKey(key: row[column], row: rowIndex, column: column,
                              plate: plate, target: .null)
                )
            }
        }

        // Targets are assigned after every plate is known, because a seam between
        // two keys depends on both of them.
        layout.placed = withTargets(placed, in: CGRect(origin: .zero, size: size))
        layout.rows = Array(repeating: [], count: page.rows.count)
        for item in layout.placed where item.row < page.rows.count {
            layout.rows[item.row].append(item)
        }
        layout.bounds = CGRect(origin: .zero, size: size)
        return layout
    }

    /// Whether a container is large enough to place keys honestly.
    ///
    /// Below these thresholds the only way to produce a layout would be to shrink a
    /// key below its own target, which is the one thing this geometry must never do.
    /// Returning nothing is the correct answer for a container that is briefly the
    /// wrong size, and it is also what keeps a keyboard from crashing on a layout
    /// pass that lands mid-animation.
    private static func isUsable(_ size: CGSize, for page: KeyGridPage) -> Bool {
        let widestRow = page.rows.reduce(0) { max($0, $1.count) }
        guard widestRow > 0, size.height >= 1 else { return false }
        let neededWidth = edgeInset * 2 + keySpacing * CGFloat(max(0, widestRow - 1))
        let neededHeight = rowSpacing * CGFloat(max(0, page.rows.count - 1)) + 1
        return size.width > neededWidth && size.height >= neededHeight
    }

    /// Distributes a row across the width in proportion to each key's weight.
    private static func weightedPlates(
        for row: [KeyGridKey],
        width: CGFloat,
        top: CGFloat,
        height: CGFloat
    ) -> [CGRect] {
        let totalWeight = row.reduce(CGFloat(0)) { $0 + max(0.01, $1.weight) }
        let available = max(0, width - edgeInset * 2 - keySpacing * CGFloat(row.count - 1))
        var x = edgeInset
        return row.map { key in
            let plateWidth = available * max(0.01, key.weight) / totalWeight
            defer { x += plateWidth + keySpacing }
            return CGRect(x: x, y: top, width: plateWidth, height: height)
        }
    }

    /// Places the command keys at the edges and shares the middle between the rest.
    ///
    /// The first and last keys keep a fixed command width so shift and delete land
    /// in the same place regardless of how many letters sit between them.
    private static func edgePinnedPlates(
        for row: [KeyGridKey],
        width: CGFloat,
        top: CGFloat,
        height: CGFloat
    ) -> [CGRect] {
        guard !row.isEmpty else { return [] }
        if row.count == 1 {
            return [CGRect(x: edgeInset, y: top,
                           width: max(0, width - edgeInset * 2), height: height)]
        }
        let commandWidth = commandPlateWidth(for: row, width: width)
        // Filled by column so the order cannot drift: the first and last keys are
        // pinned, and the middle keys fill the space between them.
        var frames = [CGRect](repeating: .null, count: row.count)
        let last = row.count - 1
        frames[0] = CGRect(x: edgeInset, y: top, width: commandWidth, height: height)
        frames[last] = CGRect(x: width - edgeInset - commandWidth, y: top,
                              width: commandWidth, height: height)

        let middle = Array(row[1..<last])
        if !middle.isEmpty {
            let middleStart = frames[0].maxX + keySpacing
            let middleEnd = frames[last].minX - keySpacing
            let available = max(
                0,
                middleEnd - middleStart - keySpacing * CGFloat(middle.count - 1)
            )
            let totalWeight = middle.reduce(CGFloat(0)) { $0 + max(0.01, $1.weight) }
            var x = middleStart
            for (offset, key) in middle.enumerated() {
                let plateWidth = available * max(0.01, key.weight) / totalWeight
                frames[offset + 1] = CGRect(x: x, y: top, width: plateWidth, height: height)
                x += plateWidth + keySpacing
            }
        }
        return frames
    }

    /// Width of a pinned command plate: a share of the row, never wider than a
    /// standard key would be, so a narrow keyboard still fits its letters.
    private static func commandPlateWidth(for row: [KeyGridKey], width: CGFloat) -> CGFloat {
        let gaps = keySpacing * CGFloat(max(0, row.count - 1))
        let usable = max(0, width - edgeInset * 2 - gaps)
        let evenShare = usable / CGFloat(max(1, row.count))
        return min(max(0, width * 0.22), evenShare)
    }

    /// Widens every plate into a target that tiles the grid.
    ///
    /// Horizontally the first target starts at the grid's left edge and the last
    /// ends at its right edge, so the margin beside the outermost keys is live. The
    /// seams between keys sit in the gaps, so a target can grow into a gap but
    /// never into a neighbour's plate.
    ///
    /// Vertically each row extends halfway into the gap above and below, and the
    /// first and last rows reach the grid's own top and bottom.
    private static func withTargets(_ placed: [PlacedKey], in bounds: CGRect) -> [PlacedKey] {
        let rowIndices = Set(placed.map(\.row)).sorted()
        var rowSpans: [Int: (CGFloat, CGFloat)] = [:]
        for (position, rowIndex) in rowIndices.enumerated() {
            let plates = placed.filter { $0.row == rowIndex }
            guard let first = plates.first, let last = plates.last else { continue }
            let top = position > 0
                ? (rowSpans[rowIndices[position - 1]]?.1 ?? first.plate.minY) + rowSpacing / 2
                : bounds.minY
            let bottom = position + 1 < rowIndices.count
                ? last.plate.maxY + rowSpacing / 2
                : bounds.maxY
            rowSpans[rowIndex] = (min(top, bottom), max(top, bottom))
        }

        var result: [PlacedKey] = []
        result.reserveCapacity(placed.count)
        for item in placed {
            let rowPlates = placed.filter { $0.row == item.row }.sorted { $0.column < $1.column }
            guard let span = rowSpans[item.row] else {
                result.append(item)
                continue
            }
            let leftSeam = seam(before: item, in: rowPlates, bounds: bounds)
            let rightSeam = seam(after: item, in: rowPlates, bounds: bounds)
            let target = CGRect(
                x: leftSeam,
                y: span.0,
                width: max(0, rightSeam - leftSeam),
                height: max(0, span.1 - span.0)
            )
            result.append(
                PlacedKey(key: item.key, row: item.row, column: item.column,
                          plate: item.plate, target: target)
            )
        }
        return result
    }

    private static func seam(
        before item: PlacedKey,
        in row: [PlacedKey],
        bounds: CGRect
    ) -> CGFloat {
        guard item.column > 0, item.column - 1 < row.count else { return bounds.minX }
        let previous = row[item.column - 1]
        // Midpoint of the gap. Confined to the gap, so neither plate is touched.
        return (previous.plate.maxX + item.plate.minX) / 2
    }

    private static func seam(
        after item: PlacedKey,
        in row: [PlacedKey],
        bounds: CGRect
    ) -> CGFloat {
        guard item.column + 1 < row.count else { return bounds.maxX }
        let next = row[item.column + 1]
        return (item.plate.maxX + next.plate.minX) / 2
    }
}
