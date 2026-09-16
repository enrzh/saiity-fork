// DictusKeyboard/Views/EmojiPickerView.swift
import SwiftUI
import AudioToolbox
import UIKit
import DictusCore

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
/// - Recents owns one page; all standard categories are one continuous stream.
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
    private let gridVerticalInset: CGFloat = 0
    private let emojiKeySpacing: CGFloat = 3
    private let gridHorizontalPadding: CGFloat = VoiceOnlyKeyboardPolicy.keyGridInset
    private let minimumEmojiTargetWidth: CGFloat = 44
    private let edgeInset: CGFloat = VoiceOnlyKeyboardPolicy.keyGridInset
    private let chromeBottomInset: CGFloat = CGFloat(VoiceOnlyKeyboardPolicy.chromeBottomInset)
    private let commandRowGap: CGFloat = CGFloat(VoiceOnlyKeyboardPolicy.visibleControlGap)

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
        var result: [EmojiPage] = [EmojiPage(
            id: "recents",
            name: "Recents",
            icon: "clock",
            categoryID: "recents",
            items: recents.enumerated().map { index, emoji in
                EmojiGridItem(id: "recents_\(index)", emoji: emoji, categoryID: "recents")
            }
        )]

        // Recents is the only standalone page. The standard categories share
        // one ordered stream so a horizontal swipe can cross a category
        // boundary without getting trapped in a nested pager.
        let standardItems = categories.flatMap { category in
            category.emojis.enumerated().map { index, emoji in
                EmojiGridItem(id: "\(category.id)_\(index)", emoji: emoji, categoryID: category.id)
            }
        }
        let capacity = max(1, emojiColumnCount * 4)
        let pageCount = EmojiNavigation.pageCount(itemCount: standardItems.count, pageCapacity: capacity)
        for pageIndex in 0..<pageCount {
            let start = pageIndex * capacity
            let end = min(start + capacity, standardItems.count)
            let pageItems = Array(standardItems[start..<end])
            guard let firstItem = pageItems.first,
                  let category = categories.first(where: { $0.id == firstItem.categoryID }) else { continue }
            result.append(EmojiPage(
                id: "emoji_page_\(pageIndex)",
                name: category.name,
                icon: category.icon,
                categoryID: category.id,
                items: pageItems
            ))
        }
        return result
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
        let deleteFrame = surfaceLocal(surfaceLayout.boardDeleteFrame)
        let categoryFrame = surfaceLocal(surfaceLayout.floatingEmojiCategoryFrame)
        ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                EmojiScrollCanvas(
                    pages: pages,
                    availableWidth: emojiGridWidth,
                    gridHeight: emojiGridHeight,
                    emojiCellWidth: emojiCellWidth,
                    columnCount: emojiColumnCount,
                    rowHeight: rowHeight,
                    rowSpacing: rowSpacing,
                    keySpacing: emojiKeySpacing,
                    gridHorizontalPadding: gridHorizontalPadding,
                    reduceMotion: reduceMotion,
                    pageRevision: pageRevision,
                    scrollRequest: canvasScrollRequest,
                    onVisibleCategory: updateSelectedCategory,
                    onTap: insertEmoji
                )
                .id("emoji-scroll-\(Int(emojiGridWidth))-\(Int(emojiGridHeight))")
                .frame(width: emojiGridWidth, height: emojiGridHeight)

                Color.clear.frame(height: commandRowGap)
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

            if !categoryFrame.isEmpty {
                EmojiCategoryBar(
                    sections: CategoryInfo.emojiBarSections,
                    selectedCategoryID: selectedCategoryID,
                    scrubbingEnabled: false,
                    onSelectCategory: { id in
                        selectedCategoryID = id
                        scrollRequest = EmojiScrollRequest(id: id, animated: false)
                    }
                )
                .frame(width: categoryFrame.width, height: categoryFrame.height)
                .keyboardGlass(in: Capsule(), interactive: false)
                .allowsHitTesting(false)
                .position(x: categoryFrame.midX, y: categoryFrame.midY)
                .zIndex(2)
            }

            if !deleteFrame.isEmpty {
                KeyboardDeleteButton(
                    onDelete: onDelete,
                    onDeleteWord: onDeleteWord,
                    visualWidth: surfaceLayout.commandKeyVisualSize.width,
                    visualHeight: surfaceLayout.commandKeyVisualSize.height,
                    hitWidth: deleteFrame.width,
                    hitHeight: deleteFrame.height
                )
                .frame(width: deleteFrame.width, height: deleteFrame.height)
                .position(x: deleteFrame.midX, y: deleteFrame.midY)
                .zIndex(4)
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

    private func surfaceLocal(_ frame: CGRect) -> CGRect {
        frame.offsetBy(
            dx: -surfaceLayout.surfaceFrame.minX,
            dy: -surfaceLayout.surfaceFrame.minY
        )
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
    }

    private func insertEmoji(_ emoji: String) {
        HapticFeedback.keyTapped()
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

private struct EmojiScrollCanvas: UIViewRepresentable {
    let pages: [EmojiPage]
    let availableWidth: CGFloat
    let gridHeight: CGFloat
    let emojiCellWidth: CGFloat
    let columnCount: Int
    let rowHeight: CGFloat
    let rowSpacing: CGFloat
    let keySpacing: CGFloat
    let gridHorizontalPadding: CGFloat
    let reduceMotion: Bool
    let pageRevision: Int
    let scrollRequest: EmojiScrollRequest?
    let onVisibleCategory: (String) -> Void
    let onTap: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> EmojiPagerCollectionView {
        let flowLayout = UICollectionViewFlowLayout()
        flowLayout.scrollDirection = .horizontal
        flowLayout.minimumLineSpacing = 0
        flowLayout.minimumInteritemSpacing = 0
        flowLayout.sectionInset = .zero
        flowLayout.itemSize = CGSize(width: availableWidth, height: gridHeight)

        let view = EmojiPagerCollectionView(frame: .zero, collectionViewLayout: flowLayout)
        view.backgroundColor = .clear
        view.isOpaque = false
        view.clipsToBounds = true
        view.isPagingEnabled = false
        view.isMultipleTouchEnabled = true
        view.isScrollEnabled = true
        view.panGestureRecognizer.minimumNumberOfTouches = 1
        view.panGestureRecognizer.maximumNumberOfTouches = 1
        view.alwaysBounceHorizontal = true
        view.alwaysBounceVertical = false
        // Let UIScrollView own the horizontal gesture from the first pixel.
        // Directional locking can keep a child button's cancelled touch in a
        // pending state after a diagonal swipe on the compact emoji grid.
        view.isDirectionalLockEnabled = false
        view.delaysContentTouches = false
        view.canCancelContentTouches = true
        view.panGestureRecognizer.delaysTouchesBegan = false
        view.panGestureRecognizer.delaysTouchesEnded = false
        view.panGestureRecognizer.cancelsTouchesInView = true
        view.decelerationRate = .normal
        view.contentInsetAdjustmentBehavior = .never
        view.showsHorizontalScrollIndicator = false
        hideTopEdgeEffect(on: view)
        view.register(EmojiPageCell.self, forCellWithReuseIdentifier: EmojiPageCell.reuseIdentifier)
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
            keySpacing: keySpacing,
            horizontalPadding: gridHorizontalPadding,
            reduceMotion: reduceMotion,
            pageRevision: pageRevision,
            onVisibleCategory: onVisibleCategory,
            onTap: onTap
        )
        view.onEmojiInsert = onTap
        view.onInteractionEnded = { [weak coordinator = context.coordinator, weak view] in
            guard let view else { return }
            coordinator?.reloadWhenIdle(view)
        }
        view.onLayoutReady = { [weak coordinator = context.coordinator, weak view] in
            guard let view else { return }
            coordinator?.retryPendingScroll(in: view)
        }
        view.reloadData()
        context.coordinator.needsReload = false
        context.coordinator.scroll(to: scrollRequest, in: view, animated: false)
        return view
    }

    func updateUIView(_ uiView: EmojiPagerCollectionView, context: Context) {
        context.coordinator.configure(
            pages: pages,
            columns: columnCount,
            rowHeight: rowHeight,
            rowSpacing: rowSpacing,
            keySpacing: keySpacing,
            horizontalPadding: gridHorizontalPadding,
            reduceMotion: reduceMotion,
            pageRevision: pageRevision,
            onVisibleCategory: onVisibleCategory,
            onTap: onTap
        )
        uiView.onEmojiInsert = onTap
        uiView.isPagingEnabled = false
        uiView.decelerationRate = .normal
        hideTopEdgeEffect(on: uiView)
        let size = CGSize(width: availableWidth, height: gridHeight)
        if let flowLayout = uiView.collectionViewLayout as? UICollectionViewFlowLayout,
           flowLayout.itemSize != size {
            flowLayout.itemSize = size
            flowLayout.invalidateLayout()
            uiView.cancelVariantSelection()
            context.coordinator.needsReload = true
        }
        uiView.onLayoutReady = { [weak coordinator = context.coordinator, weak uiView] in
            guard let uiView else { return }
            coordinator?.retryPendingScroll(in: uiView)
        }
        context.coordinator.reloadWhenIdle(uiView)
        if gridHeight > 1, availableWidth > 1, !pages.isEmpty {
            let itemCount = uiView.numberOfItems(inSection: 0)
            if itemCount == 0 || itemCount != pages.count {
                uiView.reloadData()
                context.coordinator.needsReload = false
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

    final class Coordinator: NSObject, UICollectionViewDataSource, UICollectionViewDelegate, UICollectionViewDelegateFlowLayout, UIScrollViewDelegate {
        private var pages: [EmojiPage] = []
        private var columns = 1
        private var rowHeight: CGFloat = 1
        private var rowSpacing: CGFloat = 4
        private var keySpacing: CGFloat = 3
        private var horizontalPadding: CGFloat = 0
        private var reduceMotion = false
        private var pageRevision = -1
        private var selectedIndex = -1
        private var lastScrollRequest: EmojiScrollRequest?
        private var pendingScrollRequest: EmojiScrollRequest?
        private var onVisibleCategory: ((String) -> Void)?
        private var onTap: ((String) -> Void)?
        var needsReload = false

        func configure(
            pages: [EmojiPage],
            columns: Int,
            rowHeight: CGFloat,
            rowSpacing: CGFloat,
            keySpacing: CGFloat,
            horizontalPadding: CGFloat,
            reduceMotion: Bool,
            pageRevision: Int,
            onVisibleCategory: @escaping (String) -> Void,
            onTap: @escaping (String) -> Void
        ) {
            needsReload = needsReload || self.pageRevision != pageRevision
                || self.columns != columns || self.horizontalPadding != horizontalPadding
            self.pages = pages
            self.columns = max(1, columns)
            self.rowHeight = rowHeight
            self.rowSpacing = rowSpacing
            self.keySpacing = keySpacing
            self.horizontalPadding = horizontalPadding
            self.reduceMotion = reduceMotion
            self.pageRevision = pageRevision
            self.onVisibleCategory = onVisibleCategory
            self.onTap = onTap
        }

        func collectionView(
            _ collectionView: UICollectionView,
            layout collectionViewLayout: UICollectionViewLayout,
            sizeForItemAt indexPath: IndexPath
        ) -> CGSize {
            let width = max(collectionView.bounds.width, 1)
            let height = max(collectionView.bounds.height, 1)
            return CGSize(width: width, height: height)
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
                columns: columns,
                rowHeight: rowHeight,
                rowSpacing: rowSpacing,
                keySpacing: keySpacing,
                horizontalPadding: horizontalPadding,
                reduceMotion: reduceMotion,
                onTap: { [weak self] emoji in self?.onTap?(emoji) }
            )
            return cell
        }

        func scroll(to request: EmojiScrollRequest?, in collectionView: UICollectionView, animated: Bool) {
            guard let request, request != lastScrollRequest else { return }
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
                // SwiftUI can update this representable before reloadData or
                // before its first layout pass. Do not consume the request;
                // layoutSubviews retries it when both become ready.
                return
            case .ready(let index):
                targetIndex = index
            }
            (collectionView as? EmojiPagerCollectionView)?.cancelVariantSelection()
            pendingScrollRequest = nil
            lastScrollRequest = request
            selectedIndex = targetIndex
            collectionView.scrollToItem(
                at: IndexPath(item: targetIndex, section: 0),
                at: .centeredHorizontally,
                animated: animated
            )
            notifyVisiblePage(targetIndex)
        }

        func retryPendingScroll(in collectionView: EmojiPagerCollectionView) {
            guard let request = pendingScrollRequest else { return }
            scroll(to: request, in: collectionView, animated: request.animated && !reduceMotion)
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            let index = pageIndex(for: scrollView)
            guard index != selectedIndex else { return }
            selectedIndex = index
            // Publish the page while the finger is moving so the category
            // highlight follows the native pager. The current scroll request is
            // unchanged, so updateUIView cannot start a competing scroll.
            notifyVisiblePage(index)
        }

        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            if !decelerate {
                notifyVisiblePage(pageIndex(for: scrollView))
                reloadWhenIdle(scrollView)
            }
        }

        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
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

        private func reloadIfIdle(_ view: EmojiPagerCollectionView) {
            guard needsReload, !view.hasVariantSelection,
                  !view.isTracking, !view.isDragging, !view.isDecelerating else { return }
            needsReload = false
            let offset = view.contentOffset
            view.reloadData()
            view.layoutIfNeeded()
            view.setContentOffset(offset, animated: false)
            notifyVisiblePage(pageIndex(for: view))
        }

        private func pageIndex(for scrollView: UIScrollView) -> Int {
            let pageWidth = max(scrollView.bounds.width, 1)
            return min(
                max(Int((scrollView.contentOffset.x / pageWidth).rounded()), 0),
                max(0, pages.count - 1)
            )
        }

        private func notifyVisiblePage(_ index: Int) {
            guard pages.indices.contains(index) else { return }
            let page = pages[index]
            // A standard page can straddle two categories. The category at the
            // visual center is the one the user is looking at while paging.
            let centerItem = min(
                max(columns * 2 + columns / 2, 0),
                max(0, page.items.count - 1)
            )
            let category = page.items.indices.contains(centerItem)
                ? page.items[centerItem].categoryID
                : page.categoryID
            onVisibleCategory?(category)
        }
    }
}

private final class EmojiPagerCollectionView: UICollectionView, UIGestureRecognizerDelegate {
    var onEmojiInsert: ((String) -> Void)?
    var onInteractionEnded: (() -> Void)?
    var onLayoutReady: (() -> Void)?
    private var variantSession: KeyVariantSession?
    private var popup: UIView?
    private var variantPopupHost: UIHostingController<KeyVariantPopup>?
    private var initialVariantIndex = 0
    private var holdOrigin = CGPoint.zero
    private var hasMovedVariant = false
    var hasVariantSelection: Bool { variantSession != nil }
    private var lastItemLayoutSize: CGSize = .zero
    private lazy var hold = UILongPressGestureRecognizer(target: self, action: #selector(held(_:)))

    override init(frame: CGRect, collectionViewLayout layout: UICollectionViewLayout) {
        super.init(frame: frame, collectionViewLayout: layout)
        // The pager, not a recycled button, owns the entire hold lifecycle.
        hold.minimumPressDuration = KeyboardDeletion.holdRecognitionDuration
        // Keep the tone session alive while the finger travels beyond the
        // popup. The session ends only when the touch ends or is cancelled.
        hold.allowableMovement = 10_000
        hold.delaysTouchesBegan = false
        // Once the hold is recognized, cancel the button's pending tap so a
        // tone selection cannot also insert the base emoji on release.
        hold.cancelsTouchesInView = true
        hold.delegate = self
        // Do not wait for the pager pan to fail: a stationary long press must
        // recognize on its own. `gestureRecognizerShouldBegin` rejects a
        // genuine swipe once the pan has moved past the small jitter window.
        addGestureRecognizer(hold)
    }

    required init?(coder: NSCoder) { nil }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        false
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === hold else { return super.gestureRecognizerShouldBegin(gestureRecognizer) }
        guard !isDragging, !isDecelerating,
              KeyboardInteractionPreferences.accentVariantsEnabled,
              let button = emojiButton(at: hold.location(in: self)) else { return false }
        let translation = panGestureRecognizer.translation(in: self)
        guard hypot(translation.x, translation.y) < 16 else { return false }
        return EmojiSkinToneVariants.options(for: button.item.emoji).count > 1
    }

    private func emojiButton(at point: CGPoint) -> EmojiKeyButton? {
        var view = hitTest(point, with: nil)
        while let candidate = view, candidate !== self {
            if let button = candidate as? EmojiKeyButton { return button }
            view = candidate.superview
        }
        return nil
    }

    @objc private func held(_ recognizer: UILongPressGestureRecognizer) {
        switch recognizer.state {
        case .began:
            guard let button = emojiButton(at: recognizer.location(in: self)) else { return }
            let options = EmojiSkinToneVariants.options(for: button.item.emoji)
            guard options.count > 1 else { return }
            let source = button.convert(button.bounds, to: self)
            let viewportSource = source.offsetBy(dx: -bounds.minX, dy: -bounds.minY)
            var frame = KeyVariantPopup.frame(for: viewportSource, optionCount: options.count,
                                               isEmoji: true, in: bounds.size)
            frame.size.width = min(frame.width, max(0, bounds.width - 12))
            frame.origin.x = min(frame.minX, max(6, bounds.width - frame.width - 6))
            frame = frame.offsetBy(dx: bounds.minX, dy: bounds.minY)
            variantSession = KeyVariantSession(options: options, sourceFrame: source,
                popupFrame: frame, isEmoji: true,
                selectedIndex: options.firstIndex(of: button.item.emoji) ?? 0)
            initialVariantIndex = variantSession?.selectedIndex ?? 0
            holdOrigin = recognizer.location(in: self)
            hasMovedVariant = false
            // A swipe wins immediately while the hold is pending. Once recognized,
            // only the hold tracks the finger; changing the pan cannot cancel it.
            panGestureRecognizer.isEnabled = false
            let host = UIHostingController(
                rootView: KeyVariantPopup(
                    options: options,
                    selectedIndex: variantSession?.selectedIndex ?? 0,
                    isEmoji: true
                )
            )
            host.view.backgroundColor = .clear
            host.view.isOpaque = false
            host.view.frame = frame
            host.view.isUserInteractionEnabled = false
            host.view.accessibilityElementsHidden = true
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
        let selectedIndex = EmojiToneHitTesting.selectedIndex(
            at: point, source: session.sourceFrame, popup: session.popupFrame,
            optionCount: session.options.count, initialIndex: initialVariantIndex)
        // Keep the last valid tone while the finger briefly leaves the popup's
        // selection corridor. The native picker does not lose the hold during
        // that small excursion, and release should still commit one tone.
        guard selectedIndex >= 0 else { return }
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
            isEmoji: true
        )
    }

    func cancelVariantSelection() {
        let wasActive = variantSession != nil || popup != nil
        variantSession = nil
        popup?.removeFromSuperview()
        popup = nil
        variantPopupHost = nil
        panGestureRecognizer.isEnabled = true
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

    /// Empty cells and the gaps between emoji rows belong to the pager. Return
    /// the collection view for those points so its horizontal pan recognizer
    /// starts even when the finger does not land on an emoji button.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard bounds.contains(point) else { return nil }
        guard let hit = super.hitTest(point, with: event) else { return self }
        var candidate: UIView? = hit
        while let view = candidate, view !== self {
            if view is EmojiKeyButton || view === popup {
                return hit
            }
            candidate = view.superview
        }
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
            cancelVariantSelection()
            layout.itemSize = size
            layout.invalidateLayout()
            reloadData()
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

    func configure(
        page: EmojiPage,
        columns: Int,
        rowHeight: CGFloat,
        rowSpacing: CGFloat,
        keySpacing: CGFloat,
        horizontalPadding: CGFloat,
        reduceMotion: Bool,
        onTap: @escaping (String) -> Void
    ) {
        grid?.removeFromSuperview()
        contentView.subviews.forEach { $0.removeFromSuperview() }

        let panHost = UIView()
        panHost.backgroundColor = .clear
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
        vertical.isUserInteractionEnabled = !page.items.isEmpty
        vertical.translatesAutoresizingMaskIntoConstraints = false

        for row in 0..<4 {
            let horizontal = UIStackView()
            horizontal.axis = .horizontal
            horizontal.alignment = .fill
            horizontal.distribution = .fillEqually
            horizontal.spacing = keySpacing
            horizontal.isUserInteractionEnabled = !page.items.isEmpty
            horizontal.translatesAutoresizingMaskIntoConstraints = false
            horizontal.heightAnchor.constraint(equalToConstant: rowHeight).isActive = true
            for column in 0..<max(1, columns) {
                let index = row * max(1, columns) + column
                if page.items.indices.contains(index) {
                    let button = EmojiKeyButton(item: page.items[index], reduceMotion: reduceMotion)
                    button.applyEmojiFont(.systemFont(ofSize: min(22, max(16, rowHeight * 0.62))))
                    button.onTap = onTap
                    horizontal.addArrangedSubview(button)
                } else {
                    let filler = UIView()
                    filler.isUserInteractionEnabled = false
                    filler.isAccessibilityElement = false
                    horizontal.addArrangedSubview(filler)
                }
            }
            vertical.addArrangedSubview(horizontal)
        }

        contentView.addSubview(vertical)
        NSLayoutConstraint.activate([
            vertical.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: horizontalPadding),
            vertical.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -horizontalPadding),
            vertical.topAnchor.constraint(equalTo: contentView.topAnchor),
            vertical.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor)
        ])
        grid = vertical
    }
}

private final class EmojiKeyButton: UIButton {
    let item: EmojiGridItem
    let reduceMotion: Bool
    var onTap: ((String) -> Void)?
    private let glyph = UILabel()

    init(item: EmojiGridItem, reduceMotion: Bool) {
        self.item = item
        self.reduceMotion = reduceMotion
        super.init(frame: .zero)
        // Keyboard extensions on iOS 26 drop UIButton.Configuration titles.
        // A UILabel is the reliable way to draw emoji glyphs.
        configuration = nil
        setTitle(nil, for: .normal)
        glyph.text = item.emoji
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
        accessibilityLabel = item.emoji
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
        return bounds.insetBy(dx: -6, dy: -6).contains(point)
    }

    override var isHighlighted: Bool {
        didSet {
            layer.cornerRadius = 13
            layer.masksToBounds = true
            backgroundColor = isHighlighted ? UIColor.label.withAlphaComponent(0.12) : .clear
            layer.borderWidth = isHighlighted ? 1 : 0
            layer.borderColor = isHighlighted ? UIColor.label.withAlphaComponent(0.16).cgColor : nil
        }
    }

    override func accessibilityActivate() -> Bool {
        onTap?(item.emoji)
        return true
    }

    @objc private func tapped() {
        onTap?(item.emoji)
    }

}

// MARK: - Supporting types

// Pure geometry kept here so the standalone emoji check exercises the same code.
private enum EmojiToneHitTesting {
    static func selectedIndex(at point: CGPoint, source: CGRect, popup: CGRect,
                              optionCount: Int, initialIndex: Int) -> Int {
        guard optionCount > 0 else { return -1 }
        // Popup wins where a first-row bubble overlaps its source.
        if !popup.contains(point), source.insetBy(dx: -8, dy: -8).contains(point) {
            return initialIndex
        }
        // Allow sliding through the corridor from the key to its popup.
        guard source.union(popup).insetBy(dx: -16, dy: -16).contains(point) else { return -1 }
        let cellWidth = max(1, (popup.width - 12) / CGFloat(optionCount))
        return min(max(0, Int(floor((point.x - popup.minX - 6) / cellWidth))), optionCount - 1)
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
    let items: [EmojiGridItem]
}
