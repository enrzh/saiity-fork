// DictusKeyboard/Views/EmojiCategoryBar.swift
import SwiftUI
import AudioToolbox
import DictusCore

/// Bottom bar for emoji picker matching Apple/SuperWhisper style:
/// ABC button (left) | search icon | category icons (center) | delete button (right).
/// Icons act as bookmarks into the continuous horizontal emoji grid.
struct EmojiCategoryBar: View {
    let sections: [CategoryInfo]
    let selectedCategoryID: String
    let onSelectCategory: (String) -> Void
    let onSearch: () -> Void
    let onClose: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onClose) {
                Image(systemName: "123")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Return to letters")

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

            Button(action: onDelete) {
                Image(systemName: "delete.backward")
                    .font(.system(size: 17, weight: .medium))
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Delete backward")

        }
        .frame(height: 44)
    }
}
