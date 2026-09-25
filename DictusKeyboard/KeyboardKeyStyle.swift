import SwiftUI
import UIKit
import DictusCore

/// Shared visual role used by both Solid and Liquid Glass keyboard faces.
enum KeyboardChromeRole {
    case control
    case board
}

/// A visual-only material component. Input belongs to `KeyboardKeyTouchControl`.
struct KeyboardGlassSurface<S: Shape>: ViewModifier {
    let shape: S
    var interactive: Bool = true
    var role: KeyboardChromeRole = .control
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var accessibilityContrast: ColorSchemeContrast

    func body(content: Content) -> some View {
        plate(content).allowsHitTesting(false)
    }

    @ViewBuilder
    private func plate(_ content: Content) -> some View {
        if !KeyboardInteractionPreferences.liquidGlassEnabled {
            if role == .board {
                content.allowsHitTesting(false)
            } else {
                content.background {
                    shape.fill(solidFill).allowsHitTesting(false)
                }
                .allowsHitTesting(false)
            }
        } else if reduceTransparency || accessibilityContrast == .increased {
            content.background {
                shape.fill(Color(uiColor: accessibilityContrast == .increased ? .systemFill : .secondarySystemFill))
                    .allowsHitTesting(false)
            }
            .allowsHitTesting(false)
        } else if #available(iOS 26, *) {
            // WHY `.allowsHitTesting(false)` here and not only in `body`: on iOS
            // 26 `glassEffect` installs a UIKit-backed material view. Relying on
            // the modifier wrapping the result to switch it off is not enough —
            // that layer can win the hit test on its own, and it did: Liquid Glass
            // letter/number/symbol keys became untappable while the separate
            // UIKit chrome buttons above the host kept working. Every branch now
            // marks the material non-hit-testable at the point it is installed.
            if interactive {
                content.glassEffect(.regular.interactive(), in: shape)
                    .allowsHitTesting(false)
            } else {
                content.glassEffect(.regular, in: shape)
                    .allowsHitTesting(false)
            }
        } else {
            content.background {
                shape.fill(.regularMaterial).allowsHitTesting(false)
            }
            .allowsHitTesting(false)
        }
    }

    private var solidFill: Color {
        Color(uiColor: .tertiarySystemFill)
    }
}

extension View {
    func keyboardGlass<S: Shape>(
        in shape: S,
        interactive: Bool = true,
        role: KeyboardChromeRole = .control
    ) -> some View {
        modifier(KeyboardGlassSurface(
            shape: shape,
            interactive: role == .board ? false : interactive,
            role: role
        ))
    }

    func letterKeyPlate(cornerRadius: CGFloat = VoiceOnlyKeyboardPolicy.keyCornerRadius) -> some View {
        modifier(LetterKeyPlateModifier(cornerRadius: cornerRadius))
    }

    func commandKeyPlate(cornerRadius: CGFloat = VoiceOnlyKeyboardPolicy.commandKeyCornerRadius) -> some View {
        keyboardGlass(
            in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous),
            interactive: false
        )
    }
}

struct CommandKeyFace: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let systemName: String?
    private let text: String?
    private let textWeight: Font.Weight
    private let symbolPointSize: CGFloat
    private let textPointSize: CGFloat
    private let plateWidth: CGFloat?
    private let plateHeight: CGFloat
    private let cornerRadius: CGFloat
    /// Press state published by the UIKit control that actually owns the touch.
    private let isPressed: Bool

    init(
        systemName: String,
        plateWidth: CGFloat? = nil,
        plateHeight: CGFloat,
        cornerRadius: CGFloat = VoiceOnlyKeyboardPolicy.commandKeyCornerRadius,
        symbolPointSize: CGFloat = 16,
        isPressed: Bool = false
    ) {
        self.systemName = systemName
        text = nil
        textWeight = .semibold
        self.symbolPointSize = symbolPointSize
        textPointSize = 14
        self.plateWidth = plateWidth
        self.plateHeight = plateHeight
        self.cornerRadius = cornerRadius
        self.isPressed = isPressed
    }

    init(
        text: String,
        plateWidth: CGFloat? = nil,
        plateHeight: CGFloat,
        cornerRadius: CGFloat = VoiceOnlyKeyboardPolicy.commandKeyCornerRadius,
        textPointSize: CGFloat = 14,
        textWeight: Font.Weight = .semibold,
        isPressed: Bool = false
    ) {
        systemName = nil
        self.text = text
        self.textWeight = textWeight
        symbolPointSize = 16
        self.textPointSize = textPointSize
        self.plateWidth = plateWidth
        self.plateHeight = plateHeight
        self.cornerRadius = cornerRadius
        self.isPressed = isPressed
    }

    var body: some View {
        Group {
            if let systemName {
                Image(systemName: systemName)
                    .font(.system(size: symbolPointSize, weight: .semibold))
            } else if let text {
                Text(text)
                    .font(.system(size: textPointSize, weight: textWeight))
            }
        }
        .foregroundStyle(.primary)
        .frame(
            minWidth: plateWidth,
            maxWidth: plateWidth ?? .infinity,
            minHeight: plateHeight,
            maxHeight: plateHeight
        )
        .commandKeyPlate(cornerRadius: cornerRadius)
        .scaleEffect(isPressed && !reduceMotion ? 0.94 : 1)
        .opacity(isPressed ? 0.72 : 1)
        .animation(
            reduceMotion ? nil : .easeOut(duration: isPressed ? 0.08 : 0.16),
            value: isPressed
        )
    }
}

private struct LetterKeyPlateModifier: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content.background {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.clear)
                .keyboardGlass(
                    in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous),
                    interactive: false
                )
                .opacity(KeyboardInteractionPreferences.keyContainersEnabled ? 1 : 0)
                .allowsHitTesting(false)
        }
    }
}
