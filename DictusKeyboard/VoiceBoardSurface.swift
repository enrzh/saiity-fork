import SwiftUI
import UIKit
import Foundation
import DictusCore

extension KeyboardRootView {
    @ViewBuilder
    func centerSurface(layout: VoiceOnlyKeyboardPolicy.Layout) -> some View {
        if !layout.dictateFrame.isEmpty {
            let dictateFrame = layout.dictateFrame
            let errorFrame = layout.dictationErrorFrame
            ZStack(alignment: .topLeading) {
                primaryBoardControl(frame: dictateFrame)
                    .frame(width: dictateFrame.width, height: dictateFrame.height)
                    .position(x: dictateButtonLocalX(for: dictateFrame, in: layout),
                              y: CGFloat(dictateFrame.midY - layout.surfaceFrame.minY))
                    .allowsHitTesting(!voiceBoardUsesUIKitHits)
                    .accessibilityHidden(voiceBoardUsesUIKitHits)
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
            Color.clear.allowsHitTesting(false)
        }
    }

    private func dictateButtonLocalX(for frame: CGRect, in layout: VoiceOnlyKeyboardPolicy.Layout) -> CGFloat {
        CGFloat(frame.midX - layout.surfaceFrame.minX)
    }

    /// The board's primary slot holds exactly one control.
    ///
    /// Opening sAiity and dictating are different verbs, so they are different
    /// controls rather than one button that changes its mind. Only one is ever
    /// mounted, which keeps a single hit owner per slot and removes the
    /// label/action disagreement this used to hide. `showsRecoveryAction` is the
    /// only gate, so the two can never disagree about what is on screen.
    @ViewBuilder
    private func primaryBoardControl(frame: CGRect) -> some View {
        if state.showsRecoveryAction {
            recoveryButton(frame: frame)
        } else {
            dictateButton(frame: frame)
        }
    }

    /// Independent control for the app handoff. It has one job and no session
    /// state to interpret, so a press always does the thing its label says.
    private func recoveryButton(frame: CGRect) -> some View {
        ZStack {
            recoveryControlVisual(frame: frame)
                .allowsHitTesting(false)
            ImmediateKeyButton(
                onTouchDown: { state.openDictusForRecovery() },
                onTouchUp: {},
                highlightCornerRadius: frame.height / 2,
                highlightSize: frame.size
            )
            .frame(width: frame.width, height: frame.height)
        }
        .frame(width: frame.width, height: frame.height)
        .contentShape(Capsule())
        .accessibilityLabel(state.primaryBoardActionLabel)
        .accessibilityHint("Opens sAiity so dictation can be prepared.")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("open-saiity-button")
    }

    /// Dictation only. It no longer inspects `appNeedsAppAction`, so a press can
    /// only ever mean "dictate" or "cancel" — never a silent app handoff.
    private func dictateButton(frame: CGRect) -> some View {
        let isCancellationStage = state.dictationStatus.isCancellationStage
        return ZStack {
            dictationControlVisual(frame: frame)
                .allowsHitTesting(false)
            ImmediateKeyButton(
                onTouchDown: {
                    if isCancellationStage {
                        state.cancelActiveDictation()
                    }
                },
                onTouchUp: {
                    guard !isCancellationStage else { return }
                    state.handleMicPressEnded()
                },
                highlightCornerRadius: frame.height / 2,
                highlightSize: frame.size,
                holdDuration: isCancellationStage
                    ? nil
                    : KeyboardDeletion.dictationHoldRecognitionDuration,
                onHold: isCancellationStage
                    ? nil
                    : { state.handleMicPressBegan() }
            )
            .frame(width: frame.width, height: frame.height)
        }
        .frame(width: frame.width, height: frame.height)
        .contentShape(Capsule())
        .accessibilityLabel(state.primaryBoardActionLabel)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("dictate-button")
    }

    private func dictationControlVisual(frame: CGRect) -> some View {
        boardCapsuleVisual(
            frame: frame,
            title: dictationTitle,
            symbol: dictationSymbol,
            background: dictationButtonBackground,
            foreground: dictationButtonForeground,
            liveWave: state.dictationStatus == .recording && !state.isFinishingRecording
        )
        .accessibilityIdentifier("dictate-button")
        .accessibilityLabel(state.primaryBoardActionLabel)
        .accessibilityValue(dictationTitle)
    }

    private var dictationButtonIsCancellation: Bool {
        state.dictationStatus.isCancellationStage
    }

    private var dictationButtonBackground: Color {
        dictationButtonIsCancellation ? .dictusRecording : .white
    }

    private var dictationButtonForeground: Color {
        dictationButtonIsCancellation ? .white : .black
    }

    /// Shared capsule chrome for the board's primary slot, so the recovery and
    /// dictation controls cannot drift apart visually.
    private func boardCapsuleVisual(
        frame: CGRect,
        title: String,
        symbol: String,
        background: Color,
        foreground: Color,
        liveWave: Bool = false
    ) -> some View {
        ZStack(alignment: .center) {
            VStack(spacing: 1) {
                if liveWave {
                    ListeningWaveIcon(color: foreground)
                } else {
                    Image(systemName: symbol)
                        .font(.system(size: 20, weight: .semibold))
                }
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .padding(.horizontal, 8)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: frame.width, height: frame.height)
        .background {
            ZStack {
                if KeyboardInteractionPreferences.liquidGlassEnabled {
                    appleControlSurface(Color.clear, in: Capsule(), role: .control)
                    Capsule().fill(background.opacity(dictationButtonIsCancellation ? 0.94 : 0.86))
                } else {
                    Capsule().fill(background)
                        .allowsHitTesting(false)
                }
            }
            .allowsHitTesting(false)
        }
        .clipShape(Capsule())
        .contentShape(Capsule())
        .foregroundStyle(foreground)
    }

    private func recoveryControlVisual(frame: CGRect) -> some View {
        boardCapsuleVisual(
            frame: frame,
            title: recoveryTitle,
            symbol: state.isOpeningForDictation ? "ellipsis" : "arrow.up.right.square.fill",
            background: .white,
            foreground: .black
        )
        .accessibilityIdentifier("open-saiity-button")
        .accessibilityLabel(state.primaryBoardActionLabel)
        .accessibilityValue(recoveryTitle)
    }

    /// The handoff acknowledges the press immediately, before iOS finishes
    /// switching away, so the control never looks inert while it works.
    private var recoveryTitle: String {
        if state.isOpeningForDictation { return "Opening sAiity…" }
        if state.dictationStatus == .failed, state.statusMessage != nil { return "Try again" }
        return "Open sAiity"
    }

    private func spaceBar(frame: CGRect) -> some View {
        ZStack {
            appleControlSurface(
                Text("space")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: frame.width, height: CGFloat(VoiceOnlyKeyboardPolicy.utilityVisualSize)),
                in: Capsule()
            )
            if !voiceBoardUsesUIKitHits {
                SpaceBarControl(
                    onTap: { routeProxyCommand(.space) },
                    onCursorBegan: {},
                    onCursorMoved: routeCursorMovement,
                    onCursorEnded: routeCursorEnded
                )
            }
        }
        .frame(width: frame.width, height: frame.height)
        .allowsHitTesting(!voiceBoardUsesUIKitHits)
        .accessibilityHidden(voiceBoardUsesUIKitHits)
    }

    /// Dictation's own copy. The app-handoff wording moved to the recovery
    /// control, so nothing here can promise one action and perform another.
    private var dictationTitle: String {
        switch state.dictationStatus {
        case .idle, .ready: return "Hold to dictate"
        case .requested: return "Getting ready..."
        case .recording: return state.isFinishingRecording ? "Finishing..." : "Listening..."
        case .transcribing: return "Cancel transcription"
        case .processing: return "Cancel cleanup"
        case .failed: return "Hold to dictate"
        }
    }

    private var dictationSymbol: String {
        switch state.dictationStatus {
        case .recording: return state.isFinishingRecording ? "ellipsis" : "waveform"
        case .requested: return "ellipsis"
        case .transcribing, .processing: return "xmark"
        case .failed, .idle, .ready: return "mic.fill"
        }
    }

    /// The blocked-link guidance belongs to the recovery control now, so it only
    /// appears when a session actually failed. It used to show whenever the app
    /// handoff was pending, which read as a permanent warning on a healthy board.
    private var dictationErrorMessage: String {
        if let message = state.statusMessage { return message }
        guard state.dictationStatus == .failed else { return "" }
        return "Dictation could not be completed."
    }

}

/// Compact live waveform used only while the dictation control is listening.
/// The static fallback keeps the control calm when Reduce Motion is enabled.
private struct ListeningWaveIcon: View {
    let color: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if reduceMotion {
                bars(phase: 0)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                    bars(phase: timeline.date.timeIntervalSinceReferenceDate * 5.5)
                }
            }
        }
        .frame(width: 24, height: 22)
        .accessibilityHidden(true)
    }

    private func bars(phase: Double) -> some View {
        HStack(alignment: .center, spacing: 2.5) {
            ForEach(0..<5, id: \.self) { index in
                let level = (sin(phase + Double(index) * 0.85) + 1.0) * 0.5
                Capsule()
                    .fill(color)
                    .frame(width: 2.5, height: 6 + CGFloat(level) * 14)
            }
        }
    }
}
