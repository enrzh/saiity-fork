// DictusKeyboard/Views/EmojiPickerView.swift
import SwiftUI
import AudioToolbox
import UIKit
import SyllivraKernel


typealias EmojiKeyboardSurface = EmojiPickerView

/// Shared model for category bar items (recents + standard categories).
struct CategoryInfo: Identifiable {
    let id: String
    let name: String
    let icon: String

    static var emojiBarSections: [CategoryInfo] {
        [CategoryInfo(id: "recents", name: "Recents", icon: "clock")] +
            EmojiStore.categories.map { CategoryInfo(id: $0.id, name: $0.name, icon: $0.icon) }
    }
}

/// Full emoji picker matching the native iOS keyboard:
/// - Recents is a dedicated page instead of being mixed into Smileys.
/// - Recents is always a full viewport page, including when it is empty, so a
///   blank page can still be swiped into the first standard category.
/// - A native UICollectionView owns horizontal gestures so emoji buttons
///   cannot trap scrolling after a few swipes. Pages stay free-scroll; the
///   user can stop between page widths.
/// - Bottom chrome matches ABC/123: 123, ABC, space, emoji, return, with even
///   padding from the glass edge and between controls.
/// - Category bookmarks float above the spacebar; the grid owns the full blank
///   area so a swipe can begin between emoji cells.
struct EmojiPickerView: View {
    let onEmojiInsert: (String) -> Void
    let onBackToVoice: () -> Void
    let onLetters: () -> Void
    let onSymbols: () -> Void
    let onSpace: () -> Void
    let onReturn: () -> Void
    let onSpaceCursorBegan: () -> Void
    let onSpaceCursorMoved: (KeyboardCursorStep) -> Void
    let onSpaceCursorEnded: () -> Void
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
    @Binding var selectedCategoryID: String
    @Binding var scrollRequest: EmojiScrollRequest?

    @State private var recentEmojis: [String] = []
    @State private var pageSnapshot: [EmojiPage] = []
    @State private var pageRevision = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let categories = EmojiStore.categories

    private let headerHeight: CGFloat = 0
    private let bottomBarHeight: CGFloat = 44
    private let rowSpacing: CGFloat = 2
    /// Keep the first and last glyph rows inside the glass edge instead of
    /// letting CoreText draw into the rounded rim.
    private let gridVerticalInset: CGFloat = 4
    private let emojiKeySpacing: CGFloat = 3
    /// A small fixed gap keeps adjacent free-scroll pages visually distinct.
    private let gridHorizontalPadding: CGFloat = 0
    private let minimumEmojiTargetWidth: CGFloat = 44
    private let edgeInset: CGFloat = VoiceOnlyKeyboardPolicy.keyGridInset
    private let chromeBottomInset: CGFloat = CGFloat(VoiceOnlyKeyboardPolicy.chromeBottomInset)
    private let commandRowGap: CGFloat = CGFloat(VoiceOnlyKeyboardPolicy.chromeCommandRowGap)

    /// The delete control is a fixed overlay. Let the collection view use the
    /// full surface so the last emoji columns have the same geometry as native
    /// iOS and can slide beneath that overlay during a horizontal swipe.
    private var emojiGridWidth: CGFloat {
        max(0, availableWidth)
    }

    /// Keep every grid column wide enough for the Button's hit target.
    private var emojiColumnCount: Int {
        max(1, Int((emojiGridWidth - gridHorizontalPadding * 2) / minimumEmojiTargetWidth))
    }

    /// Height reserved for the four emoji rows above the shared bottom bar.
    private var emojiGridHeight: CGFloat {
        max(
            0,
            availableHeight
                - headerHeight
                - bottomBarHeight
                - commandRowGap
                - chromeBottomInset
        )
    }

    private var rowHeight: CGFloat {
        let rows = CGFloat(4)
        let usable = emojiGridHeight - gridVerticalInset * 2 - rowSpacing * (rows - 1)
        return max(0, usable / rows)
    }

    /// Dynamic cell width based on the shared computed column count.
    private var emojiCellWidth: CGFloat {
        max(0, emojiGridWidth - gridHorizontalPadding * 2) / CGFloat(emojiColumnCount)
    }

    private var recentPageCapacity: Int { emojiColumnCount * 4 }

    // MARK: - Computed data

    private var pages: [EmojiPage] {
        pageSnapshot.isEmpty ? makePages(for: recentEmojis) : pageSnapshot
    }

    private func makePages(for recents: [String]) -> [EmojiPage] {
        makeEmojiPages(recents: recents, columns: emojiColumnCount)
    }

    private func rebuildPages(for recents: [String]? = nil) {
        pageSnapshot = makePages(for: recents ?? recentEmojis)
        pageRevision &+= 1
    }

    private var categoryAnchorIDs: [String: String] {
        EmojiNavigation.anchorPageIDs(
            for: pages.map {
                EmojiNavigationPage(
                    id: $0.id,
                    categoryID: $0.categoryID,
                    itemCategoryIDs: $0.items.map(\.categoryID)
                )
            }
        )
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                EmojiScrollCanvas(
                    pages: pages,
                    availableWidth: emojiGridWidth,
                    gridHeight: emojiGridHeight + commandRowGap,
                    emojiCellWidth: emojiCellWidth,
                    columnCount: emojiColumnCount,
                    rowHeight: rowHeight,
                    rowSpacing: rowSpacing,
                    gridVerticalInset: gridVerticalInset,
                    keySpacing: emojiKeySpacing,
                    gridHorizontalPadding: gridHorizontalPadding,
                    reduceMotion: reduceMotion,
                    pageRevision: pageRevision,
                    scrollRequest: canvasScrollRequest,
                    onVisibleCategory: updateSelectedCategory,
                    onManualScroll: { scrollRequest = nil },
                    onTap: insertEmoji
                )
                .id("emoji-scroll-\(Int(emojiGridWidth))-\(Int(emojiGridHeight))")
                .frame(width: emojiGridWidth, height: emojiGridHeight + commandRowGap)
                .contentShape(Rectangle())

                AuxiliaryBottomBar(
                    layout: surfaceLayout,
                    numbersTitle: "123",
                    onNumbers: onSymbols,
                    onLetters: onLetters,
                    onEmoji: {},
                    spaceFrame: surfaceLayout.chromeWideSpaceFrame,
                    returnFrame: surfaceLayout.chromeReturnFrame,
                    onSpace: onSpace,
                    onSpaceCursorBegan: onSpaceCursorBegan,
                    onSpaceCursorMoved: onSpaceCursorMoved,
                    onSpaceCursorEnded: onSpaceCursorEnded,
                    onReturn: onReturn,
                    showsEmojiControl: false
                )
                .frame(width: availableWidth, height: bottomBarHeight)
                Color.clear.frame(height: chromeBottomInset)
            }

        }
        .frame(width: availableWidth, height: availableHeight)
        .coordinateSpace(name: "emojiPicker")
        .onAppear {
            _ = onBackToVoice
            let recents = RecentEmojis.load(limit: recentPageCapacity)
            recentEmojis = recents
            rebuildPages(for: recents)
            let landing = landingCategoryID(recents: recents)
            selectedCategoryID = landing
            if let index = CategoryInfo.emojiBarSections.firstIndex(where: { $0.id == landing }) {
                KeyboardState.shared.setEmojiCategorySelectionIndex(index)
            }
            scrollRequest = EmojiScrollRequest(id: landing, animated: false)
        }
        .onChange(of: availableWidth) { _, _ in
            let recents = RecentEmojis.load(limit: recentPageCapacity)
            recentEmojis = recents
            rebuildPages(for: recents)
        }
        .onChange(of: scrollRequest) { _, request in
            applyCategoryJump(request)
        }
    }

    private func landingCategoryID(recents: [String]) -> String {
        EmojiNavigation.landingCategoryID(recents: recents, firstCategoryID: categories.first?.id)
    }

    /// Category bookmarks identify a category. The collection view scrolls to that
    /// category's first page without synthesizing a new request nonce on every body.
    private var canvasScrollRequest: EmojiScrollRequest? {
        guard let request = scrollRequest else { return nil }
        guard let pageID = categoryAnchorIDs[request.id] ?? pages.first(where: { $0.id == request.id })?.id else {
            return request
        }
        return request.targeting(pageID)
    }

    private func applyCategoryJump(_ request: EmojiScrollRequest?) {
        guard request?.id == "recents" else { return }
        let recents = RecentEmojis.load(limit: recentPageCapacity)
        recentEmojis = recents
        rebuildPages(for: recents)
    }

    private func updateSelectedCategory(_ categoryID: String) {
        if selectedCategoryID != categoryID {
            selectedCategoryID = categoryID
        }
        if let index = CategoryInfo.emojiBarSections.firstIndex(where: { $0.id == categoryID }) {
            KeyboardState.shared.setEmojiCategorySelectionIndex(index)
        }
    }

    private func insertEmoji(_ emoji: String) {
        HapticFeedback.playInputClick()
        onEmojiInsert(emoji)
        RecentEmojis.add(emoji, limit: recentPageCapacity)
        recentEmojis.removeAll { $0 == emoji }
        recentEmojis.insert(emoji, at: 0)
        recentEmojis = Array(recentEmojis.prefix(recentPageCapacity))
        rebuildPages(for: recentEmojis)
    }


}

// MARK: - Scroll canvas

/// Category-bar and appear jumps. `nonce` lets the same category retrigger; `targeting`
/// remaps a category id onto a page id without minting a new nonce on every body.
struct EmojiScrollRequest: Equatable {
    let id: String
    let animated: Bool
    let nonce: UUID

    init(id: String, animated: Bool = true, nonce: UUID = UUID()) {
        self.id = id
        self.animated = animated
        self.nonce = nonce
    }

    func targeting(_ pageID: String) -> EmojiScrollRequest {
        EmojiScrollRequest(id: pageID, animated: animated, nonce: nonce)
    }
}

/// The native touch owner is the scroll view itself, including unpainted space.
/// No transparent wrapper or optional inset participates in gesture delivery.
final class EmojiPagerView: EmojiPagerCollectionView {
    var onInsert: ((String) -> Void)?
    var onCategoryChanged: ((Int) -> Void)?
    private let coordinator = EmojiScrollCanvas.Coordinator()
    private var pages: [EmojiPage] = []
    private var columns = 0
    private var revision = 0
    private var configuredSize = CGSize.zero
    private var presented = false

    init() {
        super.init(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
        dataSource = coordinator
        delegate = coordinator
        onEmojiInsert = { [weak self] in self?.insert($0) }
        onInteractionEnded = { [weak self] in
            guard let self else { return }
            self.coordinator.reloadWhenIdle(self)
            self.coordinator.retryPendingScroll(in: self)
        }
        onLayoutChanged = { [weak self] in
            guard let self else { return }
            self.coordinator.markNeedsReload()
            self.coordinator.reloadWhenIdle(self)
        }
        onLayoutReady = { [weak self] in
            guard let self else { return }
            self.coordinator.retryPendingScroll(in: self)
        }
    }

    required init?(coder: NSCoder) { nil }

    override func layoutSubviews() {
        super.layoutSubviews()
        if presented { configure(force: false) }
    }

    func present() {
        presented = true
        configure(force: true)
        let recents = RecentEmojis.load(limit: max(1, columns * 4))
        let landing = EmojiNavigation.landingCategoryID(recents: recents, firstCategoryID: EmojiStore.categories.first?.id)
        coordinator.scroll(to: EmojiScrollRequest(id: landing, animated: false), in: self, animated: false)
    }

    func dismiss() {
        presented = false
        cancelVariantSelection()
    }

    func refreshPreferences() {
        cancelVariantSelection()
        if presented { configure(force: true) }
    }

    func selectCategory(at index: Int) {
        let sections = CategoryInfo.emojiBarSections
        guard presented, sections.indices.contains(index) else { return }
        if index == 0 { configure(force: true) }
        coordinator.scroll(to: EmojiScrollRequest(id: sections[index].id, animated: false),
                           in: self, animated: false)
    }

    private func configure(force: Bool) {
        layer.cornerRadius = KeyboardInteractionPreferences.keyboardInsetEnabled ? 22 : 0
        guard bounds.width > 1, bounds.height > 1,
              force || configuredSize != bounds.size else { return }
        configuredSize = bounds.size
        let count = EmojiSurfaceModel.columnCount(gridWidth: bounds.width, horizontalPadding: 0, minimumTargetWidth: 44)
        if force || count != columns {
            columns = count
            pages = makeEmojiPages(recents: RecentEmojis.load(limit: count * 4), columns: count)
            revision &+= 1
        }
        let height = EmojiSurfaceModel.rowHeight(
            gridHeight: bounds.height,
            rowSpacing: 2, gridVerticalInset: 4
        )
        coordinator.configure(
            pages: pages, columns: columns, rowHeight: height, rowSpacing: 2,
            verticalInset: 4, keySpacing: 3, horizontalPadding: 0,
            pageWidths: emojiPageWidths(pages, width: bounds.width, columns: columns, spacing: 3, padding: 0),
            pageGap: 0, reduceMotion: UIAccessibility.isReduceMotionEnabled,
            pageRevision: revision,
            onVisibleCategory: { [weak self] id in
                if let index = CategoryInfo.emojiBarSections.firstIndex(where: { $0.id == id }) {
                    self?.onCategoryChanged?(index)
                }
            },
            onManualScroll: {},
            onTap: { [weak self] in self?.insert($0) }
        )
        coordinator.reloadIfIdle(self)
    }

    private func insert(_ emoji: String) {
        HapticFeedback.playInputClick()
        onInsert?(emoji)
        RecentEmojis.add(emoji, limit: max(1, columns * 4))
    }
}

private func makeEmojiPages(recents: [String], columns: Int) -> [EmojiPage] {
    EmojiSurfaceModel.pages(
        recents: recents,
        categories: EmojiStore.categories.map {
            EmojiSurfaceCategory(id: $0.id, name: $0.name, icon: $0.icon, emojis: $0.emojis)
        },
        emojiColumnCount: columns
    ).map { plan in
        EmojiPage(id: plan.id, name: plan.name, icon: plan.icon, categoryID: plan.categoryID,
                  columns: plan.columns, items: plan.items.map {
            EmojiGridItem(id: $0.id, emoji: $0.emoji, categoryID: $0.categoryID)
        })
    }
}

private func emojiPageWidths(_ pages: [EmojiPage], width: CGFloat, columns: Int,
                             spacing: CGFloat, padding: CGFloat) -> [CGFloat] {
    let columnWidth = max(1, (width - padding * 2 - spacing * CGFloat(max(0, columns - 1))) / CGFloat(max(1, columns)))
    return pages.map { page in
        let count = min(max(1, page.columns), max(1, columns))
        return count == columns ? max(1, width)
            : max(1, padding * 2 + columnWidth * CGFloat(count) + spacing * CGFloat(max(0, count - 1)))
    }
}

private struct EmojiScrollCanvas: UIViewRepresentable {
    let pages: [EmojiPage]
    let availableWidth: CGFloat
    let gridHeight: CGFloat
    let emojiCellWidth: CGFloat
    let columnCount: Int
    let rowHeight: CGFloat
    let rowSpacing: CGFloat
    let gridVerticalInset: CGFloat
    let keySpacing: CGFloat
    let gridHorizontalPadding: CGFloat
    /// Pages share an exact viewport edge; the collection view supplies momentum.
    private let pageGap: CGFloat = 0
    let reduceMotion: Bool
    let pageRevision: Int
    let scrollRequest: EmojiScrollRequest?
    let onVisibleCategory: (String) -> Void
    let onManualScroll: () -> Void
    let onTap: (String) -> Void

    private var pageWidths: [CGFloat] {
        emojiPageWidths(pages, width: availableWidth, columns: columnCount,
                        spacing: keySpacing, padding: gridHorizontalPadding)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> KeyboardNativeSurfaceHost<EmojiPagerCollectionView> {
        let flowLayout = UICollectionViewFlowLayout()
        flowLayout.scrollDirection = .horizontal
        flowLayout.minimumLineSpacing = pageGap
        flowLayout.minimumInteritemSpacing = 0
        flowLayout.sectionInset = .zero
        flowLayout.itemSize = CGSize(width: availableWidth, height: gridHeight)

        let view = EmojiPagerCollectionView(frame: .zero, collectionViewLayout: flowLayout)
        hideTopEdgeEffect(on: view)
        view.dataSource = context.coordinator
        view.delegate = context.coordinator
        if availableWidth > 1, gridHeight > 1 {
            view.frame = CGRect(x: 0, y: 0, width: availableWidth, height: gridHeight)
            flowLayout.itemSize = CGSize(width: availableWidth, height: gridHeight)
        }
        context.coordinator.configure(
            pages: pages,
            columns: columnCount,
            rowHeight: rowHeight,
            rowSpacing: rowSpacing,
            verticalInset: gridVerticalInset,
            keySpacing: keySpacing,
            horizontalPadding: gridHorizontalPadding,
            pageWidths: pageWidths,
            pageGap: pageGap,
            reduceMotion: reduceMotion,
            pageRevision: pageRevision,
            onVisibleCategory: onVisibleCategory,
            onManualScroll: onManualScroll,
            onTap: onTap
        )
        view.onEmojiInsert = onTap
        view.onInteractionEnded = { [weak coordinator = context.coordinator, weak view] in
            guard let view else { return }
            coordinator?.reloadWhenIdle(view)
        }
        view.onLayoutChanged = { [weak coordinator = context.coordinator, weak view] in
            guard let view else { return }
            coordinator?.markNeedsReload()
            coordinator?.reloadWhenIdle(view)
        }
        view.onLayoutReady = { [weak coordinator = context.coordinator, weak view] in
            guard let view else { return }
            coordinator?.retryPendingScroll(in: view)
        }
        view.reloadData()
        context.coordinator.needsReload = false
        context.coordinator.scroll(to: scrollRequest, in: view, animated: false)
        return KeyboardNativeSurfaceHost(surface: view, requiredMode: .emoji)
    }

    func updateUIView(_ host: KeyboardNativeSurfaceHost<EmojiPagerCollectionView>, context: Context) {
        let uiView = host.surface
        context.coordinator.configure(
            pages: pages,
            columns: columnCount,
            rowHeight: rowHeight,
            rowSpacing: rowSpacing,
            verticalInset: gridVerticalInset,
            keySpacing: keySpacing,
            horizontalPadding: gridHorizontalPadding,
            pageWidths: pageWidths,
            pageGap: pageGap,
            reduceMotion: reduceMotion,
            pageRevision: pageRevision,
            onVisibleCategory: onVisibleCategory,
            onManualScroll: onManualScroll,
            onTap: onTap
        )
        uiView.onEmojiInsert = onTap
        uiView.isPagingEnabled = false
        uiView.decelerationRate = .normal
        hideTopEdgeEffect(on: uiView)
        let size = CGSize(width: availableWidth, height: gridHeight)
        if let flowLayout = uiView.collectionViewLayout as? UICollectionViewFlowLayout,
           flowLayout.itemSize != size || flowLayout.minimumLineSpacing != pageGap {
            flowLayout.itemSize = size
            flowLayout.minimumLineSpacing = pageGap
            flowLayout.invalidateLayout()
            context.coordinator.markNeedsReload()
        }
        uiView.onLayoutChanged = { [weak coordinator = context.coordinator, weak uiView] in
            guard let uiView else { return }
            coordinator?.markNeedsReload()
            coordinator?.reloadWhenIdle(uiView)
        }
        uiView.onLayoutReady = { [weak coordinator = context.coordinator, weak uiView] in
            guard let uiView else { return }
            coordinator?.retryPendingScroll(in: uiView)
        }
        context.coordinator.reloadWhenIdle(uiView)
        if gridHeight > 1, availableWidth > 1, !pages.isEmpty {
            let itemCount = uiView.numberOfItems(inSection: 0)
            if itemCount == 0 || itemCount != pages.count {
                context.coordinator.markNeedsReload()
                context.coordinator.reloadWhenIdle(uiView)
            }
        }
        context.coordinator.scroll(
            to: scrollRequest,
            in: uiView,
            animated: (scrollRequest?.animated ?? true) && !reduceMotion
        )
    }

    private func hideTopEdgeEffect(on view: UICollectionView) {
        if #available(iOS 26.0, *) {
            view.topEdgeEffect.isHidden = true
        }
    }

    static func dismantleUIView(_ host: KeyboardNativeSurfaceHost<EmojiPagerCollectionView>, coordinator: Coordinator) {
        host.surface.cancelVariantSelection()
        host.unmount()
    }

    final class Coordinator: NSObject, UICollectionViewDataSource, UICollectionViewDelegate, UICollectionViewDelegateFlowLayout, UIScrollViewDelegate {
        private var pages: [EmojiPage] = []
        private var columns = 1
        private var rowHeight: CGFloat = 1
        private var rowSpacing: CGFloat = 4
        private var verticalInset: CGFloat = 0
        private var keySpacing: CGFloat = 3
        private var horizontalPadding: CGFloat = 0
        private var pageWidths: [CGFloat] = []
        private var pageGap: CGFloat = 0
        private var reduceMotion = false
        private var pageRevision = -1
        private var selectedIndex = -1
        private var lastScrollRequest: EmojiScrollRequest?
        private var pendingScrollRequest: EmojiScrollRequest?
        private var onVisibleCategory: ((String) -> Void)?
        private var onManualScroll: (() -> Void)?
        private var onTap: ((String) -> Void)?
        var needsReload = false
        /// A finger drag owns the offset until the next explicit category jump.
        private var userHasDragged = false

        func configure(
            pages: [EmojiPage],
            columns: Int,
            rowHeight: CGFloat,
            rowSpacing: CGFloat,
            verticalInset: CGFloat,
            keySpacing: CGFloat,
            horizontalPadding: CGFloat,
            pageWidths: [CGFloat],
            pageGap: CGFloat,
            reduceMotion: Bool,
            pageRevision: Int,
            onVisibleCategory: @escaping (String) -> Void,
            onManualScroll: @escaping () -> Void,
            onTap: @escaping (String) -> Void
        ) {
            needsReload = needsReload || self.pageRevision != pageRevision
                || self.columns != columns || self.horizontalPadding != horizontalPadding
                || self.pageWidths != pageWidths
            self.pages = pages
            self.columns = max(1, columns)
            self.rowHeight = rowHeight
            self.rowSpacing = rowSpacing
            self.verticalInset = verticalInset
            self.keySpacing = keySpacing
            self.horizontalPadding = horizontalPadding
            self.pageWidths = pageWidths
            self.pageGap = max(0, pageGap)
            self.reduceMotion = reduceMotion
            self.pageRevision = pageRevision
            self.onVisibleCategory = onVisibleCategory
            self.onManualScroll = onManualScroll
            self.onTap = onTap
        }

        func markNeedsReload() {
            needsReload = true
        }

        func collectionView(
            _ collectionView: UICollectionView,
            layout collectionViewLayout: UICollectionViewLayout,
            sizeForItemAt indexPath: IndexPath
        ) -> CGSize {
            let width = max(collectionView.bounds.width, 1)
            let height = max(collectionView.bounds.height, 1)
            guard pageWidths.indices.contains(indexPath.item) else {
                return CGSize(width: width, height: height)
            }
            return CGSize(width: pageWidths[indexPath.item], height: height)
        }

        func numberOfSections(in collectionView: UICollectionView) -> Int { 1 }

        func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
            pages.count
        }

        func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
            let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: EmojiPageCell.reuseIdentifier,
                for: indexPath
            ) as? EmojiPageCell ?? EmojiPageCell(frame: .zero)
            guard pages.indices.contains(indexPath.item) else { return cell }
            cell.configure(
                page: pages[indexPath.item],
                columns: pages[indexPath.item].columns,
                rowHeight: rowHeight,
                rowSpacing: rowSpacing,
                verticalInset: verticalInset,
                keySpacing: keySpacing,
                horizontalPadding: horizontalPadding,
                reduceMotion: reduceMotion,
                onTap: { [weak self] emoji in self?.onTap?(emoji) }
            )
            return cell
        }

        func scroll(to request: EmojiScrollRequest?, in collectionView: UICollectionView, animated: Bool) {
            guard let request else { return }
            // A SwiftUI update is also emitted while the user is dragging. The
            // same request must never fight that live gesture by restoring its
            // old target offset; only a new request token is authoritative.
            guard request != lastScrollRequest else { return }
            let navigationPages = pages.map {
                EmojiNavigationPage(
                    id: $0.id,
                    categoryID: $0.categoryID,
                    itemCategoryIDs: $0.items.map(\.categoryID)
                )
            }
            let itemCount = collectionView.numberOfItems(inSection: 0)
            let targetIndex: Int
            switch EmojiNavigation.scrollResolution(
                for: request.id,
                in: navigationPages,
                availableItemCount: itemCount,
                boundsWidth: Double(collectionView.bounds.width)
            ) {
            case .unavailable:
                pendingScrollRequest = nil
                return
            case .pending:
                pendingScrollRequest = request
                return
            case .ready(let index):
                targetIndex = index
            }
            // Category jumps and SwiftUI updates must not tear down a live
            // popup. The active hold owns this touch stream until release.
            if (collectionView as? EmojiPagerCollectionView)?.hasVariantSelection == true {
                pendingScrollRequest = request
                return
            }
            userHasDragged = false
            let expectedX = CGFloat(EmojiNavigation.pageContentOffsetX(
                pageIndex: targetIndex,
                pageWidths: pageWidths.map(Double.init),
                pageGap: Double(pageGap)
            ))
            pendingScrollRequest = nil
            lastScrollRequest = request
            selectedIndex = targetIndex
            collectionView.setContentOffset(CGPoint(x: expectedX, y: 0), animated: animated)
            notifyVisiblePage(targetIndex)
        }

        func retryPendingScroll(in collectionView: EmojiPagerCollectionView) {
            guard let request = pendingScrollRequest else { return }
            scroll(to: request, in: collectionView, animated: request.animated && !reduceMotion)
        }

        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            if (scrollView as? EmojiPagerCollectionView)?.hasVariantSelection == true { return }
            #if DEBUG
            PersistentLog.log(.diagnosticProbe(
                component: "EmojiPager", instanceID: "pan", action: "began",
                details: "offset=\(Int(scrollView.contentOffset.x))"
            ))
            #endif
            // The current request belongs to the last category-bar jump. Once
            // the user starts dragging, offset 0 is a valid manual destination
            // and must not be mistaken for an unfinished programmatic jump.
            userHasDragged = true
            lastScrollRequest = nil
            pendingScrollRequest = nil
            onManualScroll?()
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            if (scrollView as? EmojiPagerCollectionView)?.hasVariantSelection == true { return }
            let index = pageIndex(for: scrollView)
            guard index != selectedIndex else { return }
            selectedIndex = index
            // Publish the page while the finger is moving so the category
            // highlight follows the native pager. The current scroll request is
            // unchanged, so updateUIView cannot start a competing scroll.
            notifyVisiblePage(index)
        }

        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            #if DEBUG
            PersistentLog.log(.diagnosticProbe(
                component: "EmojiPager", instanceID: "pan", action: "ended",
                details: "offset=\(Int(scrollView.contentOffset.x)) decelerate=\(decelerate)"
            ))
            #endif
            if !decelerate {
                notifyVisiblePage(pageIndex(for: scrollView))
                reloadWhenIdle(scrollView)
            }
        }

        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            #if DEBUG
            PersistentLog.log(.diagnosticProbe(
                component: "EmojiPager", instanceID: "pan", action: "decelerated",
                details: "offset=\(Int(scrollView.contentOffset.x))"
            ))
            #endif
            let index = pageIndex(for: scrollView)
            selectedIndex = index
            notifyVisiblePage(index)
            reloadWhenIdle(scrollView)
        }

        func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
            let index = pageIndex(for: scrollView)
            selectedIndex = index
            notifyVisiblePage(index)
            reloadWhenIdle(scrollView)
        }

        func reloadWhenIdle(_ scrollView: UIScrollView) {
            // Wait until UIKit finishes dispatching the release/cancellation.
            DispatchQueue.main.async { [weak self, weak scrollView] in
                guard let self, let view = scrollView as? EmojiPagerCollectionView else { return }
                self.reloadIfIdle(view)
            }
        }

        fileprivate func reloadIfIdle(_ view: EmojiPagerCollectionView) {
            guard needsReload, !view.hasVariantSelection,
                  !view.isTracking, !view.isDragging, !view.isDecelerating else { return }
            needsReload = false
            let offset = view.contentOffset
            view.reloadData()
            view.layoutIfNeeded()
            if userHasDragged {
                view.setContentOffset(offset, animated: false)
                notifyVisiblePage(pageIndex(for: view))
                return
            }
            if let request = lastScrollRequest, abs(offset.x) < 1 {
                lastScrollRequest = nil
                scroll(to: request, in: view, animated: false)
                return
            }
            view.setContentOffset(offset, animated: false)
            notifyVisiblePage(pageIndex(for: view))
        }

        private func pageIndex(for scrollView: UIScrollView) -> Int {
            EmojiNavigation.pageIndex(
                contentOffsetX: Double(max(0, scrollView.contentOffset.x)),
                pageWidths: pageWidths.map(Double.init),
                pageGap: Double(pageGap)
            )
        }

        private func notifyVisiblePage(_ index: Int) {
            guard pages.indices.contains(index) else { return }
            // The page's leading item owns the visible category. Mixed pages
            // remain continuous; item metadata still powers exact category
            // anchors when the bar requests a jump.
            onVisibleCategory?(pages[index].categoryID)
        }
    }
}

class EmojiPagerCollectionView: UICollectionView, UIGestureRecognizerDelegate {
    var onEmojiInsert: ((String) -> Void)?
    var onInteractionEnded: (() -> Void)?
    var onLayoutChanged: (() -> Void)?
    var onLayoutReady: (() -> Void)?
    private var variantSession: KeyVariantSession?
    private var popup: UIView?
    private var variantPopupHost: UIHostingController<KeyVariantPopup>?
    private var holdOrigin = CGPoint.zero
    private var hasMovedVariant = false
    var hasVariantSelection: Bool { variantSession != nil }
    private var lastItemLayoutSize: CGSize = .zero
    private var lastBlankHitTimestamp: TimeInterval = -1
    // Match the keyboard's native long-press tolerance. The collection view
    // may report `isDragging` during ordinary finger jitter before the hold
    // reaches its recognition duration, so translation is the real swipe gate.
    private let preRecognitionMovement: CGFloat = 8
    private lazy var hold = EmojiGestureCoordinator(
        target: self,
        action: #selector(held(_:)),
        minimumPressDuration: KeyboardDeletion.holdRecognitionDuration,
        allowableMovement: preRecognitionMovement
    )

    override init(frame: CGRect, collectionViewLayout layout: UICollectionViewLayout) {
        super.init(frame: frame, collectionViewLayout: layout)
        if let flow = layout as? UICollectionViewFlowLayout {
            flow.scrollDirection = .horizontal
            flow.minimumLineSpacing = 0
            flow.minimumInteritemSpacing = 0
            flow.sectionInset = .zero
        }
        let view = self
        // Keep the remote keyboard's native canvas painted even without its
        // decorative inset, including empty Recents and inter-emoji gaps.
        view.backgroundColor = UIColor.secondarySystemBackground.withAlphaComponent(0.02)
        // The shared surface draws the inset behind the pager AND bottom bar.
        // Blank swipes still belong to this collection, never its background.
        view.isOpaque = false
        view.clipsToBounds = true
        view.layer.cornerRadius = 22
        view.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        view.isPagingEnabled = false
        view.isMultipleTouchEnabled = true
        view.isScrollEnabled = true
        view.panGestureRecognizer.minimumNumberOfTouches = 1
        view.panGestureRecognizer.maximumNumberOfTouches = 1
        view.alwaysBounceHorizontal = true
        view.alwaysBounceVertical = false
        view.isDirectionalLockEnabled = false
        view.delaysContentTouches = false
        view.canCancelContentTouches = true
        view.panGestureRecognizer.delaysTouchesBegan = false
        view.panGestureRecognizer.delaysTouchesEnded = false
        view.panGestureRecognizer.cancelsTouchesInView = true
        view.decelerationRate = .normal
        view.contentInsetAdjustmentBehavior = .never
        view.contentInset = .zero
        view.scrollIndicatorInsets = .zero
        view.showsHorizontalScrollIndicator = false
        if #available(iOS 26.0, *) { view.topEdgeEffect.isHidden = true }
        view.register(EmojiPageCell.self, forCellWithReuseIdentifier: EmojiPageCell.reuseIdentifier)
        // The pager, not a recycled button, owns the entire hold lifecycle.
        // Once the hold is recognized, cancel the button's pending tap so a
        // tone selection cannot also insert the base emoji on release.
        hold.delegate = self
        // The hold fails after a real swipe moves beyond its jitter allowance.
        // Let the native pan start independently: a required-to-fail relation
        // stalls blank Recents and the spaces between emoji cells on iOS.
        addGestureRecognizer(hold)
        hold.shouldBeginHold = { [weak self] point in
            self?.canBeginVariantHold(at: point) ?? false
        }
    }

    fileprivate func canBeginVariantHold(at point: CGPoint) -> Bool {
        guard KeyboardInteractionPreferences.accentVariantsEnabled,
              let button = emojiButton(at: point) else { return false }
        return KeyboardVariantPreferences.options(for: button.item.emoji, kind: .emoji).count > 1
    }

    required init?(coder: NSCoder) { nil }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return false
    }

    func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        #if DEBUG
        if recognizer === panGestureRecognizer,
           emojiButton(at: touch.location(in: self)) == nil {
            PersistentLog.log(.diagnosticProbe(
                component: "EmojiPager", instanceID: "pan", action: "blankCandidate",
                details: "ready=\(numberOfItems(inSection: 0) > 0)"
            ))
        }
        #endif
        // Only eligible emoji participate in hold arbitration. Blank space and
        // filler cells belong exclusively to the collection view's native pan.
        return recognizer !== hold || canBeginVariantHold(at: touch.location(in: self))
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === hold else { return super.gestureRecognizerShouldBegin(gestureRecognizer) }
        guard !isDecelerating,
              KeyboardInteractionPreferences.accentVariantsEnabled,
              let button = emojiButton(at: hold.location(in: self)) else {
            hold.state = .failed
            return false
        }
        let translation = panGestureRecognizer.translation(in: self)
        guard hypot(translation.x, translation.y) < preRecognitionMovement else { return false }
        return KeyboardVariantPreferences.options(for: button.item.emoji, kind: .emoji).count > 1
    }

    private func emojiButton(at point: CGPoint) -> EmojiKeyButton? {
        var view = hitTest(point, with: nil)
        while let candidate = view, candidate !== self {
            if let button = candidate as? EmojiKeyButton { return button }
            view = candidate.superview
        }
        return nil
    }

    @objc private func held(_ recognizer: UIGestureRecognizer) {
        switch recognizer.state {
        case .began:
            guard let button = emojiButton(at: recognizer.location(in: self)) else { return }
            let options = KeyboardVariantPreferences.options(for: button.item.emoji, kind: .emoji)
            guard options.count > 1 else { return }
            button.suppressNextTapAfterVariantHold()
            let source = button.convert(button.bounds, to: self)
            let viewportSource = source.offsetBy(dx: -bounds.minX, dy: -bounds.minY)
            var frame = KeyVariantPopup.frame(for: viewportSource, optionCount: options.count,
                                               isEmoji: true, in: bounds.size)
            frame.size.width = min(frame.width, max(0, bounds.width - 12))
            frame.origin.x = min(frame.minX, max(6, bounds.width - frame.width - 6))
            frame = frame.offsetBy(dx: bounds.minX, dy: bounds.minY)
            variantSession = KeyVariantSession(options: options, sourceFrame: source,
                popupFrame: frame, isEmoji: true,
                selectedIndex: options.firstIndex(of: button.inputEmoji) ?? 0)
            holdOrigin = recognizer.location(in: self)
            hasMovedVariant = false
            let host = UIHostingController(
                rootView: KeyVariantPopup(
                    options: options,
                    selectedIndex: variantSession?.selectedIndex ?? 0,
                    isEmoji: true,
                    cornerRadius: VoiceOnlyKeyboardPolicy.emojiHighlightCornerRadius
                )
            )
            host.view.backgroundColor = .clear
            host.view.isOpaque = false
            host.view.frame = frame
            host.view.isUserInteractionEnabled = false
            host.view.accessibilityElementsHidden = false
            host.view.accessibilityIdentifier = "emoji-skin-tone-selector"
            host.view.accessibilityLabel = "Skin tone"
            variantPopupHost = host
            popup = host.view
            let windowHost = window ?? self
            popup?.frame = convert(frame, to: windowHost)
            if let popup {
                windowHost.addSubview(popup)
            }
            renderVariantSelection()
            HapticFeedback.variantPopupPresented()
        case .changed:
            updateVariantSelection(at: recognizer.location(in: self))
        case .ended:
            updateVariantSelection(at: recognizer.location(in: self))
            let session = variantSession
            cancelVariantSelection()
            if let session, session.options.indices.contains(session.selectedIndex) {
                onEmojiInsert?(session.options[session.selectedIndex])
            }
        case .cancelled, .failed:
            cancelVariantSelection()
        default:
            break
        }
    }

    private func updateVariantSelection(at point: CGPoint) {
        guard var session = variantSession else { return }
        // A stationary release keeps the initial tone even when a top-row
        // popup overlaps the finger. Sliding then uses popup hit testing.
        hasMovedVariant = hasMovedVariant || hypot(point.x - holdOrigin.x, point.y - holdOrigin.y) > 3
        guard hasMovedVariant else { return }
        // Match the ABC/123 popup: selection follows the horizontal finger
        // position and clamps at the edge, regardless of vertical distance or
        // whether the finger is currently over the popup's visual frame.
        let selectedIndex = EmojiToneHitTesting.selectedIndex(
            at: point, source: session.sourceFrame, popup: session.popupFrame,
            optionCount: session.options.count, initialIndex: session.selectedIndex)
        let previous = session.selectedIndex
        session.selectedIndex = selectedIndex
        variantSession = session
        renderVariantSelection()
        if selectedIndex != previous {
            HapticFeedback.variantHighlightChanged()
        }
    }

    private func renderVariantSelection() {
        guard let session = variantSession else { return }
        variantPopupHost?.rootView = KeyVariantPopup(
            options: session.options,
            selectedIndex: session.selectedIndex,
            isEmoji: true,
            cornerRadius: VoiceOnlyKeyboardPolicy.emojiHighlightCornerRadius
        )
    }

    func cancelVariantSelection() {
        let wasActive = variantSession != nil || popup != nil
        variantSession = nil
        popup?.removeFromSuperview()
        popup = nil
        variantPopupHost = nil
        if wasActive {
            onInteractionEnded?()
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { cancelVariantSelection() }
    }

    // A swipe that starts on a UIControl must be allowed to cancel that
    // control's touch tracking. Without this, UIButton keeps ownership when
    // the finger starts on an emoji and the pager stops responding after the
    // first few page changes.
    override func touchesShouldCancel(in view: UIView) -> Bool {
        true
    }

    /// The scroll view itself owns blank space. Returning a decorative background
    /// control can put the hit outside the scroll view's active content hierarchy.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard !isHidden, isUserInteractionEnabled, alpha > 0.01,
              self.point(inside: point, with: event) else { return nil }
        let hit = super.hitTest(point, with: event)
        var candidate = hit
        while let view = candidate, view !== self {
            if view is EmojiKeyButton || view === popup {
                return hit
            }
            candidate = view.superview
        }
        #if DEBUG
        if let timestamp = event?.timestamp, timestamp != lastBlankHitTimestamp {
            lastBlankHitTimestamp = timestamp
            PersistentLog.log(.diagnosticProbe(
                component: "EmojiPager", instanceID: "hit", action: "blank",
                details: "items=\(numberOfItems(inSection: 0))"
            ))
        }
        #endif
        return self
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if let popup, popup.superview === self {
            bringSubviewToFront(popup)
        }
        guard let layout = collectionViewLayout as? UICollectionViewFlowLayout else { return }
        let size = bounds.size
        guard size.width > 1, size.height > 1 else { return }
        let sizeChanged = abs(lastItemLayoutSize.width - size.width) > 0.5
            || abs(lastItemLayoutSize.height - size.height) > 0.5
        if layout.itemSize != size || sizeChanged {
            lastItemLayoutSize = size
            layout.itemSize = size
            layout.invalidateLayout()
            // Rebuilding cells inside layoutSubviews can invalidate the active
            // collection pan. The coordinator reloads after the gesture ends.
            onLayoutChanged?()
        }
        onLayoutReady?()
    }

}

private final class EmojiPageCell: UICollectionViewCell {
    static let reuseIdentifier = "emoji-page-cell"
    private var grid: UIStackView?

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        contentView.clipsToBounds = true
        backgroundColor = .clear
        contentView.backgroundColor = .clear
    }

    required init?(coder: NSCoder) { nil }

    override func prepareForReuse() {
        super.prepareForReuse()
        contentView.subviews.forEach { $0.removeFromSuperview() }
        grid = nil
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard bounds.contains(point), !isHidden, alpha > 0.01 else {
            return nil
        }
        // Prefer an emoji button when the finger lands on one. Blank Recent
        // cells and inter-key gaps must still belong to this page so the
        // pager's pan recognizer (which requires a hit inside the collection
        // hierarchy) can start a horizontal swipe from empty space.
        if let hit = super.hitTest(point, with: event) {
            var candidate: UIView? = hit
            while let view = candidate, view !== self {
                if view is EmojiKeyButton { return hit }
                candidate = view.superview
            }
        }
        return self
    }

    func configure(
        page: EmojiPage,
        columns: Int,
        rowHeight: CGFloat,
        rowSpacing: CGFloat,
        verticalInset: CGFloat,
        keySpacing: CGFloat,
        horizontalPadding: CGFloat,
        reduceMotion: Bool,
        onTap: @escaping (String) -> Void
    ) {
        grid?.removeFromSuperview()
        contentView.subviews.forEach { $0.removeFromSuperview() }

        let panHost = UIView()
        panHost.backgroundColor = .clear
        // This is visual-only; the cell returns itself for blank areas so the
        // collection view's pan receives the touch even on empty Recents.
        panHost.isUserInteractionEnabled = false
        panHost.isAccessibilityElement = false
        panHost.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(panHost)
        NSLayoutConstraint.activate([
            panHost.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            panHost.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            panHost.topAnchor.constraint(equalTo: contentView.topAnchor),
            panHost.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])

        let vertical = UIStackView()
        vertical.axis = .vertical
        vertical.alignment = .fill
        vertical.distribution = .fill
        vertical.spacing = rowSpacing
        vertical.isUserInteractionEnabled = true
        vertical.translatesAutoresizingMaskIntoConstraints = false

        let columnCount = max(1, columns)
        for row in 0..<4 {
            let horizontal = UIStackView()
            horizontal.axis = .horizontal
            horizontal.alignment = .fill
            horizontal.distribution = .fillEqually
            horizontal.spacing = keySpacing
            horizontal.isUserInteractionEnabled = true
            horizontal.translatesAutoresizingMaskIntoConstraints = false
            horizontal.heightAnchor.constraint(equalToConstant: rowHeight).isActive = true
            for column in 0..<columnCount {
                // The horizontal emoji pager fills each column from top to
                // bottom, then continues in the next column, matching the
                // native keyboard's reading order.
                let index = column * 4 + row
                if page.items.indices.contains(index) {
                    let button = EmojiKeyButton(item: page.items[index], reduceMotion: reduceMotion)
                    button.applyEmojiFont(.systemFont(ofSize: min(22, max(16, rowHeight * 0.62))))
                    button.onTap = onTap
                    horizontal.addArrangedSubview(button)
                } else {
                    let filler = UIView()
                    filler.isUserInteractionEnabled = false
                    filler.isAccessibilityElement = false
                    filler.isOpaque = false
                    filler.backgroundColor = .clear
                    horizontal.addArrangedSubview(filler)
                }
            }
            vertical.addArrangedSubview(horizontal)
        }

        contentView.addSubview(vertical)
        // Pages stay edge-abutted (gridHorizontalPadding == 0), but glyphs need
        // a few points inside the liquid-glass clip so the press highlight is not
        // sliced on the first/last columns.
        let edgeBreathingRoom = max(horizontalPadding, VoiceOnlyKeyboardPolicy.keyGridInset)
        NSLayoutConstraint.activate([
            vertical.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: edgeBreathingRoom),
            vertical.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -edgeBreathingRoom),
            vertical.topAnchor.constraint(equalTo: contentView.topAnchor, constant: verticalInset),
            vertical.heightAnchor.constraint(equalToConstant: rowHeight * 4 + rowSpacing * 3)
        ])
        grid = vertical
    }
}

private final class EmojiKeyButton: UIButton {
    var inputEmoji: String {
        item.categoryID == "recents" ? item.emoji : KeyboardVariantPreferences.preferredEmoji(item.emoji)
    }
    let item: EmojiGridItem
    let reduceMotion: Bool
    var onTap: ((String) -> Void)?
    private let glyph = UILabel()
    private var suppressNextTap = false

    init(item: EmojiGridItem, reduceMotion: Bool) {
        self.item = item
        self.reduceMotion = reduceMotion
        super.init(frame: .zero)
        // Keyboard extensions on iOS 26 drop UIButton.Configuration titles.
        // A UILabel is the reliable way to draw emoji glyphs.
        configuration = nil
        setTitle(nil, for: .normal)
        glyph.text = inputEmoji
        glyph.textAlignment = .center
        glyph.adjustsFontSizeToFitWidth = true
        glyph.minimumScaleFactor = 0.5
        glyph.isUserInteractionEnabled = false
        glyph.translatesAutoresizingMaskIntoConstraints = false
        addSubview(glyph)
        NSLayoutConstraint.activate([
            glyph.leadingAnchor.constraint(equalTo: leadingAnchor),
            glyph.trailingAnchor.constraint(equalTo: trailingAnchor),
            glyph.topAnchor.constraint(equalTo: topAnchor),
            glyph.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        applyEmojiFont(.systemFont(ofSize: 22))
        backgroundColor = .clear
        isMultipleTouchEnabled = true
        isExclusiveTouch = false
        accessibilityLabel = inputEmoji
        addTarget(self, action: #selector(tapped), for: .touchUpInside)

        accessibilityCustomActions = EmojiSkinToneVariants.options(for: item.emoji).map { option in
            UIAccessibilityCustomAction(name: option) { [weak self] _ in
                self?.onTap?(option)
                return true
            }
        }
    }

    required init?(coder: NSCoder) { nil }

    func applyEmojiFont(_ font: UIFont) {
        glyph.font = font
        glyph.adjustsFontSizeToFitWidth = true
        glyph.minimumScaleFactor = 0.5
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        guard !isHidden, isUserInteractionEnabled, isEnabled, alpha > 0.01 else { return false }
        // Each cell already meets the 44pt touch target. Do not expand into
        // neighboring cells: overlapping targets make edge swipes and
        // long-presses resolve to the wrong emoji.
        return bounds.contains(point)
    }

    override var isHighlighted: Bool {
        didSet {
            layer.cornerRadius = VoiceOnlyKeyboardPolicy.emojiHighlightCornerRadius
            layer.masksToBounds = true
            if KeyboardInteractionPreferences.keyPopupMode == .flash {
                backgroundColor = .clear
                layer.borderWidth = 0
                if isHighlighted && !oldValue {
                    flashKeyboardKey(in: bounds, cornerRadius: VoiceOnlyKeyboardPolicy.emojiHighlightCornerRadius)
                }
                return
            }
            backgroundColor = isHighlighted ? UIColor.label.withAlphaComponent(0.12) : .clear
            layer.borderWidth = isHighlighted ? 1 : 0
            layer.borderColor = isHighlighted ? UIColor.label.withAlphaComponent(0.16).cgColor : nil
        }
    }

    func suppressNextTapAfterVariantHold() {
        suppressNextTap = true
    }

    override func accessibilityActivate() -> Bool {
        onTap?(inputEmoji)
        return true
    }

    @objc private func tapped() {
        if suppressNextTap {
            suppressNextTap = false
            return
        }
        onTap?(inputEmoji)
    }

}

// MARK: - Supporting types

// Pure geometry kept here so the standalone emoji check exercises the same code.
private enum EmojiToneHitTesting {
    static func selectedIndex(at point: CGPoint, source: CGRect, popup: CGRect,
                              optionCount: Int, initialIndex: Int) -> Int {
        guard optionCount > 0 else { return -1 }
        _ = source
        _ = initialIndex
        let inset = popup.insetBy(dx: 6, dy: 0)
        let cellWidth = max(1, inset.width / CGFloat(optionCount))
        let rawIndex = Int(floor((point.x - inset.minX) / cellWidth))
        return min(max(0, rawIndex), optionCount - 1)
    }
}
// End emoji tone hit testing.

private struct EmojiGridItem: Identifiable {
    let id: String
    let emoji: String
    let categoryID: String
}

private struct EmojiPage: Identifiable {
    let id: String
    let name: String
    let icon: String
    let categoryID: String
    let columns: Int
    let items: [EmojiGridItem]
}
