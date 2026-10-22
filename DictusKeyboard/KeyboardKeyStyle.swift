import SwiftUI
import UIKit
import SyllivraKernel

/// Shared visual role of a keyboard face.
enum KeyboardChromeRole {
    case input
    case control
    case accessory
    case popup

    static var secondaryForeground: UIColor { .label.withAlphaComponent(0.72) }
    static let keyCornerRadius: CGFloat = 8
    static let commandCornerRadius: CGFloat = CommandKeyStyle.cornerRadius

    func solidFill(increasedContrast: Bool = false) -> UIColor {
        switch self {
        case .input, .control: return .tertiarySystemBackground
        case .accessory: return .clear
        case .popup: return .tertiarySystemBackground
        }
    }
}

/// The native primary control and its SwiftUI fallback share one state palette.
struct KeyboardDictationFaceStyle {
    let fill: UIColor
    let foreground: UIColor
    let symbolForeground: UIColor

    init(status: DictationStatus, finishing: Bool = false) {
        if status.isCancellationStage {
            fill = .systemRed
            foreground = .white
            symbolForeground = .white
        } else if status == .recording && !finishing {
            fill = .saiityAction
            foreground = .saiityOnAction
            symbolForeground = .saiityOnAction
        } else {
            fill = KeyboardChromeRole.control.solidFill()
            foreground = .label
            symbolForeground = .saiityAction
        }
    }
}

/// The shared opaque plate behind keys and popups. Input belongs to
/// `KeyboardKeyTouchControl`. Keys sit directly on the system keyboard backdrop,
/// like the system keyboard: there is no board slab and no glass.
struct KeyboardGlassSurface<S: Shape>: ViewModifier {
    let shape: S
    var role: KeyboardChromeRole = .control
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var accessibilityContrast: ColorSchemeContrast

    func body(content: Content) -> some View {
        // The plate is a background, never an input policy for its content.
        content.background {
            plate(Color.clear).allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func plate<Plate: View>(_ content: Plate) -> some View {
        if role == .accessory {
            content.allowsHitTesting(false)
        } else {
            content.background {
                shape.fill(solidFill)
                    .shadow(color: .black.opacity(role == .popup ? 0.2 : 0), radius: 2, y: 1)
                    .allowsHitTesting(false)
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
        role: KeyboardChromeRole = .control
    ) -> some View {
        modifier(KeyboardGlassSurface(shape: shape, role: role))
    }

    func letterKeyPlate(cornerRadius: CGFloat = VoiceOnlyKeyboardPolicy.keyCornerRadius) -> some View {
        modifier(LetterKeyPlateModifier(cornerRadius: cornerRadius))
    }

    func commandKeyPlate(cornerRadius: CGFloat = VoiceOnlyKeyboardPolicy.commandKeyCornerRadius) -> some View {
        keyboardGlass(in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
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
            let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            if accented { shape.fill(Color.saiityAction).allowsHitTesting(false) }
            else { Color.clear.keyboardGlass(in: shape, role: role) }
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
                    role: .input
                )
                .allowsHitTesting(false)
        }
    }
}
