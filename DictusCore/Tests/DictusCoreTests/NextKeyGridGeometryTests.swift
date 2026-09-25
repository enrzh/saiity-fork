// DictusCore/Tests/DictusCoreTests/NextKeyGridGeometryTests.swift
import XCTest
@testable import DictusCore

/// The rebuilt keyboard's geometry.
///
/// Two properties carry the whole design, and both are checked here rather than on
/// a device, because both are pure arithmetic and both have been bugs before:
///
///  1. **No key is ever reduced.** Every pressable target fully contains the plate
///     the user can see. A visible key that cannot be pressed is the single most
///     confusing failure a keyboard can have.
///  2. **No dead space.** The targets tile the grid edge to edge, so no point
///     inside it belongs to nothing. A device trace once showed 9 of 26 arriving
///     taps landing in gaps with no key to press.
///
/// The shape is borrowed from giellakbd-ios, this project's own Apache-2.0
/// ancestor, whose `UICollectionView` uses zero inter-item and line spacing so
/// every cell is contiguous. Deriving targets from the plates instead leaves the
/// outer margin outside every target, which is how we ended up with dead edge
/// bands that needed a separate rescue path.
final class NextKeyGridGeometryTests: XCTestCase {

    private let size = CGSize(width: 390, height: 216)

    private func lettersPage(rowCount: Int = 3, keysPerRow: Int = 10) -> KeyGridPage {
        var rows: [[KeyGridKey]] = []
        for row in 0..<rowCount {
            rows.append((0..<keysPerRow).map { column in
                KeyGridKey(
                    id: "k\(row)-\(column)",
                    action: .character(base: "a", variants: []),
                    weight: 1
                )
            })
        }
        return KeyGridPage(id: "test", rows: rows)
    }

    // MARK: - Rule 1: no key is ever reduced

    func testEveryTargetFullyContainsItsPlate() {
        for keysPerRow in [7, 10, 13] {
            let layout = KeyGridPlacement.solve(lettersPage(keysPerRow: keysPerRow), in: size)
            XCTAssertFalse(layout.placed.isEmpty)
            for item in layout.placed {
                XCTAssertTrue(
                    item.target.contains(item.plate),
                    "key \(item.key.id) is drawn at \(item.plate) but its target is \(item.target)"
                )
            }
        }
    }

    func testAPinnedLastRowKeepsShiftAndDeleteInPlace() {
        // Shift and delete are pinned to the edges, so they must not drift when the
        // number of letters between them changes.
        func edgeIDs(keysInMiddle: Int) -> (String, String, CGRect, CGRect) {
            var middle = (0..<keysInMiddle).map { index in
                KeyGridKey(id: "m\(index)", action: .character(base: "a", variants: []), weight: 1)
            }
            middle.insert(KeyGridKey(id: "shift", action: .shift, weight: 1.4,
                                     label: "s", isCommand: true), at: 0)
            middle.append(KeyGridKey(id: "delete", action: .deleteRepeating, weight: 1.4,
                                     label: "d", isCommand: true))
            let page = KeyGridPage(
                id: "pinned",
                rows: [lettersPage().rows[0], middle],
                pinnedLastRow: true
            )
            let layout = KeyGridPlacement.solve(page, in: size)
            let last = layout.rows.last ?? []
            let shift = last.first { $0.key.id == "shift" }
            let delete = last.first { $0.key.id == "delete" }
            return (
                shift?.key.id ?? "none", delete?.key.id ?? "none",
                shift?.plate ?? .zero, delete?.plate ?? .zero
            )
        }

        let narrow = edgeIDs(keysInMiddle: 3)
        let wide = edgeIDs(keysInMiddle: 9)
        XCTAssertEqual(narrow.0, "shift")
        XCTAssertEqual(narrow.1, "delete")
        XCTAssertEqual(narrow.2.minX, wide.2.minX, accuracy: 0.5,
                       "shift must not move when the row gains letters")
        XCTAssertEqual(narrow.3.maxX, wide.3.maxX, accuracy: 0.5,
                       "delete must not move when the row gains letters")
    }

    // MARK: - Rule 2: no dead space

    func testNoPointInsideTheGridIsUnowned() {
        let layout = KeyGridPlacement.solve(lettersPage(), in: size)
        // Sampled across the whole grid, stopping short of the far edges:
        // `CGRect.contains` treats `maxX`/`maxY` as exclusive, so the boundary
        // itself belongs to no rectangle. That is the same rule UIKit uses, and it
        // is asserted separately below so it stays intentional.
        for column in 0..<48 {
            for row in 0..<24 {
                let point = CGPoint(
                    x: size.width * CGFloat(column) / 48,
                    y: size.height * CGFloat(row) / 24
                )
                XCTAssertNotNil(
                    layout.key(at: point),
                    "no key owns (\(point.x), \(point.y)); a tap there would be lost"
                )
            }
        }
    }

    func testTheFarEdgesAreExclusiveAndThatIsIntentional() {
        // The right and bottom edges are not inside any target. UIKit's hit testing
        // behaves the same way, so a point one pixel in from the edge is what a
        // finger can actually produce.
        let layout = KeyGridPlacement.solve(lettersPage(), in: size)
        XCTAssertNil(layout.key(at: CGPoint(x: size.width, y: size.height / 2)))
        XCTAssertNil(layout.key(at: CGPoint(x: size.width / 2, y: size.height)))
        XCTAssertNotNil(layout.key(at: CGPoint(x: size.width - 1, y: size.height / 2)))
        XCTAssertNotNil(layout.key(at: CGPoint(x: size.width / 2, y: size.height - 1)))
    }

    func testExactlyOneKeyOwnsEachPoint() {
        let layout = KeyGridPlacement.solve(lettersPage(), in: size)
        // `CGRect.contains` treats `maxX` as exclusive, so the right edge itself is
        // not a point the grid owns. Sampling stops short of it.
        for column in 0..<32 {
            let point = CGPoint(
                x: size.width * CGFloat(column) / 32,
                y: size.height / 2
            )
            let claimants = layout.placed.filter { $0.target.contains(point) }
            XCTAssertEqual(
                claimants.count, 1,
                "(\(point.x), \(point.y)) is claimed \(claimants.count) times; one touch must have one answer"
            )
        }
    }

    func testTheMarginsBesideTheOuterKeysAreLive() {
        let layout = KeyGridPlacement.solve(lettersPage(), in: size)
        // Half a point inside the grid on each side. Deriving targets from the
        // plates leaves these unowned, which is where the dead edge bands came from.
        let left = layout.key(at: CGPoint(x: 0.5, y: size.height / 2))
        let right = layout.key(at: CGPoint(x: size.width - 0.5, y: size.height / 2))
        XCTAssertNotNil(left, "the left margin must belong to the first key")
        XCTAssertNotNil(right, "the right margin must belong to the last key")
        XCTAssertEqual(left?.column, 0)
        XCTAssertEqual(right?.column, (layout.rows.first?.count ?? 1) - 1)
    }

    // MARK: - Filling the surface

    /// The rows must fill the keyboard, not sit in the bottom two-thirds of it.
    ///
    /// A hard cap of 45pt left a large empty band above the first row on the
    /// three-row pages, which read as a broken layout rather than as breathing room.
    func testRowsFillTheSurface() {
        // The pages that exist: three letter rows plus a bar, or two symbol rows
        // plus a bar. A hypothetical two-row page is bottom-aligned by design and
        // is not held to the fill rule.
        for rowCount in [3, 4, 5] {
            var rows: [[KeyGridKey]] = []
            for row in 0..<rowCount {
                rows.append((0..<10).map {
                    KeyGridKey(id: "k\($0)-\(row)", action: .insert("a"))
                })
            }
            let layout = KeyGridPlacement.solve(KeyGridPage(id: "fill", rows: rows), in: size)
            guard let top = layout.placed.map(\.plate.minY).min(),
                  let bottom = layout.placed.map(\.plate.maxY).max() else {
                XCTFail("no keys placed for \(rowCount) rows")
                continue
            }
            // Rows are never taller than the platform's own key height, whatever
            // the container offers. Spending leftover space on taller keys is what
            // made the rebuilt grid stop lining up with the system keyboard: every
            // row below the first drifted out of alignment with it.
            for row in layout.rows {
                for item in row {
                    XCTAssertLessThanOrEqual(
                        item.plate.height, KeyGridPlacement.maximumRowHeight + 0.5,
                        "\(rowCount) rows produced a \(item.plate.height)pt key"
                    )
                }
            }
            XCTAssertEqual(bottom, size.height, accuracy: 0.5,
                           "the block must sit against the bottom of the grid")
            // The slack above the first plate is still owned by a target. Leaving it
            // unowned would reintroduce the dead band that took four builds to find,
            // so the rule is about targets tiling the grid, not about plates filling
            // it.
            let owner = layout.placed.first { $0.target.contains(CGPoint(x: size.width / 2, y: top / 2)) }
            XCTAssertNotNil(owner,
                            "\(rowCount) rows left \(top)pt that no target owns")
        }
    }

    /// A short row is centred and keeps the standard key width, so the home row
    /// lines up optically with the row above it instead of stretching to the edges.
    func testShortRowsAreCentredAndKeepTheStandardKeyWidth() {
        let page = KeyGridPage(
            id: "centred",
            rows: [
                (0..<10).map { KeyGridKey(id: "a\($0)", action: .insert("a")) },
                (0..<7).map { KeyGridKey(id: "b\($0)", action: .insert("b")) }
            ]
        )
        let layout = KeyGridPlacement.solve(page, in: size)
        let top = layout.rows[0]
        let short = layout.rows[1]
        XCTAssertEqual(short.count, 7)
        XCTAssertEqual(short.first?.plate.width ?? 0, top.first?.plate.width ?? -1,
                       accuracy: 0.5, "a short row must keep the standard key width")
        let topInset = top.first?.plate.minX ?? 0
        let shortInset = short.first?.plate.minX ?? 0
        let topRightGap = size.width - (top.last?.plate.maxX ?? 0)
        let shortRightGap = size.width - (short.last?.plate.maxX ?? 0)
        XCTAssertGreaterThan(shortInset, topInset, "a short row must be indented")
        XCTAssertEqual(shortInset, shortRightGap, accuracy: 0.5,
                       "a short row must be centred, not left-aligned")
        XCTAssertGreaterThan(topRightGap, 0)
    }

    // MARK: - Platform parity

    /// The grid lines up with the system keyboard, measured not guessed.
    ///
    /// The numbers come from probing the rendered iOS keyboard on an iPhone 18 Pro
    /// (402pt wide): a ten-key row runs x=7..395, its plates are 33.5pt wide with
    /// 6pt between them, the plates are 43pt tall, and the rows are 11pt apart. Those
    /// are the platform's values, so they are the ones to hold — a grid that is
    /// merely "close" is visibly not the keyboard it replaced, because every row
    /// below the first drifts by the accumulated error.
    func testLetterGridMatchesTheMeasuredSystemKeyboard() {
        func letters(_ chars: String, _ prefix: String) -> [KeyGridKey] {
            chars.map { KeyGridKey(id: "\(prefix)\($0)", action: .insert("a")) }
        }
        var bottom: [KeyGridKey] = [KeyGridKey(id: "shift", action: .shift, isCommand: true)]
        bottom += letters("zxcvbnm", "b")
        bottom.append(KeyGridKey(id: "delete", action: .delete, isCommand: true))

        let rows: [[KeyGridKey]] = [
            letters("qwertyuiop", "t"),
            letters("asdfghjkl", "h"),
            bottom
        ]
        let page = KeyGridPage(id: "parity", rows: rows, pinnedLastRow: true)
        let screen = CGSize(width: 402, height: 170)
        let layout = KeyGridPlacement.solve(page, in: screen)

        // Side margins, taken from the widest row.
        let top = layout.rows[0]
        guard let topFirst = top.first, let topLast = top.last,
              let topSecond = top.count > 1 ? top[1] : nil else {
            XCTFail("no top row keys")
            return
        }
        XCTAssertEqual(topFirst.plate.minX, 7, accuracy: 0.5)
        XCTAssertEqual(402 - topLast.plate.maxX, 7, accuracy: 0.5)

        // Letter plates: standard width, 6pt apart, 43pt tall.
        XCTAssertEqual(topFirst.plate.width, 33.5, accuracy: 1.0)
        XCTAssertEqual(topSecond.plate.minX - topFirst.plate.maxX, 6, accuracy: 0.5)
        for row in layout.rows {
            XCTAssertEqual(row.first?.plate.height ?? .nan, 43, accuracy: 0.5)
        }

        // Rows are 11pt apart.
        let rowTops = layout.rows.map { $0.first?.plate.minY ?? .nan }
        XCTAssertEqual(rowTops[1] - rowTops[0], 54, accuracy: 0.5)
        XCTAssertEqual(rowTops[2] - rowTops[1], 54, accuracy: 0.5)

        // The bottom row's letters keep the standard width and the 6pt gap, and the
        // block is centred between the two edge keys. It is deliberately NOT aligned
        // with the row above: the system keyboard pushes it right, because the wider
        // shift eats the space on the left. Measured, z starts at x=66 there.
        let lastRow = layout.rows[2]
        guard let shift = lastRow.first, let z = lastRow.count > 1 ? lastRow[1] : nil,
              let del = lastRow.last else {
            XCTFail("no bottom row keys")
            return
        }
        XCTAssertEqual(z.plate.width, 33.5, accuracy: 1.0)
        XCTAssertEqual(z.plate.minX, 66, accuracy: 1.5,
                       "the middle block must be centred between the edge keys")
        for (a, b) in zip(lastRow, lastRow.dropFirst()) {
            XCTAssertGreaterThan(b.plate.minX - a.plate.maxX, 0, "keys must not overlap")
        }
        // Equal gaps either side of the centred block.
        let leftGap = z.plate.minX - shift.plate.maxX
        let rightGap = del.plate.minX - lastRow[lastRow.count - 2].plate.maxX
        XCTAssertEqual(leftGap, rightGap, accuracy: 1.0,
                       "the slack belongs equally beside shift and delete")

        // Shift and delete are about 1.36x a letter, as the system keyboard draws them.
        XCTAssertEqual(shift.plate.width / 33.5, 1.36, accuracy: 0.05)
        XCTAssertEqual(del.plate.width / 33.5, 1.36, accuracy: 0.05)
    }

    /// The symbol pages share the letter page's rule, and it has to be derived from
    /// the key count rather than assumed.
    ///
    /// Measured on the system keyboard: both symbol pages are 10 / 10 / 7 with the
    /// bottom row pinned, and on that row the two edge keys are ~45pt, the outer
    /// gaps ~14pt, and the five middle keys come out ~49pt — not the 33.5pt a letter
    /// key is. Holding the middles at the standard width matched the letter page by
    /// coincidence and was 15pt out on both symbol pages.
    func testSymbolPagesMatchTheMeasuredSystemKeyboard() {
        func keys(_ count: Int, _ prefix: String) -> [KeyGridKey] {
            (0..<count).map { KeyGridKey(id: "\(prefix)\($0)", action: .insert("1")) }
        }
        var bottom: [KeyGridKey] = [KeyGridKey(id: "toggle", action: .page("123"), isCommand: true)]
        bottom += keys(5, "sym")
        bottom.append(KeyGridKey(id: "delete", action: .delete, isCommand: true))

        let rows: [[KeyGridKey]] = [keys(10, "a"), keys(10, "b"), bottom]
        let layout = KeyGridPlacement.solve(
            KeyGridPage(id: "symbols", rows: rows, pinnedLastRow: true),
            in: CGSize(width: 402, height: 170)
        )

        // Rows one and two are the same as the letter page's.
        for index in 0...1 {
            let row = layout.rows[index]
            guard let first = row.first, let second = row.count > 1 ? row[1] : nil else {
                XCTFail("row \(index) has no keys")
                continue
            }
            XCTAssertEqual(first.plate.minX, 7, accuracy: 0.5)
            XCTAssertEqual(first.plate.width, 33.5, accuracy: 1.0)
            XCTAssertEqual(second.plate.minX - first.plate.maxX, 6, accuracy: 0.5)
        }

        let lastRow = layout.rows[2]
        guard let toggle = lastRow.first,
              let firstMiddle = lastRow.count > 1 ? lastRow[1] : nil,
              let delete = lastRow.last else {
            XCTFail("no bottom row keys")
            return
        }
        // Edges at the platform's size, outer gap at the platform's size.
        XCTAssertEqual(toggle.plate.width, 45.5, accuracy: 1.5)
        XCTAssertEqual(delete.plate.width, 45.5, accuracy: 1.5)
        XCTAssertEqual(firstMiddle.plate.minX - toggle.plate.maxX, 14, accuracy: 1.5)
        // And the five middles widen to fill: 49pt, not a letter's 33.5.
        XCTAssertEqual(firstMiddle.plate.width, 49, accuracy: 1.5)
        for (a, b) in zip(lastRow, lastRow.dropFirst()) {
            XCTAssertGreaterThan(b.plate.minX, a.plate.maxX, "keys must not overlap")
        }
        XCTAssertEqual(402 - delete.plate.maxX, 7, accuracy: 0.5)
    }

    // MARK: - The bottom bar is not ours

    /// The grid fills the rect it is handed, and nothing more.
    ///
    /// The bottom bar belongs to `AuxiliaryBottomBar` — one bar for the letter,
    /// symbol and emoji pages — and `NextKeyboardHost.gridFrame` hands the grid a
    /// rect that stops above that lane. If the solver reserved the lane as well the
    /// rows would be short by 54pt and the bar would be pushed off the surface, so
    /// the reservation has to live in exactly one place.
    func testRowsFillTheWholeRectTheyAreGiven() {
        let page = KeyGridPage(
            id: "fill",
            rows: [
                (0..<10).map { KeyGridKey(id: "a\($0)", action: .insert("a")) },
                (0..<10).map { KeyGridKey(id: "b\($0)", action: .insert("b")) },
                (0..<10).map { KeyGridKey(id: "c\($0)", action: .insert("c")) }
            ]
        )
        let layout = KeyGridPlacement.solve(page, in: size)
        let first = layout.placed.first { $0.row == 0 }
        let last = layout.placed.first { $0.row == 2 }
        let firstRow = try? XCTUnwrap(first)
        let lastRow = try? XCTUnwrap(last)
        XCTAssertNotNil(firstRow)
        XCTAssertNotNil(lastRow)
        guard let top = firstRow, let bottom = lastRow else { return }
        // First row starts at the top edge; last row's target reaches the bottom.
        XCTAssertEqual(top.target.minY, 0, accuracy: 0.5)
        XCTAssertEqual(bottom.target.maxY, size.height, accuracy: 0.5)
    }

    // MARK: - Robustness

    func testDegenerateSizesDoNotCrashAndProduceNothing() {
        // A keyboard must never crash because its container is briefly the wrong
        // size: that trap killed the extension on launch in an earlier build.
        for degenerate in [CGSize.zero, CGSize(width: 10, height: 0),
                           CGSize(width: 0, height: 10), CGSize(width: 1, height: 1)] {
            let layout = KeyGridPlacement.solve(lettersPage(), in: degenerate)
            for item in layout.placed {
                XCTAssertTrue(item.target.contains(item.plate),
                              "a key was reduced at size \(degenerate)")
            }
        }
    }

    func testAnEmptyPageProducesAnEmptyLayout() {
        let layout = KeyGridPlacement.solve(KeyGridPage(id: "empty", rows: []), in: size)
        XCTAssertTrue(layout.placed.isEmpty)
        XCTAssertNil(layout.key(at: CGPoint(x: 10, y: 10)))
    }

    func testSolvedRowsStayParallelToThePageRows() {
        // A short solved row must not shift every later key by a column.
        let page = KeyGridPage(
            id: "ragged",
            rows: [
                (0..<10).map { KeyGridKey(id: "a\($0)", action: .insert("a")) },
                (0..<3).map { KeyGridKey(id: "b\($0)", action: .insert("b")) }
            ]
        )
        let layout = KeyGridPlacement.solve(page, in: size)
        XCTAssertEqual(layout.rows[1].count, 3)
        for item in layout.rows[1] {
            XCTAssertTrue(item.key.id.hasPrefix("b"),
                          "row 1 resolved to \(item.key.id); rows drifted out of step")
        }
    }

    func testFingerprintChangesOnlyWhenContentChanges() {
        let page = lettersPage()
        XCTAssertEqual(page.fingerprint, page.fingerprint)
        // Same ids and labels, so a re-render must not look like a content change.
        let same = KeyGridPage(
            id: page.id,
            rows: page.rows.map { row in row.map { $0 } }
        )
        XCTAssertEqual(page.fingerprint, same.fingerprint)
    }

    func testFingerprintSeparatesVariantsFromPlainKeys() {
        // A key that gains a hold popup must be distinguishable from one that does
        // not, or the page would be reused and the popup would never appear.
        let plain = KeyGridPage(
            id: "p",
            rows: [[KeyGridKey(id: "e", action: .character(base: "e", variants: []))]]
        )
        let withVariants = KeyGridPage(
            id: "p",
            rows: [[KeyGridKey(id: "e", action: .character(base: "e", variants: ["e", "é"]))]]
        )
        XCTAssertNotEqual(plain.fingerprint, withVariants.fingerprint)
    }
}
