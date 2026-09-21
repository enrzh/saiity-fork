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

/// Pure category navigation for the horizontally free-scrolling emoji pages.
public enum EmojiNavigation {
    /// Points per millisecond-scale UIScrollView velocity. Below this, the
    /// finger's projected resting page wins.
    public static let flickVelocity: Double = 0.05
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

    public static func pageContentOffsetX(
        pageIndex: Int,
        pageWidth: Double,
        pageGap: Double = 0
    ) -> Double {
        guard pageIndex > 0, pageWidth > 0 else { return 0 }
        return Double(pageIndex) * (pageWidth + max(0, pageGap))
    }

    /// Resolves offsets for responsive pages whose final category page may be
    /// narrower than the viewport. Widths are measured at runtime, so emoji
    /// capacity changes do not create a fake blank page tail.
    public static func pageContentOffsetX(
        pageIndex: Int,
        pageWidths: [Double],
        pageGap: Double = 0
    ) -> Double {
        guard pageIndex > 0, !pageWidths.isEmpty else { return 0 }
        let end = min(pageIndex, pageWidths.count)
        return pageWidths.prefix(end).reduce(0, +)
            + Double(end) * max(0, pageGap)
    }

    /// Page whose span contains the offset. Unlike `pageIndex`, a point near
    /// the next page's edge still belongs to the page under the finger.
    public static func containingPageIndex(
        contentOffsetX: Double,
        pageWidths: [Double],
        pageGap: Double = 0
    ) -> Int {
        guard pageWidths.count > 1 else { return 0 }
        let gap = max(0, pageGap)
        var origin = 0.0
        for index in 0..<pageWidths.count - 1 {
            origin += max(0, pageWidths[index]) + gap
            if contentOffsetX < origin { return index }
        }
        return pageWidths.count - 1
    }

    /// Page a finger-up should land on. A flick moves one page from the page
    /// under the finger. A slow release uses the nearest projected page.
    public static func settledPageIndex(
        contentOffsetX: Double,
        projectedOffsetX: Double,
        velocityX: Double,
        pageWidths: [Double],
        pageGap: Double = 0
    ) -> Int {
        guard pageWidths.count > 1 else { return 0 }
        let last = pageWidths.count - 1
        let origin = containingPageIndex(
            contentOffsetX: contentOffsetX,
            pageWidths: pageWidths,
            pageGap: pageGap
        )
        // A light flick should change pages. The pager also uses a fast
        // deceleration rate so the settle does not coast.
        if velocityX > flickVelocity { return min(last, origin + 1) }
        if velocityX < -flickVelocity { return max(0, origin - 1) }
        return pageIndex(
            contentOffsetX: projectedOffsetX,
            pageWidths: pageWidths,
            pageGap: pageGap
        )
    }

    public static func pageIndex(
        contentOffsetX: Double,
        pageWidths: [Double],
        pageGap: Double = 0
    ) -> Int {
        guard pageWidths.count > 1 else { return 0 }
        let gap = max(0, pageGap)
        var origin = 0.0
        var selectedIndex = 0
        var bestDistance = abs(contentOffsetX)
        for index in 1..<pageWidths.count {
            origin += max(0, pageWidths[index - 1]) + gap
            let distance = abs(contentOffsetX - origin)
            if distance < bestDistance {
                bestDistance = distance
                selectedIndex = index
            }
        }
        return selectedIndex
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
