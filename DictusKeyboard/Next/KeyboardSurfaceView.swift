import UIKit
import SwiftUI
import SyllivraKernel

/// The shared bottom bar and complete Emoji board use ordinary UIKit hit testing.
/// SwiftUI supplies non-interactive chrome; other native siblings own the grid.
final class KeyboardSurfaceView: UIView {
    let bottomBar = KeyboardBottomBarView()
    var period: KeyboardPeriodKeyView { bottomBar.period }
    let emoji = EmojiPagerView()
    let emojiCategory = EmojiCategoryControl()
    let emojiDelete = KeyboardDeleteRepeatControl()
    private var emojiChrome: UIHostingController<KeyboardEmojiCategoryFace>?
    private var mode: KeyboardAreaMode?
    private var lastLoggedSize = CGSize.zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        // Remote keyboard hit regions need a painted native owner even when
        // the optional inset and passive SwiftUI category face are absent.
        backgroundColor = UIColor.secondarySystemBackground.withAlphaComponent(0.02)
        isHidden = true
        addSubview(emoji)
        addSubview(bottomBar)
        emojiCategory.accessibilityIdentifier = "emoji-category-scrubber"
        emojiCategory.categoryNames = CategoryInfo.emojiBarSections.map(\.name)
        emojiCategory.sectionCount = CategoryInfo.emojiBarSections.count
        addSubview(emojiCategory)
        addSubview(emojiDelete)
    }

    required init?(coder: NSCoder) { nil }

    func show(_ next: KeyboardAreaMode, layout: VoiceOnlyKeyboardPolicy.Layout,
              inputHeight: CGFloat, fieldKeys: HostFieldPolicy.LetterFieldKeys) {
        let previous = mode
        mode = next
        isHidden = next != .letters && next != .panel && next != .emoji
        bottomBar.show(next, layout: layout, inputHeight: inputHeight, fieldKeys: fieldKeys)
        let surface = layout.surfaceFrame
        let pager = CGRect(x: surface.minX, y: surface.minY, width: surface.width,
                           height: max(0, layout.floatingEmojiCategoryFrame.minY - surface.minY))
        emoji.frame = layout.inputFrame(pager, inputViewHeight: inputHeight)
        emojiCategory.frame = layout.inputFrame(layout.floatingEmojiCategoryFrame, inputViewHeight: inputHeight)
        emojiDelete.frame = layout.inputFrame(layout.boardDeleteFrame, inputViewHeight: inputHeight)
        emoji.isHidden = next != .emoji
        emojiCategory.isHidden = emoji.isHidden
        emojiDelete.isHidden = emoji.isHidden
        emojiChrome?.view.isHidden = emoji.isHidden
        if next == .emoji {
            updateEmojiChrome(visualFrame: layout.commandKeyVisualFrame.offsetBy(
                dx: -layout.boardDeleteFrame.minX, dy: -layout.boardDeleteFrame.minY))
            if previous != .emoji { emoji.present() }
        } else {
            emoji.dismiss()
            emojiCategory.cancelTracking(with: nil)
            emojiDelete.cancelInteraction()
        }
        if previous != next || lastLoggedSize != bounds.size {
            lastLoggedSize = bounds.size
            PersistentLog.log(.diagnosticProbe(
                component: "NativeKeyboardSlice", instanceID: next.rawValue, action: "layout",
                details: "bounds=\(bounds) bar=\(bottomBar.frame) pager=\(emoji.frame) category=\(emojiCategory.frame) delete=\(emojiDelete.frame) unified=true"
            ))
        }
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard !isHidden, isUserInteractionEnabled, alpha > 0.01,
              bounds.contains(point) else { return nil }
        // Delete floats over the full-width pager. Category hit expansion only
        // claims free space; it must not intercept the newly extended last row.
        for owner in [emojiDelete, bottomBar, emoji, emojiCategory] as [UIView] {
            guard !owner.isHidden, owner.isUserInteractionEnabled, owner.alpha > 0.01 else { continue }
            if let hit = owner.hitTest(owner.convert(point, from: self), with: event) { return hit }
        }
        return nil
    }

    private func updateEmojiChrome(visualFrame: CGRect) {
        emojiDelete.keyboardFace.configure(symbol: CommandKeyStyle.deleteSymbolName, visualSize: visualFrame.size)
        emojiDelete.keyboardFace.autoresizingMask = []
        emojiDelete.keyboardFace.frame = visualFrame
        let chrome = KeyboardEmojiCategoryFace(liquidGlassEnabled: KeyboardInteractionPreferences.liquidGlassEnabled)
        if let emojiChrome {
            if emojiChrome.rootView.liquidGlassEnabled != chrome.liquidGlassEnabled {
                emojiChrome.rootView = chrome
            }
        } else {
            let host = UIHostingController(rootView: chrome)
            emojiChrome = host
        }
        emojiChrome?.view.frame = emojiCategory.bounds
        emojiChrome?.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        if let emojiChrome {
            attachKeyboardVisualController(emojiChrome, from: emojiCategory)
        }
        emojiChrome?.view.isHidden = false
    }

    func refreshAppearance() {
        bottomBar.refreshAppearance()
        emojiDelete.existingKeyboardFace?.refreshAppearance()
        emoji.refreshPreferences()
        if let emojiChrome {
            var chrome = emojiChrome.rootView
            chrome.liquidGlassEnabled = KeyboardInteractionPreferences.liquidGlassEnabled
            emojiChrome.rootView = chrome
        }
    }

    func cancelInteractions() {
        bottomBar.cancelInteractions()
        emoji.dismiss()
        emojiCategory.cancelTracking(with: nil)
        emojiDelete.cancelInteraction()
        mode = nil
    }
}

/// Existing shared faces, nested normally under their native touch owners.
private struct KeyboardEmojiCategoryFace: View {
    @ObservedObject var state = KeyboardState.shared
    var liquidGlassEnabled: Bool

    var body: some View {
        let sections = CategoryInfo.emojiBarSections
        let index = state.emojiCategorySelectionIndex
        EmojiCategoryBar(
                sections: sections,
                selectedCategoryID: sections.indices.contains(index) ? sections[index].id : "recents"
            )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .ignoresSafeArea()
        .environment(\.keyboardLiquidGlassEnabled, liquidGlassEnabled)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Native face and native touch owner share the same frame and lifetime.
/// Only the non-interactive popup/preview uses SwiftUI.
final class KeyboardPeriodKeyView: UIView {
    var onInsert: ((String) -> Void)?
    var onDelete: (() -> Void)?
    private let control = KeyboardKeyTouchControl()
    private let plate = UIVisualEffectView(effect: nil)
    private let labels = UIStackView()
    private let holdWork = KeyboardHoldSession()
    private var active = false
    private var variants: KeyVariantSession?
    private var popup: UIHostingController<KeyVariantPopup>?
    private var preview: UIHostingController<KeyPressPreviewHost>?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        accessibilityIdentifier = "period-key"
        accessibilityLabel = "Period"
        accessibilityHint = "Hold for punctuation options."
        accessibilityTraits = [.button]
        isAccessibilityElement = true
        plate.isUserInteractionEnabled = false
        plate.layer.cornerRadius = CommandKeyStyle.cornerRadius
        plate.clipsToBounds = true
        labels.axis = .vertical
        labels.alignment = .center
        labels.spacing = 0
        for (text, size, weight, color) in [
            (".", CGFloat(19), UIFont.Weight.regular, UIColor.label),
            (",", CGFloat(11), UIFont.Weight.medium, KeyboardChromeRole.secondaryForeground)
        ] {
            let label = UILabel()
            label.text = text
            label.font = .systemFont(ofSize: size, weight: weight)
            label.textColor = color
            labels.addArrangedSubview(label)
        }
        control.addSubview(plate)
        labels.isUserInteractionEnabled = false
        labels.translatesAutoresizingMaskIntoConstraints = false
        control.addSubview(labels)
        NSLayoutConstraint.activate([
            labels.centerXAnchor.constraint(equalTo: control.centerXAnchor),
            labels.centerYAnchor.constraint(equalTo: control.centerYAnchor)
        ])
        control.isAccessibilityElement = false
        control.onBegan = { [weak self] _ in self?.begin() }
        control.onMoved = { [weak self] point in self?.move(point) }
        control.onEnded = { [weak self] cancelled in self?.finish(cancelled: cancelled) }
        addSubview(control)
        refreshAppearance()
    }

    required init?(coder: NSCoder) { nil }

    override func layoutSubviews() {
        super.layoutSubviews()
        if active, let container = window ?? superview,
           let source = variants?.sourceFrame ?? preview?.rootView.session?.sourceFrame,
           source != convert(bounds, to: container) {
            cancelInteraction()
        }
        let size = CGSize(width: min(bounds.width, VoiceOnlyKeyboardPolicy.periodKeyPlateWidth),
                          height: VoiceOnlyKeyboardPolicy.bottomBarVisualHeight)
        plate.frame = CGRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2,
                             width: size.width, height: size.height)
        control.frame = bounds
        control.highlightSize = size
        control.highlightCornerRadius = CommandKeyStyle.cornerRadius
    }

    func refreshAppearance() {
        plate.effect = nil
        plate.alpha = 1
        plate.backgroundColor = KeyboardChromeRole.input.solidFill(increasedContrast:
            UIAccessibility.isDarkerSystemColorsEnabled || UIAccessibility.isReduceTransparencyEnabled)
        plate.layer.cornerRadius = CommandKeyStyle.cornerRadius
    }

    override func accessibilityActivate() -> Bool {
        guard !isHidden else { return false }
        begin()
        finish(cancelled: false)
        return true
    }

    private func begin() {
        guard !active, !isHidden else { return }
        active = true
        PersistentLog.log(.keyboardPeriodKeyProbe(details: "began native=true frame=\(frame)"))
        HapticFeedback.playInputClick()
        onInsert?(".")
        if KeyboardInteractionPreferences.keyPopupMode == .flash {
            control.flashKeyboardKey(in: plate.frame, cornerRadius: CommandKeyStyle.cornerRadius)
        }
        let container = window ?? superview
        if KeyboardInteractionPreferences.keyPopupMode.showsPreview, let container {
            let source = convert(bounds, to: container)
            let session = KeyPreviewSession(text: ".", sourceFrame: source,
                popupFrame: KeyPressPreviewHost.frame(for: source, in: container.bounds.size))
            let host = UIHostingController(rootView: KeyPressPreviewHost(session: .constant(session)))
            host.view.backgroundColor = .clear
            host.view.isUserInteractionEnabled = false
            host.view.frame = container.bounds
            attachKeyboardVisualController(host, from: container)
            preview = host
        }
        holdWork.begin(after: KeyboardDeletion.holdRecognitionDuration) { [weak self] in self?.showVariants() }
    }

    private func showVariants() {
        guard active, let container = window ?? superview else { return }
        let options = KeyboardVariantPreferences.options(for: ".", kind: .symbol)
        guard options.count > 1 else { return }
        detachKeyboardVisualController(preview)
        preview = nil
        let source = convert(bounds, to: container)
        let rect = KeyVariantPopup.frame(for: source, optionCount: options.count,
                                        isEmoji: false, in: container.bounds.size)
        variants = KeyVariantSession(options: options, sourceFrame: source, popupFrame: rect,
                                     isEmoji: false, selectedIndex: 0)
        let host = UIHostingController(rootView: KeyVariantPopup(options: options, selectedIndex: 0, isEmoji: false))
        host.view.backgroundColor = .clear
        host.view.isUserInteractionEnabled = false
        host.view.frame = rect
        attachKeyboardVisualController(host, from: container)
        popup = host
        HapticFeedback.variantPopupPresented()
    }

    private func move(_ point: CGPoint) {
        guard var session = variants, let container = popup?.view.superview else { return }
        let index = KeyVariantPopup.selectedIndex(at: control.convert(point, to: container),
                                                 popupFrame: session.popupFrame, optionCount: session.options.count)
        guard index != session.selectedIndex else { return }
        session.selectedIndex = index
        variants = session
        popup?.rootView = KeyVariantPopup(options: session.options, selectedIndex: index, isEmoji: false)
        HapticFeedback.variantHighlightChanged()
    }

    private func finish(cancelled: Bool) {
        guard active else { return }
        active = false
        holdWork.cancel()
        let session = variants
        variants = nil
        detachKeyboardVisualController(popup)
        popup = nil
        detachKeyboardVisualController(preview)
        preview = nil
        PersistentLog.log(.keyboardPeriodKeyProbe(details: "ended native=true cancelled=\(cancelled)"))
        if !cancelled, let session, session.options.indices.contains(session.selectedIndex),
           session.options[session.selectedIndex] != "." {
            onDelete?()
            onInsert?(session.options[session.selectedIndex])
        }
    }

    func cancelInteraction() {
        control.clearKeyboardKeyFlashes()
        control.cancelInteraction()
        finish(cancelled: true)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { cancelInteraction() }
    }
}
