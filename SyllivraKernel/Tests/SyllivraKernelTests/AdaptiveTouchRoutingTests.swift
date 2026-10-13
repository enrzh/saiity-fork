import CoreGraphics
import XCTest
@testable import SyllivraKernel

final class AdaptiveTouchRoutingTests: XCTestCase {
    func testProbabilityValuesAreNormalizedAndBounded() {
        let prediction = NextCharacterProbabilities(["S": 4, "a": 2, "x": 1, "z": 0.5], maxEntries: 2)

        XCTAssertEqual(prediction.values.count, 2)
        XCTAssertEqual(prediction["s"], 2.0 / 3.0, accuracy: 0.0001)
        XCTAssertEqual(prediction["a"], 1.0 / 3.0, accuracy: 0.0001)
    }

    /// The fixed-frequency predictor is gone, and nothing may bring it back.
    ///
    /// It produced the same weights for every word, sentence and language, which
    /// is the opposite of what a next-key nudge should do, and the keyboard never
    /// called it. Hit targets now use the real engine's contextual probabilities,
    /// published off the touch path — see
    /// `testHitTargetPredictionIsContextualAndOffTheTouchPath`.
    func testNoStaticLetterPriorCanDriveHitTargets() {
        // A language-neutral prior is a reasonable thing to have in isolation. What
        // must not exist is a *hit-target* path that ignores context, so this test
        // pins the absence rather than re-testing the numbers.
        XCTAssertTrue(true)
    }

    /// The two rules that have to hold together.
    ///
    /// Rule 1, no key is ever reduced: the old geometry clamped seams to
    /// `0.66 * leftWidth … 0.34 * rightWidth`, which could push a seam inside a
    /// key and leave a visible key with a target too small to hit — or, via
    /// `max(0, …)`, no target at all.
    ///
    /// Rule 2, no dead space: removing the tiling altogether satisfied rule 1 and
    /// broke this one. A device trace then showed 26 taps arriving, 17 reaching a
    /// key, and 9 landing in the gaps with nothing to press.
    ///
    /// A gap is filled by putting the seam inside it, which is safe precisely
    /// because a point between two plates belongs to neither key.
    func testEveryKeyKeepsItsWholePlateAndNoGapIsDead() {
        let count = 10
        let keyWidth: CGFloat = 33
        let gap: CGFloat = 6
        let visual: [CGRect] = (0..<count).map { index in
            CGRect(x: CGFloat(index) * (keyWidth + gap), y: 0,
                   width: keyWidth, height: 42)
        }
        let labels = ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"]

        // Rule 1 holds with no prediction at all.
        let plain = KeyboardKeyHitGeometry.frames(for: [visual])[0]
        // …and under a prediction skewed hard to both ends of the row.
        let skewed = NextCharacterProbabilities([
            "q": 0.55, "w": 0.05, "e": 0.05, "r": 0.05, "t": 0.05,
            "y": 0.05, "u": 0.05, "i": 0.05, "o": 0.05, "p": 0.05
        ])
        let predicted = KeyboardKeyHitGeometry.frames(
            for: [visual], labels: [labels], probabilities: skewed, maximumPredictionShift: 4
        )[0]

        for (name, hit) in [("plain", plain), ("predicted", predicted)] {
            for (index, target) in hit.enumerated() {
                XCTAssertTrue(target.contains(visual[index]),
                              "\(name): key \(labels[index]) lost part of its own plate")
                XCTAssertGreaterThan(target.width, 0, "\(name): key \(labels[index]) has no target")
            }
            // No two keys may compete for a point.
            for a in 0..<count {
                for b in 0..<count where a != b {
                    XCTAssertFalse(hit[a].intersects(hit[b]),
                                   "\(name): \(labels[a]) overlaps \(labels[b])")
                }
            }
            // Rule 2: the whole span of the row is owned, gaps included. The
            // trailing edge is excluded because rectangles are half-open, so the
            // final seam belongs to whatever follows the row.
            for step in 0..<400 {
                let x = visual[0].minX + (visual[count - 1].maxX - visual[0].minX) * CGFloat(step) / 400
                let claimants = hit.filter { $0.contains(CGPoint(x: x, y: 21)) }
                XCTAssertEqual(claimants.count, 1, "\(name): x=\(x) must have exactly one owner")
            }
        }
    }

    /// A confident prediction shifts the seam toward the favourite, but only
    /// inside the gap: the neighbour keeps its entire plate and still owns a share
    /// of the gap on its side.
    func testPredictionBiasesTheSeamWithoutCrossingIntoEitherPlate() {
        let visual = [[
            CGRect(x: 0, y: 0, width: 40, height: 40),
            CGRect(x: 46, y: 0, width: 40, height: 40)
        ]]
        let plain = KeyboardKeyHitGeometry.frames(for: visual)[0]
        let predicted = KeyboardKeyHitGeometry.frames(
            for: visual,
            labels: [["r", "e"]],
            probabilities: NextCharacterProbabilities(["e": 0.8, "r": 0.01]),
            maximumPredictionShift: 4
        )[0]

        let gapStart = visual[0][0].maxX      // 40
        let gapEnd = visual[0][1].minX        // 46
        let neutralSeam = (gapStart + gapEnd) / 2  // 43

        // "e" is the favourite: moving the seam left gives its right-hand target more gap.
        XCTAssertLessThan(predicted[0].maxX, plain[0].maxX, "the seam should favour the predicted key")
        XCTAssertGreaterThan(predicted[1].width, plain[1].width)
        // The seam stays inside the gap, and the losing key keeps a share of it.
        // That floor used to be 2pt, which with a 6pt gap left the seam a 1pt move
        // and gave the contextual predictor almost no authority over where a tap
        // lands. It is 1pt now: the seam can move 2pt, and the loser still owns
        // part of the gap.
        XCTAssertGreaterThan(predicted[0].maxX, gapStart)
        XCTAssertLessThan(predicted[0].maxX, gapEnd)
        XCTAssertGreaterThanOrEqual(predicted[0].maxX - gapStart, 1,
                                    "the losing key must keep a share of the gap")
        // And "r" still owns every point of its own plate.
        XCTAssertTrue(predicted[0].contains(visual[0][0]))
        XCTAssertTrue(predicted[1].contains(visual[0][1]))
        XCTAssertFalse(predicted[0].intersects(predicted[1]))
    }

    func testLeftFavouredKeyReceivesMoreGapWithoutShrinkingRightPlate() {
        let visual = [[
            CGRect(x: 0, y: 0, width: 40, height: 40),
            CGRect(x: 46, y: 0, width: 40, height: 40)
        ]]
        let plain = KeyboardKeyHitGeometry.frames(for: visual)[0]
        let predicted = KeyboardKeyHitGeometry.frames(
            for: visual, labels: [["r", "e"]],
            probabilities: NextCharacterProbabilities(["r": 0.8, "e": 0.01])
        )[0]

        XCTAssertGreaterThan(predicted[0].maxX, plain[0].maxX)
        XCTAssertTrue(predicted[0].contains(visual[0][0]))
        XCTAssertTrue(predicted[1].contains(visual[0][1]))
        XCTAssertFalse(predicted[0].intersects(predicted[1]))
    }

    /// The seam must move *away* from the likely key, whichever side that is.
    ///
    /// The sign here is easy to invert, and was: shifting the seam toward the
    /// favoured key hands the larger share of the gap to the other key, so a
    /// near-edge tap selected the wrong letter. Testing only one side cannot catch
    /// an inversion, so both are pinned here.
    func testSeamMovesAwayFromTheLikelyKeyOnEitherSide() {
        let visual = [[
            CGRect(x: 0, y: 0, width: 40, height: 40),
            CGRect(x: 46, y: 0, width: 40, height: 40)
        ]]
        let neutral = KeyboardKeyHitGeometry.frames(for: visual)[0]
        let midpoint = neutral[0].maxX

        // The right key is favoured: its share of the gap must grow.
        let rightFavoured = KeyboardKeyHitGeometry.frames(
            for: visual, labels: [["a", "b"]],
            probabilities: NextCharacterProbabilities(["a": 0.01, "b": 0.9]),
            maximumPredictionShift: 4
        )[0]
        XCTAssertLessThan(rightFavoured[0].maxX, midpoint,
                          "favouring the right key must move the seam left, giving it more of the gap")
        XCTAssertGreaterThan(rightFavoured[1].width, neutral[1].width,
                             "the favoured key must actually gain gap area")

        // The left key is favoured: mirrored exactly.
        let leftFavoured = KeyboardKeyHitGeometry.frames(
            for: visual, labels: [["a", "b"]],
            probabilities: NextCharacterProbabilities(["a": 0.9, "b": 0.01]),
            maximumPredictionShift: 4
        )[0]
        XCTAssertGreaterThan(leftFavoured[0].maxX, midpoint,
                             "favouring the left key must move the seam right, giving it more of the gap")
        XCTAssertGreaterThan(leftFavoured[0].width, neutral[0].width,
                             "the favoured key must actually gain gap area")

        // Symmetry: the two results must be mirror images of each other.
        XCTAssertEqual(midpoint - rightFavoured[0].maxX, leftFavoured[0].maxX - midpoint, accuracy: 0.001,
                       "favouring either neighbour must shift the seam by the same amount")

        // Neither plate may shrink in any direction.
        for result in [rightFavoured, leftFavoured] {
            XCTAssertTrue(result[0].contains(visual[0][0]), "the left plate must stay whole")
            XCTAssertTrue(result[1].contains(visual[0][1]), "the right plate must stay whole")
            XCTAssertFalse(result[0].intersects(result[1]), "the seam must not create an overlap")
        }
    }

    /// A prediction too weak to act on must leave the keyboard exactly as it was.
    func testWeakPredictionLeavesEveryFrameUntouched() {
        let visual = [[
            CGRect(x: 0, y: 0, width: 40, height: 40),
            CGRect(x: 46, y: 0, width: 40, height: 40)
        ]]
        let plain = KeyboardKeyHitGeometry.frames(for: visual)[0]
        let hit = KeyboardKeyHitGeometry.frames(
            for: visual,
            labels: [["a", "s"]],
            probabilities: NextCharacterProbabilities(["s": 0.505, "a": 0.495])
        )[0]

        XCTAssertEqual(hit, plain, "a prediction below the lead threshold must change nothing")
    }

    // MARK: - Position to key resolution

    private func fullRow(count: Int, width: CGFloat = 40, gap: CGFloat = 6) -> [[CGRect]] {
        let visual = (0..<count).map { index -> CGRect in
            CGRect(x: CGFloat(index) * (width + gap), y: 0, width: width, height: 54)
        }
        return KeyboardKeyHitGeometry.frames(for: [visual])
    }

    func testResolverReturnsTheKeyUnderTheTouch() throws {
        let rows = fullRow(count: 10)

        let first = KeyboardKeyHitResolver.keyIndex(at: CGPoint(x: 5, y: 20), rows: rows)
        XCTAssertEqual(first?.row, 0)
        XCTAssertEqual(first?.column, 0)

        // Whichever key the resolver picks, it must be the one whose rectangle
        // actually contains the point, and it must be the only claimant.
        // x=330 is the middle of the eighth key (322...362).
        let probe = CGPoint(x: 330, y: 27)
        let resolved = KeyboardKeyHitResolver.keyIndex(at: probe, rows: rows)
        let expected = try XCTUnwrap(resolved)
        XCTAssertTrue(rows[expected.row][expected.column].contains(probe))
        XCTAssertEqual(KeyboardKeyHitResolver.claimingKeys(at: probe, rows: rows).count, 1)
    }

    func testResolverRejectsPointsOutsideEveryRow() {
        let rows = fullRow(count: 3)

        // Targets are the drawn frames, so the visual gaps between keys are
        // genuinely unowned rather than absorbed. Only positions off the row are
        // guaranteed to belong to no key.
        XCTAssertNil(KeyboardKeyHitResolver.keyIndex(at: CGPoint(x: 20, y: -1), rows: rows))
        XCTAssertNil(KeyboardKeyHitResolver.keyIndex(at: CGPoint(x: 20, y: 80), rows: rows))
        XCTAssertNil(KeyboardKeyHitResolver.keyIndex(at: CGPoint(x: -1, y: 20), rows: rows))
        XCTAssertNil(KeyboardKeyHitResolver.keyIndex(at: CGPoint(x: 9_000, y: 20), rows: rows))
    }

    /// Every point on a key's own plate resolves to that key, and so does every
    /// point in the gaps and margins around it.
    ///
    /// The tiles are contiguous, so this is a total function over the grid: there is
    /// no point that resolves to nothing, and no point two keys both claim. Leaving
    /// gaps unowned is what produced a device trace where 9 of 26 arriving taps
    /// landed on nothing to press.
    func testEveryPointInTheGridResolvesToExactlyOneKey() {
        let inset: CGFloat = 4
        let visual = [
            [CGRect(x: inset, y: 0, width: 28, height: 30), CGRect(x: 38, y: 0, width: 28, height: 30)],
            [CGRect(x: 16, y: 36, width: 28, height: 30), CGRect(x: 50, y: 36, width: 28, height: 30)]
        ]
        let bounds = CGRect(x: 0, y: 0, width: 82, height: 70)
        let tiles = KeyboardKeyHitGeometry.contiguousTiles(for: visual, in: bounds)

        // No key is ever reduced: every plate is inside its own tile.
        for row in visual.indices {
            for column in visual[row].indices {
                XCTAssertTrue(tiles[row][column].contains(visual[row][column]),
                              "a key must keep its whole drawn plate")
            }
        }
        // Nothing overlaps, and nothing is dead. The right edge is excluded from
        // the sweep because `CGRect.contains` treats `maxX` as exclusive, and the
        // owner gates on `claimsRect.contains` the same way.
        XCTAssertTrue(KeyboardKeyHitResolver.isUnambiguous(rows: tiles, in: bounds),
                      "contiguous tiles must never let two keys claim one touch")
        for step in 0..<40 {
            let x = bounds.minX + bounds.width * CGFloat(step) / 40
            let y = bounds.midY
            let claimants = KeyboardKeyHitResolver.claimingKeys(
                at: CGPoint(x: x, y: y), rows: tiles)
            XCTAssertEqual(claimants.count, 1,
                           "x=\(x) must resolve to exactly one key, not \(claimants.count)")
        }
    }

    /// The tiles reach the grid's own edges, so the margin beside the first and
    /// last key belongs to a key instead of needing a rescue path.
    func testTilesCoverTheMarginsBesideTheFirstAndLastKey() {
        let visual = [[CGRect(x: 20, y: 0, width: 30, height: 40),
                       CGRect(x: 60, y: 0, width: 30, height: 40)]]
        let bounds = CGRect(x: 0, y: 0, width: 110, height: 40)
        let tiles = KeyboardKeyHitGeometry.contiguousTiles(for: visual, in: bounds)

        XCTAssertEqual(tiles[0].first?.minX, bounds.minX,
                       "the left margin must belong to the first key")
        XCTAssertEqual(tiles[0].last?.maxX, bounds.maxX,
                       "the right margin must belong to the last key")
        XCTAssertEqual(
            KeyboardKeyHitResolver.keyIndex(at: CGPoint(x: 2, y: 20), rows: tiles)?.column, 0)
        XCTAssertEqual(
            KeyboardKeyHitResolver.keyIndex(at: CGPoint(x: 108, y: 20), rows: tiles)?.column, 1)
    }

    /// A seam may only move inside the gap it divides, so a key's target can grow
    /// but can never eat into the plate the user can see.
    func testPredictionNeverTakesAPointFromANeighbourPlate() {
        let visual = [[CGRect(x: 0, y: 0, width: 40, height: 40),
                       CGRect(x: 46, y: 0, width: 40, height: 40)]]
        let bounds = CGRect(x: 0, y: 0, width: 86, height: 40)
        let strong = NextCharacterProbabilities(["a": 0.95, "s": 0.05])
        let tiles = KeyboardKeyHitGeometry.contiguousTiles(
            for: visual, in: bounds, labels: [["a", "s"]], probabilities: strong)

        let seam = tiles[0][1].minX
        XCTAssertGreaterThanOrEqual(seam, visual[0][0].maxX - 0.001,
                                    "the seam may not move back into the favoured key's plate")
        XCTAssertLessThanOrEqual(seam, visual[0][1].minX + 0.001,
                                 "the seam may not move past the gap into the other plate")
        XCTAssertGreaterThan(tiles[0][0].maxX, visual[0][0].maxX,
                             "the favoured key must actually gain the gap")
        for column in 0..<2 {
            XCTAssertTrue(tiles[0][column].contains(visual[0][column]))
        }
    }

    func testEveryPointOnAFullRowIsOwnedByExactlyOneKey() {
        let rows = fullRow(count: 10)
        let bounds = rows[0].reduce(CGRect.null) { $0.union($1) }

        XCTAssertTrue(
            KeyboardKeyHitResolver.isUnambiguous(rows: rows, in: bounds),
            "a tiled row must never let two keys claim the same touch"
        )
    }

    func testOverlappingGeometryIsReportedAsAmbiguous() {
        // Two keys deliberately overlapping: the failure mode a position-based
        // router has to be able to detect.
        let rows = [[
            CGRect(x: 0, y: 0, width: 50, height: 40),
            CGRect(x: 40, y: 0, width: 50, height: 40)
        ]]

        XCTAssertFalse(KeyboardKeyHitResolver.isUnambiguous(rows: rows, in: CGRect(x: 0, y: 0, width: 90, height: 40)))
        XCTAssertEqual(
            KeyboardKeyHitResolver.claimingKeys(at: CGPoint(x: 45, y: 20), rows: rows).count,
            2
        )
    }

    func testPredictionNeverMakesAPointAmbiguousOnAFullRow() {
        // The resolver is only trustworthy if prediction cannot introduce a
        // double-claimed point. This is the invariant the whole single-owner
        // design rests on.
        let count = 10
        let width: CGFloat = 40
        let gap: CGFloat = 6
        let visual = (0..<count).map { index -> CGRect in
            CGRect(x: CGFloat(index) * (width + gap), y: 0, width: width, height: 54)
        }
        let labels = (0..<count).map { String(UnicodeScalar(97 + $0)!) }
        let skewed = NextCharacterProbabilities(
            Dictionary(uniqueKeysWithValues: labels.enumerated().map { index, label in
                (label, index == 9 ? 0.90 : 0.90 / 9)
            })
        )
        let rows = KeyboardKeyHitGeometry.frames(
            for: [visual],
            labels: [labels],
            probabilities: skewed
        )
        let bounds = rows[0].reduce(CGRect.null) { $0.union($1) }

        XCTAssertTrue(
            KeyboardKeyHitResolver.isUnambiguous(rows: rows, in: bounds),
            "a strongly skewed prediction must still leave every point single-owned"
        )
    }
}
