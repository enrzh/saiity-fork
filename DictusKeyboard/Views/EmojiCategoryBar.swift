// DictusKeyboard/Views/EmojiCategoryBar.swift
import SwiftUI
import DictusCore

/// Native-style category bookmarks floating over the emoji grid.
/// Icons are decorative; UIKit `EmojiCategoryScrubControl` owns tap and scrub.
struct EmojiCategoryBar: View {
    let sections: [CategoryInfo]
    let selectedCategoryID: String
    var scrubbingEnabled: Bool = true
    let onSelectCategory: (String) -> Void

    var body: some View {
        GeometryReader { proxy in
            let insetX = VoiceOnlyKeyboardPolicy.emojiCategoryHorizontalInset
            let insetY = VoiceOnlyKeyboardPolicy.emojiCategoryVerticalInset
            let count = max(1, sections.count)
            let innerWidth = max(0, proxy.size.width - insetX * 2)
            let innerHeight = max(0, proxy.size.height - insetY * 2)
            let slotWidth = innerWidth / CGFloat(count)
            ZStack {
                HStack(spacing: 0) {
                    ForEach(Array(sections.enumerated()), id: \.element.id) { _, section in
                        let isSelected = selectedCategoryID == section.id
                        ZStack {
                            if isSelected {
                                Capsule()
                                    .fill(Color(.tertiarySystemFill))
                                    .frame(
                                        width: min(28, max(18, slotWidth - 6)),
                                        height: min(22, innerHeight - 4)
                                    )
                            }
                            Image(systemName: section.icon)
                                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                                .foregroundStyle(.primary)
                                .symbolVariant(isSelected ? .fill : .none)
                        }
                        .frame(width: slotWidth, height: innerHeight)
                        .accessibilityLabel(section.name)
                        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
                        .accessibilityAction {
                            onSelectCategory(section.id)
                        }
                    }
                    .allowsHitTesting(false)
                }
                .padding(.horizontal, insetX)
                .padding(.vertical, insetY)
                if scrubbingEnabled {
                    CategorySwipeControl(sectionCount: sections.count) { index in
                        guard sections.indices.contains(index) else { return }
                        onSelectCategory(sections[index].id)
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .allowsHitTesting(scrubbingEnabled)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // UIKit `EmojiCategoryScrubControl` matches the floating bar frame.
        .allowsHitTesting(scrubbingEnabled)
    }
}

/// Owns the category strip gesture as one control so horizontal scrubbing is
/// continuous instead of ending when the finger crosses an individual button.
struct CategorySwipeControl: UIViewRepresentable {
    let sectionCount: Int
    let onIndexChanged: (Int) -> Void

    func makeUIView(context: Context) -> EmojiCategoryScrubControl {
        let view = EmojiCategoryScrubControl()
        view.sectionCount = sectionCount
        view.onIndexChanged = onIndexChanged
        return view
    }

    func updateUIView(_ uiView: EmojiCategoryScrubControl, context: Context) {
        uiView.sectionCount = sectionCount
        uiView.onIndexChanged = onIndexChanged
    }
}

/// UIControl tracking survives keyboard-extension hosting, including the
/// suggestion lane where a plain UIView often never sees touchesMoved.
final class EmojiCategoryScrubControl: UIControl {
    var sectionCount = 0 {
        didSet {
            if oldValue != sectionCount { selectedIndex = -1 }
        }
    }
    var onIndexChanged: ((Int) -> Void)?
    /// Small touch slop makes the compact category strip usable without
    /// expanding it far enough to steal the neighboring toolbar controls.
    var hitExpansion: CGFloat = 6
    var contentInset = UIEdgeInsets(
        top: VoiceOnlyKeyboardPolicy.emojiCategoryVerticalInset,
        left: VoiceOnlyKeyboardPolicy.emojiCategoryHorizontalInset,
        bottom: VoiceOnlyKeyboardPolicy.emojiCategoryVerticalInset,
        right: VoiceOnlyKeyboardPolicy.emojiCategoryHorizontalInset
    )
    private var selectedIndex = -1

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
        isAccessibilityElement = false
        isUserInteractionEnabled = true
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard !isHidden, isUserInteractionEnabled, isEnabled, alpha > 0.01,
              interactiveBounds.contains(point) else { return nil }
        return self
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        guard !isHidden, isUserInteractionEnabled, isEnabled, alpha > 0.01 else { return false }
        return interactiveBounds.contains(point)
    }

    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        select(touch.location(in: self), force: true)
        return true
    }

    override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        select(touch.location(in: self), force: false)
        return true
    }

    override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
        if let touch { select(touch.location(in: self), force: false) }
    }

    override func cancelTracking(with event: UIEvent?) {
        selectedIndex = -1
    }

    private func select(_ point: CGPoint, force: Bool) {
        guard sectionCount > 0, bounds.width > 0,
              !isHidden, isUserInteractionEnabled, isEnabled, alpha > 0.01 else { return }
        let insetBounds = bounds.inset(by: contentInset)
        let trackWidth = insetBounds.width > 0 ? insetBounds.width : bounds.width
        let originX = insetBounds.width > 0 ? insetBounds.minX : 0
        let width = trackWidth / CGFloat(sectionCount)
        let index = min(max(Int((point.x - originX) / width), 0), sectionCount - 1)
        guard force || index != selectedIndex else { return }
        selectedIndex = index
        onIndexChanged?(index)
    }

    private var interactiveBounds: CGRect {
        bounds.insetBy(dx: -hitExpansion, dy: -hitExpansion)
    }
}
