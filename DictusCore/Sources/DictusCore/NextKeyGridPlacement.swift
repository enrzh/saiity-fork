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
    /// Rows grow past `preferredRowHeight` to fill the surface, up to this.
    ///
    /// A hard cap at 45pt left most of a three-row page empty above the first row,
    /// which read as a broken layout rather than as breathing room. The cap only
    /// exists to stop a very tall container producing absurd keys; at 66pt a
    /// three-row page fills a 216pt keyboard exactly.
    public static let maximumRowHeight: CGFloat = 66
    public static let keyCornerRadius: CGFloat = 8
    public static let commandCornerRadius: CGFloat = 18
    /// Bottom-bar lane metrics, matching the legacy bar exactly.
    public static let barEdgeInset: CGFloat = 8
    public static let barGap: CGFloat = 4
    public static let compactBarWidth: CGFloat = 44
    public static let wideBarWidth: CGFloat = 88

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
        // The bar is not one of the rows: it lives in its own lane below the grid,
        // so the grid is solved into what is left above it.
        let gridHeight = max(1, size.height - (page.bottomBar.isEmpty ? 0 : reservedBarHeight))
        let rowHeight = max(
            1,
            min((gridHeight - gaps) / rowCount, maximumRowHeight)
        )
        let blockHeight = rowHeight * rowCount + gaps
        // Bottom-aligned inside the grid area, so any slack sits above the first row
        // exactly as it did in the legacy layout.
        let originY = max(0, gridHeight - blockHeight)
        // Short rows are centred and keep the width of a standard key rather than
        // stretching to fill. A nine-key row made of nine full-width keys looks
        // wrong next to a ten-key row; this is how a native keyboard draws them.
        let widestRow = page.rows.reduce(0) { max($0, $1.count) }
        let standardWidth = standardKeyWidth(for: widestRow, in: size.width)

        var placed: [PlacedKey] = []
        for (rowIndex, row) in page.rows.enumerated() {
            guard !row.isEmpty else { continue }
            let rowTop = originY + CGFloat(rowIndex) * (rowHeight + rowSpacing)
            let plates = (rowIndex == page.rows.count - 1 && page.pinnedLastRow)
                ? edgePinnedPlates(for: row, width: size.width, top: rowTop, height: rowHeight)
                : weightedPlates(
                    for: row,
                    width: size.width,
                    top: rowTop,
                    height: rowHeight,
                    standardWidth: standardWidth
                )
            for (column, plate) in plates.enumerated() {
                placed.append(
                    PlacedKey(key: row[column], row: rowIndex, column: column,
                              plate: plate, target: .null)
                )
            }
        }

        // The bar is placed as its own row so the same draw and hit-test path
        // handles it. Its lanes are the targets; the drawn faces are inset inside
        // them.
        let barRow = page.rows.count
        if !page.bottomBar.isEmpty {
            for (column, lane) in barPlates(for: page.bottomBar, in: size).enumerated() {
                let key = page.bottomBar[column]
                placed.append(
                    PlacedKey(
                        key: key, row: barRow, column: column,
                        plate: face(for: key, in: lane), target: lane
                    )
                )
            }
        }

        // Targets are assigned after every plate is known, because a seam between
        // two keys depends on both of them. The bar is excluded: its lane is already
        // its hit area, and widening it would let the space key steal presses from
        // the controls beside it.
        layout.placed = placed.map { item in
            guard item.row != barRow else { return item }
            return widened(item, in: CGRect(origin: .zero, size: size), rows: placed)
        }
        layout.rows = Array(repeating: [], count: page.rows.count + (page.bottomBar.isEmpty ? 0 : 1))
        for item in layout.placed where item.row < layout.rows.count {
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
        let barHeight = page.bottomBar.isEmpty ? 0 : reservedBarHeight
        let neededHeight = rowSpacing * CGFloat(max(0, page.rows.count - 1))
            + 1 + barHeight
        return size.width > neededWidth && size.height >= neededHeight
    }

    /// Vertical space the bottom bar occupies, including the gap above it and the
    /// inset below it. The legacy layout reserved exactly this much.
    public static let commandRowGap: CGFloat = 4
    public static let bottomBarHeight: CGFloat = 44
    public static let bottomInset: CGFloat = 6
    private static var reservedBarHeight: CGFloat {
        commandRowGap + bottomBarHeight + bottomInset
    }

    /// Lays the bottom bar out as fixed lanes.
    ///
    /// Each control keeps its own width and only the space key flexes, so a longer
    /// return label or a different language never shifts its neighbours. The drawn
    /// face is inset inside the lane, matching the legacy bar where the glass did
    /// not run edge to edge.
    private static func barPlates(
        for bar: [KeyGridKey],
        in size: CGSize
    ) -> [CGRect] {
        guard !bar.isEmpty else { return [] }
        let y = size.height - bottomInset - bottomBarHeight
        let gaps = barGap * CGFloat(max(0, bar.count - 1))
        let fixedTotal = bar.reduce(CGFloat(0)) { total, key in
            switch key.barWidth {
            case .compact: return total + compactBarWidth
            case .wide: return total + wideBarWidth
            case .flex: return total
            }
        }
        let usable = max(0, size.width - barEdgeInset * 2 - gaps - fixedTotal)
        let flexCount = CGFloat(bar.filter { $0.barWidth == .flex }.count)
        let flexWidth = flexCount > 0 ? max(0, usable / flexCount) : 0

        var x = barEdgeInset
        return bar.map { key in
            let width: CGFloat
            switch key.barWidth {
            case .compact: width = compactBarWidth
            case .wide: width = wideBarWidth
            case .flex: width = flexWidth
            }
            defer { x += width + barGap }
            return CGRect(x: x, y: y, width: width, height: bottomBarHeight)
        }
    }

    /// The face actually drawn for a bar key: its lane inset on every side.
    private static func face(for key: KeyGridKey, in lane: CGRect) -> CGRect {
        let inset = key.faceInset
        return lane.insetBy(dx: inset.width / 2, dy: inset.height / 2)
    }

    /// Width of one standard key in the widest row, which every other row is
    /// measured against.
    private static func standardKeyWidth(for count: Int, in width: CGFloat) -> CGFloat {
        guard count > 0 else { return 0 }
        let gaps = keySpacing * CGFloat(count - 1)
        return max(1, (width - edgeInset * 2 - gaps) / CGFloat(count))
    }

    /// Distributes a row across the width in proportion to each key's weight.
    ///
    /// A row with fewer keys than the widest is centred and keeps the standard key
    /// width, so the plates in a nine-key row line up optically with the ten-key
    /// row above it. It only stretches when there is genuinely spare width.
    private static func weightedPlates(
        for row: [KeyGridKey],
        width: CGFloat,
        top: CGFloat,
        height: CGFloat,
        standardWidth: CGFloat
    ) -> [CGRect] {
        let count = CGFloat(row.count)
        let totalWeight = row.reduce(CGFloat(0)) { $0 + max(0.01, $1.weight) }
        let unit = max(1, width - edgeInset * 2 - keySpacing * (count - 1))
        // Weight one standard key, so weights mean the same thing in every row.
        let perWeight = standardWidth > 0 ? standardWidth : unit / totalWeight
        var natural = row.reduce(CGFloat(0)) { $0 + max(0.01, $1.weight) * perWeight }
        natural += keySpacing * (count - 1)
        // Only stretch when the row is genuinely narrower than the space available.
        let rowWidth = min(unit + keySpacing * (count - 1), max(natural, 0))
        var x = edgeInset + max(0, (width - edgeInset * 2 - rowWidth) / 2)
        return row.map { key in
            let plateWidth = max(1, max(0.01, key.weight) * perWeight)
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

    /// One key's target: its plate widened to the contiguous tile that owns it.
    ///
    /// Horizontally the first target starts at the grid's left edge and the last ends
    /// at its right edge, so the margin beside the outermost keys is live. Seams sit
    /// in the gaps, so a target grows into a gap and never into a neighbour's plate.
    ///
    /// Vertically the span is bounded by the midpoints of the gaps above and below,
    /// with the grid's own edges outermost. Those midpoints come from **plate** edges:
    /// deriving a row's top from the previous row's target bottom adds the row gap
    /// twice and leaves a dead band between every pair of rows.
    private static func widened(
        _ item: PlacedKey,
        in bounds: CGRect,
        rows placed: [PlacedKey]
    ) -> PlacedKey {
        let rowPlates = placed
            .filter { $0.row == item.row }
            .sorted { $0.column < $1.column }
        guard !rowPlates.isEmpty else { return item }

        // Plate extents per row, for the vertical spans.
        var plateTop: [Int: CGFloat] = [:]
        var plateBottom: [Int: CGFloat] = [:]
        for candidate in placed {
            plateTop[candidate.row] = min(
                plateTop[candidate.row] ?? candidate.plate.minY, candidate.plate.minY
            )
            plateBottom[candidate.row] = max(
                plateBottom[candidate.row] ?? candidate.plate.maxY, candidate.plate.maxY
            )
        }
        let rowIndices = plateTop.keys.sorted()
        guard let position = rowIndices.firstIndex(of: item.row),
              let top = plateTop[item.row], let bottom = plateBottom[item.row] else {
            return item
        }
        let upper = position > 0
            ? ((plateBottom[rowIndices[position - 1]] ?? top) + top) / 2
            : bounds.minY
        let lower = position + 1 < rowIndices.count
            ? (bottom + (plateTop[rowIndices[position + 1]] ?? bottom)) / 2
            : bounds.maxY

        let leftSeam = seam(before: item, in: rowPlates, bounds: bounds)
        let rightSeam = seam(after: item, in: rowPlates, bounds: bounds)
        let target = CGRect(
            x: leftSeam,
            y: min(upper, lower),
            width: max(0, rightSeam - leftSeam),
            height: max(0, abs(lower - upper))
        )
        return PlacedKey(key: item.key, row: item.row, column: item.column,
                         plate: item.plate, target: target)
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
