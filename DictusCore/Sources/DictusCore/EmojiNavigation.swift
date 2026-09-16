// DictusCore/Sources/DictusCore/EmojiNavigation.swift

/// Page metadata used to resolve emoji category jumps without UIKit state.
public struct EmojiNavigationPage: Equatable, Sendable {
    public let id: String
    public let categoryID: String
    public let itemCategoryIDs: [String]

    public init(id: String, categoryID: String, itemCategoryIDs: [String]) {
        self.id = id
        self.categoryID = categoryID
        self.itemCategoryIDs = itemCategoryIDs
    }
}

/// Pure category navigation for the horizontally continuous emoji stream.
public enum EmojiNavigation {
    public enum ScrollResolution: Equatable, Sendable {
        case unavailable
        case pending(index: Int)
        case ready(index: Int)
    }

    /// Recents is useful as the initial page only when it contains an item.
    /// Empty recents should open on the first standard category instead.
    public static func landingCategoryID(recents: [String], firstCategoryID: String?) -> String {
        recents.isEmpty ? (firstCategoryID ?? "smileys") : "recents"
    }

    /// Includes a trailing incomplete page so the last category stays reachable.
    public static func pageCount(itemCount: Int, pageCapacity: Int) -> Int {
        guard itemCount > 0, pageCapacity > 0 else { return 0 }
        return (itemCount + pageCapacity - 1) / pageCapacity
    }

    /// Recents always occupies page 0, including when it has no glyphs.
    public static func collectionPageCount(standardItemCount: Int, pageCapacity: Int) -> Int {
        1 + pageCount(itemCount: standardItemCount, pageCapacity: pageCapacity)
    }

    public static func pageContentOffsetX(pageIndex: Int, pageWidth: Double) -> Double {
        guard pageIndex > 0, pageWidth > 0 else { return 0 }
        return Double(pageIndex) * pageWidth
    }

    /// Returns the first page containing an item from each category.
    public static func anchorPageIDs(for pages: [EmojiNavigationPage]) -> [String: String] {
        var anchors: [String: String] = [:]
        for page in pages {
            let categoryIDs = page.itemCategoryIDs.isEmpty
                ? [page.categoryID]
                : page.itemCategoryIDs
            for categoryID in categoryIDs where anchors[categoryID] == nil {
                anchors[categoryID] = page.id
            }
        }
        return anchors
    }

    /// Resolves an exact page id first, then the first page containing the
    /// category's first item.
    public static func pageIndex(for requestID: String, in pages: [EmojiNavigationPage]) -> Int? {
        if let index = pages.firstIndex(where: { $0.id == requestID }) {
            return index
        }
        guard let anchorID = anchorPageIDs(for: pages)[requestID] else { return nil }
        return pages.firstIndex(where: { $0.id == anchorID })
    }

    /// Resolves a request without consuming it until the collection view has
    /// both a usable width and the target item. This models the first layout
    /// pass, where reloadData may not have populated UICollectionView yet.
    public static func scrollResolution(
        for requestID: String,
        in pages: [EmojiNavigationPage],
        availableItemCount: Int,
        boundsWidth: Double
    ) -> ScrollResolution {
        guard let index = pageIndex(for: requestID, in: pages) else { return .unavailable }
        guard boundsWidth > 1, availableItemCount > index else { return .pending(index: index) }
        return .ready(index: index)
    }
}
