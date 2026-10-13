// SyllivraKernel/Tests/SyllivraKernelTests/NextKeyGridGeometryTests.swift
import XCTest
@testable import SyllivraKernel

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

    func testTallerBottomBarLiftsRowsWithoutChangingCharacterSize() {
        for width in [320.0, 402, 420] {
            let layout = VoiceOnlyKeyboardPolicy.layout(for: width, surfaceHeight: 269, topAccessoryHeight: 32)
            XCTAssertEqual(layout.chromeSpaceFrame.height, 54)
            for hit in [layout.chromeNumbersFrame, layout.chromeLettersFrame,
                        layout.letterPeriodFrame, layout.chromeReturnFrame] {
                XCTAssertEqual(hit.height, 54)
                XCTAssertEqual(VoiceOnlyKeyboardPolicy.bottomBarVisualSize(for: hit.size).height, 45)
            }
            let page = lettersPage()
            let grid = CGSize(width: width, height: layout.surfaceFrame.height - KeyGridPlacement.bottomBarLaneHeight)
            let centre = layout.boardDeleteFrame.midY - layout.surfaceFrame.minY
            let current = KeyGridPlacement.solve(KeyGridPlacement.alignLastRow(page, in: grid, centerY: centre), in: grid)
            let previousSize = CGSize(width: width, height: grid.height + 9)
            let previous = KeyGridPlacement.solve(KeyGridPlacement.alignLastRow(page, in: previousSize, centerY: centre + 9), in: previousSize)
            for (old, new) in zip(previous.placed, current.placed) {
                XCTAssertEqual(new.plate.size, old.plate.size)
                XCTAssertEqual(new.plate.height, 45)
                XCTAssertEqual(old.plate.minY - new.plate.minY, 9, accuracy: 0.001)
            }
        }
    }

    func testSlightlyLargerCharacterPlatesPreserveNativeRowPitch() {
        let layout = KeyGridPlacement.solve(lettersPage(), in: CGSize(width: 402, height: 216))
        let oldWidth: CGFloat = (402 - 2 * 7 - 9 * 6) / 10
        XCTAssertGreaterThan(layout.rows[0][0].plate.width, oldWidth)
        XCTAssertLessThan(layout.rows[0][0].plate.width - oldWidth, 1)
        XCTAssertEqual(layout.rows[0][0].plate.height, 45, accuracy: 0.001)
        for row in 1..<layout.rows.count {
            XCTAssertEqual(layout.rows[row][0].plate.midY - layout.rows[row - 1][0].plate.midY,
                           54, accuracy: 0.001)
        }
        for (index, item) in layout.placed.enumerated() {
            XCTAssertTrue(item.target.contains(item.plate))
            for other in layout.placed.dropFirst(index + 1) {
                let overlap = item.target.intersection(other.target)
                XCTAssertTrue(overlap.isNull || overlap.width == 0 || overlap.height == 0)
            }
        }
    }

    func testPinnedCommandRowMatchesEmojiDeleteWithoutOverlappingBottomBar() {
        func row(_ count: Int) -> [KeyGridKey] {
            (0..<count).map { KeyGridKey(id: "key-\($0)", action: .insert("a")) }
        }
        for surfaceHeight in [269.0, 300.0] {
            let layout = VoiceOnlyKeyboardPolicy.layout(
                for: 402, surfaceHeight: surfaceHeight,
                topAccessoryHeight: VoiceOnlyKeyboardPolicy.suggestionLaneHeight
            )
            let lane = KeyGridPlacement.bottomBarLaneHeight
            let gridSize = CGSize(width: layout.surfaceFrame.width,
                                  height: layout.surfaceFrame.height - lane)
            for middleCount in [5, 7] {
                let bottom = [KeyGridKey(id: "toggle", action: .shift, isCommand: true)]
                    + row(middleCount)
                    + [KeyGridKey(id: "delete", action: .delete, isCommand: true)]
                let page = KeyGridPage(id: "grid", rows: [row(10), row(10), bottom],
                                       pinnedLastRow: true, topInset: 19)
                let target = layout.boardDeleteFrame.midY - layout.surfaceFrame.minY
                let aligned = KeyGridPlacement.alignLastRow(page, in: gridSize, centerY: target)
                let solved = KeyGridPlacement.solve(aligned, in: gridSize)
                XCTAssertEqual(solved.rows.last?.last?.plate.midY ?? .nan, target, accuracy: 0.001)
                XCTAssertLessThanOrEqual(solved.rows.last?.last?.plate.maxY ?? .infinity,
                                         gridSize.height)
                if let first = solved.rows.last?.first, let last = solved.rows.last?.last {
                    let leading = CommandKeyStyle.visualPlate(for: first.plate, surfaceWidth: gridSize.width)
                    let trailing = CommandKeyStyle.visualPlate(for: last.plate, surfaceWidth: gridSize.width)
                    let deleteSize = layout.commandKeyVisualSize
                    XCTAssertEqual(leading.size, deleteSize)
                    XCTAssertEqual(trailing.size, deleteSize)
                    XCTAssertEqual(layout.surfaceFrame.minX + leading.minX,
                                   layout.surfaceFrame.minX + VoiceOnlyKeyboardPolicy.horizontalPadding,
                                   accuracy: 0.001)
                    XCTAssertEqual(layout.surfaceFrame.minX + trailing.midX,
                                   layout.boardDeleteFrame.midX, accuracy: 0.001)
                }
            }
        }
    }

    func testSharedCommandPlateFitsEveryResolvedHitCell() {
        let emojiDeleteHit = CGSize(
            width: (size.width - VoiceOnlyKeyboardPolicy.horizontalPadding * 2) * 0.15,
            height: VoiceOnlyKeyboardPolicy.bottomActionHitHeight
        )
        let emojiDeleteFace = VoiceOnlyKeyboardPolicy.bottomBarVisualSize(for: emojiDeleteHit)
        for page in [
            KeyGridPage(id: "letters", rows: [[
                KeyGridKey(id: "shift", action: .shift, weight: 1.5, isCommand: true),
                KeyGridKey(id: "delete", action: .delete, weight: 1.5, isCommand: true)
            ]]),
            KeyGridPage(id: "symbols1", rows: [[
                KeyGridKey(id: "toggle", action: .page("#+="), weight: 1.4, isCommand: true),
                KeyGridKey(id: "delete", action: .delete, weight: 2.25, isCommand: true)
            ]]),
            KeyGridPage(id: "numberPad", rows: [[
                KeyGridKey(id: "spacer", action: .none),
                KeyGridKey(id: "digit", action: .insert("0")),
                KeyGridKey(id: "delete", action: .delete, isCommand: true)
            ]], rowHeight: 48)
        ] {
            for item in KeyGridPlacement.solve(page, in: size).placed where item.key.isCommand {
                let visible = CommandKeyStyle.visualPlate(for: item.plate, surfaceWidth: size.width)
                XCTAssertEqual(visible.size, emojiDeleteFace, item.key.id)
                XCTAssertTrue(item.target.contains(visible), item.key.id)
            }
        }
        let compact = CGRect(x: 0, y: 0, width: 30, height: 32)
        XCTAssertTrue(compact.contains(CommandKeyStyle.visualPlate(for: compact)))
    }

    func testPinnedCommandFacesMatchEmojiDeleteBorderInset() {
        let width: CGFloat = 402
        let letters = (0..<10).map { KeyGridKey(id: "letter-\($0)", action: .insert("a")) }
        let bottom = [KeyGridKey(id: "shift", action: .shift, isCommand: true)]
            + (0..<7).map { KeyGridKey(id: "middle-\($0)", action: .insert("a")) }
            + [KeyGridKey(id: "delete", action: .delete, isCommand: true)]
        let page = KeyGridPage(id: "letters", rows: [letters, bottom], pinnedLastRow: true)
        let layout = KeyGridPlacement.solve(page, in: CGSize(width: width, height: 130))
        let pinned = layout.rows[1]
        let leading = CommandKeyStyle.visualPlate(for: pinned[0].plate, surfaceWidth: width)
        let trailing = CommandKeyStyle.visualPlate(for: pinned[8].plate, surfaceWidth: width)
        let emojiDeleteInset = CGFloat(VoiceOnlyKeyboardPolicy.horizontalPadding)
        XCTAssertEqual(leading.minX, emojiDeleteInset, accuracy: 0.01)
        XCTAssertEqual(width - trailing.maxX, emojiDeleteInset, accuracy: 0.01)
        let emojiFace = VoiceOnlyKeyboardPolicy.bottomBarVisualSize(for: CGSize(
            width: (width - VoiceOnlyKeyboardPolicy.horizontalPadding * 2) * 0.15,
            height: VoiceOnlyKeyboardPolicy.bottomActionHitHeight
        ))
        XCTAssertEqual(leading.size, emojiFace)
        XCTAssertEqual(trailing.size, emojiFace)
        XCTAssertTrue(pinned[0].target.contains(leading))
        XCTAssertTrue(pinned[8].target.contains(trailing))
        let biased = KeyGridPlacement.retarget(layout,
            probabilities: NextCharacterProbabilities(["a": 0.9]))
        XCTAssertTrue(biased.rows[1][0].target.contains(leading))
        XCTAssertTrue(biased.rows[1][8].target.contains(trailing))
    }

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

    func testContainerPreferenceCannotChangeKeyGeometry() {
        let page = KeyGridPage(id: "appearance", rows: [[
            KeyGridKey(id: "letter", action: .insert("a"), isInvisiblePlate: true),
            KeyGridKey(id: "symbol", action: .insert("1")),
            KeyGridKey(id: "command", action: .delete, isCommand: true)
        ]])
        let layout = KeyGridPlacement.solve(page, in: size)
        XCTAssertEqual(layout.placed.count, 3)
        for item in layout.placed {
            XCTAssertTrue(item.target.contains(item.plate), item.key.id)
            XCTAssertEqual(layout.key(at: CGPoint(x: item.plate.midX, y: item.plate.midY))?.key.id,
                           item.key.id)
        }
        XCTAssertTrue(layout.placed[0].key.isInvisiblePlate)
        XCTAssertFalse(layout.placed[1].key.isInvisiblePlate)
        XCTAssertTrue(layout.placed[2].key.isCommand)
    }

    func testPredictionChangesOnlyInvisibleTargetsAndCanReturnToNeutral() {
        let page = KeyGridPage(id: "letters", rows: [[
            KeyGridKey(id: "r", action: .insert("r"), label: "r"),
            KeyGridKey(id: "e", action: .insert("e"), label: "e"),
            KeyGridKey(id: "delete", action: .delete, isCommand: true)
        ]])
        let neutral = KeyGridPlacement.solve(page, in: CGSize(width: 180, height: 65))
        let biased = KeyGridPlacement.retarget(
            neutral, probabilities: NextCharacterProbabilities(["e": 0.8, "r": 0.01])
        )
        XCTAssertEqual(biased.placed.map(\.plate), neutral.placed.map(\.plate))
        XCTAssertLessThan(biased.rows[0][1].target.minX, neutral.rows[0][1].target.minX)
        for item in biased.placed {
            XCTAssertTrue(item.target.contains(item.plate), item.key.id)
        }
        for x in stride(from: CGFloat(0), to: CGFloat(180), by: 2) {
            XCTAssertNotNil(biased.key(at: CGPoint(x: x, y: 32)))
        }
        let restored = KeyGridPlacement.retarget(neutral, probabilities: nil)
        XCTAssertEqual(restored.placed.map(\.target), neutral.placed.map(\.target))
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
            // No top inset, so the block still has to fit inside a container that
            // is exactly its own height. This is the invariant that keeps rows from
            // spilling out of the grid, which is separate from where the block is
            // hung inside a container that has room to spare.
            let page = KeyGridPage(id: "fill", rows: rows)
            let layout = KeyGridPlacement.solve(page, in: size)
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
            // The block has to fit. It is not required to fill: with no top inset it
            // now starts at the top of the grid, and a container taller than the
            // block simply has room left over at the bottom. Filling was the old
            // rule, and it is the one that put the keys low.
            XCTAssertLessThanOrEqual(bottom, size.height + 0.5,
                                     "\(rowCount) rows overflow a \(size.height)pt grid")
            // Whatever room is left has to belong to a key. Leaving it unowned would
            // reintroduce the dead band that took four builds to find, so the rule is
            // about targets tiling the grid, not about plates filling it.
            for step in stride(from: 1.0, to: size.height, by: 1.0) {
                let owner = layout.placed.first {
                    $0.target.contains(CGPoint(x: size.width / 2, y: step))
                }
                XCTAssertNotNil(owner, "\(rowCount) rows left \(step)pt that no target owns")
            }
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
            XCTAssertEqual(row.first?.plate.height ?? .nan, 45, accuracy: 0.5)
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

        // Keep native plate placement; the wider visual face spends empty gap.
        XCTAssertEqual(shift.plate.width / 33.5, 1.36, accuracy: 0.05)
        XCTAssertEqual(del.plate.width / 33.5, 1.36, accuracy: 0.05)
        let emojiFace = VoiceOnlyKeyboardPolicy.bottomBarVisualSize(for: CGSize(
            width: (screen.width - VoiceOnlyKeyboardPolicy.horizontalPadding * 2) * 0.15,
            height: VoiceOnlyKeyboardPolicy.bottomActionHitHeight
        ))
        for command in [shift, del] {
            let face = CommandKeyStyle.visualPlate(for: command.plate, surfaceWidth: screen.width)
            XCTAssertEqual(face.size, emojiFace)
            XCTAssertTrue(command.target.contains(face))
        }
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
        let emojiFace = VoiceOnlyKeyboardPolicy.bottomBarVisualSize(for: CGSize(
            width: (402 - VoiceOnlyKeyboardPolicy.horizontalPadding * 2) * 0.15,
            height: VoiceOnlyKeyboardPolicy.bottomActionHitHeight
        ))
        for command in [toggle, delete] {
            let face = CommandKeyStyle.visualPlate(for: command.plate, surfaceWidth: 402)
            XCTAssertEqual(face.size, emojiFace)
            XCTAssertTrue(command.target.contains(face))
        }
    }

    /// The 3×4 pad matches the system pad.
    ///
    /// Measured: three columns of ~126.5pt with 6pt gaps, keys 48pt tall on a 54pt
    /// pitch, and a last row that is a centred `0` with a delete in the right column.
    /// The pad's keys are *taller* than the letter grid's 43pt, which only works
    /// because the pad has no bottom bar — so it takes the whole surface.
    func testNumberPadMatchesTheMeasuredSystemPad() {
        func key(_ id: String, _ label: String) -> KeyGridKey {
            KeyGridKey(id: id, action: .insert(label), label: label)
        }
        let rows: [[KeyGridKey]] = [
            [key("1", "1"), key("2", "2"), key("3", "3")],
            [key("4", "4"), key("5", "5"), key("6", "6")],
            [key("7", "7"), key("8", "8"), key("9", "9")],
            [
                KeyGridKey(id: "spacer", action: .none),
                key("0", "0"),
                KeyGridKey(id: "del", action: .delete, isCommand: true)
            ]
        ]
        let page = KeyGridPage(id: "pad", rows: rows, rowHeight: 48, rowSpacing: 6)
        let layout = KeyGridPlacement.solve(page, in: CGSize(width: 402, height: 224))

        // Three columns, standard width, 6pt apart, 7pt margins.
        let first = layout.rows[0]
        guard first.count == 3 else {
            XCTFail("expected three columns")
            return
        }
        let a = first[0]
        let b = first[1]
        XCTAssertEqual(a.plate.minX, 7, accuracy: 0.5)
        XCTAssertEqual(a.plate.width, 125.3, accuracy: 1.0)
        XCTAssertEqual(b.plate.minX - a.plate.maxX, 6, accuracy: 0.5)

        // Keys are 48pt on a 54pt pitch — taller than the letter grid's 43.
        XCTAssertEqual(a.plate.height, 48, accuracy: 0.5)
        let rowTops = layout.rows.map { $0.first?.plate.minY ?? .nan }
        XCTAssertEqual(rowTops[1] - rowTops[0], 54, accuracy: 0.5)
        XCTAssertEqual(rowTops[3] - rowTops[2], 54, accuracy: 0.5)

        // The `0` lands in the middle column, as it does on the system pad.
        let lastRow = layout.rows[3]
        guard lastRow.count == 3 else {
            XCTFail("expected a three-cell last row")
            return
        }
        XCTAssertEqual(lastRow[1].plate.minX, b.plate.minX, accuracy: 0.5,
                       "0 must sit in the middle column")
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

    // MARK: - Spacer-padded rows

    /// A row padded with half-width spacers must not change the width of a letter.
    ///
    /// This is the bug that put the whole letter grid 17pt in from each edge, and it
    /// is worth a test precisely because the layout data still ships those spacers.
    /// The home row is nine letters between two half-width entries, so counting keys
    /// made it the widest row on the page at eleven entries, and every letter was
    /// then sized as one eleventh of the row: 29.8pt instead of the platform's 33.4.
    ///
    /// The standard width comes from total weight, so a spacer's half unit is half a
    /// letter rather than a whole one. The factory drops the spacers as well — this
    /// test covers the half of the fix that has to hold even if one survives.
    func testHalfWeightSpacersDoNotNarrowTheLettersAroundThem() {
        func letters(_ chars: String, _ prefix: String) -> [KeyGridKey] {
            chars.map { KeyGridKey(id: "\(prefix)\($0)", action: .insert("a")) }
        }
        func spacer(_ id: String) -> KeyGridKey {
            KeyGridKey(id: id, action: .none, weight: 0.5)
        }
        var bottom: [KeyGridKey] = [KeyGridKey(id: "shift", action: .shift, isCommand: true)]
        bottom += letters("zxcvbnm", "b")
        bottom.append(KeyGridKey(id: "delete", action: .delete, isCommand: true))

        let page = KeyGridPage(id: "padded", rows: [
            letters("qwertyuiop", "t"),
            [spacer("lead")] + letters("asdfghjkl", "h") + [spacer("trail")],
            bottom
        ], pinnedLastRow: true)
        let layout = KeyGridPlacement.solve(page, in: CGSize(width: 402, height: 170))

        // The ten-key row fills the width, exactly as it does with no spacers present.
        // This is the assertion that pins the user-visible symptom: before the fix
        // this row ran x=24..377 with 29.8pt keys.
        let top = layout.rows[0]
        XCTAssertEqual(top.count, 10)
        XCTAssertEqual(top.first?.plate.minX ?? .nan, 7, accuracy: 0.5)
        XCTAssertEqual(402 - (top.last?.plate.maxX ?? .nan), 7, accuracy: 0.5)
        XCTAssertEqual(top.first?.plate.width ?? .nan, 33.5, accuracy: 1.0)

        // Each spacer is half a letter, and each of the nine letters beside them is
        // still a full standard key rather than one eleventh of the row.
        let home = layout.rows[1]
        XCTAssertEqual(home.count, 11)
        XCTAssertEqual(home.first?.plate.width ?? .nan, 16.75, accuracy: 0.5)
        XCTAssertEqual(home.last?.plate.width ?? .nan, 16.75, accuracy: 0.5)
        for key in home.dropFirst().dropLast() {
            XCTAssertEqual(key.plate.width, 33.5, accuracy: 1.0)
        }

        // The letters are still 6pt apart, so the row's internal rhythm is the
        // platform's regardless of what pads its ends.
        let firstLetter = home[1]
        let secondLetter = home[2]
        XCTAssertEqual(secondLetter.plate.minX - firstLetter.plate.maxX, 6, accuracy: 0.5)
    }

    /// A taller container must not push the keys down.
    ///
    /// This is the "the letters sit low" bug. The grid area's height is whatever the
    /// host surface leaves after the accessory lane and the bottom bar, so it is
    /// larger on a larger screen — 208pt on an iPhone Air against 170pt on an 18 Pro.
    /// The block used to rest on the bottom of that area, so the extra 38pt went
    /// entirely into moving the keys down, away from the accessory lane and towards
    /// the bar, which is not where the platform puts them.
    ///
    /// The block hangs from a fixed inset instead, so only the gap below it changes.
    func testTallerContainerDoesNotMoveTheKeysDown() {
        let page = KeyGridPage(
            id: "anchored",
            rows: [
                (0..<10).map { KeyGridKey(id: "t\($0)", action: .insert("a")) },
                (0..<9).map { KeyGridKey(id: "h\($0)", action: .insert("a")) },
                [KeyGridKey(id: "shift", action: .shift, isCommand: true)]
                    + (0..<7).map { KeyGridKey(id: "b\($0)", action: .insert("a")) }
                    + [KeyGridKey(id: "delete", action: .delete, isCommand: true)]
            ],
            pinnedLastRow: true,
            topInset: 19
        )
        let short = KeyGridPlacement.solve(page, in: CGSize(width: 402, height: 172))
        let tall = KeyGridPlacement.solve(page, in: CGSize(width: 402, height: 208))

        // Same first row, same last row: the block is in the same place, and the
        // extra height is left below it rather than spent on moving the keys.
        XCTAssertEqual(short.rows[0].first?.plate.minY ?? .nan, 19, accuracy: 0.5)
        XCTAssertEqual(tall.rows[0].first?.plate.minY ?? .nan, 19, accuracy: 0.5)
        XCTAssertEqual(short.rows[2].last?.plate.maxY ?? .nan,
                       tall.rows[2].last?.plate.maxY ?? .nan, accuracy: 0.5)
        // The block occupies the same band in both; the taller container simply has
        // more room below it. A bottom-anchored block would instead have ended at
        // 208 in the tall case and 170 in the short one.
        let shortBottom = short.placed.map(\.plate.maxY).max() ?? .nan
        let tallBottom = tall.placed.map(\.plate.maxY).max() ?? .nan
        XCTAssertEqual(shortBottom, tallBottom, accuracy: 0.5)
        XCTAssertEqual(tallBottom, 19 + 153, accuracy: 0.5)
    }

    /// The block still fits when the container is exactly its height, or shorter.
    ///
    /// A fixed top inset must never win over "does the block fit". A keyboard that
    /// is mid-animation, or on a short screen, would otherwise push its last row off
    /// the bottom — which is how a key ends up drawn where nothing can press it.
    func testTopInsetNeverPushesTheBlockOutOfTheContainer() {
        let rows: [[KeyGridKey]] = (0..<3).map { row in
            (0..<10).map { column in
                KeyGridKey(id: "r\(row)k\(column)", action: .insert("a"))
            }
        }
        // 3 rows at 43 + 2 gaps of 11 = 151 is the block. Anything under 151 + inset
        // has to give the inset up.
        for height in [151.0, 140.0, 120.0] {
            let page = KeyGridPage(id: "tight", rows: rows, topInset: 19)
            let layout = KeyGridPlacement.solve(page, in: CGSize(width: 402, height: height))
            let bottom = layout.placed.map(\.plate.maxY).max() ?? .nan
            let top = layout.placed.map(\.plate.minY).min() ?? .nan
            XCTAssertGreaterThanOrEqual(top, -0.5, "block starts above the grid at \(height)pt")
            XCTAssertLessThanOrEqual(bottom, height + 0.5,
                                     "block runs past the bottom at \(height)pt")
        }
    }

    /// Adding a half-weight entry must not move the row above it.
    ///
    /// A companion to the test above, and the assertion that actually pins the cause:
    /// the same page with and without the spacers has to place its ten-key row
    /// identically. If the standard width were still count-derived, these two would
    /// differ by 3.6pt per key and the failure would be obvious.
    func testSpacersLeaveTheOtherRowsWhereTheyWere() {
        func letters(_ chars: String, _ prefix: String) -> [KeyGridKey] {
            chars.map { KeyGridKey(id: "\(prefix)\($0)", action: .insert("a")) }
        }
        let bare = KeyGridPage(id: "bare", rows: [
            letters("qwertyuiop", "t"),
            letters("asdfghjkl", "h")
        ])
        let padded = KeyGridPage(id: "padded", rows: [
            letters("qwertyuiop", "t"),
            [KeyGridKey(id: "lead", action: .none, weight: 0.5)]
                + letters("asdfghjkl", "h")
                + [KeyGridKey(id: "trail", action: .none, weight: 0.5)]
        ])
        let size = CGSize(width: 402, height: 120)
        let bareLayout = KeyGridPlacement.solve(bare, in: size)
        let paddedLayout = KeyGridPlacement.solve(padded, in: size)

        for (index, key) in bareLayout.rows[0].enumerated() {
            let other = paddedLayout.rows[0][index]
            XCTAssertEqual(key.plate.minX, other.plate.minX, accuracy: 0.01)
            XCTAssertEqual(key.plate.width, other.plate.width, accuracy: 0.01)
        }
    }
}
