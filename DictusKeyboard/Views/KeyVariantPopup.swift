// DictusKeyboard/Views/KeyVariantPopup.swift
import SwiftUI

/// Native-style long-press bubble of alternate characters or emoji skin tones.
struct KeyVariantPopup: View {
    let options: [String]
    let selectedIndex: Int
    let isEmoji: Bool
    var onSelect: ((Int) -> Void)? = nil

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                let label = Text(option)
                    .font(.system(size: isEmoji ? 28 : 20))
                    .frame(width: Self.cellWidth(isEmoji: isEmoji), height: Self.cellHeight(isEmoji: isEmoji))
                    .background {
                        if index == selectedIndex {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.primary.opacity(0.18))
                        }
                    }
                if let onSelect {
                    Button { onSelect(index) } label: { label }
                        .buttonStyle(.plain)
                } else {
                    label
                }
            }
        }
        .padding(6)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
                .shadow(color: Color.black.opacity(0.22), radius: 10, y: 4)
        }
        .accessibilityElement(children: .contain)
    }

    static func cellWidth(isEmoji: Bool) -> CGFloat { isEmoji ? 44 : 36 }
    static func cellHeight(isEmoji: Bool) -> CGFloat { isEmoji ? 44 : 36 }

    static func size(optionCount: Int, isEmoji: Bool) -> CGSize {
        CGSize(
            width: CGFloat(optionCount) * cellWidth(isEmoji: isEmoji) + 12,
            height: cellHeight(isEmoji: isEmoji) + 12
        )
    }

    static func selectedIndex(at location: CGPoint, popupFrame: CGRect, optionCount: Int) -> Int {
        guard optionCount > 0 else { return 0 }
        let inset = popupFrame.insetBy(dx: 6, dy: 0)
        let cell = max(1, inset.width / CGFloat(optionCount))
        let raw = Int(floor((location.x - inset.minX) / cell))
        return min(max(0, raw), optionCount - 1)
    }

    static func frame(for source: CGRect, optionCount: Int, isEmoji: Bool, in bounds: CGSize) -> CGRect {
        let size = self.size(optionCount: optionCount, isEmoji: isEmoji)
        var x = source.midX - size.width / 2
        x = min(max(6, x), max(6, bounds.width - size.width - 6))
        let above = source.minY - size.height - 4
        let y = above >= 4 ? above : min(max(4, source.minY), max(4, bounds.height - size.height - 4))
        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }
}

struct NamedFramePreference: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

struct KeyVariantSession {
    let options: [String]
    let sourceFrame: CGRect
    let popupFrame: CGRect
    let isEmoji: Bool
    var selectedIndex: Int
}
