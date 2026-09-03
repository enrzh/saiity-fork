// DictusKeyboard/Views/EmojiCategoryBar.swift
import SwiftUI
import AudioToolbox
import DictusCore

/// Bottom bar for emoji picker containing category navigation only.
/// Icons act as bookmarks into the vertical emoji grid and stay outside its scroll view.
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
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Return to voice keyboard")

            // Category marks are deliberately plain ASCII so they stay stable across themes.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(sections) { section in
                        let isSelected = selectedCategoryID == section.id
                        Button {
                            onSelectCategory(section.id)
                        } label: {
                            Text(section.icon)
                                .font(.system(size: 16, weight: isSelected ? .semibold : .regular))
                                .foregroundStyle(.primary)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(section.name)
                        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
                    }
                }
                .padding(.horizontal, 2)
            }
            .frame(maxWidth: .infinity, minHeight: 44, maxHeight: 44)
            .clipped()

        }
        .frame(height: 44)
        .clipped()
    }
}
