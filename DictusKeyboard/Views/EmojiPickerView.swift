// DictusKeyboard/Views/EmojiPickerView.swift
import SwiftUI
import AudioToolbox
import DictusCore

/// Shared model for category bar items (recents + standard categories).
struct CategoryInfo: Identifiable {
    let id: String
    let name: String
    let icon: String
}

/// Full emoji picker matching the native iOS keyboard:
/// - Recents is a dedicated page instead of being mixed into Smileys.
/// - Every category owns a fixed-width page, so horizontal paging has a real
///   scroll surface even when a category contains only a few items.
/// - Bottom bar: microphone, category bookmarks, delete.
struct EmojiPickerView: View {
    let onEmojiInsert: (String) -> Void
    let onBackToVoice: () -> Void
    let onDelete: () -> Void
    let onDeleteWord: () -> Void
    let surfaceLayout: VoiceOnlyKeyboardPolicy.Layout
    /// Actual available width passed from the parent GeometryReader.
    /// WHY a parameter: In keyboard extensions, UIHostingController may not give
    /// SwiftUI content the full screen width due to safe area or layout margins.
    /// Using the measured parent width guarantees the grid fits without clipping.
    let availableWidth: CGFloat
    /// Actual available height for the picker (excludes the toolbar).
    let availableHeight: CGFloat

    @State private var recentEmojis: [String] = []
    @State private var selectedCategoryID: String = "smileys"
    @State private var scrollRequest: EmojiScrollRequest?
    @State private var variantSession: KeyVariantSession?
    @AppStorage(SharedKeys.keyPopupsEnabled, store: AppGroup.defaults) private var keyPopupsEnabled = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let categories = EmojiStore.categories

    private let headerHeight: CGFloat = 0
    private let categoryBarHeight: CGFloat = 44
    private let bottomBarHeight: CGFloat = 44
    private let rowSpacing: CGFloat = 1
    private let gridHorizontalPadding: CGFloat = 2
    private let minimumEmojiTargetWidth: CGFloat = 44
    private let edgeInset: CGFloat = CGFloat(VoiceOnlyKeyboardPolicy.visibleControlGap)

    /// Keep every grid column wide enough for the Button's hit target.
    private var emojiColumnCount: Int {
        max(1, Int((availableWidth - gridHorizontalPadding * 2) / minimumEmojiTargetWidth))
    }

    /// Height per emoji row, computed to fill available space evenly.
    private var rowHeight: CGFloat {
        max(1, (max(0, availableHeight - headerHeight - bottomBarHeight - edgeInset * 2) - rowSpacing * 3) / 4)
    }

    /// Dynamic cell width based on the shared computed column count.
    private var emojiCellWidth: CGFloat {
        max(0, availableWidth - gridHorizontalPadding * 2) / CGFloat(emojiColumnCount)
    }

    private var recentPageCapacity: Int { emojiColumnCount * 4 }

    // MARK: - Computed data

    private var pages: [EmojiPage] {
        var result: [EmojiPage] = []
        result.append(EmojiPage(
            id: "recents",
            name: "Recents",
            icon: "clock",
            categoryID: "recents",
            items: recentEmojis.enumerated().map { index, emoji in
                EmojiGridItem(id: "recents_\(index)", emoji: emoji, categoryID: "recents")
            }
        ))
        let capacity = max(1, emojiColumnCount * 4)
        for category in categories {
            let items = category.emojis.enumerated().map { index, emoji in
                EmojiGridItem(id: "\(category.id)_\(index)", emoji: emoji, categoryID: category.id)
            }
            for pageIndex in stride(from: 0, to: items.count, by: capacity) {
                let end = min(pageIndex + capacity, items.count)
                result.append(EmojiPage(
                    id: pageIndex == 0 ? category.id : "\(category.id)_page_\(pageIndex / capacity)",
                    name: category.name,
                    icon: category.icon,
                    categoryID: category.id,
                    items: Array(items[pageIndex..<end])
                ))
            }
        }
        return result
    }

    private var categoryAnchorIDs: [String: String] {
        var anchors: [String: String] = [:]
        for page in pages where anchors[page.categoryID] == nil {
            anchors[page.categoryID] = page.id
        }
        return anchors
    }

    private var sectionInfos: [CategoryInfo] {
        [CategoryInfo(id: "recents", name: "Recents", icon: "clock")] +
            categories.map { CategoryInfo(id: $0.id, name: $0.name, icon: $0.icon) }
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                Color.clear.frame(height: edgeInset)
                EmojiScrollCanvas(
                    pages: pages,
                    availableWidth: availableWidth,
                    gridHeight: max(0, availableHeight - headerHeight - bottomBarHeight - edgeInset * 2),
                    emojiCellWidth: emojiCellWidth,
                    rowHeight: rowHeight,
                    gridHorizontalPadding: gridHorizontalPadding,
                    reduceMotion: reduceMotion,
                    scrollRequest: scrollRequest,
                    onVisibleCategory: updateSelectedCategory,
                    onTap: commitEmojiFromTap,
                    onLongPress: presentEmojiVariants
                )
                .id("emoji-scroll-canvas")
                emojiBottomBar
                Color.clear.frame(height: edgeInset)
            }
            if let session = variantSession {
                emojiVariantOverlay(session)
            }
        }
        .frame(width: availableWidth, height: availableHeight)
        .coordinateSpace(name: "emojiPicker")
        .onAppear {
            recentEmojis = RecentEmojis.load(limit: recentPageCapacity)
            selectedCategoryID = "recents"
            scrollRequest = EmojiScrollRequest(id: "recents")
        }
    }

    private var emojiBottomBar: some View {
        let surface = surfaceLayout.surfaceFrame
        // Emoji's bottom bar has no second utility control, so the return-to-voice
        // microphone occupies the leftmost accessory slot and gives the category
        // strip the remaining width.
        let delete = CGRect(
            x: surface.maxX - VoiceOnlyKeyboardPolicy.visibleControlGap - VoiceOnlyKeyboardPolicy.actionHitSize.width,
            y: 0,
            width: VoiceOnlyKeyboardPolicy.actionHitSize.width,
            height: VoiceOnlyKeyboardPolicy.actionHitSize.height
        )
        // The return microphone is a page-local control, not part of the
        // order-dependent voice accessory pair. Keeping it in the first 44pt
        // slot removes the large gap when the 123-first preference is active.
        let microphoneLocalX = CGFloat(
            VoiceOnlyKeyboardPolicy.visibleControlGap
                + VoiceOnlyKeyboardPolicy.controlSize / 2
        )
        let deleteLocalX = CGFloat(delete.midX - surface.minX)
        let categoryMinX = CGFloat(
            VoiceOnlyKeyboardPolicy.visibleControlGap
                + VoiceOnlyKeyboardPolicy.controlSize
                + VoiceOnlyKeyboardPolicy.railSpacing
        )
        let categoryWidth = max(0, deleteLocalX - CGFloat(VoiceOnlyKeyboardPolicy.actionHitSize.width / 2 + VoiceOnlyKeyboardPolicy.railSpacing) - categoryMinX)

        return ZStack(alignment: .topLeading) {
            glassRoundControl(systemName: "mic.fill", label: "Return to voice keyboard", action: onBackToVoice)
                .position(x: microphoneLocalX, y: 22)
            EmojiCategoryBar(
                sections: sectionInfos,
                selectedCategoryID: selectedCategoryID,
                onSelectCategory: { id in
                    selectedCategoryID = id
                    if let anchor = categoryAnchorIDs[id] {
                        scrollRequest = EmojiScrollRequest(id: anchor)
                    }
                }
            )
            .frame(width: categoryWidth, height: 44)
            .position(x: categoryMinX + categoryWidth / 2, y: 22)
            glassDeleteControl
                .position(x: deleteLocalX, y: 22)
        }
        .frame(width: CGFloat(surface.width), height: max(bottomBarHeight, categoryBarHeight))
    }

    private func glassRoundControl(systemName: String, label: String, action: @escaping () -> Void) -> some View {
        Button {
            HapticFeedback.keyTapped()
            action()
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(
                    width: CGFloat(VoiceOnlyKeyboardPolicy.utilityVisualSize),
                    height: CGFloat(VoiceOnlyKeyboardPolicy.utilityVisualSize)
                )
                .keyboardGlass(in: Circle())
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var glassDeleteControl: some View {
        KeyboardDeleteButton(onDelete: onDelete, onDeleteWord: onDeleteWord)
    }

    private func updateSelectedCategory(_ categoryID: String) {
        if selectedCategoryID != categoryID {
            selectedCategoryID = categoryID
        }
    }

    private func insertEmoji(_ emoji: String) {
        HapticFeedback.keyTapped()
        onEmojiInsert(emoji)
        RecentEmojis.add(emoji, limit: recentPageCapacity)
    }

    private func commitEmojiFromTap(_ emoji: String) {
        guard variantSession == nil else { return }
        insertEmoji(emoji)
    }

    private func presentEmojiVariants(item: EmojiGridItem, source: CGRect) {
        guard keyPopupsEnabled else { return }
        let options = EmojiSkinToneVariants.options(for: item.emoji)
        guard options.count > 1 else { return }
        HapticFeedback.keyTapped()
        let popupFrame = KeyVariantPopup.frame(
            for: source,
            optionCount: options.count,
            isEmoji: true,
            in: CGSize(width: availableWidth, height: availableHeight)
        )
        variantSession = KeyVariantSession(
            options: options,
            sourceFrame: source,
            popupFrame: popupFrame,
            isEmoji: true,
            selectedIndex: 0
        )
    }

    @ViewBuilder
    private func emojiVariantOverlay(_ session: KeyVariantSession) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture {
                variantSession = nil
            }
        KeyVariantPopup(
            options: session.options,
            selectedIndex: session.selectedIndex,
            isEmoji: true,
            onSelect: { index in
                guard session.options.indices.contains(index) else { return }
                insertEmoji(session.options[index])
                variantSession = nil
            }
        )
        .frame(width: session.popupFrame.width, height: session.popupFrame.height)
        .position(x: session.popupFrame.midX, y: session.popupFrame.midY)
    }
}

// MARK: - Scroll canvas

private struct EmojiScrollRequest: Equatable {
    let id: String
    let nonce = UUID()
}

private struct EmojiScrollCanvas: View {
    let pages: [EmojiPage]
    let availableWidth: CGFloat
    let gridHeight: CGFloat
    let emojiCellWidth: CGFloat
    let rowHeight: CGFloat
    let gridHorizontalPadding: CGFloat
    let reduceMotion: Bool
    let scrollRequest: EmojiScrollRequest?
    let onVisibleCategory: (String) -> Void
    let onTap: (String) -> Void
    let onLongPress: (EmojiGridItem, CGRect) -> Void
    private let rowSpacing: CGFloat = 1
    @State private var selectedPageID: String? = "recents"

    var body: some View {
        TabView(selection: $selectedPageID) {
            ForEach(pages) { page in
                pageGrid(page)
                    .frame(width: availableWidth, height: gridHeight)
                    .tag(Optional(page.id))
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(width: availableWidth, height: gridHeight)
        .onAppear {
            if let page = pages.first(where: { $0.id == selectedPageID }) ?? pages.first {
                selectedPageID = page.id
                onVisibleCategory(page.categoryID)
            }
        }
        .onChange(of: selectedPageID) { _, id in
            guard let id, pages.contains(where: { $0.id == id }) else { return }
            if let page = pages.first(where: { $0.id == id }) {
                onVisibleCategory(page.categoryID)
            }
        }
        .onChange(of: scrollRequest) { _, request in
            guard let request, pages.contains(where: { $0.id == request.id }) else { return }
            var transaction = Transaction()
            transaction.disablesAnimations = reduceMotion
            withTransaction(transaction) {
                selectedPageID = request.id
            }
        }
    }

    private func pageGrid(_ page: EmojiPage) -> some View {
        let columns = max(1, Int((availableWidth - gridHorizontalPadding * 2) / max(1, emojiCellWidth)))
        let cellWidth = max(1, (availableWidth - gridHorizontalPadding * 2) / CGFloat(columns))
        return LazyVGrid(
                columns: Array(repeating: GridItem(.fixed(cellWidth), spacing: 0), count: columns),
                spacing: rowSpacing
            ) {
                ForEach(page.items) { item in
                    EmojiKey(
                        item: item,
                        emojiCellWidth: cellWidth,
                        rowHeight: rowHeight,
                        reduceMotion: reduceMotion,
                        onTap: { onTap(item.emoji) },
                        onLongPress: { frame in onLongPress(item, frame) }
                    )
                }
            }
            .padding(.horizontal, gridHorizontalPadding)
        .frame(width: availableWidth, height: gridHeight, alignment: .topLeading)
    }

}

private struct EmojiKey: View {
    let item: EmojiGridItem
    let emojiCellWidth: CGFloat
    let rowHeight: CGFloat
    let reduceMotion: Bool
    let onTap: () -> Void
    let onLongPress: (CGRect) -> Void

    @GestureState private var isPressed = false
    @State private var localFrame: CGRect = .zero
    @State private var holdTriggered = false

    private var hasSkinTones: Bool {
        EmojiSkinToneVariants.options(for: item.emoji).count > 1
    }

    @ViewBuilder
    var body: some View {
        if hasSkinTones {
            keyContent.simultaneousGesture(emojiGesture)
        } else {
            keyContent
        }
    }

    private var keyContent: some View {
        Button {
            // A long press opens the variant popup. The button release that
            // follows must not insert the base emoji a second time.
            if holdTriggered {
                holdTriggered = false
                return
            }
            onTap()
        } label: {
            Text(item.emoji)
                .font(.system(size: min(32, max(18, rowHeight * 0.72))))
                .frame(width: emojiCellWidth, height: rowHeight)
                .background {
                    if isPressed {
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .fill(Color.primary.opacity(0.12))
                            .overlay {
                                RoundedRectangle(cornerRadius: 13, style: .continuous)
                                    .stroke(Color.primary.opacity(0.16), lineWidth: 1)
                            }
                            .frame(width: min(emojiCellWidth, rowHeight) - 8, height: rowHeight - 8)
                            .allowsHitTesting(false)
                    }
                }
                .scaleEffect(reduceMotion ? 1 : isPressed ? 1.08 : 1)
                .animation(reduceMotion ? nil : .snappy(duration: 0.16), value: isPressed)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { localFrame = geo.frame(in: .named("emojiPicker")) }
                    .onChange(of: geo.frame(in: .named("emojiPicker"))) { _, frame in
                        localFrame = frame
                    }
            }
        )
        .accessibilityLabel(item.emoji)
    }

    private var emojiGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.4, maximumDistance: 10)
            .updating($isPressed) { value, pressed, _ in pressed = value }
            .onEnded { _ in
                guard hasSkinTones else { return }
                holdTriggered = true
                onLongPress(localFrame)
            }
    }
}

// MARK: - Supporting types

private struct EmojiGridItem: Identifiable {
    let id: String
    let emoji: String
    let categoryID: String
}

private struct VisibleEmojiPagesKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

private struct EmojiPage: Identifiable {
    let id: String
    let name: String
    let icon: String
    let categoryID: String
    let items: [EmojiGridItem]
}
