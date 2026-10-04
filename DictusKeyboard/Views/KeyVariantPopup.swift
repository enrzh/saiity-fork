// DictusKeyboard/Views/KeyVariantPopup.swift
import SwiftUI
import DictusCore

/// Native-style long-press bubble of alternate characters or emoji skin tones.
struct KeyVariantPopup: View {
    let options: [String]
    let selectedIndex: Int
    let isEmoji: Bool
    var cornerRadius: CGFloat = VoiceOnlyKeyboardPolicy.keyCornerRadius
    var onSelect: ((Int) -> Void)?
    var liquidGlassEnabled = KeyboardInteractionPreferences.liquidGlassEnabled

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                let label = Text(option)
                    .font(.system(size: isEmoji ? 28 : 20, weight: .regular))
                    .frame(width: Self.cellWidth(isEmoji: isEmoji), height: Self.cellHeight(isEmoji: isEmoji))
                    .background {
                        if index == selectedIndex {
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .fill(Color.primary.opacity(0.12))
                                .overlay {
                                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                        .stroke(Color.primary.opacity(0.16), lineWidth: 1)
                                }
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
        .keyboardGlass(
            in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous),
            interactive: false,
            role: .popup
        )
        // Selection changes arrive for every movement sample. Keep the popup
        // visually stable instead of animating/rebuilding during the drag.
        .transaction { transaction in
            transaction.animation = nil
        }
        .accessibilityElement(children: .contain)
        .environment(\.keyboardLiquidGlassEnabled, liquidGlassEnabled)
        .ignoresSafeArea()
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

    static func frame(
        for source: CGRect,
        optionCount: Int,
        isEmoji: Bool,
        in bounds: CGSize,
        topOverflow: CGFloat = 0
    ) -> CGRect {
        let size = self.size(optionCount: optionCount, isEmoji: isEmoji)
        var x = source.midX - size.width / 2
        x = min(max(6, x), max(6, bounds.width - size.width - 6))
        let topBoundary = -max(0, topOverflow)
        let bottomBoundary = max(topBoundary, bounds.height - size.height - 4)
        let y = min(max(topBoundary, source.minY - size.height - 4), bottomBoundary)
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
    var cornerRadius: CGFloat = VoiceOnlyKeyboardPolicy.keyCornerRadius

    var body: some View {
        Text(text)
            .font(.system(size: 28, weight: .regular))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .keyboardGlass(
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous),
                interactive: false,
                role: .popup
            )
            .transaction { transaction in
                transaction.animation = nil
            }
            .accessibilityHidden(true)
    }

    static let width: CGFloat = 44
    static let height: CGFloat = 56

    static func frame(for source: CGRect, in bounds: CGSize, topOverflow: CGFloat = 0) -> CGRect {
        let size = CGSize(width: min(max(width, source.width + 6), max(1, bounds.width - 8)),
                          height: min(height, max(32, source.height * 1.3), max(1, bounds.height - 8)))
        var x = source.midX - size.width / 2
        x = min(max(4, x), max(4, bounds.width - size.width - 4))
        let topBoundary = -max(0, topOverflow)
        let bottomBoundary = max(topBoundary, bounds.height - size.height - 4)
        let y = min(max(topBoundary, source.minY - size.height - 4), bottomBoundary)
        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }
}

struct KeyPreviewSession {
    let text: String
    let sourceFrame: CGRect
    let popupFrame: CGRect
    var cornerRadius: CGFloat = VoiceOnlyKeyboardPolicy.keyCornerRadius
    /// Which key owns this popup. There is one popup, so with two fingers the
    /// first press keeps it and later presses do not steal it; only the owner
    /// may dismiss it.
    var ownerKeyID: String?
}

/// Hosts either the balloon popup or the zoom-out popout for a pressed key.
struct KeyPressPreviewHost: View {
    @Binding var session: KeyPreviewSession?
    var identity: UUID?
    var liquidGlassEnabled = KeyboardInteractionPreferences.liquidGlassEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let preview = session {
                previewView(preview)
                    .id(identity)
                    .frame(width: preview.popupFrame.width, height: preview.popupFrame.height)
                    .position(x: preview.popupFrame.midX, y: preview.popupFrame.midY)
                    .allowsHitTesting(false)
                    .environment(\.keyboardLiquidGlassEnabled, liquidGlassEnabled)
                    .zIndex(20)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .ignoresSafeArea()
    }

    @ViewBuilder
    private func previewView(_ preview: KeyPreviewSession) -> some View {
        switch KeyPopupMode.active {
        case .off, .flash:
            EmptyView()
        case .popup:
            KeyPreviewPopup(text: preview.text, cornerRadius: preview.cornerRadius)
        case .popout:
            KeyPopoutPreview(
                text: preview.text,
                cornerRadius: preview.cornerRadius,
                reduceMotion: reduceMotion,
                sourceScale: CGSize(width: preview.sourceFrame.width / max(1, preview.popupFrame.width),
                                    height: preview.sourceFrame.height / max(1, preview.popupFrame.height)),
                anchor: UnitPoint(x: (preview.sourceFrame.midX - preview.popupFrame.minX) / max(1, preview.popupFrame.width),
                                  y: (preview.sourceFrame.midY - preview.popupFrame.minY) / max(1, preview.popupFrame.height))
            )
        }
    }

    static func frame(for source: CGRect, in bounds: CGSize, topOverflow: CGFloat = 0) -> CGRect {
        switch KeyPopupMode.active {
        case .off, .flash:
            return .zero
        case .popup:
            return KeyPreviewPopup.frame(for: source, in: bounds, topOverflow: topOverflow)
        case .popout:
            return KeyPopoutPreview.frame(for: source, in: bounds, topOverflow: topOverflow)
        }
    }
}

/// Enlarges out of the pressed key and fades away.
struct KeyPopoutPreview: View {
    let text: String
    var cornerRadius: CGFloat = VoiceOnlyKeyboardPolicy.keyCornerRadius
    var reduceMotion: Bool = false
    var sourceScale = CGSize(width: 1 / expansionScale, height: 1 / expansionScale)
    var anchor = UnitPoint.center
    @State private var expanded = false

    static let expansionScale: CGFloat = 1.55

    var body: some View {
        Text(text)
            .font(.system(size: 28, weight: .regular))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .keyboardGlass(
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous),
                interactive: false,
                role: .popup
            )
            // The host reserves the expanded bounds. Start at the pressed-key
            // size inside that frame, then grow to the frame itself so the
            // transform cannot escape and be clipped by the keyboard canvas.
            .scaleEffect(expanded || reduceMotion ? CGSize(width: 1, height: 1) : sourceScale, anchor: anchor)
            .opacity(1)
            .onAppear {
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.12)) {
                    expanded = true
                }
            }
            .accessibilityHidden(true)
    }

    static func frame(for source: CGRect, in bounds: CGSize, topOverflow: CGFloat = 0) -> CGRect {
        let expandedWidth = min(source.width * expansionScale, max(1, bounds.width - 8))
        let expandedHeight = min(source.height * expansionScale, max(1, bounds.height - 8))
        let size = CGSize(width: expandedWidth, height: expandedHeight)
        var x = source.midX - size.width / 2
        var y = source.midY - size.height / 2
        x = min(max(4, x), max(4, bounds.width - size.width - 4))
        let topBoundary = -max(0, topOverflow)
        let bottomBoundary = max(topBoundary, bounds.height - size.height - 4)
        y = min(max(topBoundary, y), bottomBoundary)
        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }
}
