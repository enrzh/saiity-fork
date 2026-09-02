// DictusKeyboard/Views/EmojiPickerView.swift
import SwiftUI
import AudioToolbox
import DictusCore

/// Shared model for category bar items (recents + standard categories).
struct CategoryInfo: Identifiable {
    let id: String
    let name: String
    let icon: String
    let representativeEmoji: String?  // nil for recents (uses SF Symbol clock icon)
}

/// Full emoji picker matching Apple/SuperWhisper style:
/// - Single category-focused vertical grid
/// - Category bar at bottom as bookmarks into the grid
struct EmojiPickerView: View {
    let onEmojiInsert: (String) -> Void
    /// Actual available width passed from the parent GeometryReader.
    /// WHY a parameter: In keyboard extensions, UIHostingController may not give
    /// SwiftUI content the full screen width due to safe area or layout margins.
    /// Using the measured parent width guarantees the grid fits without clipping.
    let availableWidth: CGFloat
    /// Actual available height for the picker (excludes the toolbar).
    let availableHeight: CGFloat

    @State private var recentEmojis: [String] = []
    @State private var selectedCategoryID: String = "smileys"

    private let categories = EmojiStore.categories

    // Grid sizing constants
    private let headerHeight: CGFloat = 20
    private let categoryBarHeight: CGFloat = 36
    private let rowSpacing: CGFloat = 1

    /// Number of rows that fit in available height after subtracting header + category bar.
    private var rowCount: Int {
        let gridSpace = availableHeight - headerHeight - categoryBarHeight
        let rowWithSpacing: CGFloat = rowHeight + rowSpacing
        return max(3, Int(gridSpace / rowWithSpacing))
    }

    /// Height per emoji row, computed to fill available space evenly.
    private var rowHeight: CGFloat { 44 }

    private var gridRows: [GridItem] {
        Array(repeating: GridItem(.fixed(rowHeight), spacing: rowSpacing), count: rowCount)
    }

    /// Columns for vertical grid: 8 emojis per row filling the full width.
    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.fixed(emojiCellWidth), spacing: 0), count: 8)
    }

    /// Dynamic cell width: exactly 8 emojis per row based on actual available width.
    private var emojiCellWidth: CGFloat {
        (availableWidth - 4) / 8
    }

    // MARK: - Computed data

    /// Returns only the emojis for the currently selected category.
    /// WHY category pagination: The previous flat grid rendered ALL ~1800 emojis at once,
    /// causing CoreText to cache every glyph (~65KB each) = 139 MiB. By showing only one
    /// category at a time (max ~230 emojis), peak memory stays under ~15 MiB.
    private var currentCategoryEmojis: [EmojiGridItem] {
        if selectedCategoryID == "recents" {
            return recentEmojis.enumerated().map { i, emoji in
                EmojiGridItem(id: "recents_\(i)", emoji: emoji, categoryID: "recents")
            }
        }
        guard let cat = categories.first(where: { $0.id == selectedCategoryID }) else {
            return []
        }
        return cat.emojis.enumerated().map { i, emoji in
            EmojiGridItem(id: "\(cat.id)_\(i)", emoji: emoji, categoryID: cat.id)
        }
    }

    private var sectionInfos: [CategoryInfo] {
        var infos: [CategoryInfo] = []
        if !recentEmojis.isEmpty {
            infos.append(CategoryInfo(id: "recents", name: "Récents", icon: "clock", representativeEmoji: nil))
        }
        for cat in categories {
            infos.append(CategoryInfo(id: cat.id, name: cat.name, icon: cat.icon, representativeEmoji: cat.representativeEmoji))
        }
        return infos
    }

    /// Display name for the currently selected category.
    private var selectedCategoryName: String {
        sectionInfos.first(where: { $0.id == selectedCategoryID })?.name.uppercased() ?? ""
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            normalMode
        }
        .frame(width: availableWidth, height: availableHeight)
        .clipped()
        .onAppear {
            recentEmojis = RecentEmojis.load()
            if !recentEmojis.isEmpty {
                selectedCategoryID = "recents"
            }
        }
    }

    // MARK: - Normal mode

    @ViewBuilder
    private var normalMode: some View {
        // Category name label (e.g. "SMILEYS & PEOPLE")
        HStack {
            Text(selectedCategoryName)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .layoutPriority(1)
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.top, 4)
        .padding(.bottom, 1)

        // Vertical emoji grid — fills width first, scrolls down for more.
        // .id(selectedCategoryID) forces SwiftUI to destroy and recreate the grid when
        // the user switches categories, which releases the old Text views and their
        // CoreText glyph caches -- this is the key to keeping memory under 50 MiB.
        ScrollView(.vertical, showsIndicators: false) {
            LazyVGrid(columns: gridColumns, spacing: 0) {
                ForEach(currentCategoryEmojis) { item in
                    Button {
                        HapticFeedback.keyTapped()
                        onEmojiInsert(item.emoji)
                        RecentEmojis.add(item.emoji)
                        recentEmojis = RecentEmojis.load()
                    } label: {
                        Text(item.emoji)
                            .font(.system(size: 32))
                            .frame(width: emojiCellWidth, height: rowHeight)
                    }
                    .id(item.id)
                }
            }
            .padding(.horizontal, 2)
            .id(selectedCategoryID)
        }

        EmojiCategoryBar(
            sections: sectionInfos,
            selectedCategoryID: selectedCategoryID,
            onSelectCategory: { id in
                selectedCategoryID = id
            },
        )
    }

}

// MARK: - Supporting types

private struct EmojiGridItem: Identifiable {
    let id: String
    let emoji: String
    let categoryID: String
}
