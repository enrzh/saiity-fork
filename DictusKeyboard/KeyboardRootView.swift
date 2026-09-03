// DictusKeyboard/KeyboardRootView.swift
import SwiftUI
import DictusCore

/// Root SwiftUI view for the voice-only keyboard surface.
struct KeyboardRootView: View {
    let controllerID: String
    let routeText: (String) -> Void
    let routeCommand: (KeyboardCommand) -> Void
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
                surfaceHeight: Double(surfaceHeight),
                controlOrder: KeyboardAccessoryOrder.current
            )
            let surfaceFrame = layout.surfaceFrame
            let usesAuxiliarySurface = state.areaMode == .emoji || state.areaMode == .panel

            ZStack(alignment: .topLeading) {
                // Keep the hosting canvas transparent so the native UIInputView
                // backdrop is the only layer behind the inset surface.
                Color.clear
                    .allowsHitTesting(false)
                embeddedSurface(
                    areaSurface(layout: layout, contentFrame: surfaceFrame),
                    frame: surfaceFrame
                )
                    .position(x: surfaceFrame.midX, y: surfaceFrame.midY)
                if !usesAuxiliarySurface {
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
            .background(Color.clear)
            .onChange(of: state.areaMode) { _, mode in
                if mode == .panel {
                    symbolPage = .symbols1
                }
            }
        }
    }

    @ViewBuilder
    private func areaSurface(layout: VoiceOnlyKeyboardPolicy.Layout, contentFrame: CGRect) -> some View {
        let surfaceFrame = contentFrame
        let availableWidth = surfaceFrame.width
        switch state.areaMode {
        case .keys, .recording:
            centerSurface(layout: layout)
        case .emoji:
            EmojiPickerView(
                onEmojiInsert: { emoji in
                    routeText(emoji)
                },
                onBackToVoice: { state.closeArea() },
                onDelete: { routeProxyCommand(.delete) },
                availableWidth: availableWidth,
                availableHeight: surfaceFrame.height
            )
            .frame(width: surfaceFrame.width, height: surfaceFrame.height)
            .accessibilityIdentifier("emoji-picker-surface")
        case .panel:
            LiquidSymbolPageView(
                page: symbolPage,
                availableWidth: surfaceFrame.width,
                availableHeight: surfaceFrame.height,
                onInsert: { text in routeProxyText(text) },
                onDelete: { routeProxyCommand(.delete) },
                onReturn: { routeProxyCommand(.returnKey) },
                onTogglePage: { nextPage in symbolPage = nextPage },
                onClose: { state.closeArea() },
                onBackToVoice: { state.closeArea() },
                onEmoji: { state.presentArea(.emoji) },
            )
            .frame(width: surfaceFrame.width, height: surfaceFrame.height)
            .accessibilityIdentifier("number-layer-surface")
        }
    }

    private func routeProxyText(_ text: String) {
        routeText(text)
    }

    private func routeProxyCommand(_ command: KeyboardCommand) {
        routeCommand(command)
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
                let errorFrame = layout.dictationErrorFrame
            ZStack(alignment: .topLeading) {
                dictateButton(frame: dictateFrame)
                    .frame(width: dictateFrame.width, height: dictateFrame.height)
                    .position(x: dictateButtonLocalX(for: dictateFrame, in: layout),
                              y: CGFloat(dictateFrame.midY - layout.surfaceFrame.minY))
                if !layout.spaceFrame.isEmpty {
                    spaceBar(frame: layout.spaceFrame)
                        .position(
                            x: CGFloat(layout.spaceFrame.midX - layout.surfaceFrame.minX),
                            y: CGFloat(layout.spaceFrame.midY - layout.surfaceFrame.minY)
                        )
                }
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

    private func dictateButtonLocalX(for frame: CGRect, in layout: VoiceOnlyKeyboardPolicy.Layout) -> CGFloat {
        CGFloat(frame.midX - layout.surfaceFrame.minX)
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
        // Intentional white primary control: it is the strongest voice action on both themes;
        // its semantic black foreground keeps the label readable in light and dark mode.
        .background(Capsule().fill(Color.white))
        .clipShape(Capsule())
        .contentShape(Capsule())
        .foregroundStyle(.black)
        .accessibilityIdentifier("dictate-button")
        .accessibilityLabel("Hold to dictate")
        .accessibilityValue(dictationTitle)
        // UIKit overlay is the primary hit target. This gesture is the fallback
        // when the overlay frame misses the visible capsule.
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in state.handleMicPressBegan() }
                .onEnded { _ in state.handleMicPressEnded() }
        )
    }

    private func spaceBar(frame: CGRect) -> some View {
        appleControlSurface(
            Text("space")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: frame.width, height: CGFloat(VoiceOnlyKeyboardPolicy.utilityVisualSize)),
            in: Capsule()
        )
        .frame(width: frame.width, height: frame.height)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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
        .allowsHitTesting(false)
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
    @State private var symbolDragAxis: DragAxis?
    @State private var symbolCommitLocked = false
    @State private var variantSession: KeyVariantSession?

    private let rowSpacing: CGFloat = 6
    private let keySpacing: CGFloat = 5
    private let bottomBarHeight: CGFloat = 44
    private let edgeInset: CGFloat = CGFloat(VoiceOnlyKeyboardPolicy.visibleControlGap)
    // Match the spacing around the shared inset surface so symbol keys and
    // auxiliary controls land on the same visual grid as the voice page.
    private let horizontalInset: CGFloat = CGFloat(VoiceOnlyKeyboardPolicy.horizontalPadding)

    private enum DragAxis {
        case horizontal
        case vertical
    }

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: edgeInset)
            GeometryReader { proxy in
                let gridSize = CGSize(width: proxy.size.width, height: proxy.size.height)
                let frames = positionedKeys(in: gridSize)
                ZStack(alignment: .topLeading) {
                    ForEach(frames) { positionedKey in
                        symbolKey(
                            positionedKey.key,
                            isActive: activeKeyID == positionedKey.key.id,
                            frame: positionedKey.frame,
                            bounds: gridSize
                        )
                            .frame(width: positionedKey.frame.width, height: positionedKey.frame.height)
                            .position(x: positionedKey.frame.midX, y: positionedKey.frame.midY)
                    }
                    .frame(width: gridSize.width, height: gridSize.height)
                    if let session = variantSession {
                        variantOverlay(session, in: gridSize)
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
                .coordinateSpace(name: "symbolPage")
                .simultaneousGesture(symbolPointerGesture(frames: frames))
                .accessibilityElement(children: .contain)
            }
            AuxiliaryBottomBar(
                controlOrder: KeyboardAccessoryOrder.current,
                onEmoji: onEmoji,
                onVoice: onBackToVoice,
                onSpace: { onInsert(" ") },
                onDelete: onDelete,
                onReturn: onReturn
            )
            .frame(width: availableWidth, height: bottomBarHeight)
            Color.clear.frame(height: edgeInset)
        }
        .frame(width: availableWidth, height: availableHeight)
        .onChange(of: page) { _, _ in
            activeKeyID = nil
            variantSession = nil
        }
    }

    private var rows: [[LiquidSymbolKey]] {
        switch page {
        case .symbols2: return KeyboardSymbolsLayout.symbols.enumerated().map { rowIndex, row in
            row.enumerated().map { columnIndex, key in
                LiquidSymbolKey(id: "\(page)-\(rowIndex)-\(columnIndex)", key: key, page: page)
            }
        }
        case .symbols1: return KeyboardSymbolsLayout.numbers.enumerated().map { rowIndex, row in
            row.enumerated().map { columnIndex, key in
                LiquidSymbolKey(id: "\(page)-\(rowIndex)-\(columnIndex)", key: key, page: page)
            }
        }
        default: return []
    }
    }

    private func positionedKeys(in size: CGSize) -> [PositionedLiquidSymbolKey] {
        guard !rows.isEmpty else { return [] }
        let rowWeights = rows.map { row in row.map(\.width) }
        let frames = VoiceOnlyKeyboardPolicy.SymbolGrid.frames(
            for: rowWeights, in: size, spacing: keySpacing,
            inset: horizontalInset, rowSpacing: rowSpacing
        )
        return zip(rows, frames).flatMap { row, rowFrames in
            zip(row, rowFrames).map { PositionedLiquidSymbolKey(key: $0, frame: $1) }
        }
    }

    private func key(at point: CGPoint, in frames: [PositionedLiquidSymbolKey]) -> LiquidSymbolKey? {
        if let direct = frames.first(where: {
            $0.frame.contains(point) && !$0.key.isSpacer
        }) {
            return direct.key
        }
        return nil
    }

    @ViewBuilder
    private func symbolKey(_ key: LiquidSymbolKey, isActive: Bool, frame: CGRect, bounds: CGSize) -> some View {
        if key.isSpacer {
            Color.clear
                .accessibilityHidden(true)
        } else {
            let variants = insertVariants(for: key)
            Button { commitSymbolFromTap(key) } label: {
                ZStack {
                    if isActive {
                        symbolPointerHighlight
                    }
                    keyContent(key)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .buttonStyle(SymbolGlowButtonStyle(isActive: isActive, reduceMotion: reduceMotion))
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(key.accessibilityLabel)
            .accessibilityAddTraits(.isButton)
            .modifier(OptionalLongPressModifier(
                enabled: variants.count > 1,
                gesture: symbolVariantGesture(variants: variants, source: frame, bounds: bounds)
            ))
        }
    }

    private func insertVariants(for key: LiquidSymbolKey) -> [String] {
        guard case .insert(let value) = key.action else { return [] }
        return SymbolKeyVariants.options(for: value)
    }

    @ViewBuilder
    private func variantOverlay(_ session: KeyVariantSession, in _: CGSize) -> some View {
        KeyVariantPopup(
            options: session.options,
            selectedIndex: session.selectedIndex,
            isEmoji: session.isEmoji
        )
        .frame(width: session.popupFrame.width, height: session.popupFrame.height)
        .position(x: session.popupFrame.midX, y: session.popupFrame.midY)
        .allowsHitTesting(false)
    }

    private func symbolVariantGesture(variants: [String], source: CGRect, bounds: CGSize) -> some Gesture {
        LongPressGesture(minimumDuration: 0.4)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named("symbolPage")))
            .onChanged { value in
                guard case .second(true, let drag?) = value else { return }
                var session = variantSession
                if session == nil {
                    session = makeVariantSession(variants, source: source, in: bounds)
                    variantSession = session
                    symbolCommitLocked = true
                }
                guard var session else { return }
                let index = KeyVariantPopup.selectedIndex(
                    at: drag.location,
                    popupFrame: session.popupFrame,
                    optionCount: session.options.count
                )
                if session.selectedIndex != index {
                    session.selectedIndex = index
                    variantSession = session
                    HapticFeedback.keyTapped()
                }
            }
            .onEnded { _ in
                commitVariantSession()
            }
    }

    private func makeVariantSession(_ options: [String], source: CGRect, in bounds: CGSize) -> KeyVariantSession {
        HapticFeedback.keyTapped()
        let popupFrame = KeyVariantPopup.frame(
            for: source,
            optionCount: options.count,
            isEmoji: false,
            in: bounds
        )
        return KeyVariantSession(
            options: options,
            sourceFrame: source,
            popupFrame: popupFrame,
            isEmoji: false,
            selectedIndex: 0
        )
    }

    private func commitVariantSession() {
        guard let session = variantSession,
              session.options.indices.contains(session.selectedIndex) else {
            variantSession = nil
            resetSymbolGestureLock()
            return
        }
        onInsert(session.options[session.selectedIndex])
        variantSession = nil
        resetSymbolGestureLock()
    }

    private func symbolPointerGesture(frames: [PositionedLiquidSymbolKey]) -> some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .local)
            .onChanged { value in
                guard variantSession == nil else { return }
                if symbolDragAxis == nil {
                    symbolDragAxis = abs(value.translation.width) >= abs(value.translation.height)
                        ? .horizontal : .vertical
                }
                guard symbolDragAxis == .horizontal else { return }
                activeKeyID = key(at: value.location, in: frames)?.id
            }
            .onEnded { value in
                let shouldCommit = symbolDragAxis == .horizontal && !symbolCommitLocked && variantSession == nil
                symbolCommitLocked = true
                let key = key(at: value.location, in: frames)
                defer {
                    symbolDragAxis = nil
                    activeKeyID = nil
                    resetSymbolGestureLock()
                }
                guard shouldCommit, let key else { return }
                commit(key)
            }
    }

    private func commitSymbolFromTap(_ key: LiquidSymbolKey) {
        guard !symbolCommitLocked else { return }
        symbolCommitLocked = true
        commit(key)
        resetSymbolGestureLock()
    }

    private func resetSymbolGestureLock() {
        DispatchQueue.main.async {
            symbolCommitLocked = false
        }
    }

    private var symbolPointerHighlight: some View {
        RoundedRectangle(cornerRadius: 13, style: .continuous)
            .fill(Color.primary.opacity(0.12))
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(Color.primary.opacity(0.16), lineWidth: 1)
            }
            .padding(4)
            .allowsHitTesting(false)
    }

    @ViewBuilder
    private func keyContent(_ key: LiquidSymbolKey) -> some View {
        switch key.action {
        case .togglePage:
            Text(key.label)
                .font(.system(size: 14, weight: .medium))
        case .insert, .close:
            Text(key.label)
                .font(.system(size: 22, weight: .regular))
        }
    }

    private func commit(_ key: LiquidSymbolKey) {
        guard !key.isSpacer else { return }
        switch key.action {
        case .insert(let value): onInsert(value)
        case .togglePage:
            switch VoiceOnlyKeyboardPolicy.SymbolPageTransition.forToggle(
                from: page == .symbols1 ? .symbols1 : .symbols2
            ) {
            case .symbols1ToSymbols2:
                onTogglePage(.symbols2)
            case .symbols2ToSymbols1:
                onTogglePage(.symbols1)
            }
        case .close: onClose()
        }
    }
}

private struct LiquidSymbolKey: Identifiable {
    enum Action {
        case insert(String)
        case togglePage
        case close
    }

    let id: String
    let label: String
    let width: CGFloat
    let action: Action
    let isSpacer: Bool

    init(id: String, key: KeyboardSymbolsLayout.Key, page: KeyboardPage) {
        self.id = id
        self.width = CGFloat(key.width)
        switch key.kind {
        case .insert(let value):
            label = value
            action = .insert(value)
            isSpacer = false
        case .pageToggle:
            label = page == .symbols1 ? "#+=" : "123"
            action = .togglePage
            isSpacer = false
        case .emoji, .voice, .space, .delete, .returnKey, .spacer:
            label = ""
            action = .close
            isSpacer = true
        }
    }

    var accessibilityLabel: String {
        switch action {
        case .insert: return label
        case .togglePage: return label == "#+=" ? "More symbols" : "Return to numbers keyboard"
        case .close: return "Close"
        }
    }

    var isPageToggle: Bool {
        if case .togglePage = action { return true }
        return false
    }
}

private struct PositionedLiquidSymbolKey: Identifiable {
    let key: LiquidSymbolKey
    let frame: CGRect
    var id: String { key.id }
}

private struct OptionalLongPressModifier<G: Gesture>: ViewModifier {
    let enabled: Bool
    let gesture: G

    init(enabled: Bool, gesture: G) {
        self.enabled = enabled
        self.gesture = gesture
    }

    func body(content: Content) -> some View {
        if enabled {
            content.highPriorityGesture(gesture)
        } else {
            content
        }
    }
}

private struct SymbolGlowButtonStyle: ButtonStyle {
    let isActive: Bool
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed || isActive
        configuration.label
            .background {
                if pressed {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(Color.primary.opacity(0.12))
                        .overlay {
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .stroke(Color.primary.opacity(0.16), lineWidth: 1)
                        }
                        .padding(4)
                }
            }
            .scaleEffect(reduceMotion ? 1 : pressed ? 1.08 : 1)
            .animation(reduceMotion ? nil : .snappy(duration: 0.14), value: pressed)
    }
}
