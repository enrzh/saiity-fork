// DictusKeyboard/InputView.swift
import UIKit
import DictusCore

/// Custom UIInputView that enables the system keyboard click sound.
/// UIInputViewAudioFeedback protocol must be adopted by a UIView subclass,
/// not by a SwiftUI view. We set this as the inputView of
/// UIInputViewController to enable UIDevice.current.playInputClick().
///
/// UIInputView (not UIView) is required because UIInputViewController.inputView
/// is typed as UIInputView?. Using .keyboard style tells iOS this view behaves
/// like a keyboard, which is necessary for playInputClick() to work.
class KeyboardInputView: UIInputView, UIInputViewAudioFeedback {
    /// Front-to-back native owners, published with their frames by the controller.
    /// Material hosts and legacy placement markers never participate in routing.
    var nativeTouchOwners: [UIView] = []
    weak var emojiPager: UIView?
    weak var periodKey: UIView?
    private let nativeMounts = NSHashTable<UIView>.weakObjects()
    private var lastHitTimestamp: TimeInterval = -1
    private var lastHitPoint = CGPoint(x: -1, y: -1)

    func registerNativeMount(_ mount: UIView) {
        nativeMounts.add(mount)
    }
    /// Return true to enable keyboard click sounds via playInputClick().
    var enableInputClicksWhenVisible: Bool { true }

    /// Convenience initializer using .keyboard input view style.
    convenience init() {
        self.init(frame: .zero, inputViewStyle: .keyboard)
    }

    override init(frame: CGRect, inputViewStyle: UIInputView.Style) {
        super.init(frame: frame, inputViewStyle: inputViewStyle)
        // Let UIKit honor the declared height constraint instead of replacing
        // the custom surface with its transient default keyboard height.
        allowsSelfSizing = true
        clipsToBounds = false
        layer.masksToBounds = false
        reassertTransparentBackdrop()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        allowsSelfSizing = true
        reassertTransparentBackdrop()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        reassertTransparentBackdrop()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        reassertTransparentBackdrop()
        // The hosting view can move while its child's local size stays fixed.
        // Reconvert placement on input-view layout, not only child-size changes.
        for mount in nativeMounts.allObjects {
            mount.setNeedsLayout()
            mount.layoutIfNeeded()
        }
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard !isHidden, isUserInteractionEnabled, alpha > 0.01,
              bounds.contains(point) else { return nil }
        let hit: UIView?
        if nativeTouchOwners.isEmpty {
            hit = super.hitTest(point, with: event)
        } else {
            hit = nativeTouchOwners.lazy.compactMap { owner -> UIView? in
                guard owner.superview === self, !owner.isHidden,
                      owner.isUserInteractionEnabled, owner.alpha > 0.01 else { return nil }
                return owner.hitTest(owner.convert(point, from: self), with: event)
            }.first ?? self
        }
        #if DEBUG
        let mode = KeyboardState.shared.areaMode
        let timestamp = event?.timestamp ?? -1
        let probePoint = CGPoint(x: point.x.rounded(), y: point.y.rounded())
        if event != nil,
           (mode == .emoji || hit?.isDescendant(of: nativeTouchOwners.first ?? self) != true),
           probePoint != lastHitPoint || (event != nil && timestamp != lastHitTimestamp) {
            lastHitTimestamp = timestamp
            lastHitPoint = probePoint
            PersistentLog.log(.diagnosticProbe(
                component: "KeyboardTouchRoute", instanceID: "root", action: "hit",
                details: "mode=\(mode.rawValue) point=\(Int(point.x)),\(Int(point.y)) winner=\(hit.map { String(describing: type(of: $0)) } ?? "none") event=\(event == nil ? "preflight" : "touch") glass=\(KeyboardInteractionPreferences.liquidGlassEnabled) height=\(Int(bounds.height))"
            ))
        }
        #endif
        return hit
    }

    private func reassertTransparentBackdrop() {
        backgroundColor = .clear
        isOpaque = false
        clipsToBounds = false
        layer.masksToBounds = false
        layer.backgroundColor = UIColor.clear.cgColor
    }
}
