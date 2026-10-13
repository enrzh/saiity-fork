#if os(iOS)
// SyllivraKernel/Sources/SyllivraKernel/Design/DictusTypography.swift
// Typography system using the platform's default SF Pro text styles.
import SwiftUI

/// Typography scale for Dictus.
///
/// WHY system text styles instead of fixed sizes:
/// System text styles (`.title`, `.body`, `.caption`) automatically scale with
/// Dynamic Type -- Apple's accessibility feature that lets users set their preferred
/// text size. Using these styles means Dictus respects the user's accessibility
/// preferences without any extra code.
///
public extension Font {
    /// Large heading using the default platform text face.
    static let dictusHeading: Font = .system(.title, weight: .bold)

    /// Section subheading using the default platform text face.
    static let dictusSubheading: Font = .system(.title3, weight: .semibold)

    /// Body text -- SF Pro Text (system default)
    static let dictusBody: Font = .system(.body)

    /// Caption text -- SF Pro Text small
    static let dictusCaption: Font = .system(.caption)
}
#endif
