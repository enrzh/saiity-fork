#if os(iOS)
// DictusCore/Sources/DictusCore/Design/DictusColors.swift
// Brand color system with hex initializer and light/dark mode support.
import SwiftUI

/// Shared sAiity color tokens. The dictus names remain as source-compatible API.
///
/// WHY Color(hex:) instead of Asset Catalog:
/// The app's .xcassets currently contains the legacy app icon, while this shared
/// color system is defined in code so it is also available to DictusCore clients
/// without duplicating color resources. Hex initializers provide exact brand colors.
/// Colors adapt to light/dark mode via the colorScheme-aware static properties.
///
/// WHY static computed properties returning adaptive colors:
/// SwiftUI re-evaluates computed properties when colorScheme changes, so the colors
/// automatically adapt to light/dark mode without manual observation.
public extension Color {
    // MARK: - Semantic Colors

    /// The app tint follows the user's system appearance and accessibility settings.
    static let dictusAccent = Color.accentColor

    /// Compatibility emphasis token backed by the system tint.
    static let dictusAccentHighlight = Color.accentColor

    /// Recording state uses the system semantic red.
    static let dictusRecording = Color(.systemRed)

    /// Success state uses the system semantic green.
    static let dictusSuccess = Color(.systemGreen)

    /// Smart mode uses the same system tint as other accent actions.
    static let dictusSmartMode = Color.accentColor

    // MARK: - Adaptive Colors (light/dark mode)

    /// System background that adapts to light/dark appearance.
    static var dictusBackground: Color { Color(.systemBackground) }

    /// System grouped surface that adapts to light/dark appearance.
    static var dictusSurface: Color { Color(.secondarySystemBackground) }

    // MARK: - Keyboard pill controls

    /// Icon tint for a secondary pill control in the keyboard area: the panel
    /// toggle and gear in `ToolbarView`, the cancel button in `RecordingOverlay`.
    ///
    /// WHY it is shared (#241): those pills sit in the same 52pt bar and swap
    /// places as the keyboard changes state, so a control that is black in one
    /// bar and grey in the next reads as two different systems. One token keeps
    /// them from drifting apart the next time either file is edited.
    ///
    static var dictusPillIconSecondary: Color { Color(.secondaryLabel) }

    // MARK: - Legacy color aliases

    /// Compatibility alias; intentionally solid to avoid introducing gradients.
    static let dictusGradientStart = Color.dictusAccent

    /// Compatibility alias; intentionally solid to avoid introducing gradients.
    static let dictusGradientEnd = Color.dictusAccent

    // MARK: - Hex Initializer

    /// Create a Color from a hex integer value (e.g., 0x3D7EFF).
    ///
    /// WHY UInt rather than String:
    /// Compile-time validation -- a typo in a hex literal causes a build error.
    /// String parsing would silently fail at runtime.
    init(hex: UInt, opacity: Double = 1.0) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: opacity
        )
    }

    /// Create an adaptive Color that switches between light and dark variants.
    ///
    /// WHY UIColor bridge:
    /// SwiftUI's Color doesn't have a built-in light/dark initializer on iOS 16.
    /// UIColor.init(dynamicProvider:) handles trait collection changes automatically,
    /// then we wrap it back in SwiftUI Color.
    init(light: Color, dark: Color) {
        #if canImport(UIKit)
        self.init(uiColor: UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? UIColor(dark)
                : UIColor(light)
        })
        #else
        self = dark
        #endif
    }
}
#endif
