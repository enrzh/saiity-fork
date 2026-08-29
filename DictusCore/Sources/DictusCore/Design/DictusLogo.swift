#if os(iOS)
// DictusCore/Sources/DictusCore/Design/DictusLogo.swift
// Shared sAiity logo expression.
import SwiftUI

/// Uses the real legacy sAiity app icon asset when hosted by the app bundle.
///
/// This preserves the existing type and initializer while keeping branding in one asset.
public struct DictusLogo: View {
    /// Overall height of the tallest bar (center).
    public var height: CGFloat = 80

    public init(height: CGFloat = 80) {
        self.height = height
    }

    public var body: some View {
        Image("AppIcon-1024")
            .resizable()
            .scaledToFit()
            .frame(width: height, height: height)
            .clipShape(RoundedRectangle(cornerRadius: height * 0.22))
            .accessibilityLabel("sAiity")
    }
}
#endif
