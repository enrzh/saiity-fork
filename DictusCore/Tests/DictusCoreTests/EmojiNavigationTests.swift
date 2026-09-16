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

    func testCategoryAnchorsToPageContainingItsFirstItem() {
        let pages = [
            EmojiNavigationPage(id: "page-0", categoryID: "smileys", itemCategoryIDs: ["smileys", "animals"]),
            EmojiNavigationPage(id: "page-1", categoryID: "animals", itemCategoryIDs: ["animals", "food"]),
            EmojiNavigationPage(id: "page-2", categoryID: "food", itemCategoryIDs: ["food"])
        ]

        XCTAssertEqual(EmojiNavigation.anchorPageIDs(for: pages)["animals"], "page-0")
        XCTAssertEqual(EmojiNavigation.anchorPageIDs(for: pages)["food"], "page-1")
    }

    func testPageIndexPrefersExactPageAndUsesFirstCategoryAnchor() {
        let pages = [
            EmojiNavigationPage(id: "page-0", categoryID: "smileys", itemCategoryIDs: ["smileys", "animals"]),
            EmojiNavigationPage(id: "page-1", categoryID: "animals", itemCategoryIDs: ["animals"])
        ]

        XCTAssertEqual(EmojiNavigation.pageIndex(for: "page-1", in: pages), 1)
        XCTAssertEqual(EmojiNavigation.pageIndex(for: "animals", in: pages), 0)
        XCTAssertNil(EmojiNavigation.pageIndex(for: "missing", in: pages))
    }

    func testLastIncompletePageIsCounted() {
        XCTAssertEqual(EmojiNavigation.pageCount(itemCount: 0, pageCapacity: 32), 0)
        XCTAssertEqual(EmojiNavigation.pageCount(itemCount: 32, pageCapacity: 32), 1)
        XCTAssertEqual(EmojiNavigation.pageCount(itemCount: 33, pageCapacity: 32), 2)
        XCTAssertEqual(EmojiNavigation.pageCount(itemCount: 65, pageCapacity: 32), 3)
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

    func testEmptyRecentsPageStillAnchorsToRecents() {
        let pages = [
            EmojiNavigationPage(id: "recents", categoryID: "recents", itemCategoryIDs: []),
            EmojiNavigationPage(id: "page-0", categoryID: "smileys", itemCategoryIDs: ["smileys"])
        ]

        XCTAssertEqual(EmojiNavigation.anchorPageIDs(for: pages)["recents"], "recents")
        XCTAssertEqual(EmojiNavigation.pageIndex(for: "smileys", in: pages), 1)
    }

    func testScrollRequestRemainsPendingUntilLayoutAndDataAreReady() {
        let pages = [
            EmojiNavigationPage(id: "recents", categoryID: "recents", itemCategoryIDs: []),
            EmojiNavigationPage(id: "page-0", categoryID: "smileys", itemCategoryIDs: ["smileys"])
        ]

        XCTAssertEqual(
            EmojiNavigation.scrollResolution(
                for: "smileys", in: pages, availableItemCount: 0, boundsWidth: 0
            ),
            .pending(index: 1)
        )
        XCTAssertEqual(
            EmojiNavigation.scrollResolution(
                for: "smileys", in: pages, availableItemCount: 2, boundsWidth: 0
            ),
            .pending(index: 1)
        )
        XCTAssertEqual(
            EmojiNavigation.scrollResolution(
                for: "smileys", in: pages, availableItemCount: 0, boundsWidth: 320
            ),
            .pending(index: 1)
        )
        XCTAssertEqual(
            EmojiNavigation.scrollResolution(
                for: "smileys", in: pages, availableItemCount: 2, boundsWidth: 320
            ),
            .ready(index: 1)
        )
        XCTAssertEqual(
            EmojiNavigation.scrollResolution(
                for: "missing", in: pages, availableItemCount: 2, boundsWidth: 320
            ),
            .unavailable
        )
    }
}
