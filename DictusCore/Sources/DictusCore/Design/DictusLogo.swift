#if os(iOS)
// DictusCore/Sources/DictusCore/Design/DictusLogo.swift
// Shared sAiity logo expression.
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

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
        Group {
            #if canImport(UIKit)
            if let appIcon = UIImage(named: "AppIcon-1024", in: .main, compatibleWith: nil) {
                Image(uiImage: appIcon)
                    .resizable()
                    .scaledToFit()
            } else {
                nativeMark
            }
            #else
            nativeMark
            #endif
        }
        .frame(width: height, height: height)
        .clipShape(RoundedRectangle(cornerRadius: height * 0.22))
        .accessibilityLabel("sAiity")
    }

    /// Resource-free mark for package and extension bundles without the app icon asset.
    private var nativeMark: some View {
        ZStack {
            RoundedRectangle(cornerRadius: height * 0.22)
                .fill(Color.dictusAccent)
            HStack(alignment: .center, spacing: height * 0.055) {
                ForEach([0.42, 0.68, 1.0, 0.68, 0.42], id: \.self) { scale in
                    Capsule()
                        .fill(Color.white)
                        .frame(width: height * 0.105, height: height * 0.62 * scale)
                }
            }
        }
    }
}
#endif
