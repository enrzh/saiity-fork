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
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        #if DEBUG
        // Arrival counting lives in `PassthroughControlsView.traceArrival`, which
        // every routed touch must pass through. An earlier gate here tested
        // `phase == .began` and logged exactly zero lines for an entire typing
        // session: UIKit does not expose the touch list in the expected state at
        // this point in hit-testing, so the condition was never true. A stage that
        // cannot fail loudly is worse than no stage, because "no lines" looked
        // like a finding rather than a broken probe.
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
