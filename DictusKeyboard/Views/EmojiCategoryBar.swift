// DictusKeyboard/Views/EmojiCategoryBar.swift
import SwiftUI
import AudioToolbox
import DictusCore

/// Bottom bar for emoji picker containing only search and category navigation.
/// Icons act as bookmarks into the continuous horizontal emoji grid.
struct EmojiCategoryBar: View {
    let sections: [CategoryInfo]
    let selectedCategoryID: String
    let onSelectCategory: (String) -> Void
    let onSearch: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            // Search button — 44pt minimum tap target (Apple HIG)
            Button {
                HapticFeedback.keyTapped()
                onSearch()
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(Color(.label))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .fixedSize()

            // Category icons — representative emojis like native iOS picker
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(sections) { section in
                        let isSelected = selectedCategoryID == section.id
                        Button {
                            onSelectCategory(section.id)
                        } label: {
                            Group {
                                if let emoji = section.representativeEmoji {
                                    Text(emoji)
                                        .font(.system(size: 20))
                                } else {
                                    // Recents: use clock SF Symbol
                                    Image(systemName: section.icon)
                                        .font(.system(size: 16))
                                        .foregroundColor(isSelected ? Color(.label) : Color(.tertiaryLabel))
                                }
                            }
                            .frame(width: 44, height: 44)
                            .background(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(isSelected ? Color(.systemGray4) : Color.clear)
                            )
                            .opacity(isSelected ? 1.0 : 0.5)
                        }
                    }
                }
                .padding(.horizontal, 2)
            }

        }
        .frame(height: 44)
    }
}
