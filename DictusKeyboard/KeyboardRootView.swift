// DictusKeyboard/KeyboardRootView.swift
import SwiftUI
import DictusCore

/// Root SwiftUI view for the voice-only keyboard surface.
struct KeyboardRootView: View {
    let controllerID: String
    @ObservedObject private var state = KeyboardState.shared
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
            let contentFrame = usesAuxiliarySurface ? layout.alternateContentFrame : layout.micCenterArea
            let centerSurface = embeddedSurface(
                areaSurface(layout: layout, contentFrame: contentFrame, surfaceHeight: surfaceHeight),
                frame: surfaceFrame
            )

            ZStack(alignment: .topLeading) {
                centerSurface
                    .offset(x: surfaceFrame.minX, y: surfaceFrame.minY)

                if (state.areaMode == .keys || state.areaMode == .recording) && layout.showsLanguageIndicator {
                    languageIndicator
                        .position(x: CGFloat(layout.languageFrame.midX), y: CGFloat(layout.languageFrame.midY))
                }

                if layout.leftRailWidth > 0 {
                    if state.areaMode != .panel && state.areaMode != .emoji {
                        utilityGlyph(systemName: "at")
                            .position(x: CGFloat(layout.leftUtilityFrames.at.midX), y: CGFloat(layout.leftUtilityFrames.at.midY))
                        utilityGlyph(systemName: "face.smiling")
                            .position(x: CGFloat(layout.leftUtilityFrames.emoji.midX), y: CGFloat(layout.leftUtilityFrames.emoji.midY))
                    }
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
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity
            )
            .background {
                if reduceTransparency {
                    Color(uiColor: .secondarySystemFill)
                } else {
                    Color(uiColor: .secondarySystemBackground)
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
            EmojiPickerView(
                onEmojiInsert: { emoji in
                    guard let controller = state.controller as? KeyboardViewController else {
                        DictationErrorChannel.record("Keyboard input is unavailable. Please reopen the keyboard.", disposition: .requiresApp)
                        return
                    }
                    controller.routeProxyText(emoji)
                    state.closeArea()
                },
                availableWidth: availableWidth,
                availableHeight: contentFrame.height
            )
            .accessibilityIdentifier("emoji-picker-surface")
        case .panel:
            Color(uiColor: .systemBackground).accessibilityIdentifier("number-layer-surface")
        }
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
            dictateButton(frame: dictateFrame)
                .frame(
                    width: dictateFrame.width,
                    height: dictateFrame.height
                )
                .position(x: CGFloat(surfaceCenterX - layout.surfaceFrame.minX),
                          y: CGFloat(dictateFrame.midY - layout.surfaceFrame.minY))
                .frame(maxWidth: .infinity, minHeight: CGFloat(layout.surfaceFrame.height), maxHeight: CGFloat(layout.surfaceFrame.height))
        } else {
            Color.clear
        }
    }

    private func dictateButton(frame: CGRect) -> some View {
        VStack(spacing: 1) {
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
            if let statusMessage = state.statusMessage, !statusMessage.isEmpty {
                Text(statusMessage)
                    .font(.caption2)
                    .foregroundStyle(state.dictationStatus == .failed ? .red : .secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .foregroundStyle(.primary)
        .frame(width: frame.width, height: frame.height)
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
        case .failed: return state.failedRequiresApp ? "Open sAiity" : "Try again"
        }
    }

    private var dictationSymbol: String {
        switch state.dictationStatus {
        case .recording: return "waveform"
        case .requested, .transcribing, .processing: return "ellipsis"
        case .failed: return state.failedRequiresApp ? "arrow.up.forward.app" : "arrow.clockwise"
        case .idle, .ready: return "mic.fill"
        }
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
