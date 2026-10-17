#if os(iOS)
import SwiftUI

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
