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
    let onBackToVoice: () -> Void
    /// Actual available width passed from the parent GeometryReader.
    /// WHY a parameter: In keyboard extensions, UIHostingController may not give
    /// SwiftUI content the full screen width due to safe area or layout margins.
    /// Using the measured parent width guarantees the grid fits without clipping.
    let availableWidth: CGFloat
    /// Actual available height for the picker (excludes the toolbar).
    let availableHeight: CGFloat

    @State private var recentEmojis: [String] = []
    @State private var selectedCategoryID: String = "smileys"
    @State private var pressedEmojiIndex: Int?

    private let categories = EmojiStore.categories

    // Grid sizing constants
    private let headerHeight: CGFloat = 0
    private let categoryBarHeight: CGFloat = 44
    private let rowSpacing: CGFloat = 1
    private let emojiColumnCount: Int = 8
    private let gridHorizontalPadding: CGFloat = 2

    /// Number of complete rows that fit above the category bar.
    private var rowCount: Int {
        let gridSpace = availableHeight - headerHeight - categoryBarHeight
        let rowWithSpacing: CGFloat = rowHeight + rowSpacing
        return max(1, Int(gridSpace / rowWithSpacing))
    }

    /// Height per emoji row, computed to fill available space evenly.
    private var rowHeight: CGFloat { 44 }

    private var gridRows: [GridItem] {
        Array(repeating: GridItem(.fixed(rowHeight), spacing: rowSpacing), count: rowCount)
    }

    /// Columns for vertical grid: 8 emojis per row filling the full width.
    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.fixed(emojiCellWidth), spacing: 0), count: emojiColumnCount)
    }

    /// Dynamic cell width: exactly 8 emojis per row based on actual available width.
    private var emojiCellWidth: CGFloat {
        (availableWidth - gridHorizontalPadding * 2) / CGFloat(emojiColumnCount)
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
        // Vertical emoji grid — fills width first, scrolls down for more.
        // .id(selectedCategoryID) forces SwiftUI to destroy and recreate the grid when
        // the user switches categories, which releases the old Text views and their
        // CoreText glyph caches -- this is the key to keeping memory under 50 MiB.
        ScrollView(.vertical, showsIndicators: false) {
            ZStack(alignment: .topLeading) {
                emojiPointerHighlight

                LazyVGrid(columns: gridColumns, spacing: rowSpacing) {
                    ForEach(currentCategoryEmojis) { item in
                        let itemIndex = currentCategoryEmojis.firstIndex(where: { $0.id == item.id }) ?? 0
                        Text(item.emoji)
                            .font(.system(size: 32))
                            .frame(width: emojiCellWidth, height: rowHeight)
                            .contentShape(Rectangle())
                            .scaleEffect(pressedEmojiIndex == itemIndex ? 1.08 : 1)
                            .animation(.snappy(duration: 0.16), value: pressedEmojiIndex)
                            .accessibilityLabel(item.emoji)
                            .accessibilityAddTraits(.isButton)
                            .accessibilityAction {
                                insertEmoji(item.emoji)
                            }
                            .id(item.id)
                        }
                }
            .padding(.horizontal, gridHorizontalPadding)
            .id(selectedCategoryID)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        pressedEmojiIndex = emojiIndex(at: value.location)
                    }
                    .onEnded { value in
                        guard let index = emojiIndex(at: value.location), currentCategoryEmojis.indices.contains(index) else {
                            pressedEmojiIndex = nil
                            return
                        }
                        insertEmoji(currentCategoryEmojis[index].emoji)
                        pressedEmojiIndex = nil
                    }
            )
        }
        }

        EmojiCategoryBar(
            sections: sectionInfos,
            selectedCategoryID: selectedCategoryID,
            onSelectCategory: { id in
                selectedCategoryID = id
            },
            onBackToVoice: onBackToVoice
        )
    }

    @ViewBuilder
    private var emojiPointerHighlight: some View {
        if let index = pressedEmojiIndex {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(.thinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                }
                .frame(width: max(emojiCellWidth - 8, 36), height: rowHeight - 8)
                .position(
                    x: gridHorizontalPadding + CGFloat(index % emojiColumnCount) * emojiCellWidth + emojiCellWidth / 2,
                    y: CGFloat(index / emojiColumnCount) * (rowHeight + rowSpacing) + rowHeight / 2
                )
                .allowsHitTesting(false)
                .transition(.opacity)
        }
    }

    private func emojiIndex(at point: CGPoint) -> Int? {
        let column = Int((point.x - gridHorizontalPadding) / emojiCellWidth)
        let row = Int(point.y / (rowHeight + rowSpacing))
        guard column >= 0, column < emojiColumnCount, row >= 0 else { return nil }
        let index = row * emojiColumnCount + column
        return currentCategoryEmojis.indices.contains(index) ? index : nil
    }

    private func insertEmoji(_ emoji: String) {
        HapticFeedback.keyTapped()
        onEmojiInsert(emoji)
        RecentEmojis.add(emoji)
        recentEmojis = RecentEmojis.load()
    }

}

extension View {
    @ViewBuilder
    func keyboardGlassEffect() -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular.interactive(), in: .rect(cornerRadius: 12))
        } else {
            self.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}

// MARK: - Supporting types

private struct EmojiGridItem: Identifiable {
    let id: String
    let emoji: String
    let categoryID: String
}
