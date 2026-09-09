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

    /// Number of complete rows that fit above the bottom bar.
    private var rowCount: Int {
        let gridSpace = availableHeight - headerHeight - bottomBarHeight - edgeInset * 2
        let rowWithSpacing: CGFloat = rowHeight + rowSpacing
        return max(1, Int(gridSpace / rowWithSpacing))
    }

    /// Height per emoji row, computed to fill available space evenly.
    private var rowHeight: CGFloat { 44 }

    private var gridRows: [GridItem] {
        Array(repeating: GridItem(.fixed(rowHeight), spacing: rowSpacing), count: rowCount)
    }

    /// Dynamic cell width based on the shared computed column count.
    private var emojiCellWidth: CGFloat {
        max(0, availableWidth - gridHorizontalPadding * 2) / CGFloat(emojiColumnCount)
    }

    // MARK: - Computed data

    private var pages: [EmojiPage] {
        var result: [EmojiPage] = []
        if !recentEmojis.isEmpty {
            result.append(EmojiPage(
                id: "recents",
                name: "Recents",
                icon: "clock",
                items: recentEmojis.enumerated().map { index, emoji in
                    EmojiGridItem(id: "recents_\(index)", emoji: emoji, categoryID: "recents")
                }
            ))
        }
        result.append(contentsOf: categories.map { category in
            EmojiPage(
                id: category.id,
                name: category.name,
                icon: category.icon,
                items: category.emojis.enumerated().map { index, emoji in
                    EmojiGridItem(id: "\(category.id)_\(index)", emoji: emoji, categoryID: category.id)
                }
            )
        })
        return result
    }

    private var categoryAnchorIDs: [String: String] {
        Dictionary(uniqueKeysWithValues: pages.map { ($0.id, $0.id) })
    }

    private var sectionInfos: [CategoryInfo] {
        pages.map { CategoryInfo(id: $0.id, name: $0.name, icon: $0.icon) }
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
                    gridRows: gridRows,
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
            recentEmojis = RecentEmojis.load()
            if !recentEmojis.isEmpty {
                selectedCategoryID = "recents"
            }
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
        RecentEmojis.add(emoji)
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
    let gridRows: [GridItem]
    let gridHorizontalPadding: CGFloat
    let reduceMotion: Bool
    let scrollRequest: EmojiScrollRequest?
    let onVisibleCategory: (String) -> Void
    let onTap: (String) -> Void
    let onLongPress: (EmojiGridItem, CGRect) -> Void
    private let rowSpacing: CGFloat = 1

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                // Keep the page track eager and stable. LazyHStack can stop
                // extending a horizontal keyboard track after its initially
                // realized pages, which makes a swipe appear to hit an invisible
                // end. The emoji cells remain lazy inside each page.
                HStack(spacing: 0) {
                    ForEach(pages) { page in
                        let columns = columnsPerPage(for: page)
                        let pageWidth = pageWidth(for: page, columns: columns)
                        LazyVGrid(
                            columns: Array(repeating: GridItem(.fixed(emojiCellWidthForPage(page, columns: columns)), spacing: 0), count: columns),
                            spacing: rowSpacing
                        ) {
                            ForEach(page.items) { item in
                                EmojiKey(
                                    item: item,
                                    emojiCellWidth: emojiCellWidthForPage(page, columns: columns),
                                    rowHeight: rowHeight,
                                    reduceMotion: reduceMotion,
                                    onTap: { onTap(item.emoji) },
                                    onLongPress: { frame in onLongPress(item, frame) }
                                )
                            }
                        }
                        .frame(width: pageWidth, height: gridHeight, alignment: .topLeading)
                        .id(page.id)
                        .background(
                            GeometryReader { geometry in
                                Color.clear.preference(
                                    key: VisibleEmojiPagesKey.self,
                                    value: [page.id: geometry.frame(in: .named("emojiViewport"))]
                                )
                            }
                        )
                    }
                }
                .padding(.horizontal, gridHorizontalPadding)
            }
            .coordinateSpace(name: "emojiViewport")
            .frame(width: availableWidth, height: gridHeight, alignment: .top)
            .clipped()
            .onPreferenceChange(VisibleEmojiPagesKey.self) { frames in
                guard let category = leftmostVisiblePage(in: frames) else { return }
                onVisibleCategory(category)
            }
            .onChange(of: scrollRequest) { _, request in
                guard let request else { return }
                var transaction = Transaction()
                transaction.disablesAnimations = reduceMotion
                withTransaction(transaction) {
                    proxy.scrollTo(request.id, anchor: .leading)
                }
            }
        }
    }

    private func columnsPerPage(for page: EmojiPage) -> Int {
        let itemCount = max(1, page.items.count)
        return max(1, Int(ceil(Double(itemCount) / Double(max(1, gridRows.count)))))
    }

    private func emojiCellWidthForPage(_ page: EmojiPage, columns: Int) -> CGFloat {
        max(44, (availableWidth - gridHorizontalPadding * 2) / CGFloat(max(1, columns)))
    }

    private func pageWidth(for page: EmojiPage, columns: Int) -> CGFloat {
        max(availableWidth, CGFloat(columns) * emojiCellWidthForPage(page, columns: columns) + gridHorizontalPadding * 2)
    }

    private func leftmostVisiblePage(in frames: [String: CGRect]) -> String? {
        frames
            .filter { $0.value.maxX > gridHorizontalPadding && $0.value.minX < availableWidth - gridHorizontalPadding }
            .min(by: { abs($0.value.minX - gridHorizontalPadding) < abs($1.value.minX - gridHorizontalPadding) })?
            .key
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
        Button(action: onTap) {
            Text(item.emoji)
                .font(.system(size: 32))
                .frame(minWidth: 44, minHeight: 44)
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
    let items: [EmojiGridItem]
}
