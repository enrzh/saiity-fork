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
    /// Actual available width passed from the parent GeometryReader.
    /// WHY a parameter: In keyboard extensions, UIHostingController may not give
    /// SwiftUI content the full screen width due to safe area or layout margins.
    /// Using the measured parent width guarantees the grid fits without clipping.
    let availableWidth: CGFloat
    /// Actual available height for the picker (excludes the toolbar).
    let availableHeight: CGFloat

    @State private var recentEmojis: [String] = []
    @State private var selectedCategoryID: String = "smileys"
    @State private var pressedEmojiIndex: Int?
    @State private var emojiCommitLocked = false
    @State private var variantSession: KeyVariantSession?
    @State private var programmaticScroll = false
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
                horizontalGrid
                emojiBottomBar
                Color.clear.frame(height: edgeInset)
            }
            if let session = variantSession {
                emojiVariantOverlay(session)
            }
        }
        .frame(width: availableWidth, height: availableHeight)
        .coordinateSpace(name: "emojiPicker")
        .onPreferenceChange(NamedFramePreference.self) { NamedFramePreference.latest.merge($0, uniquingKeysWith: { $1 }) }
        .onAppear {
            recentEmojis = RecentEmojis.load()
            if !recentEmojis.isEmpty {
                selectedCategoryID = "recents"
            }
        }
    }

    // MARK: - Horizontal grid

    @ViewBuilder
    private var horizontalGrid: some View {
        let items = allGridItems
        let gridHeight = max(0, availableHeight - headerHeight - bottomBarHeight - edgeInset * 2)

        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHGrid(rows: gridRows, spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        emojiCell(item, index: index)
                            .id(item.id)
                    }
                }
                .padding(.horizontal, gridHorizontalPadding)
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: EmojiScrollOffsetKey.self,
                            value: geo.frame(in: .named("emojiViewport")).minX
                        )
                    }
                )
            }
            .coordinateSpace(name: "emojiViewport")
            .frame(width: availableWidth, height: gridHeight, alignment: .top)
            .clipped()
            .onPreferenceChange(EmojiScrollOffsetKey.self) { minX in
                updateSelectedCategory(contentMinX: minX, items: items)
            }
            .onChange(of: selectedCategoryID) { _, id in
                guard programmaticScroll, let anchor = categoryAnchorIDs[id] else { return }
                proxy.scrollTo(anchor, anchor: .leading)
                DispatchQueue.main.async {
                    programmaticScroll = false
                }
            }
        }
    }

    private func emojiCell(_ item: EmojiGridItem, index: Int) -> some View {
        let variants = EmojiSkinToneVariants.options(for: item.emoji)
        return Button { commitEmojiFromTap(item.emoji) } label: {
            ZStack {
                if pressedEmojiIndex == index {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(Color.primary.opacity(0.12))
                        .overlay {
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .stroke(Color.primary.opacity(0.16), lineWidth: 1)
                        }
                        .frame(width: min(emojiCellWidth, rowHeight) - 8, height: rowHeight - 8)
                        .allowsHitTesting(false)
                }
                Text(item.emoji)
                    .font(.system(size: 32))
                    .frame(width: emojiCellWidth, height: rowHeight)
                    .scaleEffect(reduceMotion ? 1 : pressedEmojiIndex == index ? 1.08 : 1)
                    .animation(reduceMotion ? nil : .snappy(duration: 0.16), value: pressedEmojiIndex)
            }
            .frame(minWidth: 44, minHeight: 44)
            .frame(width: emojiCellWidth, height: rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: NamedFramePreference.self,
                    value: [item.id: geo.frame(in: .named("emojiPicker"))]
                )
            }
        )
        .modifier(OptionalEmojiLongPress(
            enabled: variants.count > 1,
            onChanged: { location in
                handleEmojiLongPressChanged(item: item, location: location)
            },
            onEnded: {
                commitEmojiVariantSession()
            }
        ))
        .frame(minWidth: 44, minHeight: 44)
        .accessibilityLabel(item.emoji)
    }

    private var emojiBottomBar: some View {
        HStack(spacing: 6) {
            glassRoundControl(systemName: "mic.fill", label: "Return to voice keyboard", action: onBackToVoice)
            EmojiCategoryBar(
                sections: sectionInfos,
                selectedCategoryID: selectedCategoryID,
                onSelectCategory: { id in
                    programmaticScroll = true
                    selectedCategoryID = id
                }
            )
            glassDeleteControl
        }
        .padding(.horizontal, CGFloat(VoiceOnlyKeyboardPolicy.horizontalPadding))
        .frame(width: availableWidth, height: max(bottomBarHeight, categoryBarHeight))
    }

    private func glassRoundControl(systemName: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
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
        DeleteRepeatButton(onDelete: onDelete)
    }

    private func updateSelectedCategory(contentMinX: CGFloat, items: [EmojiGridItem]) {
        guard !programmaticScroll, !items.isEmpty, emojiCellWidth > 0 else { return }
        let scrolled = max(0, -contentMinX - gridHorizontalPadding)
        let column = Int(scrolled / emojiCellWidth)
        let index = min(items.count - 1, max(0, column * rowCount))
        let category = items[index].categoryID
        if selectedCategoryID != category {
            selectedCategoryID = category
        }
    }

    private func insertEmoji(_ emoji: String) {
        HapticFeedback.keyTapped()
        onEmojiInsert(emoji)
        RecentEmojis.add(emoji)
        recentEmojis = RecentEmojis.load()
    }

    private func commitEmojiFromTap(_ emoji: String) {
        guard !emojiCommitLocked, variantSession == nil else { return }
        emojiCommitLocked = true
        insertEmoji(emoji)
        resetEmojiGestureLock()
    }

    private func handleEmojiLongPressChanged(item: EmojiGridItem, location: CGPoint) {
        let options = EmojiSkinToneVariants.options(for: item.emoji)
        guard options.count > 1 else { return }
        if variantSession == nil {
            emojiCommitLocked = true
            HapticFeedback.keyTapped()
            let source = NamedFramePreference.latest[item.id] ?? CGRect(
                x: location.x - emojiCellWidth / 2,
                y: location.y - rowHeight / 2,
                width: emojiCellWidth,
                height: rowHeight
            )
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
            return
        }
        guard var session = variantSession else { return }
        let index = KeyVariantPopup.selectedIndex(
            at: location,
            popupFrame: session.popupFrame,
            optionCount: session.options.count
        )
        if session.selectedIndex != index {
            session.selectedIndex = index
            variantSession = session
            HapticFeedback.keyTapped()
        }
    }

    @ViewBuilder
    private func emojiVariantOverlay(_ session: KeyVariantSession) -> some View {
        KeyVariantPopup(
            options: session.options,
            selectedIndex: session.selectedIndex,
            isEmoji: true
        )
        .frame(width: session.popupFrame.width, height: session.popupFrame.height)
        .position(x: session.popupFrame.midX, y: session.popupFrame.midY)
        .allowsHitTesting(false)
    }

    private func commitEmojiVariantSession() {
        guard let session = variantSession,
              session.options.indices.contains(session.selectedIndex) else {
            variantSession = nil
            resetEmojiGestureLock()
            return
        }
        insertEmoji(session.options[session.selectedIndex])
        variantSession = nil
        resetEmojiGestureLock()
    }

    private func resetEmojiGestureLock() {
        DispatchQueue.main.async {
            emojiCommitLocked = false
        }
    }
}

// MARK: - Supporting types

private struct EmojiGridItem: Identifiable {
    let id: String
    let emoji: String
    let categoryID: String
}

private struct EmojiScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct OptionalEmojiLongPress: ViewModifier {
    let enabled: Bool
    let onChanged: (CGPoint) -> Void
    let onEnded: () -> Void

    func body(content: Content) -> some View {
        if enabled {
            content.highPriorityGesture(
                LongPressGesture(minimumDuration: 0.4)
                    .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named("emojiPicker")))
                    .onChanged { value in
                        if case .second(true, let drag?) = value {
                            onChanged(drag.location)
                        }
                    }
                    .onEnded { _ in
                        onEnded()
                    }
            )
        } else {
            content
        }
    }
}

private struct DeleteRepeatButton: View {
    let onDelete: () -> Void
    @State private var deleteRepeatTimer: Timer?
    @State private var deleteRepeatStarted = false

    var body: some View {
        Button {
            if deleteRepeatStarted {
                deleteRepeatStarted = false
                return
            }
            onDelete()
        } label: {
            Image(systemName: "delete.backward")
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
        .accessibilityLabel("Delete backward")
        .onLongPressGesture(minimumDuration: 0.35, pressing: { pressing in
            if pressing {
                startDeleteRepeat()
            } else {
                stopDeleteRepeat()
            }
        }, perform: {})
        .onDisappear { stopDeleteRepeat() }
    }

    private func startDeleteRepeat() {
        stopDeleteRepeat()
        deleteRepeatStarted = true
        onDelete()
        let timer = Timer(timeInterval: 0.1, repeats: true) { _ in
            onDelete()
        }
        deleteRepeatTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopDeleteRepeat() {
        deleteRepeatTimer?.invalidate()
        deleteRepeatTimer = nil
    }
}

extension NamedFramePreference {
    static var latest: [String: CGRect] = [:]
}
