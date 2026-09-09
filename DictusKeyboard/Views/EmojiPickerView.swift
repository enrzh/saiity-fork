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
/// - One continuous horizontal grid (recents, then every category in order)
/// - Bottom bar: microphone, category bookmarks, delete
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

    /// Recents, then every category, concatenated so scrolling past one section
    /// continues into the next — the native iOS emoji keyboard layout.
    private var allGridItems: [EmojiGridItem] {
        var items: [EmojiGridItem] = []
        if !recentEmojis.isEmpty {
            items.append(contentsOf: recentEmojis.enumerated().map { i, emoji in
                EmojiGridItem(id: "recents_\(i)", emoji: emoji, categoryID: "recents")
            })
        }
        for cat in categories {
            items.append(contentsOf: cat.emojis.enumerated().map { i, emoji in
                EmojiGridItem(id: "\(cat.id)_\(i)", emoji: emoji, categoryID: cat.id)
            })
        }
        return items
    }

    private var categoryAnchorIDs: [String: String] {
        var anchors: [String: String] = [:]
        for item in allGridItems where anchors[item.categoryID] == nil {
            anchors[item.categoryID] = item.id
        }
        return anchors
    }

    private var sectionInfos: [CategoryInfo] {
        var infos: [CategoryInfo] = []
        if !recentEmojis.isEmpty {
            infos.append(CategoryInfo(id: "recents", name: "Recents", icon: "clock"))
        }
        for cat in categories {
            infos.append(CategoryInfo(id: cat.id, name: cat.name, icon: cat.icon))
        }
        return infos
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                Color.clear.frame(height: edgeInset)
                EmojiScrollCanvas(
                    items: allGridItems,
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
    let items: [EmojiGridItem]
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

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHGrid(rows: gridRows, spacing: 0) {
                    ForEach(items) { item in
                        EmojiKey(
                            item: item,
                            emojiCellWidth: emojiCellWidth,
                            rowHeight: rowHeight,
                            reduceMotion: reduceMotion,
                            onTap: { onTap(item.emoji) },
                            onLongPress: { frame in onLongPress(item, frame) }
                        )
                        .id(item.id)
                    }
                }
                .padding(.horizontal, gridHorizontalPadding)
            }
            .coordinateSpace(name: "emojiViewport")
            .frame(width: availableWidth, height: gridHeight, alignment: .top)
            .clipped()
            .onPreferenceChange(VisibleCategoryFramesKey.self) { frames in
                guard let category = leftmostVisibleCategory(in: frames) else { return }
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

    private func leftmostVisibleCategory(in frames: [String: VisibleEmojiFrame]) -> String? {
        frames.values
            .filter { $0.frame.maxX > 1 && $0.frame.minX < availableWidth - 1 }
            .min(by: { $0.frame.minX < $1.frame.minX })?
            .categoryID
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

    private var hasSkinTones: Bool {
        EmojiSkinToneVariants.options(for: item.emoji).count > 1
    }

    var body: some View {
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
            .background(
                GeometryReader { geo in
                    Color.clear.preference(
                        key: VisibleCategoryFramesKey.self,
                        value: [item.id: VisibleEmojiFrame(
                            categoryID: item.categoryID,
                            frame: geo.frame(in: .named("emojiViewport"))
                        )]
                    )
                    .onAppear { localFrame = geo.frame(in: .named("emojiPicker")) }
                    .onChange(of: geo.frame(in: .named("emojiPicker"))) { _, frame in
                        localFrame = frame
                    }
                }
            )
            // A bounded hold fails as soon as scrolling starts. No cell pan
            // recognizer competes with the scroll view's horizontal pan.
            .gesture(emojiGesture)
            .accessibilityLabel(item.emoji)
    }

    private var emojiGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.4, maximumDistance: 10)
            .updating($isPressed) { value, pressed, _ in pressed = value }
            .exclusively(before: TapGesture())
            .onEnded { value in
                switch value {
                case .first(true):
                    if hasSkinTones { onLongPress(localFrame) } else { onTap() }
                case .second:
                    onTap()
                default:
                    break
                }
            }
    }
}

// MARK: - Supporting types

private struct EmojiGridItem: Identifiable {
    let id: String
    let emoji: String
    let categoryID: String
}

private struct VisibleEmojiFrame: Equatable {
    let categoryID: String
    let frame: CGRect
}

private struct VisibleCategoryFramesKey: PreferenceKey {
    static var defaultValue: [String: VisibleEmojiFrame] = [:]

    static func reduce(value: inout [String: VisibleEmojiFrame], nextValue: () -> [String: VisibleEmojiFrame]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}
