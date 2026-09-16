// DictusKeyboard/Views/KeyVariantPopup.swift
import SwiftUI
import DictusCore

/// Native-style long-press bubble of alternate characters or emoji skin tones.
struct KeyVariantPopup: View {
    let options: [String]
    let selectedIndex: Int
    let isEmoji: Bool
    var onSelect: ((Int) -> Void)?

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                let label = Text(option)
                    .font(.system(size: isEmoji ? 28 : 20))
                    .frame(width: Self.cellWidth(isEmoji: isEmoji), height: Self.cellHeight(isEmoji: isEmoji))
                    .background {
                        if index == selectedIndex {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.accentColor.opacity(0.38))
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
            let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
            if KeyboardInteractionPreferences.liquidGlassEnabled {
                Color.clear
                    .keyboardGlass(in: shape, interactive: false)
            } else {
                shape
                    .fill(Color(uiColor: .tertiarySystemFill))
            }
        }
        // Selection changes arrive for every movement sample. Keep the popup
        // visually stable instead of animating/rebuilding during the drag.
        .transaction { transaction in
            transaction.animation = nil
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

/// Native-style press preview that sits above a key until release or a hold menu.
struct KeyPreviewPopup: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 28, weight: .regular))
            .frame(width: Self.width, height: Self.height)
            .background {
                let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
                if KeyboardInteractionPreferences.liquidGlassEnabled {
                    Color.clear
                        .keyboardGlass(in: shape, interactive: false)
                } else {
                    shape
                        .fill(Color(uiColor: .tertiarySystemFill))
                }
            }
            .transaction { transaction in
                transaction.animation = nil
            }
            .accessibilityHidden(true)
    }

    static let width: CGFloat = 44
    static let height: CGFloat = 56

    static func frame(for source: CGRect, in bounds: CGSize) -> CGRect {
        let size = CGSize(width: max(width, source.width + 6), height: height)
        var x = source.midX - size.width / 2
        x = min(max(4, x), max(4, bounds.width - size.width - 4))
        let y = source.minY - size.height - 4
        _ = bounds
        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }
}

struct KeyPreviewSession {
    let text: String
    let sourceFrame: CGRect
    let popupFrame: CGRect
}

/// Hosts either the balloon popup or the zoom-out popout for a pressed key.
struct KeyPressPreviewHost: View {
    @Binding var session: KeyPreviewSession?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let preview = session {
            previewView(preview)
                .frame(width: preview.popupFrame.width, height: preview.popupFrame.height)
                .position(x: preview.popupFrame.midX, y: preview.popupFrame.midY)
                .allowsHitTesting(false)
                .zIndex(20)
        }
    }

    @ViewBuilder
    private func previewView(_ preview: KeyPreviewSession) -> some View {
        switch KeyPopupMode.active {
        case .off:
            EmptyView()
        case .popup:
            KeyPreviewPopup(text: preview.text)
        case .popout:
            KeyPopoutPreview(
                text: preview.text,
                reduceMotion: reduceMotion
            )
            .onAppear {
                let token = preview.text
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.36) {
                    if session?.text == token {
                        session = nil
                    }
                }
            }
        }
    }

    static func frame(for source: CGRect, in bounds: CGSize) -> CGRect {
        switch KeyPopupMode.active {
        case .off:
            return .zero
        case .popup:
            return KeyPreviewPopup.frame(for: source, in: bounds)
        case .popout:
            return KeyPopoutPreview.frame(for: source, in: bounds)
        }
    }
}

/// Enlarges out of the pressed key and fades away.
struct KeyPopoutPreview: View {
    let text: String
    var reduceMotion: Bool = false
    @State private var expanded = false

    var body: some View {
        Text(text)
            .font(.system(size: 28, weight: .regular))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                let shape = RoundedRectangle(
                    cornerRadius: VoiceOnlyKeyboardPolicy.keyCornerRadius,
                    style: .continuous
                )
                if KeyboardInteractionPreferences.liquidGlassEnabled {
                    Color.clear
                        .keyboardGlass(in: shape, interactive: false)
                } else {
                    shape
                        .fill(Color(uiColor: .tertiarySystemFill))
                }
            }
            .scaleEffect(expanded && !reduceMotion ? 1.55 : 1)
            .opacity(expanded ? 0 : 1)
            .onAppear {
                withAnimation(.easeOut(duration: reduceMotion ? 0.12 : 0.32)) {
                    expanded = true
                }
            }
            .accessibilityHidden(true)
    }

    static func frame(for source: CGRect, in bounds: CGSize) -> CGRect {
        // Stay on the pressed key; scaleEffect enlarges out of that face.
        _ = bounds
        return source
    }
}
