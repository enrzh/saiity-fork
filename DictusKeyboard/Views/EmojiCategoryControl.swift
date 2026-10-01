import UIKit
import DictusCore

/// Single native owner for every cell in the permanently visible category rail.
final class EmojiCategoryControl: UIControl {
    var sectionCount = 0 {
        didSet { setCurrentIndex(currentIndex) }
    }
    var categoryNames: [String] = [] {
        didSet { updateAccessibilityValue() }
    }
    var onIndexChanged: ((Int) -> Void)?
    private(set) var currentIndex = 0
    var dragActivationDistance: CGFloat = 7
    var hitExpansion: CGFloat = 6
    private var touchOrigin = CGPoint.zero
    private var dragging = false
    private var lastDragIndex: Int?

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        backgroundColor = .clear
        isOpaque = false
        isMultipleTouchEnabled = false
        isExclusiveTouch = false
        isAccessibilityElement = true
        accessibilityTraits = [.button, .adjustable]
        accessibilityLabel = "Emoji category"
        accessibilityHint = "Tap or swipe left or right to choose an emoji category."
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        self.point(inside: point, with: event) ? self : nil
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        !isHidden && isUserInteractionEnabled && isEnabled && alpha > 0.01
            && bounds.insetBy(dx: 0, dy: -hitExpansion).contains(point)
    }

    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        touchOrigin = touch.location(in: self)
        dragging = false
        lastDragIndex = nil
        return true
    }

    override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        let point = touch.location(in: self)
        let dx = abs(point.x - touchOrigin.x)
        if dx >= dragActivationDistance && dx >= abs(point.y - touchOrigin.y) { dragging = true }
        if dragging { selectAccessibilityCategory(nearestIndex(toX: point.x)) }
        return true
    }

    override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
        if let touch { selectAccessibilityCategory(nearestIndex(toX: touch.location(in: self).x)) }
        cancelTracking(with: event)
    }

    override func cancelTracking(with event: UIEvent?) {
        dragging = false
        lastDragIndex = nil
    }

    func setCurrentIndex(_ index: Int) {
        currentIndex = min(max(index, 0), max(0, sectionCount - 1))
        updateAccessibilityValue()
    }

    private func nearestIndex(toX x: CGFloat) -> Int {
        EmojiCategoryBarMetrics.index(atX: x, trackWidth: bounds.width, sectionCount: sectionCount)
    }

    private func selectAccessibilityCategory(_ index: Int) {
        guard sectionCount > 0 else { return }
        let normalized = min(max(index, 0), sectionCount - 1)
        if dragging && lastDragIndex == normalized { return }
        if currentIndex != normalized { HapticFeedback.variantHighlightChanged() }
        lastDragIndex = normalized
        setCurrentIndex(normalized)
        onIndexChanged?(normalized)
    }

    private func updateAccessibilityValue() {
        accessibilityValue = categoryNames.indices.contains(currentIndex) ? categoryNames[currentIndex] : nil
    }

    override func accessibilityActivate() -> Bool {
        guard sectionCount > 0 else { return false }
        selectAccessibilityCategory(currentIndex)
        return true
    }

    override func accessibilityIncrement() { selectAccessibilityCategory(currentIndex + 1) }
    override func accessibilityDecrement() { selectAccessibilityCategory(currentIndex - 1) }
}
