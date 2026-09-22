import XCTest
import CoreGraphics
@testable import DictusCore

final class AdaptiveTouchRoutingTests: XCTestCase {
    private let keys = [
        AdaptiveTouchKey(
            id: "a", label: "a", frame: CGRect(x: 0, y: 0, width: 40, height: 40),
            row: 0, column: 0, isCommand: false, hasVariants: false
        ),
        AdaptiveTouchKey(
            id: "s", label: "s", frame: CGRect(x: 46, y: 0, width: 40, height: 40),
            row: 0, column: 1, isCommand: false, hasVariants: false
        )
    ]

    func testProbabilityValuesAreNormalizedAndBounded() {
        let prediction = NextCharacterProbabilities([
            "S": 4, "a": 2, "x": 1, "z": 0.5
        ], maxEntries: 2)

        XCTAssertEqual(prediction.values.count, 2)
        XCTAssertEqual(prediction["s"], 2.0 / 3.0, accuracy: 0.0001)
        XCTAssertEqual(prediction["a"], 1.0 / 3.0, accuracy: 0.0001)
    }

    func testConfidentAdjacentBoundaryTapRedirects() {
        let prediction = NextCharacterProbabilities(["s": 0.8, "a": 0.2])

        XCTAssertEqual(
            AdaptiveTouchResolver.redirectedKey(
                at: CGPoint(x: 43, y: 20), keys: keys, probabilities: prediction
            ),
            "s"
        )
    }

    func testKeyCenterDoesNotRedirect() {
        let prediction = NextCharacterProbabilities(["s": 0.9, "a": 0.1])

        XCTAssertNil(
            AdaptiveTouchResolver.redirectedKey(
                at: CGPoint(x: 20, y: 20), keys: keys, probabilities: prediction
            )
        )
    }

    func testCommandsAreProtectedButVariantKeysRemainRoutable() {
        let command = AdaptiveTouchKey(
            id: "delete", label: "", frame: CGRect(x: 46, y: 0, width: 40, height: 40),
            row: 0, column: 1, isCommand: true, hasVariants: false
        )
        let variant = AdaptiveTouchKey(
            id: "s", label: "s", frame: CGRect(x: 46, y: 0, width: 40, height: 40),
            row: 0, column: 1, isCommand: false, hasVariants: true
        )
        let prediction = NextCharacterProbabilities(["s": 0.9])

        XCTAssertNil(AdaptiveTouchResolver.redirectedKey(
            at: CGPoint(x: 43, y: 20), keys: [keys[0], command], probabilities: prediction
        ))
        XCTAssertEqual(AdaptiveTouchResolver.redirectedKey(
            at: CGPoint(x: 43, y: 20), keys: [keys[0], variant], probabilities: prediction
        ), "s")
    }

    func testAmbiguousLeadFallsBackToStaticRouting() {
        let prediction = NextCharacterProbabilities(["s": 0.52, "a": 0.48])

        XCTAssertNil(
            AdaptiveTouchResolver.redirectedKey(
                at: CGPoint(x: 43, y: 20), keys: keys, probabilities: prediction
            )
        )
    }

    func testEqualPriorsNeverRedirectBecauseOfSpatialLikelihood() {
        let prediction = NextCharacterProbabilities(["a": 0.5, "s": 0.5])

        XCTAssertEqual(
            AdaptiveTouchResolver.resolve(
                at: CGPoint(x: 35, y: 20), keys: keys, probabilities: prediction
            ),
            .keep("a")
        )
    }

    func testSpatialLikelihoodCanKeepStaticSideWithConfidentFixedPrior() {
        let prediction = NextCharacterProbabilities(["a": 0.30, "s": 0.70])

        XCTAssertEqual(
            AdaptiveTouchResolver.resolve(
                at: CGPoint(x: 35, y: 20), keys: keys, probabilities: prediction
            ),
            .keep("a")
        )
        XCTAssertEqual(
            AdaptiveTouchResolver.resolve(
                at: CGPoint(x: 43, y: 20), keys: keys, probabilities: prediction
            ),
            .redirect("s")
        )
    }

    func testInvalidOrEmptyProbabilitiesUseStaticFallback() {
        let invalid = NextCharacterProbabilities([
            "a": .nan, "s": .infinity, "x": -1, "": 2
        ])

        XCTAssertTrue(invalid.isEmpty)
        XCTAssertNil(AdaptiveTouchResolver.redirectedKey(
            at: CGPoint(x: 43, y: 20), keys: keys, probabilities: invalid
        ))
    }

    func testOuterBoundaryAndRowSeparationDoNotRedirect() {
        let prediction = NextCharacterProbabilities(["a": 0.10, "s": 0.90])
        let secondRowKey = AdaptiveTouchKey(
            id: "q", label: "q", frame: CGRect(x: 46, y: 50, width: 40, height: 40),
            row: 1, column: 1, isCommand: false, hasVariants: false
        )

        XCTAssertNil(AdaptiveTouchResolver.redirectedKey(
            at: CGPoint(x: 1, y: 20), keys: keys, probabilities: prediction
        ))
        XCTAssertNil(AdaptiveTouchResolver.redirectedKey(
            at: CGPoint(x: 43, y: 45), keys: [keys[0], secondRowKey], probabilities: prediction
        ))
    }

    func testCommandBetweenColumnsCannotCreateCrossCommandBoundary() {
        let command = AdaptiveTouchKey(
            id: "delete", label: "", frame: CGRect(x: 46, y: 0, width: 40, height: 40),
            row: 0, column: 1, isCommand: true, hasVariants: false
        )
        let rightLetter = AdaptiveTouchKey(
            id: "d", label: "d", frame: CGRect(x: 92, y: 0, width: 40, height: 40),
            row: 0, column: 2, isCommand: false, hasVariants: false
        )

        XCTAssertNil(AdaptiveTouchResolver.redirectedKey(
            at: CGPoint(x: 69, y: 20),
            keys: [keys[0], command, rightLetter],
            probabilities: NextCharacterProbabilities(["a": 0.10, "d": 0.90])
        ))
    }

    func testConfidentPredictionExtendsTheInvisibleTargetWithoutTakingTheCenter() {
        let adjacent = [
            AdaptiveTouchKey(
                id: "a", label: "a", frame: CGRect(x: 0, y: 0, width: 40, height: 40),
                row: 0, column: 0, isCommand: false, hasVariants: false
            ),
            AdaptiveTouchKey(
                id: "s", label: "s", frame: CGRect(x: 40, y: 0, width: 40, height: 40),
                row: 0, column: 1, isCommand: false, hasVariants: false
            )
        ]
        let strong = NextCharacterProbabilities(["s": 0.9, "a": 0.1])

        XCTAssertEqual(
            AdaptiveTouchResolver.redirectedKey(
                at: CGPoint(x: 32, y: 20), keys: adjacent, probabilities: strong
            ),
            "s"
        )
        XCTAssertNil(
            AdaptiveTouchResolver.redirectedKey(
                at: CGPoint(x: 20, y: 20), keys: adjacent, probabilities: strong
            )
        )

        let mild = NextCharacterProbabilities(["s": 0.62, "a": 0.38])
        XCTAssertNil(
            AdaptiveTouchResolver.redirectedKey(
                at: CGPoint(x: 32, y: 20), keys: adjacent, probabilities: mild
            )
        )
    }

    func testCustomConfidenceGuardRequiresBothFloorAndProbabilityLead() {
        let prediction = NextCharacterProbabilities(["a": 0.44, "s": 0.56])

        XCTAssertEqual(
            AdaptiveTouchResolver.resolve(
                at: CGPoint(x: 43, y: 20), keys: keys, probabilities: prediction
            ),
            .keep("a")
        )
    }
}
