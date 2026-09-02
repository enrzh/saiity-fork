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
/// - Search bar at top (pill shape)
/// - Single continuous horizontal LazyHGrid (4 rows, swipe left/right)
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
    private let language = SupportedLanguage.active.rawValue

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

/// Mini keyboard for emoji search with key popups and haptic feedback.
/// Uses 40pt key height to fit within the emoji picker without clipping.
/// Equatable to prevent re-renders when search text changes (layout is static).
private struct MiniSearchKeyboard: View, Equatable {
    let onCharacter: (String) -> Void
    let onDelete: () -> Void
    let onSpace: () -> Void

    static func == (lhs: MiniSearchKeyboard, rhs: MiniSearchKeyboard) -> Bool {
        true // Layout never changes, only closures differ
    }

    private let keyHeight: CGFloat = 44

    private var rows: [[String]] {
        switch LayoutType.active {
        case .azerty:
            return [
                ["a", "z", "e", "r", "t", "y", "u", "i", "o", "p"],
                ["q", "s", "d", "f", "g", "h", "j", "k", "l", "m"],
                ["w", "x", "c", "v", "b", "n"]
            ]
        case .qwerty:
            return [
                ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"],
                ["a", "s", "d", "f", "g", "h", "j", "k", "l"],
                ["z", "x", "c", "v", "b", "n", "m"]
            ]
        case .qwertz:
            // Read from the shared layout data rather than re-typed here, so the
            // search keyboard cannot drift from the real one (#151).
            return QWERTZLayout.lowercasedLettersRows
        }
    }

    var body: some View {
        VStack(spacing: 3) {
            ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                HStack(spacing: 4) {
                    ForEach(row, id: \.self) { letter in
                        MiniKeyButton(label: letter, height: keyHeight) {
                            HapticFeedback.keyTapped()
                            AudioServicesPlaySystemSound(1104)
                            onCharacter(letter)
                        }
                    }
                    if rowIndex == 2 {
                        Button {
                            HapticFeedback.keyTapped()
                            AudioServicesPlaySystemSound(1155)
                            onDelete()
                        } label: {
                            Image(systemName: "delete.backward")
                                .font(.system(size: 18))
                                .frame(maxWidth: .infinity)
                                .frame(height: keyHeight)
                                .background(KeyMetrics.letterKeyColor)
                                .cornerRadius(KeyMetrics.keyCornerRadius)
                        }
                        .foregroundColor(Color(.label))
                    }
                }
            }
            Button {
                HapticFeedback.keyTapped()
                AudioServicesPlaySystemSound(1156)
                onSpace()
            } label: {
                Text("space")
                    .font(.system(size: 16))
                    .frame(maxWidth: .infinity)
                    .frame(height: keyHeight)
                    .background(KeyMetrics.letterKeyColor)
                    .cornerRadius(KeyMetrics.keyCornerRadius)
            }
            .foregroundColor(Color(.label))
        }
        .padding(.horizontal, KeyMetrics.rowSidePadding)
        .padding(.bottom, 2)
    }
}

/// A single key in the mini search keyboard with press popup.
/// Uses a lightweight ButtonStyle instead of DragGesture for better performance.
private struct MiniKeyButton: View {
    let label: String
    let height: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 22))
                .foregroundColor(Color(.label))
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .background(KeyMetrics.letterKeyColor)
                .cornerRadius(KeyMetrics.keyCornerRadius)
        }
        .buttonStyle(MiniKeyButtonStyle(label: label, height: height))
    }
}

private struct MiniKeyButtonStyle: ButtonStyle {
    let label: String
    let height: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay(
                Group {
                    if configuration.isPressed {
                        KeyPopup(label: label)
                            .offset(y: -(height + 8))
                    }
                },
                alignment: .top
            )
    }
}
