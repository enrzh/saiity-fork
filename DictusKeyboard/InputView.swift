// DictusKeyboard/InputView.swift
import UIKit

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

    private func reassertTransparentBackdrop() {
        backgroundColor = .clear
        isOpaque = false
        clipsToBounds = false
        layer.masksToBounds = false
        layer.backgroundColor = UIColor.clear.cgColor
    }
}
