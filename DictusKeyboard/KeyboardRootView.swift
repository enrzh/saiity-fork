// DictusKeyboard/KeyboardRootView.swift
import SwiftUI
import DictusCore

/// Root SwiftUI view for the voice-only keyboard surface.
struct KeyboardRootView: View {
    let controllerID: String
    @ObservedObject private var state = KeyboardState.shared
    @State private var symbolPage: KeyboardPage = .symbols1
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var accessibilityContrast: ColorSchemeContrast

    var body: some View {
        GeometryReader { proxy in
            let surfaceHeight = max(proxy.size.height, 1)
            let layout = VoiceOnlyKeyboardPolicy.layout(
                for: proxy.size.width,
                surfaceHeight: Double(surfaceHeight)
            )
            let usesAuxiliarySurface = state.areaMode == .emoji || state.areaMode == .panel
            let surfaceFrame = layout.surfaceFrame
            let contentFrame = usesAuxiliarySurface
                ? layout.auxiliaryContentFrame
                : layout.micCenterArea

            ZStack(alignment: .topLeading) {
                if usesAuxiliarySurface {
                    areaSurface(layout: layout, contentFrame: contentFrame, surfaceHeight: surfaceHeight)
                        .frame(width: proxy.size.width, height: surfaceHeight, alignment: .topLeading)
                } else {
                    embeddedSurface(
                        areaSurface(layout: layout, contentFrame: contentFrame, surfaceHeight: surfaceHeight),
                        frame: surfaceFrame
                    )
                        .offset(x: surfaceFrame.minX, y: surfaceFrame.minY)
                    if (state.areaMode == .keys || state.areaMode == .recording) && layout.showsLanguageIndicator {
                        languageIndicator
                            .position(x: CGFloat(layout.languageFrame.midX), y: CGFloat(layout.languageFrame.midY))
                    }

                    if layout.leftRailWidth > 0 {
                        utilityGlyph(systemName: "at")
                            .position(x: CGFloat(layout.leftUtilityFrames.at.midX), y: CGFloat(layout.leftUtilityFrames.at.midY))
                        utilityGlyph(systemName: "face.smiling")
                            .position(x: CGFloat(layout.leftUtilityFrames.emoji.midX), y: CGFloat(layout.leftUtilityFrames.emoji.midY))
                        utilityGlyph(text: state.areaMode.modeControlTitle)
                            .position(x: CGFloat(layout.leftUtilityFrames.number.midX), y: CGFloat(layout.leftUtilityFrames.number.midY))
                    }

                    if layout.rightRailWidth > 0 {
                        utilityGlyph(systemName: "delete.backward", width: VoiceOnlyKeyboardPolicy.actionHitSize.width, height: VoiceOnlyKeyboardPolicy.actionHitSize.height, visualWidth: 80, visualHeight: 36, visualCornerRadius: 18)
                            .position(x: CGFloat(layout.deleteFrame.midX), y: CGFloat(layout.deleteFrame.midY))
                        utilityGlyph(systemName: "return", width: VoiceOnlyKeyboardPolicy.actionHitSize.width, height: VoiceOnlyKeyboardPolicy.actionHitSize.height, visualWidth: 80, visualHeight: 36, visualCornerRadius: 18)
                            .position(x: CGFloat(layout.returnFrame.midX), y: CGFloat(layout.returnFrame.midY))

                        utilityGlyph(systemName: "keyboard.chevron.compact.down", width: VoiceOnlyKeyboardPolicy.actionHitSize.width, height: VoiceOnlyKeyboardPolicy.actionHitSize.height, usesInteractiveSurface: false)
                            .position(
                                x: CGFloat(layout.dismissFrame.midX),
                                y: CGFloat(layout.dismissFrame.midY)
                            )
                    }
                }
            }
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity
            )
            .onChange(of: state.areaMode) { _, mode in
                if mode == .panel {
                    symbolPage = .symbols1
                }
            }
        }
    }

    @ViewBuilder
    private func areaSurface(layout: VoiceOnlyKeyboardPolicy.Layout, contentFrame: CGRect, surfaceHeight: CGFloat) -> some View {
        let availableWidth = contentFrame.width
        switch state.areaMode {
        case .keys, .recording:
            centerSurface(layout: layout)
        case .emoji:
            VStack(spacing: 0) {
                Color.clear.frame(height: max(0, contentFrame.minY))
                EmojiPickerView(
                    onEmojiInsert: { emoji in
                        guard let controller = state.controller as? KeyboardViewController else {
                            DictationErrorChannel.record("Keyboard input is unavailable. Please reopen the keyboard.", disposition: .requiresApp)
                            return
                        }
                        controller.routeProxyText(emoji)
                        state.closeArea()
                    },
                    onBackToVoice: { state.closeArea() },
                    availableWidth: availableWidth,
                    availableHeight: contentFrame.height
                )
                .frame(width: contentFrame.width, height: contentFrame.height)
                .accessibilityIdentifier("emoji-picker-surface")
            }
            .frame(width: proxyWidth(layout), height: surfaceHeight, alignment: .top)
        case .panel:
            VStack(spacing: 0) {
                Color.clear.frame(height: max(0, contentFrame.minY))
                LiquidSymbolPageView(
                    page: symbolPage,
                    availableWidth: contentFrame.width,
                    availableHeight: contentFrame.height,
                    onInsert: { text in routeProxyText(text) },
                    onDelete: { routeProxyCommand(.delete) },
                    onReturn: { routeProxyCommand(.returnKey) },
                    onTogglePage: { nextPage in symbolPage = nextPage },
                    onClose: { state.closeArea() },
                    onBackToVoice: { state.closeArea() },
                    onEmoji: { state.presentArea(.emoji) },
                )
                .frame(width: contentFrame.width, height: contentFrame.height)
                .accessibilityIdentifier("number-layer-surface")
            }
            .frame(width: proxyWidth(layout), height: surfaceHeight, alignment: .top)
        }
    }

    private func routeProxyText(_ text: String) {
        guard let controller = state.controller as? KeyboardViewController else {
            DictationErrorChannel.record("Keyboard input is unavailable. Please reopen the keyboard.", disposition: .requiresApp)
            return
        }
        controller.routeProxyText(text)
    }

    private func routeProxyCommand(_ command: KeyboardCommand) {
        guard let controller = state.controller as? KeyboardViewController else {
            DictationErrorChannel.record("Keyboard input is unavailable. Please reopen the keyboard.", disposition: .requiresApp)
            return
        }
        controller.routeProxyCommand(command)
    }

    private func proxyWidth(_ layout: VoiceOnlyKeyboardPolicy.Layout) -> CGFloat {
        CGFloat(layout.surfaceWidth)
    }

    private var languageIndicator: some View {
        Menu {
            Menu {
                ForEach(state.translationTargets, id: \.self) { target in
                    let status = state.translationTargetStatus(target)
                    Button {
                        state.selectTranslation(target)
                    } label: {
                        Label(
                            state.translationTargetMenuLabel(target),
                            systemImage: state.selectedTranslationTarget == target
                                ? "checkmark"
                                : status == .supportedNeedsDownload ? "arrow.down.circle" : "character.bubble"
                        )
                    }
                    .accessibilityLabel(state.translationTargetAccessibilityLabel(target))
                }
            } label: {
                Text(state.selectedTranslationTarget.map(state.translationTargetMenuLabel) ?? "Translate")
            }
            .disabled(state.translationTargets.isEmpty)
        } label: {
            appleControlSurface(
                    Text(languageIndicatorTitle)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 8)
                    .frame(width: CGFloat(VoiceOnlyKeyboardPolicy.languageVisualWidth), height: CGFloat(VoiceOnlyKeyboardPolicy.utilityVisualSize)),
                in: Capsule()
            )
        }
        .tint(.primary)
        .frame(width: CGFloat(VoiceOnlyKeyboardPolicy.languageVisualWidth), height: CGFloat(VoiceOnlyKeyboardPolicy.controlSize))
        .accessibilityLabel("Translation language")
        .accessibilityValue(languageIndicatorTitle)
    }

    private var languageIndicatorTitle: String {
        if let target = state.selectedTranslationTarget {
            return "->\(target.shortCode)"
        }
        let code = state.asrCapability.displaySourceCode
        switch code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() {
        case "", "--", "UNKNOWN", "N/A", "NA", "NONE", "NULL", "UNAVAILABLE", "UNSUPPORTED", "AUTO":
            return "AUTO"
        default:
            return code
        }
    }

    @ViewBuilder
    private func centerSurface(layout: VoiceOnlyKeyboardPolicy.Layout) -> some View {
        if !layout.dictateFrame.isEmpty {
            let dictateFrame = layout.dictateFrame
            let surfaceCenterX = layout.surfaceFrame.midX
            let errorFrame = layout.dictationErrorFrame
            ZStack(alignment: .topLeading) {
                dictateButton(frame: dictateFrame)
                    .frame(width: dictateFrame.width, height: dictateFrame.height)
                    .position(x: CGFloat(surfaceCenterX - layout.surfaceFrame.minX),
                              y: CGFloat(dictateFrame.midY - layout.surfaceFrame.minY))
                if !dictationErrorMessage.isEmpty && !errorFrame.isEmpty {
                    Text(dictationErrorMessage)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .allowsTightening(true)
                        .frame(width: max(CGFloat.zero, errorFrame.width - 8), height: errorFrame.height)
                        .position(x: CGFloat(errorFrame.midX - layout.surfaceFrame.minX),
                                  y: CGFloat(errorFrame.midY - layout.surfaceFrame.minY))
                        .accessibilityIdentifier("dictation-error")
                }
            }
            .frame(maxWidth: .infinity, minHeight: CGFloat(layout.surfaceFrame.height), maxHeight: CGFloat(layout.surfaceFrame.height))
        } else {
            Color.clear
        }
    }

    private func dictateButton(frame: CGRect) -> some View {
        let capsuleHeight = frame.height
        return VStack(spacing: 1) {
            Image(systemName: dictationSymbol)
                .font(.system(size: 20, weight: .semibold))
                .symbolEffect(
                    .pulse,
                    isActive: state.dictationStatus == .recording && !reduceMotion
                )
            Text(dictationTitle)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .foregroundStyle(.primary)
        .frame(width: frame.width, height: capsuleHeight)
        .background(Capsule().fill(Color.white))
        .clipShape(Capsule())
        .contentShape(Capsule())
        .foregroundStyle(.black)
        .accessibilityHidden(true)
        .accessibilityIdentifier("dictate-button")
        .accessibilityLabel("Hold to dictate")
        .accessibilityValue(dictationTitle)
    }

    private var dictationTitle: String {
        switch state.dictationStatus {
        case .idle, .ready: return "Hold to dictate"
        case .requested: return "Getting ready..."
        case .recording: return "Listening..."
        case .transcribing: return "Transcribing..."
        case .processing: return "Cleaning up..."
        case .failed: return "Hold to dictate"
        }
    }

    private var dictationSymbol: String {
        switch state.dictationStatus {
        case .recording: return "waveform"
        case .requested, .transcribing, .processing: return "ellipsis"
        case .failed: return "mic.fill"
        case .idle, .ready: return "mic.fill"
        }
    }

    private var dictationErrorMessage: String {
        guard state.dictationStatus == .failed else { return "" }
        return state.statusMessage ?? "Dictation could not be completed."
    }

    private let surfaceCornerRadius: CGFloat = 24

    private func embeddedSurface<Content: View>(_ content: Content, frame: CGRect) -> some View {
        appleControlSurface(
            content.frame(width: frame.width, height: frame.height, alignment: .topLeading),
            in: RoundedRectangle(cornerRadius: surfaceCornerRadius, style: .continuous)
        )
        .clipShape(RoundedRectangle(cornerRadius: surfaceCornerRadius, style: .continuous))
        .frame(width: frame.width, height: frame.height)
    }

    @ViewBuilder
    private func appleControlSurface<Content: View, S: Shape>(
        _ content: Content,
        in shape: S
    ) -> some View {
        if reduceTransparency || accessibilityContrast == .increased {
            content
                .background(shape.fill(Color(uiColor: accessibilityContrast == .increased ? .systemFill : .secondarySystemFill)))
        } else if #available(iOS 26, *) {
            content.glassEffect(.regular.interactive(), in: shape)
        } else {
            content
                .background(shape.fill(.regularMaterial))
        }
    }

    private func utilityGlyph(
        systemName: String,
        width: Double = VoiceOnlyKeyboardPolicy.controlSize,
        height: Double = VoiceOnlyKeyboardPolicy.controlSize,
        visualSize: Double = VoiceOnlyKeyboardPolicy.utilityVisualSize,
        visualWidth: Double? = nil,
        visualHeight: Double? = nil,
        visualCornerRadius: Double? = nil,
        usesInteractiveSurface: Bool = true
    ) -> some View {
        Group {
            if usesInteractiveSurface {
                if let visualWidth, let visualHeight, let visualCornerRadius {
                    appleControlSurface(
                        Image(systemName: systemName)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.primary)
                            .frame(width: CGFloat(visualWidth), height: CGFloat(visualHeight)),
                        in: RoundedRectangle(cornerRadius: CGFloat(visualCornerRadius), style: .continuous)
                    )
                } else {
                    appleControlSurface(
                        Image(systemName: systemName)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.primary)
                            .frame(width: CGFloat(visualSize), height: CGFloat(visualSize)),
                        in: Circle()
                    )
                }
            } else {
                Image(systemName: systemName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: CGFloat(visualSize), height: CGFloat(visualSize))
            }
        }
        .frame(width: CGFloat(width), height: CGFloat(height))
        .accessibilityHidden(true)
    }

    private func utilityGlyph(text: String) -> some View {
        appleControlSurface(
            Text(text)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: CGFloat(VoiceOnlyKeyboardPolicy.utilityVisualSize), height: CGFloat(VoiceOnlyKeyboardPolicy.utilityVisualSize)),
            in: Circle()
        )
        .frame(width: CGFloat(VoiceOnlyKeyboardPolicy.controlSize), height: CGFloat(VoiceOnlyKeyboardPolicy.controlSize))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

}

private struct LiquidSymbolPageView: View {
    let page: KeyboardPage
    let availableWidth: CGFloat
    let availableHeight: CGFloat
    let onInsert: (String) -> Void
    let onDelete: () -> Void
    let onReturn: () -> Void
    let onTogglePage: (KeyboardPage) -> Void
    let onClose: () -> Void
    let onBackToVoice: () -> Void
    let onEmoji: () -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var accessibilityContrast: ColorSchemeContrast
    @State private var activeKeyID: String?

    private let rowSpacing: CGFloat = 6
    private let keySpacing: CGFloat = 5
    private let horizontalInset: CGFloat = 4

    var body: some View {
        GeometryReader { proxy in
            let frames = positionedKeys(in: proxy.size)
            ZStack(alignment: .topLeading) {
                ForEach(frames) { positionedKey in
                    symbolKey(positionedKey.key, isActive: activeKeyID == positionedKey.key.id)
                        .frame(width: positionedKey.frame.width, height: positionedKey.frame.height)
                        .position(x: positionedKey.frame.midX, y: positionedKey.frame.midY)
                }
                VStack(spacing: 4) {
                    symbolControl(page == .symbols1 ? "#+=" : "ABC") { onTogglePage(.symbols2) }
                    HStack(spacing: 4) {
                        symbolControl("face.smiling") { onEmoji() }
                        symbolControl("mic.fill", systemImage: true, action: onBackToVoice)
                    }
                }
                .padding(.leading, horizontalInset)
                .padding(.bottom, horizontalInset)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        let nextID = key(at: value.location, in: frames)?.id
                        if nextID != activeKeyID {
                            activeKeyID = nextID
                            HapticFeedback.keyTapped()
                        }
                    }
                    .onEnded { value in
                        if let key = key(at: value.location, in: frames) {
                            commit(key)
                        }
                        activeKeyID = nil
                    }
            )
            .accessibilityElement(children: .contain)
        }
        .frame(width: availableWidth, height: availableHeight)
        .clipped()
        .onChange(of: page) { _, _ in activeKeyID = nil }
    }

    private func symbolControl(_ label: String, systemImage: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                if systemImage { Image(systemName: label) } else { Text(label) }
            }
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(systemImage ? "Return to voice keyboard" : "Emoji")
        .keyboardGlassEffect()
    }

    private var rows: [[LiquidSymbolKey]] {
        let layout = KeyboardLayouts.current().currentDeviceLayout
        let definitions: [[KeyDefinition]]
        switch page {
        case .symbols2:
            definitions = layout?.symbols2 ?? []
        default:
            definitions = layout?.symbols1 ?? []
        }

        return definitions.enumerated().map { rowIndex, row in
            row.enumerated().map { columnIndex, definition in
                LiquidSymbolKey(
                    id: "\(page)-\(rowIndex)-\(columnIndex)",
                    definition: definition,
                    page: page
                )
            }
        }
    }

    private func positionedKeys(in size: CGSize) -> [PositionedLiquidSymbolKey] {
        guard !rows.isEmpty else { return [] }
        let frames = VoiceOnlyKeyboardPolicy.SymbolGrid.frames(
            for: rows.map { $0.map(\.width) }, in: size, spacing: keySpacing,
            inset: horizontalInset, rowSpacing: rowSpacing
        )
        return zip(rows, frames).flatMap { row, rowFrames in
            zip(row, rowFrames).map { PositionedLiquidSymbolKey(key: $0, frame: $1) }
        }
    }

    private func key(at point: CGPoint, in frames: [PositionedLiquidSymbolKey]) -> LiquidSymbolKey? {
        if let direct = frames.first(where: { $0.frame.contains(point) && !$0.key.isSpacer }) {
            return direct.key
        }
        return nil
    }

    @ViewBuilder
    private func symbolKey(_ key: LiquidSymbolKey, isActive: Bool) -> some View {
        if key.isSpacer {
            Color.clear
                .accessibilityHidden(true)
        } else {
            keyContent(key)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background {
                    let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
                    if reduceTransparency || accessibilityContrast == .increased {
                        shape.fill(Color(uiColor: accessibilityContrast == .increased ? .systemFill : .secondarySystemFill))
                    } else if #available(iOS 26, *) {
                        shape.fill(.clear).glassEffect(.regular.interactive(), in: shape)
                    } else {
                        shape.fill(.regularMaterial)
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(isActive ? Color.primary.opacity(0.24) : .clear, lineWidth: 1)
                }
                .scaleEffect(isActive ? 1.035 : 1)
                .animation(reduceMotion ? nil : .snappy(duration: 0.14), value: isActive)
                .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(key.accessibilityLabel)
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { commit(key) }
        }
    }

    @ViewBuilder
    private func keyContent(_ key: LiquidSymbolKey) -> some View {
        switch key.action {
        case .delete:
            Image(systemName: "delete.backward")
                .font(.system(size: 18, weight: .semibold))
        case .togglePage:
            Text(key.label)
                .font(.system(size: 14, weight: .medium))
        case .insert, .returnKey, .close:
            Text(key.label)
                .font(.system(size: 22, weight: .regular))
        }
    }

    private func commit(_ key: LiquidSymbolKey) {
        guard !key.isSpacer else { return }
        switch key.action {
        case .insert(let value): onInsert(value)
        case .delete: onDelete()
        case .returnKey: onReturn()
        case .togglePage:
            switch VoiceOnlyKeyboardPolicy.SymbolPageTransition.forToggle(
                from: page == .symbols1 ? .symbols1 : .symbols2
            ) {
            case .symbols1ToSymbols2:
                onTogglePage(.symbols2)
            case .symbols2ToClose:
                onClose()
            }
        case .close: onClose()
        }
    }
}

private struct LiquidSymbolKey: Identifiable {
    enum Action {
        case insert(String)
        case delete
        case returnKey
        case togglePage
        case close
    }

    let id: String
    let label: String
    let width: CGFloat
    let action: Action
    let isSpacer: Bool

    init(id: String, definition: KeyDefinition, page: KeyboardPage) {
        self.id = id
        self.width = definition.size.width
        switch definition.type {
        case .input(let value, _):
            label = value
            action = .insert(value)
            isSpacer = false
        case .backspace:
            label = "Delete"
            action = .delete
            isSpacer = false
        case .returnkey:
            label = "Return"
            action = .returnKey
            isSpacer = false
        case .shiftSymbols:
            label = page == .symbols1 ? "#+=" : "ABC"
            action = .togglePage
            isSpacer = false
        case .symbols:
            label = "123"
            action = .togglePage
            isSpacer = false
        case .spacer:
            label = ""
            action = .close
            isSpacer = true
        default:
            label = ""
            action = .close
            isSpacer = true
        }
    }

    var accessibilityLabel: String {
        switch action {
        case .insert: return label
        case .delete: return "Delete backward"
        case .returnKey: return "Return"
        case .togglePage: return label == "#+=" ? "More symbols" : "Return to voice keyboard"
        case .close: return "Close"
        }
    }
}

private struct PositionedLiquidSymbolKey: Identifiable {
    let key: LiquidSymbolKey
    let frame: CGRect
    var id: String { key.id }
}
