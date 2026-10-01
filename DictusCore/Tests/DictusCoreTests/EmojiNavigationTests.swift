import XCTest
@testable import DictusCore

final class EmojiNavigationTests: XCTestCase {
    func testBlankPagerAndCategoryDragKeepTouchOwnership() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        func source(_ name: String) throws -> String {
            try String(contentsOf: root.appendingPathComponent("DictusKeyboard/Views/\(name).swift"), encoding: .utf8)
        }

        let picker = try source("EmojiPickerView")
        let hold = try source("EmojiGestureCoordinator")
        let category = try source("EmojiCategoryControl")
        XCTAssertFalse(picker.contains("panGestureRecognizer.require(toFail: hold)"),
                       "blank pager swipes must not wait on emoji hold arbitration")
        XCTAssertTrue(picker.contains("return recognizer !== hold || canBeginVariantHold(at: touch.location(in: self))"))
        XCTAssertTrue(picker.contains("return self\n    }\n\n    func configure("),
                      "a blank page cell must remain in the pager's hit hierarchy")
        XCTAssertTrue(hold.contains("let eligible = shouldBeginHold?(point) ?? true"))
        XCTAssertTrue(hold.contains("guard let touch = touches.first, let view else {\n            state = .failed"),
                      "a missing hold target must not leave the pager pan waiting")
        XCTAssertTrue(category.contains("bounds.insetBy(dx: 0, dy: -hitExpansion).contains(point)"))
        XCTAssertFalse(category.contains("isTracking || interactionBounds.contains(point)"),
                       "tracking must not steal a new touch outside the visible category handle")
        XCTAssertTrue(category.contains("if dragging { selectAccessibilityCategory(nearestIndex(toX: point.x)) }"),
                      "UIKit tracking keeps the original drag even when it leaves the handle")
    }

    func testEmptyRecentsAndIncompletePageRetainPagerSlots() {
        let pages = EmojiSurfaceModel.pages(
            recents: [],
            categories: [.init(id: "smileys", name: "Smileys", icon: "face.smiling", emojis: ["😀"])],
            emojiColumnCount: 8
        )
        XCTAssertEqual(pages.map(\.columns), [8, 1])
        XCTAssertTrue(pages[0].items.isEmpty)
        XCTAssertEqual(pages[1].items.count, 1)
    }

    func testEmptyRecentsLandOnFirstStandardCategory() {
        XCTAssertEqual(
            EmojiNavigation.landingCategoryID(recents: [], firstCategoryID: "smileys"),
            "smileys"
        )
        XCTAssertEqual(
            EmojiNavigation.landingCategoryID(recents: ["😀"], firstCategoryID: "smileys"),
            "recents"
        )
    }

    func testCategoryAnchorsToItsOwnPage() {
        let pages = [
            EmojiNavigationPage(id: "page-0", categoryID: "smileys", itemCategoryIDs: ["smileys"]),
            EmojiNavigationPage(id: "page-1", categoryID: "animals", itemCategoryIDs: ["animals"]),
            EmojiNavigationPage(id: "page-2", categoryID: "food", itemCategoryIDs: ["food"])
        ]

        XCTAssertEqual(EmojiNavigation.anchorPageIDs(for: pages)["animals"], "page-1")
        XCTAssertEqual(EmojiNavigation.anchorPageIDs(for: pages)["food"], "page-2")
    }

    func testFlagsRemainReachableOnASeparatePage() {
        let pages = [
            EmojiNavigationPage(id: "page-0", categoryID: "symbols", itemCategoryIDs: ["symbols"]),
            EmojiNavigationPage(id: "page-1", categoryID: "flags", itemCategoryIDs: ["flags"])
        ]

        XCTAssertEqual(EmojiNavigation.anchorPageIDs(for: pages)["flags"], "page-1")
        XCTAssertEqual(EmojiNavigation.pageIndex(for: "flags", in: pages), 1)
    }

    func testPageIndexPrefersExactPageAndUsesFirstCategoryAnchor() {
        let pages = [
            EmojiNavigationPage(id: "page-0", categoryID: "smileys", itemCategoryIDs: ["smileys"]),
            EmojiNavigationPage(id: "page-1", categoryID: "animals", itemCategoryIDs: ["animals"])
        ]

        XCTAssertEqual(EmojiNavigation.pageIndex(for: "page-1", in: pages), 1)
        XCTAssertEqual(EmojiNavigation.pageIndex(for: "animals", in: pages), 1)
        XCTAssertNil(EmojiNavigation.pageIndex(for: "missing", in: pages))
    }

    func testLastIncompletePageIsCounted() {
        XCTAssertEqual(EmojiNavigation.pageCount(itemCount: 0, pageCapacity: 32), 0)
        XCTAssertEqual(EmojiNavigation.pageCount(itemCount: 32, pageCapacity: 32), 1)
        XCTAssertEqual(EmojiNavigation.pageCount(itemCount: 33, pageCapacity: 32), 2)
        XCTAssertEqual(EmojiNavigation.pageCount(itemCount: 65, pageCapacity: 32), 3)
        XCTAssertEqual(EmojiNavigation.pageContentOffsetX(pageIndex: 3, pageWidth: 390, pageGap: 0), 1170)
        XCTAssertEqual(EmojiNavigation.pageContentOffsetX(pageIndex: 0, pageWidth: 390), 0)
    }

    func testResponsivePageOffsetsUseMeasuredFinalPageWidth() {
        let widths = [390.0, 390.0, 214.0, 390.0]
        XCTAssertEqual(
            EmojiNavigation.pageContentOffsetX(pageIndex: 2, pageWidths: widths),
            780
        )
        XCTAssertEqual(
            EmojiNavigation.pageContentOffsetX(pageIndex: 3, pageWidths: widths),
            994
        )
        XCTAssertEqual(
            EmojiNavigation.pageIndex(contentOffsetX: 980, pageWidths: widths),
            3
        )
        XCTAssertEqual(
            EmojiNavigation.settledPageIndex(
                contentOffsetX: 20,
                projectedOffsetX: 40,
                velocityX: 0.8,
                pageWidths: widths
            ),
            1
        )
        XCTAssertEqual(
            EmojiNavigation.settledPageIndex(
                contentOffsetX: 400,
                projectedOffsetX: 390,
                velocityX: 0,
                pageWidths: widths
            ),
            1
        )
    }

    func testFlagsCategoryAnchorsToItsLastIncompletePage() {
        let pages = [
            EmojiNavigationPage(id: "recents", categoryID: "recents", itemCategoryIDs: []),
            EmojiNavigationPage(id: "page-0", categoryID: "symbols", itemCategoryIDs: ["symbols", "symbols"]),
            EmojiNavigationPage(id: "page-1", categoryID: "flags", itemCategoryIDs: ["flags"])
        ]

        XCTAssertEqual(EmojiNavigation.anchorPageIDs(for: pages)["flags"], "page-1")
        XCTAssertEqual(EmojiNavigation.pageIndex(for: "flags", in: pages), 2)
        XCTAssertEqual(
            EmojiNavigation.scrollResolution(
                for: "flags", in: pages, availableItemCount: 3, boundsWidth: 320
            ),
            .ready(index: 2)
        )
    }

    func testEmptyRecentsRemainsAReachablePagerPage() {
        let pages = [
            EmojiNavigationPage(id: "recents", categoryID: "recents", itemCategoryIDs: []),
            EmojiNavigationPage(id: "page-0", categoryID: "smileys", itemCategoryIDs: ["smileys"])
        ]

        XCTAssertEqual(EmojiNavigation.anchorPageIDs(for: pages)["recents"], "recents")
        XCTAssertEqual(EmojiNavigation.pageIndex(for: "recents", in: pages), 0)
        XCTAssertEqual(EmojiNavigation.pageIndex(for: "smileys", in: pages), 1)
    }

    func testScrollRequestRemainsPendingUntilLayoutAndDataAreReady() {
        let pages = [
            EmojiNavigationPage(id: "page-0", categoryID: "smileys", itemCategoryIDs: ["smileys"])
        ]

        XCTAssertEqual(
            EmojiNavigation.scrollResolution(
                for: "smileys", in: pages, availableItemCount: 0, boundsWidth: 0
            ),
            .pending(index: 0)
        )
        XCTAssertEqual(
            EmojiNavigation.scrollResolution(
                for: "smileys", in: pages, availableItemCount: 1, boundsWidth: 0
            ),
            .pending(index: 0)
        )
        XCTAssertEqual(
            EmojiNavigation.scrollResolution(
                for: "smileys", in: pages, availableItemCount: 0, boundsWidth: 320
            ),
            .pending(index: 0)
        )
        XCTAssertEqual(
            EmojiNavigation.scrollResolution(
                for: "smileys", in: pages, availableItemCount: 1, boundsWidth: 320
            ),
            .ready(index: 0)
        )
        XCTAssertEqual(
            EmojiNavigation.scrollResolution(
                for: "missing", in: pages, availableItemCount: 2, boundsWidth: 320
            ),
            .unavailable
        )
    }
}
