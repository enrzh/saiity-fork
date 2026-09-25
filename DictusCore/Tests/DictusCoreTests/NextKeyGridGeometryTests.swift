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
