import CoreGraphics
import Foundation

/// Page plan for the emoji grid. The picker still owns the collection view;
/// this value type owns which glyphs land on which page.
public struct EmojiSurfaceCategory: Equatable, Sendable {
    public var id: String
    public var name: String
    public var icon: String
    public var emojis: [String]

    public init(id: String, name: String, icon: String, emojis: [String]) {
        self.id = id
        self.name = name
        self.icon = icon
        self.emojis = emojis
    }
}

public struct EmojiSurfaceItemPlan: Equatable, Sendable {
    public var id: String
    public var emoji: String
    public var categoryID: String

    public init(id: String, emoji: String, categoryID: String) {
        self.id = id
        self.emoji = emoji
        self.categoryID = categoryID
    }
}

public struct EmojiSurfacePagePlan: Equatable, Sendable {
    public var id: String
    public var name: String
    public var icon: String
    public var categoryID: String
    public var columns: Int
    public var items: [EmojiSurfaceItemPlan]

    public init(
        id: String,
        name: String,
        icon: String,
        categoryID: String,
        columns: Int,
        items: [EmojiSurfaceItemPlan]
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.categoryID = categoryID
        self.columns = columns
        self.items = items
    }
}

public enum EmojiSurfaceModel {
    public static func columnCount(
        gridWidth: CGFloat,
        horizontalPadding: CGFloat,
        minimumTargetWidth: CGFloat
    ) -> Int {
        max(1, Int((gridWidth - horizontalPadding * 2) / minimumTargetWidth))
    }

    public static func pageColumnCount(itemCount: Int, emojiColumnCount: Int) -> Int {
        min(emojiColumnCount, max(1, (max(0, itemCount) + 3) / 4))
    }

    public static func rowHeight(
        gridHeight: CGFloat,
        rowSpacing: CGFloat,
        gridVerticalInset: CGFloat,
        rowCount: CGFloat = 4
    ) -> CGFloat {
        let usable = gridHeight - gridVerticalInset * 2 - rowSpacing * (rowCount - 1)
        return max(0, usable / rowCount)
    }

    /// Recents is always one full-width page. Each standard category is then
    /// split into its own pages and never shares a page with another category.
    public static func pages(
        recents: [String],
        categories: [EmojiSurfaceCategory],
        emojiColumnCount: Int
    ) -> [EmojiSurfacePagePlan] {
        var result: [EmojiSurfacePagePlan] = []
        result.append(EmojiSurfacePagePlan(
            id: "recents",
            name: "Recents",
            icon: "clock",
            categoryID: "recents",
            columns: emojiColumnCount,
            items: recents.enumerated().map { index, emoji in
                EmojiSurfaceItemPlan(id: "recents_\(index)", emoji: emoji, categoryID: "recents")
            }
        ))

        let capacity = max(1, emojiColumnCount * 4)
        for category in categories {
            let items = category.emojis.enumerated().map { index, emoji in
                EmojiSurfaceItemPlan(
                    id: "\(category.id)_\(index)",
                    emoji: emoji,
                    categoryID: category.id
                )
            }
            let pageCount = EmojiNavigation.pageCount(itemCount: items.count, pageCapacity: capacity)
            for pageIndex in 0..<pageCount {
                let start = pageIndex * capacity
                let end = min(start + capacity, items.count)
                let pageItems = Array(items[start..<end])
                result.append(EmojiSurfacePagePlan(
                    id: "emoji_\(category.id)_page_\(pageIndex)",
                    name: category.name,
                    icon: category.icon,
                    categoryID: category.id,
                    columns: pageColumnCount(itemCount: pageItems.count, emojiColumnCount: emojiColumnCount),
                    items: pageItems
                ))
            }
        }
        return result
    }
}
