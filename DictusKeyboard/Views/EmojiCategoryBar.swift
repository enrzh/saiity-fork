// DictusKeyboard/Views/EmojiCategoryBar.swift
import SwiftUI
import AudioToolbox
import DictusCore

/// Category bookmarks for the emoji grid. The shared emoji / mic / space / delete /
/// return bar lives below this row.
struct EmojiCategoryBar: View {
    let sections: [CategoryInfo]
    let selectedCategoryID: String
    let onSelectCategory: (String) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(sections) { section in
                        let isSelected = selectedCategoryID == section.id
                        Button {
                            onSelectCategory(section.id)
                        } label: {
                            Image(systemName: section.icon)
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
