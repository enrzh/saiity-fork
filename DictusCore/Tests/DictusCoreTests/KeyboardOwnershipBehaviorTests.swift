import CoreGraphics
import XCTest
@testable import DictusCore

final class KeyboardOwnershipBehaviorTests: XCTestCase {
    /// Prediction must never take area from a key. The old geometry moved the
    /// seam *between* two keys, so the predicted key grew and its neighbour
    /// shrank by the same amount — which is how a visible key ended up with a
    /// target too small to hit, and silently stopped responding.
    func testPredictedFramesNeverShrinkTheirNeighbour() {
        let visual = [[
            CGRect(x: 0, y: 0, width: 40, height: 40),
            CGRect(x: 46, y: 0, width: 40, height: 40)
        ]]
        let hit = KeyboardKeyHitGeometry.frames(
            for: visual,
            labels: [["r", "e"]],
            probabilities: NextCharacterProbabilities(["e": 0.8, "r": 0.01]),
            maximumPredictionShift: 4
        )[0]

        // "e" is predicted and may reach into the gap…
        XCTAssertLessThan(hit[1].minX, visual[0][1].minX)
        XCTAssertGreaterThanOrEqual(hit[1].minX, visual[0][0].maxX,
                                    "the predicted key must not reach into its neighbour")
        // …but "r" keeps its entire drawn plate, and neither plate overlaps.
        XCTAssertGreaterThanOrEqual(hit[0].width, visual[0][0].width)
        XCTAssertTrue(hit[0].contains(CGPoint(x: 20, y: 20)))
        XCTAssertTrue(hit[1].contains(CGPoint(x: 66, y: 20)))
        XCTAssertFalse(hit[0].intersects(hit[1]))
    }

    /// Two rules together: no key is ever reduced, and no point across a row is
    /// dead. Dropping the tiling fixed the first and broke the second — a device
    /// trace showed 26 taps arriving, 17 reaching a key, 9 landing on nothing.
    /// Filling the gap with a seam confined to that gap is what satisfies both.
    func testTargetsCoverEveryKeyWholeAndLeaveNoDeadSeam() {
        let visual = [
            [CGRect(x: 4, y: 0, width: 28, height: 30), CGRect(x: 38, y: 0, width: 28, height: 30)],
            [CGRect(x: 16, y: 36, width: 28, height: 30), CGRect(x: 50, y: 36, width: 28, height: 30)]
        ]
        let hit = KeyboardKeyHitGeometry.frames(for: visual)

        for row in visual.indices {
            for column in visual[row].indices {
                XCTAssertTrue(hit[row][column].contains(visual[row][column]),
                              "a key must keep its whole drawn plate")
                XCTAssertGreaterThan(hit[row][column].width, 0)
            }
        }
        // The horizontal gap inside a row is owned, not dead.
        let gapMid = (visual[0][0].maxX + visual[0][1].minX) / 2
        let resolved = KeyboardKeyHitResolver.keyIndex(
            at: CGPoint(x: gapMid, y: visual[0][0].midY), rows: hit)
        XCTAssertNotNil(resolved, "a point in the gap must still press a key")
        XCTAssertEqual(resolved?.row, 0)
    }

    /// The tiles the touch owner receives must be contiguous across the whole grid.
    ///
    /// This is the property that makes a tap impossible to lose: every point inside
    /// the grid belongs to exactly one key, including the gaps between plates and
    /// the margins beside the first and last key. It is asserted on the geometry
    /// function, and the surfaces are covered by the contract tests, because a
    /// regression here is invisible on screen — the keys still look perfect.
    func testPublishedTilesAreContiguousAcrossTheWholeGrid() {
        let visual = [
            [CGRect(x: 4, y: 0, width: 28, height: 30), CGRect(x: 38, y: 0, width: 28, height: 30)],
            [CGRect(x: 16, y: 36, width: 28, height: 30), CGRect(x: 50, y: 36, width: 28, height: 30)]
        ]
        let bounds = CGRect(x: 0, y: 0, width: 82, height: 70)
        let tiles = KeyboardKeyHitGeometry.contiguousTiles(for: visual, in: bounds)

        for row in tiles {
            XCTAssertEqual(row.first?.minX, bounds.minX)
            XCTAssertEqual(row.last?.maxX, bounds.maxX)
            for index in 1..<max(1, row.count) {
                XCTAssertEqual(row[index].minX, row[index - 1].maxX,
                               "consecutive tiles must share an edge, not a gap")
            }
        }
        XCTAssertEqual(tiles.first?.first?.minY, bounds.minY)
        XCTAssertEqual(tiles.last?.first?.maxY, bounds.maxY)
        XCTAssertTrue(KeyboardKeyHitResolver.isUnambiguous(rows: tiles, in: bounds))
    }

    /// Every surface must publish contiguous tiles, and must not reintroduce
    /// overlapping targets that need a tie-break to resolve.
    func testEverySurfacePublishesContiguousTiles() throws {
        for surface in ["LetterKeyboardSurface", "SymbolKeyboardSurface", "NumberKeyboardSurface"] {
            let source = try String(
                contentsOf: URL(fileURLWithPath: #filePath)
                    .deletingLastPathComponent()
                    .deletingLastPathComponent()
                    .deletingLastPathComponent()
                    .deletingLastPathComponent()
                    .appending(path: "DictusKeyboard/\(surface).swift"),
                encoding: .utf8)
            XCTAssertTrue(source.contains("KeyboardKeyHitGeometry.contiguousTiles("),
                          "\(surface) must publish contiguous tiles to the touch owner")
            XCTAssertFalse(source.contains("KeyboardKeyHitGeometry.growing("),
                           "\(surface) must not publish overlapping grown targets")
        }
    }

    /// Hit-target prediction must follow the word being typed.
    ///
    /// This used to assert the opposite — that the same fixed letter priors were
    /// produced for "Schick" and for "Please send die Rechnung" — which is exactly
    /// the defect: a next-key nudge that ignores context. The static table has been
    /// deleted, and the letter grid now uses the real engine's contextual
    /// probabilities, computed off the touch path.
    func testLetterFrequencyFollowsTheWordBeingTyped() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let surface = try String(
            contentsOf: repository.appending(path: "DictusKeyboard/LetterKeyboardSurface.swift"),
            encoding: .utf8)
        let state = try String(
            contentsOf: repository.appending(path: "DictusKeyboard/TextPrediction/SuggestionState.swift"),
            encoding: .utf8)

        // The grid reads the published contextual probabilities and hands them to
        // the geometry solver. The prediction is first bound to a local because
        // the same value keys the memoised geometry, and it is gated on the
        // Settings toggle, so asserting one exact call-site string here only
        // asserted a refactor rather than the behaviour.
        XCTAssertTrue(surface.contains("? suggestionState.adaptiveTouchPrediction : nil"),
                      "the letter grid must use the published contextual probabilities")
        XCTAssertTrue(surface.contains("probabilities: prediction,"),
                      "those probabilities must be what the hit geometry is solved from")
        XCTAssertTrue(state.contains("self.engine.nextCharacterProbabilities(\n                        for: partial, after: previousWords"),
                      "the estimate must be conditioned on the partial word and the words before it")
    }

    func testRecoveryAllowsANewTapAfterThePreviousHandoffGoesStale() {
        let opened = Date(timeIntervalSince1970: 1_000)
        XCTAssertFalse(KeyboardDictationBridge.shouldOpen(lastOpen: opened, now: opened.addingTimeInterval(0.4)))
        XCTAssertTrue(KeyboardDictationBridge.shouldOpen(lastOpen: opened, now: opened.addingTimeInterval(1.2)))
    }

    func testHomeReadinessDoesNotCallAMissingModelReady() {
        let waiting = DictationReadiness(
            serviceEnabled: true,
            microphonePermission: .authorized,
            modelReady: false,
            modelLoadState: .idle,
            status: .idle
        )
        XCTAssertNotEqual(waiting.title, "Ready to dictate")

        let ready = DictationReadiness(
            serviceEnabled: true,
            microphonePermission: .authorized,
            modelReady: true,
            modelLoadState: .ready,
            status: .idle
        )
        XCTAssertEqual(ready.title, "Ready to dictate")
        XCTAssertEqual(ready.action, .start)
    }

    func testLiveActivityStandbyFollowsTheDictationSwitch() {
        let suite = "ownership-live-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            XCTFail("Could not create isolated preferences")
            return
        }
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(false, forKey: SharedKeys.serviceEnabled)
        XCTAssertFalse(KeyboardDictationService.isEnabled(in: defaults))
        defaults.set(true, forKey: SharedKeys.serviceEnabled)
        XCTAssertTrue(KeyboardDictationService.isEnabled(in: defaults))
    }
}
