// DictusKeyboard/Views/EmojiCategoryBar.swift
import SwiftUI
import AudioToolbox
import DictusCore

/// Bottom bar for emoji picker containing category navigation only.
/// Icons act as bookmarks into the continuous horizontal emoji grid.
struct EmojiCategoryBar: View {
    let sections: [CategoryInfo]
    let selectedCategoryID: String
    let onSelectCategory: (String) -> Void
    let onBackToVoice: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onBackToVoice) {
                Image(systemName: "mic.fill")
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Return to voice keyboard")

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
                            .opacity(isSelected ? 1.0 : 0.5)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(section.name)
                        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
                    }
                }
                .padding(.horizontal, 2)
            }

        }
        .frame(height: 44)
    }
}
