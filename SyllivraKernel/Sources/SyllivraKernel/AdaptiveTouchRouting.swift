import Foundation
import CoreGraphics

/// A bounded, normalized next-character distribution from local prediction data.
public struct NextCharacterProbabilities: Equatable {
    public let values: [String: Double]

    public init(_ rawValues: [String: Double], maxEntries: Int = 8) {
        let normalized = rawValues.reduce(into: [String: Double]()) { result, item in
            let key = item.key.lowercased()
            guard key.count == 1, item.value.isFinite, item.value > 0 else { return }
            result[key, default: 0] += item.value
        }
        let bounded = normalized
            .sorted { lhs, rhs in
                lhs.value == rhs.value ? lhs.key < rhs.key : lhs.value > rhs.value
            }
            .prefix(max(0, maxEntries))
        let total = bounded.reduce(0) { $0 + $1.value }
        values = total > 0
            ? Dictionary(uniqueKeysWithValues: bounded.map { ($0.key, $0.value / total) })
            : [:]
    }

    public subscript(character: String) -> Double {
        values[character.lowercased()] ?? 0
    }

    public var isEmpty: Bool { values.isEmpty }
}

/// Hit targets for a keyboard surface.
///
/// Three rules, and they only hold together:
///
/// 1. **No key is ever reduced.** Every target fully contains the key drawn on
///    screen, at all times, under any prediction.
/// 2. **No dead space.** Every point across a row belongs to some key, so a tap
///    in a gap still presses the key beside it.
/// 3. **Targets are allowed to overlap, and the overlap is resolved by the drawn
///    plate.** See `KeyboardKeyHitResolver.keyIndex(at:rows:plates:)`.
///
/// `growing(_:horizontal:vertical:)` applies rule 3's slop as a separate step, so
/// the rectangles SwiftUI lays out with are unaffected by it.
///
/// The previous implementation satisfied neither of the first two. It cut each
/// row into tiles at neighbour midpoints and then clamped every seam to
/// `left.minX + left.width * 0.66 … right.minX + right.width * 0.34`. That clamp
/// could push a seam *inside* a key, so a key drawn on screen ended up with a
/// target smaller than itself, and `max(0, …)` could collapse it to zero width.
/// Prediction then moved the shared seam far enough that the loser's target
/// shrank on every keystroke.
///
/// Dropping the tiling altogether fixed rule 1 and broke rule 2. A device trace
/// then showed 26 taps arriving at the extension, 17 reaching a key, and 9
/// landing in the gaps with nothing at all to press. Dead gaps are exactly as
/// broken as dead keys.
///
/// So the seam stays, with one change that makes both rules hold: **a seam is
/// confined to the gap between the two keys it divides.** A point strictly
/// between two visual frames belongs to neither key, so placing the seam
/// anywhere inside that gap — including a prediction-biased position — cannot
/// take a single point from either key's own plate.
///
/// Prediction biases where inside the gap the seam sits. The key that loses that
/// bias keeps its entire drawn plate; it merely receives a smaller share of the
/// gap, and gap area is a bonus rather than a subtraction. Nothing is ever taken
/// from anyone.
///
/// `slop` then grows every target past its share, so a key's invisible target is
/// meaningfully larger than its visible plate. That deliberately breaks the old
/// "no two targets intersect" property, which is why rule 3 exists: a grown
/// target overlaps its neighbours, and the key whose *drawn plate* is nearest the
/// touch wins. Rules 1 and 2 still hold — nothing shrinks, and nothing is dead.
///
/// Material preferences never affect this geometry.
public enum KeyboardKeyHitGeometry {
    /// Smallest share of a gap that must remain on each side of a biased seam, so
    /// a gap always has an owner either side of the split.
    ///
    /// This is the binding constraint on prediction, not `maximumPredictionShift`.
    /// With the 6pt column gap the usable room is `gap/2 - minimumGapShare`, so a
    /// floor of 2 left the seam a 1pt move — small enough that the contextual
    /// predictor we already ship had almost no effect on where a tap lands. At 1
    /// the seam can move 2pt, doubling the predictor's authority while still
    /// guaranteeing the disfavoured key keeps a share of the gap.
    private static let minimumGapShare: CGFloat = 1

    public static func frames(
        for visualRows: [[CGRect]],
        labels: [[String?]]? = nil,
        probabilities: NextCharacterProbabilities? = nil,
        maximumPredictionShift: CGFloat = 4,
        minimumProbability: Double = 0.10,
        minimumLead: Double = 0.03
    ) -> [[CGRect]] {
        let visibleRows = visualRows.indices.filter { !visualRows[$0].isEmpty }

        // Vertical seams are the midpoint of the gap between two rows, so each
        // row spans its own plate plus half of the gap above and below it.
        let vertical = Dictionary(uniqueKeysWithValues: visibleRows.enumerated().map { position, rowIndex in
            let row = visualRows[rowIndex]
            let rowTop = row.map(\.minY).min() ?? 0
            let rowBottom = row.map(\.maxY).max() ?? rowTop
            let top: CGFloat
            if position > 0 {
                let previousBottom = visualRows[visibleRows[position - 1]].map(\.maxY).max() ?? rowTop
                top = (previousBottom + rowTop) / 2
            } else {
                top = rowTop
            }
            let bottom: CGFloat
            if position + 1 < visibleRows.count {
                let nextTop = visualRows[visibleRows[position + 1]].map(\.minY).min() ?? rowBottom
                bottom = (rowBottom + nextTop) / 2
            } else {
                bottom = rowBottom
            }
            return (rowIndex, (top, bottom))
        })

        return visualRows.enumerated().map { rowIndex, row in
            guard !row.isEmpty else { return [] }
            let span = vertical[rowIndex] ?? (row[0].minY, row[0].maxY)
            let rowLabels = labels.flatMap { $0.indices.contains(rowIndex) ? $0[rowIndex] : nil }
            // Same seam rule as `contiguousTiles`, but bounded by the first and
            // last plate rather than the grid, because these rectangles are what
            // SwiftUI lays the keys out with and a layout box must describe the key
            // as drawn.
            let seams = horizontalSeams(
                row: row,
                rowLabels: rowLabels,
                probabilities: probabilities,
                maximumPredictionShift: maximumPredictionShift,
                minimumProbability: minimumProbability,
                minimumLead: minimumLead,
                leadingEdge: row[0].minX,
                trailingEdge: row[row.count - 1].maxX
            )
            guard seams.count == row.count + 1 else { return [] }
            return row.indices.map { index in
                CGRect(
                    x: seams[index],
                    y: span.0,
                    width: max(0, seams[index + 1] - seams[index]),
                    height: max(0, span.1 - span.0)
                )
            }
        }
    }

    /// Grows already-tiled targets by an invisible slop.
    ///
    /// Superseded by `contiguousTiles(for:in:…)`, which removes the need for a
    /// slop entirely. Kept out of the build path deliberately: overlapping targets
    /// need an arbitration rule to pick a winner, and a mature keyboard does not
    /// need that rule at all because its targets are contiguous. See the type
    /// comment for why contiguous tiling is the better shape.
    public static func growing(
        _ rows: [[CGRect]],
        horizontal: CGFloat,
        vertical: CGFloat
    ) -> [[CGRect]] {
        guard horizontal > 0 || vertical > 0 else { return rows }
        return rows.map { row in
            row.map { $0.insetBy(dx: -horizontal, dy: -vertical) }
        }
    }

    /// Hit targets that tile the **whole** grid, edge to edge, with no gaps and no
    /// overlaps.
    ///
    /// This is the shape a real keyboard uses, and it is worth being explicit about
    /// why, because the obvious alternative is worse:
    ///
    /// - giellakbd-ios, this project's own Apache-2.0 ancestor, lays its keys out
    ///   as a `UICollectionView` with `minimumInteritemSpacing` and
    ///   `minimumLineSpacing` both `0`, sizes each cell to a full unit of the row,
    ///   resolves touches with `indexPathForItem(at:)`, and then draws the visible
    ///   key plate *inset inside* its cell. The cell is the target; the plate is
    ///   decoration inside it.
    /// - Deriving targets from the plates instead — "plate plus half of each
    ///   gap" — leaves the outer margin outside every target, and those bands need
    ///   a separate rescue path. That is where the dead edge bands came from.
    ///
    /// So the tiles span `bounds` exactly, the outer edges of the first and last
    /// key are the grid's own edges, and the interior seams stay confined to the
    /// gaps between plates. A seam can therefore never take a point from a
    /// neighbour's plate, and no point inside the grid is unowned.
    ///
    /// Because the tiles are contiguous there is nothing to arbitrate: exactly one
    /// tile contains any point, so `KeyboardKeyHitResolver.keyIndex` stays a plain
    /// containment test with no tie-break to get wrong.
    ///
    /// `visualRows` must be the drawn plates in the same coordinate space as
    /// `bounds`, because the gaps between them are what place the seams.
    public static func contiguousTiles(
        for visualRows: [[CGRect]],
        in bounds: CGRect,
        labels: [[String?]]? = nil,
        probabilities: NextCharacterProbabilities? = nil,
        maximumPredictionShift: CGFloat = 4,
        minimumProbability: Double = 0.10,
        minimumLead: Double = 0.03
    ) -> [[CGRect]] {
        guard bounds.width > 0, bounds.height > 0 else { return [] }
        let visibleRows = visualRows.indices.filter { !visualRows[$0].isEmpty }
        guard !visibleRows.isEmpty else { return [] }

        // Vertical boundaries are the midpoints between consecutive rows; the
        // outermost boundaries are the grid's own top and bottom, so the first and
        // last row absorb the leftover space rather than leaving it dead.
        var vertical: [Int: (CGFloat, CGFloat)] = [:]
        for (position, rowIndex) in visibleRows.enumerated() {
            let row = visualRows[rowIndex]
            let rowTop = row.map(\.minY).min() ?? bounds.minY
            let rowBottom = row.map(\.maxY).max() ?? rowTop
            let top: CGFloat
            if position > 0 {
                let previousBottom = visualRows[visibleRows[position - 1]].map(\.maxY).max() ?? rowTop
                top = (previousBottom + rowTop) / 2
            } else {
                top = bounds.minY
            }
            let bottom: CGFloat
            if position + 1 < visibleRows.count {
                let nextTop = visualRows[visibleRows[position + 1]].map(\.minY).min() ?? rowBottom
                bottom = (rowBottom + nextTop) / 2
            } else {
                bottom = bounds.maxY
            }
            vertical[rowIndex] = (min(top, bottom), max(top, bottom))
        }

        return visualRows.enumerated().map { rowIndex, row in
            guard !row.isEmpty, let span = vertical[rowIndex] else { return [] }
            let rowLabels = labels.flatMap { $0.indices.contains(rowIndex) ? $0[rowIndex] : nil }
            let seams = horizontalSeams(
                row: row,
                rowLabels: rowLabels,
                probabilities: probabilities,
                maximumPredictionShift: maximumPredictionShift,
                minimumProbability: minimumProbability,
                minimumLead: minimumLead,
                leadingEdge: bounds.minX,
                trailingEdge: bounds.maxX
            )
            return row.indices.map { index in
                CGRect(
                    x: seams[index],
                    y: span.0,
                    width: max(0, seams[index + 1] - seams[index]),
                    height: max(0, span.1 - span.0)
                )
            }
        }
    }

    /// The seam positions for one row: `row.count + 1` of them, ordered, and with
    /// every interior seam inside the gap it divides.
    ///
    /// Both `frames(for:)` and `contiguousTiles(for:in:)` call this, so prediction
    /// can only ever be described in one place. The two differ solely in the outer
    /// seams: `frames` uses the first and last plate's own edges, while
    /// `contiguousTiles` uses the grid's edges so no band is left unowned.
    private static func horizontalSeams(
        row: [CGRect],
        rowLabels: [String?]?,
        probabilities: NextCharacterProbabilities?,
        maximumPredictionShift: CGFloat,
        minimumProbability: Double,
        minimumLead: Double,
        leadingEdge: CGFloat,
        trailingEdge: CGFloat
    ) -> [CGFloat] {
        guard let first = row.first, let last = row.last else { return [] }
        var seams = [leadingEdge]
        for index in 0..<(row.count - 1) {
            let gapStart = row[index].maxX
            let gapEnd = row[index + 1].minX
            let gap = gapEnd - gapStart
            var seam = (gapStart + gapEnd) / 2

            if gap > 0,
               let probabilities,
               let rowLabels,
               rowLabels.indices.contains(index),
               rowLabels.indices.contains(index + 1),
               let leftLabel = rowLabels[index],
               let rightLabel = rowLabels[index + 1] {
                let leftProbability = probabilities[leftLabel]
                let rightProbability = probabilities[rightLabel]
                if max(leftProbability, rightProbability) >= minimumProbability,
                   abs(leftProbability - rightProbability) >= minimumLead {
                    // The seam may move at most halfway across the gap, and must
                    // still leave `minimumGapShare` on the far side. Measuring the
                    // room from the midpoint is what guarantees a share for both
                    // keys; capping it against the whole gap would let the
                    // favoured key take all of it.
                    let room = max(0, gap / 2 - minimumGapShare)
                    let shift = min(max(0, maximumPredictionShift), room)
                    // Moving the seam *away* from the likely key gives that key the
                    // larger share of the gap, and neither visible plate shrinks
                    // either way.
                    //
                    // This direction is easy to invert and was: a seam shifted
                    // toward the likely key hands the extra gap to the *other* key,
                    // so a near-edge tap selected the wrong letter.
                    seam += rightProbability > leftProbability ? -shift : shift
                }
            }

            // The seam is confined to the gap by construction; this clamp makes
            // that a property of the resulting value rather than of the arithmetic
            // that produced it.
            seams.append(min(max(seam, gapStart), gapEnd))
        }
        seams.append(trailingEdge)
        // Monotonic seams are what make the tiles contiguous, and a degenerate row
        // (zero-width plate, or a seam pinned to both ends of a zero-width gap) must
        // not be allowed to produce a negative width.
        for index in 1..<max(1, seams.count) where seams[index] < seams[index - 1] {
            seams[index] = seams[index - 1]
        }
        if let first = seams.first, let last = seams.last, last < first {
            seams[seams.count - 1] = first
        }
        return seams
    }
}

/// Resolves a touch position to the key that owns it.
///
/// `KeyboardKeyHitGeometry.frames` produces the rectangles; nothing consumed
/// them by position. Each key therefore owned itself through its own view, so a
/// key could be unreachable, double-owned, or claimed by whatever view happened
/// to sit above it. This is the single lookup that makes position the source of
/// truth: one geometry, one owner, one answer per point.
public enum KeyboardKeyHitResolver {
    /// The key containing `point`, or `nil` when the point is outside every row.
    ///
    /// Contiguous tiles make this exact: exactly one tile contains any point
    /// inside the grid, so the scan order never decides the answer. Rows are
    /// scanned in order, so a caller supplying overlapping geometry would get the
    /// first match — `claimingKeys(at:rows:)` exists to detect that case.
    public static func keyIndex(
        at point: CGPoint,
        rows: [[CGRect]]
    ) -> (row: Int, column: Int)? {
        for (rowIndex, row) in rows.enumerated() {
            for (columnIndex, frame) in row.enumerated() where frame.contains(point) {
                return (rowIndex, columnIndex)
            }
        }
        return nil
    }

    /// Every key that claims `point`. More than one means the geometry is
    /// ambiguous and the touch could resolve differently depending on view
    /// order — the exact failure this resolver exists to prevent.
    public static func claimingKeys(
        at point: CGPoint,
        rows: [[CGRect]]
    ) -> [(row: Int, column: Int)] {
        var claims: [(row: Int, column: Int)] = []
        for (rowIndex, row) in rows.enumerated() {
            for (columnIndex, frame) in row.enumerated() where frame.contains(point) {
                claims.append((rowIndex, columnIndex))
            }
        }
        return claims
    }

    /// True when no point inside `bounds` is claimed by more than one key.
    /// Sampled on a grid; the geometry is axis-aligned rectangles, so the only
    /// places answers can change are rectangle edges.
    public static func isUnambiguous(
        rows: [[CGRect]],
        in bounds: CGRect,
        samplesPerAxis: Int = 24
    ) -> Bool {
        guard bounds.width > 0, bounds.height > 0, samplesPerAxis > 1 else { return true }
        for rowIndex in 0...samplesPerAxis {
            for columnIndex in 0...samplesPerAxis {
                let x = bounds.minX + bounds.width * CGFloat(columnIndex) / CGFloat(samplesPerAxis)
                let y = bounds.minY + bounds.height * CGFloat(rowIndex) / CGFloat(samplesPerAxis)
                if claimingKeys(at: CGPoint(x: x, y: y), rows: rows).count > 1 { return false }
            }
        }
        return true
    }
}
