import XCTest
@testable import DictusCore

final class EmojiNavigationTests: XCTestCase {
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

    func testEmptyRecentsDoesNotCreateAnEmptyPage() {
        let pages = [
            EmojiNavigationPage(id: "page-0", categoryID: "smileys", itemCategoryIDs: ["smileys"])
        ]

        XCTAssertNil(EmojiNavigation.anchorPageIDs(for: pages)["recents"])
        XCTAssertEqual(EmojiNavigation.pageIndex(for: "smileys", in: pages), 0)
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
