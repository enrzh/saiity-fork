import SwiftUI
import UIKit
import DictusCore

enum EmojiCategoryBarMetrics {
    // The icon rail and its Liquid Glass capsule move together while scrubbing.
    static let slotWidth: CGFloat = 16
    /// Finger movement is multiplied so Recents and Flags are a short drag
    /// apart instead of a slide across the keyboard.
    static let travelGain: CGFloat = 2
    static let slotSpacing: CGFloat = 2
    static let expandedBarWidth: CGFloat = 176
    static let railInset: CGFloat = 3

    static func renderedSlotWidth(forInnerWidth innerWidth: CGFloat, sectionCount: Int) -> CGFloat {
        guard sectionCount > 0 else { return slotWidth }
        let gapWidth = CGFloat(max(0, sectionCount - 1)) * slotSpacing
        return min(slotWidth, max(1, (innerWidth - gapWidth) / CGFloat(sectionCount)))
    }

    static func handleWidth(forTrackWidth trackWidth: CGFloat) -> CGFloat {
        min(expandedBarWidth, max(0, trackWidth - railInset * 2))
    }

    static func maximumHandleOffset(trackWidth: CGFloat, handleWidth: CGFloat) -> CGFloat {
        max(0, trackWidth - railInset * 2 - handleWidth)
    }

    static func handleOffset(
        forIndex index: Int,
        sectionCount: Int,
        trackWidth: CGFloat,
        handleWidth: CGFloat
    ) -> CGFloat {
        let maximum = maximumHandleOffset(trackWidth: trackWidth, handleWidth: handleWidth)
        guard sectionCount > 1 else { return 0 }
        let contentWidth = max(0, handleWidth - railInset * 2)
        let slotWidth = renderedSlotWidth(forInnerWidth: contentWidth, sectionCount: sectionCount)
        let clampedIndex = CGFloat(min(max(index, 0), sectionCount - 1))
        let iconCenterInBar = railInset * 2 + slotWidth / 2
            + clampedIndex * (slotWidth + slotSpacing)
        return min(max(trackWidth / 2 - iconCenterInBar, 0), maximum)
    }

    static func index(
        forHandleOffset offset: CGFloat,
        sectionCount: Int,
        trackWidth: CGFloat,
        handleWidth: CGFloat
    ) -> Int {
        guard sectionCount > 1 else { return 0 }
        let contentWidth = max(0, handleWidth - railInset * 2)
        let slotWidth = renderedSlotWidth(forInnerWidth: contentWidth, sectionCount: sectionCount)
        let step = max(1, slotWidth + slotSpacing)
        let firstIconCenterInBar = railInset * 2 + slotWidth / 2
        let markerPositionInBar = trackWidth / 2 - min(max(offset, 0), maximumHandleOffset(
            trackWidth: trackWidth,
            handleWidth: handleWidth
        ))
        return min(
            max(Int(((markerPositionInBar - firstIconCenterInBar) / step).rounded()), 0),
            sectionCount - 1
        )
    }
}

/// A compact current-category control that expands into a horizontal scrubber
/// only while the user drags it.
struct EmojiCategoryBar: View {
    let sections: [CategoryInfo]
    let selectedCategoryID: String
    let isExpanded: Bool
    @Binding var contentOffset: CGFloat

    var body: some View {
        GeometryReader { proxy in
            let insetY = VoiceOnlyKeyboardPolicy.emojiCategoryVerticalInset
            let count = max(1, sections.count)
            let trackWidth = proxy.size.width
            let innerHeight = max(0, proxy.size.height - insetY * 2)
            let handleWidth = EmojiCategoryBarMetrics.handleWidth(forTrackWidth: trackWidth)
            let maximumOffset = EmojiCategoryBarMetrics.maximumHandleOffset(
                trackWidth: trackWidth,
                handleWidth: handleWidth
            )
            let handleOffset = min(max(contentOffset, 0), maximumOffset)
            let handleCenterX = EmojiCategoryBarMetrics.railInset + handleWidth / 2 + handleOffset
            let barContentWidth = max(0, handleWidth - EmojiCategoryBarMetrics.railInset * 2)
            let railSlotWidth = EmojiCategoryBarMetrics.renderedSlotWidth(
                forInnerWidth: barContentWidth,
                sectionCount: count
            )
            let selectedIndex = sections.firstIndex(where: { $0.id == selectedCategoryID }) ?? 0
            let collapsedDiameter = min(proxy.size.height, proxy.size.width)
            let collapsedCenterX = trackWidth / 2
            ZStack {
                if isExpanded {
                    ZStack {
                        ZStack {
                            glassSurface(in: Capsule())
                                .overlay {
                                    Capsule()
                                        .stroke(Color.primary.opacity(0.10), lineWidth: 0.5)
                                }
                            .frame(width: handleWidth, height: innerHeight)
                            .position(x: handleCenterX, y: innerHeight / 2)
                            HStack(spacing: EmojiCategoryBarMetrics.slotSpacing) {
                                ForEach(Array(sections.enumerated()), id: \.element.id) { index, section in
                                    Image(systemName: section.icon)
                                        .font(.system(size: min(12, railSlotWidth), weight: .regular))
                                        .foregroundStyle(.primary)
                                        .symbolVariant(.none)
                                        .frame(width: railSlotWidth, height: innerHeight)
                                        .accessibilityLabel(section.name)
                                        .accessibilityAddTraits(.isButton)
                                }
                            }
                            .frame(width: barContentWidth, height: innerHeight)
                            .position(x: handleCenterX, y: innerHeight / 2)
                        }
                        if sections.indices.contains(selectedIndex) {
                            ZStack {
                                Circle()
                                    .fill(Color(.systemBackground).opacity(0.82))
                                    .overlay {
                                        Circle()
                                            .stroke(Color.primary.opacity(0.28), lineWidth: 1)
                                    }
                                Image(systemName: sections[selectedIndex].icon)
                                    .font(.system(size: min(12, railSlotWidth), weight: .regular))
                                    .foregroundStyle(.primary)
                                    .symbolVariant(.none)
                                    .accessibilityLabel(sections[selectedIndex].name)
                            }
                            .frame(width: min(20, innerHeight), height: min(20, innerHeight))
                            .position(x: trackWidth / 2, y: innerHeight / 2)
                            .allowsHitTesting(false)
                            .zIndex(1)
                        }
                    }
                    .frame(width: trackWidth, height: innerHeight)
                    .position(x: trackWidth / 2, y: proxy.size.height / 2)
                } else {
                    let shape = Circle()
                    ZStack {
                        glassSurface(in: shape)
                        if sections.indices.contains(selectedIndex) {
                            Image(systemName: sections[selectedIndex].icon)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.primary)
                                .symbolVariant(.fill)
                                .accessibilityLabel(sections[selectedIndex].name)
                        }
                    }
                    .frame(width: collapsedDiameter, height: collapsedDiameter)
                    .position(x: collapsedCenterX, y: proxy.size.height / 2)
                    .overlay(shape.stroke(Color.primary.opacity(0.10), lineWidth: 0.5))
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .onAppear {
                alignSelectedCategory(
                    trackWidth: trackWidth,
                    handleWidth: handleWidth
                )
            }
            .onChange(of: selectedCategoryID) { _, _ in
                // While the UIKit scrubber is expanded, the selected thumb is
                // updated by the active drag. Only the collapsed circle needs
                // to realign its stored geometry.
                guard !isExpanded else { return }
                alignSelectedCategory(
                    trackWidth: trackWidth,
                    handleWidth: handleWidth
                )
            }
            .onChange(of: isExpanded) { _, expanded in
                if !expanded {
                    alignSelectedCategory(
                        trackWidth: trackWidth,
                        handleWidth: handleWidth
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // UIKit owns the drag; this view is visual-only.
        .allowsHitTesting(false)
    }

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var accessibilityContrast: ColorSchemeContrast

    @ViewBuilder
    private func glassSurface<S: Shape>(in shape: S) -> some View {
        if reduceTransparency || accessibilityContrast == .increased {
            shape.fill(Color(.secondarySystemFill))
        } else if #available(iOS 26, *) {
            Color.clear
                .glassEffect(.regular.interactive(), in: shape)
        } else {
            shape.fill(.regularMaterial)
        }
    }

    private func alignSelectedCategory(
        trackWidth: CGFloat,
        handleWidth: CGFloat
    ) {
        guard let index = sections.firstIndex(where: { $0.id == selectedCategoryID }) else { return }
        let target = EmojiCategoryBarMetrics.handleOffset(
            forIndex: index,
            sectionCount: sections.count,
            trackWidth: trackWidth,
            handleWidth: handleWidth
        )
        guard abs(contentOffset - target) > 0.5 else { return }
        contentOffset = target
    }

}

/// Owns the category drag so a stationary touch is inert and a horizontal
/// movement expands the visual control without losing the gesture.
final class EmojiCategoryScrubControl: UIControl {
    var sectionCount = 0 {
        didSet {
            if oldValue != sectionCount {
                selectedIndex = -1
                currentIndex = min(max(currentIndex, 0), max(sectionCount - 1, 0))
            }
        }
    }
    var onIndexChanged: ((Int) -> Void)?
    var onExpansionChanged: ((Bool) -> Void)?
    var onScrollOffsetChanged: ((CGFloat) -> Void)?
    var slotWidth: CGFloat = EmojiCategoryBarMetrics.slotWidth
    var slotSpacing: CGFloat = EmojiCategoryBarMetrics.slotSpacing
    var categoryNames: [String] = [] {
        didSet { updateAccessibilityValue() }
    }
    var currentIndex = 0
    var dragActivationDistance: CGFloat = 7
    /// Small touch slop keeps the compact circle usable without stealing
    /// neighboring controls before the user actually drags.
    var hitExpansion: CGFloat = 6
    var contentInset = UIEdgeInsets(
        top: VoiceOnlyKeyboardPolicy.emojiCategoryVerticalInset,
        left: VoiceOnlyKeyboardPolicy.emojiCategoryHorizontalInset,
        bottom: VoiceOnlyKeyboardPolicy.emojiCategoryVerticalInset,
        right: VoiceOnlyKeyboardPolicy.emojiCategoryHorizontalInset
    )
    private var selectedIndex = -1
    private var dragActive = false
    private var trackingStartX: CGFloat = 0
    private var trackingStartY: CGFloat = 0
    private var trackingStartOffset: CGFloat = 0
    private(set) var isExpanded = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        isMultipleTouchEnabled = false
        isExclusiveTouch = false
        backgroundColor = .clear
        isOpaque = false
        isAccessibilityElement = true
        accessibilityTraits = [.button, .adjustable]
        accessibilityLabel = "Emoji category"
        accessibilityHint = "Swipe up or down to choose an emoji category."
        isUserInteractionEnabled = true
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard !isHidden, isUserInteractionEnabled, isEnabled, alpha > 0.01,
              interactionBounds.contains(point) else { return nil }
        return self
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        guard !isHidden, isUserInteractionEnabled, isEnabled, alpha > 0.01 else { return false }
        return interactionBounds.contains(point)
    }

    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        let location = touch.location(in: self)
        trackingStartX = location.x
        trackingStartY = location.y
        trackingStartOffset = scrollOffset
        dragActive = false
        setExpanded(false)
        return true
    }

    override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        let point = touch.location(in: self)
        let deltaX = point.x - trackingStartX
        let deltaY = point.y - trackingStartY
        if !dragActive,
           abs(deltaX) >= dragActivationDistance,
           abs(deltaX) >= abs(deltaY) {
            dragActive = true
            setExpanded(true)
        }
        guard dragActive else { return true }
        // The complete Liquid Glass bar follows the finger directly.
        setScrollOffset(trackingStartOffset + (point.x - trackingStartX) * EmojiCategoryBarMetrics.travelGain)
        selectCategory(at: scrollOffset)
        return true
    }

    override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
        if dragActive {
            selectCategory(at: scrollOffset)
            let index = selectedIndex >= 0 ? selectedIndex : currentIndex
            setScrollOffset(handleOffset(for: index))
        }
        finishTracking()
    }

    override func cancelTracking(with event: UIEvent?) {
        finishTracking()
    }

    func setExpanded(_ expanded: Bool) {
        guard isExpanded != expanded else { return }
        isExpanded = expanded
        onExpansionChanged?(expanded)
    }

    func setCurrentIndex(_ index: Int) {
        currentIndex = min(max(index, 0), max(sectionCount - 1, 0))
        selectedIndex = currentIndex
        updateAccessibilityValue()
        if !dragActive {
            setScrollOffset(handleOffset(for: currentIndex))
        }
    }

    override func accessibilityActivate() -> Bool {
        selectAccessibilityCategory(currentIndex)
        return true
    }

    override func accessibilityIncrement() {
        selectAccessibilityCategory(currentIndex + 1)
    }

    override func accessibilityDecrement() {
        selectAccessibilityCategory(currentIndex - 1)
    }

    private func selectAccessibilityCategory(_ index: Int) {
        guard sectionCount > 0 else { return }
        let normalized = min(max(index, 0), sectionCount - 1)
        currentIndex = normalized
        selectedIndex = normalized
        setScrollOffset(handleOffset(for: normalized))
        onIndexChanged?(normalized)
        updateAccessibilityValue()
    }

    private func updateAccessibilityValue() {
        guard categoryNames.indices.contains(currentIndex) else {
            accessibilityValue = nil
            return
        }
        accessibilityValue = categoryNames[currentIndex]
    }

    private func finishTracking() {
        dragActive = false
        setExpanded(false)
        selectedIndex = -1
        trackingStartX = 0
        trackingStartY = 0
        trackingStartOffset = scrollOffset
    }

    private func selectCategory(at offset: CGFloat) {
        guard sectionCount > 0, bounds.width > 0,
              !isHidden, isUserInteractionEnabled, isEnabled, alpha > 0.01 else { return }
        let index = EmojiCategoryBarMetrics.index(
            forHandleOffset: offset,
            sectionCount: sectionCount,
            trackWidth: bounds.width,
            handleWidth: handleWidth
        )
        guard index != selectedIndex else { return }
        selectedIndex = index
        currentIndex = index
        onIndexChanged?(index)
    }

    var scrollOffset: CGFloat = 0

    func setScrollOffset(_ offset: CGFloat) {
        let clamped = min(max(offset, 0), maximumScrollOffset)
        guard abs(scrollOffset - clamped) > 0.5 else { return }
        scrollOffset = clamped
        onScrollOffsetChanged?(clamped)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        setScrollOffset(scrollOffset)
    }

    private var interactionBounds: CGRect {
        if isExpanded { return bounds.insetBy(dx: -hitExpansion, dy: -hitExpansion) }
        // Floating chrome is an invisible full-width track above the spacebar.
        // Keep the collapsed artwork as a circle, but accept scrub starts
        // anywhere on the track so category paging stays reachable.
        return bounds.insetBy(dx: 0, dy: -hitExpansion)
    }

    private var handleWidth: CGFloat {
        EmojiCategoryBarMetrics.handleWidth(forTrackWidth: bounds.width)
    }

    private var maximumScrollOffset: CGFloat {
        EmojiCategoryBarMetrics.maximumHandleOffset(
            trackWidth: bounds.width,
            handleWidth: handleWidth
        )
    }

    private func handleOffset(for index: Int) -> CGFloat {
        EmojiCategoryBarMetrics.handleOffset(
            forIndex: index,
            sectionCount: sectionCount,
            trackWidth: bounds.width,
            handleWidth: handleWidth
        )
    }
}
