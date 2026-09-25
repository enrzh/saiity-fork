import UIKit
import DictusCore

/// Owns the category drag so a stationary touch is inert and a horizontal
/// movement expands the visual control without losing the gesture.
final class EmojiCategoryControl: UIControl {
    var sectionCount = 0 {
        didSet {
            if oldValue != sectionCount {
                if !isTracking && !dragActive {
                    selectedIndex = -1
                }
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
        accessibilityHint = "Tap or swipe left or right to choose an emoji category."
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
        } else if let touch {
            // A tap on the bar selects the nearest category. A stationary
            // release used to be inert, so the bar only responded to drags and
            // read as completely unresponsive to anyone who tapped it.
            selectAccessibilityCategory(nearestIndex(toX: touch.location(in: self).x))
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
        // A layout pass while the finger is down must not publish a new offset
        // and restart the drag from the resting circle.
        guard !dragActive, !isTracking else { return }
        setScrollOffset(scrollOffset)
    }

    /// The whole visible track is the target, not just the collapsed circle.
    ///
    /// This used to collapse to a 22pt circle whenever no drag was underway,
    /// which contradicted the doc comment directly above it and left the bar
    /// drawn across the full width while only a small circle could be touched.
    /// Once a drag is underway the moving capsule becomes the target so the
    /// finger can travel past the original circle.
    private var interactionBounds: CGRect {
        if dragActive || isExpanded {
            return expandedHandleFrame.insetBy(dx: -hitExpansion, dy: -hitExpansion)
        }
        return bounds.insetBy(dx: 0, dy: -hitExpansion)
    }

    /// Nearest category handle centre to a tap, so a tap anywhere on the track
    /// resolves to a category instead of being dropped.
    private func nearestIndex(toX x: CGFloat) -> Int {
        guard sectionCount > 0 else { return 0 }
        var best = 0
        var bestDistance = CGFloat.greatestFiniteMagnitude
        for index in 0..<sectionCount {
            let center = EmojiCategoryBarMetrics.railInset
                + handleOffset(for: index)
                + handleWidth / 2
            let distance = abs(center - x)
            if distance < bestDistance {
                bestDistance = distance
                best = index
            }
        }
        return best
    }

    /// The glass capsule that is on screen while scrubbing.
    private var expandedHandleFrame: CGRect {
        let width = handleWidth
        let offset = min(max(scrollOffset, 0), maximumScrollOffset)
        return CGRect(
            x: EmojiCategoryBarMetrics.railInset + offset,
            y: contentInset.top,
            width: width,
            height: max(0, bounds.height - contentInset.top - contentInset.bottom)
        )
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
