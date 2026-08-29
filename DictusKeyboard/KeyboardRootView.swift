// DictusKeyboard/KeyboardRootView.swift
import SwiftUI
import DictusCore

/// Root SwiftUI view for the voice-only keyboard surface.
struct KeyboardRootView: View {
    let controllerID: String
    @ObservedObject private var state = KeyboardState.shared
    @State private var pressStarted = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        GeometryReader { _ in
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    languageIndicator
                    Spacer(minLength: 0)
                    utilityButton(
                        systemName: "globe",
                        accessibilityLabel: "Switch keyboard",
                        identifier: "switch-keyboard"
                    ) {
                        state.controller?.advanceToNextInputMode()
                    }
                }
                .padding(.vertical, CGFloat(VoiceOnlyKeyboardPolicy.leftRailVerticalPadding))
                .frame(width: CGFloat(VoiceOnlyKeyboardPolicy.controlSize))

                Spacer(minLength: 0)

                centerSurface

                Spacer(minLength: 0)

                VStack(spacing: CGFloat(VoiceOnlyKeyboardPolicy.railSpacing)) {
                    utilityButton(
                        systemName: "delete.backward",
                        accessibilityLabel: "Delete backward",
                        identifier: "delete-backward"
                    ) {
                        state.controller?.textDocumentProxy.deleteBackward()
                    }
                    utilityButton(
                        systemName: "return",
                        accessibilityLabel: "Insert return",
                        identifier: "return-key"
                    ) {
                        state.controller?.textDocumentProxy.insertText("\n")
                    }
                    utilityButton(
                        systemName: "at",
                        accessibilityLabel: "Insert at sign",
                        identifier: "at-key"
                    ) {
                        state.controller?.textDocumentProxy.insertText("@")
                    }
                    utilityButton(
                        systemName: "keyboard.chevron.compact.down",
                        accessibilityLabel: "Dismiss keyboard",
                        identifier: "dismiss-keyboard"
                    ) {
                        state.controller?.dismissKeyboard()
                    }
                }
                .padding(.vertical, CGFloat(VoiceOnlyKeyboardPolicy.verticalPadding))
                .frame(width: CGFloat(VoiceOnlyKeyboardPolicy.controlSize))
            }
            .padding(.horizontal, CGFloat(VoiceOnlyKeyboardPolicy.horizontalPadding))
            .frame(
                maxWidth: .infinity,
                minHeight: CGFloat(VoiceOnlyKeyboardPolicy.surfaceHeight),
                maxHeight: CGFloat(VoiceOnlyKeyboardPolicy.surfaceHeight)
            )
            // systemGray6 is the same semantic dark surface used by Apple's
            // keyboard. A solid base prevents the host app from bleeding through
            // the voice-only area while glass controls remain native and subtle.
            .background(Color(uiColor: .systemGray6))
        }
    }

    private var languageIndicator: some View {
        appleControlSurface(
            Text("AUTO")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 8)
                .frame(height: 24),
            in: Capsule()
        )
        .accessibilityLabel("Automatic transcription language")
    }

    private var centerSurface: some View {
        ZStack {
            dictateButton
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .top) {
            Text(dictationTitle)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.top, 42)
        }
        .overlay(alignment: .bottom) {
            if let statusMessage = state.statusMessage, !statusMessage.isEmpty {
                Text(statusMessage)
                    .font(.caption2)
                    .foregroundStyle(state.dictationStatus == .failed ? .red : .secondary)
                    .lineLimit(1)
                    .padding(.bottom, 8)
            }
        }
    }

    private var dictateButton: some View {
        appleControlSurface(
            Image(systemName: dictationSymbol)
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(dictationColor)
                .symbolEffect(.pulse, isActive: state.dictationStatus == .recording)
                .frame(
                    width: CGFloat(VoiceOnlyKeyboardPolicy.controlSize),
                    height: CGFloat(VoiceOnlyKeyboardPolicy.controlSize)
                ),
            in: Circle()
        )
        .scaleEffect(pressStarted ? 0.94 : 1)
        .animation(.easeOut(duration: 0.12), value: pressStarted)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !pressStarted else { return }
                    pressStarted = true
                    state.startRecording()
                }
                .onEnded { _ in
                    defer { pressStarted = false }
                    guard state.dictationStatus == .requested
                            || state.dictationStatus == .recording
                    else { return }
                    state.requestStop()
                }
        )
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
        case .failed: return "Try again"
        }
    }

    private var dictationSymbol: String {
        switch state.dictationStatus {
        case .recording: return "waveform"
        case .requested, .transcribing, .processing: return "ellipsis"
        case .failed: return "arrow.clockwise"
        case .idle, .ready: return "mic.fill"
        }
    }

    private var dictationColor: Color {
        switch state.dictationStatus {
        case .recording: return .blue
        case .failed: return .orange
        default: return .primary
        }
    }

    @ViewBuilder
    private func appleControlSurface<Content: View, S: Shape>(
        _ content: Content,
        in shape: S
    ) -> some View {
        if reduceTransparency {
            content
                .background(shape.fill(Color(uiColor: .systemGray5)))
                .overlay(shape.stroke(Color.white.opacity(0.10), lineWidth: 0.75))
        } else if #available(iOS 26, *) {
            content.glassEffect(.regular, in: shape)
        } else {
            content
                .background(shape.fill(Color(uiColor: .systemGray5)))
                .overlay(shape.stroke(Color.white.opacity(0.10), lineWidth: 0.75))
        }
    }

    private func utilityButton(
        systemName: String,
        accessibilityLabel: String,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            appleControlSurface(
                Image(systemName: systemName)
                    .font(.system(size: 16, weight: .semibold))
                    .frame(
                        width: CGFloat(VoiceOnlyKeyboardPolicy.controlSize),
                        height: CGFloat(VoiceOnlyKeyboardPolicy.controlSize)
                    ),
                in: Circle()
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier(identifier)
    }

}
