#if os(iOS)
import SwiftUI

/// Shared app action geometry; the keyboard keeps its own resolved hit frames.
public struct SaiityPrimaryActionStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Color.saiityOnAction)
            .padding(.horizontal, 20).padding(.vertical, 16)
            .frame(maxWidth: .infinity, minHeight: 58)
            .background(Color.saiityAction, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.45)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
    }
}

public struct SaiityVoiceActionLabel: View {
    public let title: LocalizedStringKey
    public var systemImage: String?

    public init(_ title: LocalizedStringKey, systemImage: String? = nil) {
        self.title = title
        self.systemImage = systemImage
    }

    public var body: some View {
        HStack(spacing: 10) {
            if let systemImage { Image(systemName: systemImage).accessibilityHidden(true) }
            else { DictusLogo(height: 22, foregroundOnly: true, tint: .saiityOnAction).accessibilityHidden(true) }
            Text(title).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity)
    }
}

/// Real input energy changes only the passive mark, never the action's frame.
public struct SaiityVoiceSignal: View {
    public var level: Float?
    public var height: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(level: Float? = nil, height: CGFloat = 28) {
        self.level = level
        self.height = height
    }

    private var scale: CGFloat {
        guard let level, level.isFinite, !reduceMotion else { return 1 }
        return 0.75 + CGFloat(min(1, max(0, level))) * 0.25
    }

    public var body: some View {
        DictusLogo(height: height, foregroundOnly: true)
            .scaleEffect(x: 1, y: scale)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: scale)
            .accessibilityHidden(true)
    }
}
#endif
