import SwiftUI
import UIKit
import DictusCore

/// Shared visual role used by both Solid and Liquid Glass keyboard faces.
enum KeyboardChromeRole {
    case input
    case control
    case board
    case accessory
    case popup

    static var secondaryForeground: UIColor { .label.withAlphaComponent(0.72) }
    static var keyCornerRadius: CGFloat { KeyboardInteractionPreferences.usesIOSStyling ? 5 : 8 }
    static var commandCornerRadius: CGFloat { KeyboardInteractionPreferences.usesIOSStyling ? 5 : 8 }

    func solidFill(increasedContrast: Bool = false) -> UIColor {
        let native = KeyboardInteractionPreferences.usesIOSStyling
        switch self {
        case .input:
            if increasedContrast { return .tertiarySystemBackground }
            return native ? UIColor { traits in
                traits.userInterfaceStyle == .dark ? UIColor.systemGray3.resolvedColor(with: traits) : .white
            } : UIColor.label.withAlphaComponent(0.035)
        case .accessory: return .clear
        case .control: return native ? .systemGray4 : increasedContrast ? .secondarySystemBackground : .clear
        case .board: return native ? .systemGray5 : .secondarySystemBackground
        case .popup: return .tertiarySystemBackground
        }
    }
}

private struct KeyboardLiquidGlassKey: EnvironmentKey {
    static var defaultValue: Bool { KeyboardInteractionPreferences.liquidGlassEnabled }
}

extension EnvironmentValues {
    var keyboardLiquidGlassEnabled: Bool {
        get { self[KeyboardLiquidGlassKey.self] }
        set { self[KeyboardLiquidGlassKey.self] = newValue }
    }
}

/// A visual-only material component. Input belongs to `KeyboardKeyTouchControl`.
struct KeyboardGlassSurface<S: Shape>: ViewModifier {
    let shape: S
    var interactive: Bool = true
    var role: KeyboardChromeRole = .control
    @Environment(\.keyboardLiquidGlassEnabled) private var liquidGlassEnabled
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var accessibilityContrast: ColorSchemeContrast

    func body(content: Content) -> some View {
        // Material is a background, never an input policy for its content.
        content.background {
            plate(Color.clear).allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func plate<Plate: View>(_ content: Plate) -> some View {
        if role == .accessory {
            content.allowsHitTesting(false)
        } else if !liquidGlassEnabled || (role != .board && role != .popup) {
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
                shape.fill(Color(uiColor: role.solidFill(increasedContrast: reduceTransparency || accessibilityContrast == .increased)))
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
        Color(uiColor: role.solidFill(increasedContrast: reduceTransparency || accessibilityContrast == .increased))
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
    private let accented: Bool
    private let role: KeyboardChromeRole

    init(
        systemName: String,
        plateWidth: CGFloat? = nil,
        plateHeight: CGFloat,
        cornerRadius: CGFloat = CommandKeyStyle.cornerRadius,
        symbolPointSize: CGFloat = CommandKeyStyle.glyphSize,
        isPressed: Bool = false,
        accented: Bool = false,
        role: KeyboardChromeRole = .control
    ) {
        self.systemName = systemName
        text = nil
        textWeight = .semibold
        self.symbolPointSize = symbolPointSize
        textPointSize = CommandKeyStyle.textSize
        self.plateWidth = plateWidth
        self.plateHeight = plateHeight
        self.cornerRadius = cornerRadius
        self.isPressed = isPressed
        self.accented = accented
        self.role = role
    }

    init(
        text: String,
        plateWidth: CGFloat? = nil,
        plateHeight: CGFloat,
        cornerRadius: CGFloat = VoiceOnlyKeyboardPolicy.commandKeyCornerRadius,
        textPointSize: CGFloat = CommandKeyStyle.textSize,
        textWeight: Font.Weight = .semibold,
        isPressed: Bool = false,
        accented: Bool = false,
        role: KeyboardChromeRole = .control
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
        self.accented = accented
        self.role = role
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
        .foregroundStyle(accented ? Color.saiityOnAction : Color.primary)
        .frame(
            minWidth: plateWidth,
            maxWidth: plateWidth ?? .infinity,
            minHeight: plateHeight,
            maxHeight: plateHeight
        )
        .background {
            let shape = RoundedRectangle(cornerRadius: KeyboardChromeRole.commandCornerRadius, style: .continuous)
            if accented { shape.fill(Color.saiityAction).allowsHitTesting(false) }
            else { Color.clear.keyboardGlass(in: shape, interactive: false, role: role) }
        }
        // The numbers come from the shared command-key treatment, which the UIKit
        // grid reads too. Hardcoding them here is how the two drifted apart.
        .scaleEffect(isPressed && !reduceMotion ? CommandKeyStyle.pressScale : 1)
        .opacity(isPressed ? CommandKeyStyle.pressOpacity : 1)
        .animation(
            reduceMotion
                ? nil
                : .easeOut(duration: isPressed ? CommandKeyStyle.pressDurationIn
                                                : CommandKeyStyle.pressDurationOut),
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
                    interactive: false,
                    role: .input
                )
                .opacity(KeyboardInteractionPreferences.keyContainersEnabled ? 1 : 0)
                .allowsHitTesting(false)
        }
    }
}
