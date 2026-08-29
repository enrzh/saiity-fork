#if os(iOS)
// DictusCore/Sources/DictusCore/Design/DictusColors.swift
// Brand color system with hex initializer and light/dark mode support.
import SwiftUI

/// Shared sAiity color tokens. The dictus names remain as source-compatible API.
///
/// WHY Color(hex:) instead of Asset Catalog:
/// The project has no .xcassets directory yet for DictusApp. Using hex initializers
/// provides exact brand colors from the brand kit without needing asset catalog setup.
/// Colors adapt to light/dark mode via the colorScheme-aware static properties.
///
/// WHY static computed properties returning adaptive colors:
/// SwiftUI re-evaluates computed properties when colorScheme changes, so the colors
/// automatically adapt to light/dark mode without manual observation.
public extension Color {
    // MARK: - Brand Colors (fixed, non-adaptive)

    /// Primary sAiity teal, matching the legacy app icon.
    static let dictusAccent = Color(hex: 0x16A6A8)

    /// Accessible teal highlight used for secondary emphasis.
    static let dictusAccentHighlight = Color(hex: 0x0B7F82)

    /// Recording state red (#EF4444)
    static let dictusRecording = Color(hex: 0xEF4444)

    /// Success state green (#22C55E)
    static let dictusSuccess = Color(hex: 0x22C55E)

    /// Smart mode uses the same restrained brand accent.
    static let dictusSmartMode = Color(hex: 0x0B7F82)

    // MARK: - Adaptive Colors (light/dark mode)

    /// System background with a stable dark counterpart.
    static var dictusBackground: Color {
        Color(light: Color(.systemBackground), dark: Color(hex: 0x101718))
    }

    /// System surface with a stable dark counterpart.
    static var dictusSurface: Color {
        Color(light: Color(.secondarySystemBackground), dark: Color(hex: 0x1B2324))
    }

    // MARK: - Keyboard pill controls

    /// Icon tint for a secondary pill control in the keyboard area: the panel
    /// toggle and gear in `ToolbarView`, the cancel button in `RecordingOverlay`.
    ///
    /// WHY it is shared (#241): those pills sit in the same 52pt bar and swap
    /// places as the keyboard changes state, so a control that is black in one
    /// bar and grey in the next reads as two different systems. One token keeps
    /// them from drifting apart the next time either file is edited.
    ///
    /// WHY 50% rather than full strength: the glass pill is the affordance; the
    /// glyph only labels it. Full-strength icons compete with the mic and the
    /// validate button, which are the primary actions in their respective bars.
    static var dictusPillIconSecondary: Color {
        Color(
            light: Color(white: 0.15).opacity(0.5),
            dark: Color.white.opacity(0.5)
        )
    }

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
