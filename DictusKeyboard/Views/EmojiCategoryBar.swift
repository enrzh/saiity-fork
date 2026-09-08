// DictusKeyboard/Views/EmojiCategoryBar.swift
import SwiftUI
import AudioToolbox
import DictusCore

/// Native-style category bookmarks. Highlight follows the currently visible
/// section of the continuous horizontal emoji grid, and the strip scrolls to
/// keep that highlight on screen.
struct EmojiCategoryBar: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let sections: [CategoryInfo]
    let selectedCategoryID: String
    let onSelectCategory: (String) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ScrollViewReader { proxy in
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
                                    .frame(width: 36, height: 36)
                                    .background {
                                        if isSelected {
                                            Circle()
                                                .fill(Color.primary.opacity(0.12))
                                        }
                                    }
                                    .frame(width: 44, height: 44)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .id(section.id)
                            .accessibilityLabel(section.name)
                            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
                        }
                    }
                    .padding(.horizontal, 2)
                }
                .frame(maxWidth: .infinity, minHeight: 44, maxHeight: 44)
                .onChange(of: selectedCategoryID) { _, id in
                    var transaction = Transaction()
                    transaction.disablesAnimations = reduceMotion
                    withTransaction(transaction) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
                .onAppear {
                    proxy.scrollTo(selectedCategoryID, anchor: .center)
                }
            }
        }
        .frame(height: 44)
    }
}
