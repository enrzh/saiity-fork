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
                let titleHeight = max(0, dictateFrame.minY - layout.surfaceFrame.minY - 8)
                if titleHeight >= 18 {
                    VStack(spacing: 4) {
                        Text(boardStateTitle(width: dictateFrame.width))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Color(uiColor: KeyboardChromeRole.secondaryForeground))
                            .multilineTextAlignment(.center)
                        if titleHeight >= 38, let preview = state.currentDictationPreview {
                            Text(preview).font(.caption).foregroundStyle(.primary)
                                .lineLimit(titleHeight >= 58 ? 2 : 1)
                        }
                    }
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .frame(width: dictateFrame.width, height: titleHeight)
                    .position(x: CGFloat(dictateFrame.midX - layout.surfaceFrame.minX), y: titleHeight / 2)
                    .allowsHitTesting(false)
                    .accessibilityElement(children: .combine)
                }
                if !voiceBoardUsesUIKitHits {
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
                }
                if !dictationErrorMessage.isEmpty && !errorFrame.isEmpty {
                    Text(dictationErrorMessage)
                        .font(.caption)
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                        .foregroundStyle(.red)
                        .lineLimit(1)
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
        .accessibilityHint("Opens Syllivra so dictation can be prepared.")
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
            symbolForeground: Color(uiColor: dictationFaceStyle.symbolForeground),
            liveWave: state.dictationStatus == .recording && !state.isFinishingRecording
        )
        .accessibilityIdentifier("dictate-button")
        .accessibilityLabel(state.primaryBoardActionLabel)
        .accessibilityValue(dictationTitle)
    }

    private var dictationFaceStyle: KeyboardDictationFaceStyle {
        KeyboardDictationFaceStyle(status: state.dictationStatus, finishing: state.isFinishingRecording)
    }

    private var dictationButtonBackground: Color {
        Color(uiColor: dictationFaceStyle.fill)
    }

    private var dictationButtonForeground: Color {
        Color(uiColor: dictationFaceStyle.foreground)
    }

    /// Shared capsule chrome for the board's primary slot, so the recovery and
    /// dictation controls cannot drift apart visually.
    private func boardCapsuleVisual(
        frame: CGRect,
        title: String,
        symbol: String,
        background: Color,
        foreground: Color,
        symbolForeground: Color,
        liveWave: Bool = false
    ) -> some View {
        ZStack(alignment: .center) {
            VStack(spacing: 1) {
                if liveWave {
                    ListeningWaveIcon(color: symbolForeground)
                } else {
                    Image(systemName: symbol)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(symbolForeground)
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
            Capsule().fill(background).allowsHitTesting(false)
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
            background: Color(uiColor: KeyboardDictationFaceStyle(status: .idle).fill),
            foreground: .primary,
            symbolForeground: Color.saiityAction
        )
        .accessibilityIdentifier("open-saiity-button")
        .accessibilityLabel(state.primaryBoardActionLabel)
        .accessibilityValue(recoveryTitle)
    }

    /// The handoff acknowledges the press immediately, before iOS finishes
    /// switching away, so the control never looks inert while it works.
    private var recoveryTitle: String {
        state.recoveryBoardTitle
    }

    private func spaceBar(frame: CGRect) -> some View {
        ZStack {
            appleControlSurface(
                Color.clear
                    .frame(width: frame.width, height: CGFloat(VoiceOnlyKeyboardPolicy.bottomBarVisualHeight)),
                in: RoundedRectangle(cornerRadius: CommandKeyStyle.cornerRadius, style: .continuous),
                role: .input
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
        state.dictationBoardTitle
    }

    private func boardStateTitle(width: CGFloat) -> String {
        guard state.dictationStatus == .recording, state.recordingElapsed.isFinite else {
            return state.dictationBoardStateTitle
        }
        let seconds = Int(min(max(state.recordingElapsed, 0), 86_400))
        return state.dictationBoardStateTitle + (width < 128 ? "\n" : " · ")
            + String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private var dictationSymbol: String {
        state.dictationBoardSymbol
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
