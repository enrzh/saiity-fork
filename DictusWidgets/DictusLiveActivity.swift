import ActivityKit
import SwiftUI
import WidgetKit
import DictusCore

struct DictusLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DictusLiveActivityAttributes.self) { context in
            DictationActivityCard(state: context.state)
                .activityBackgroundTint(Color(uiColor: .secondarySystemGroupedBackground))
                .activitySystemActionForegroundColor(.primary)
                .widgetURL(URL(string: "saiity://open"))
        } dynamicIsland: { context in
            let status = DictationActivityStatus(state: context.state)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 8) {
                        DictusLogo(height: 28, foregroundOnly: true)
                        Text("sAiity").font(.headline).foregroundStyle(.white)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ActivityAction(state: context.state, dark: true)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    DictationActivityDetail(state: context.state, dark: true)
                        .padding(.top, 6)
                }
            } compactLeading: {
                DictusLogo(height: 20, foregroundOnly: true)
                    .accessibilityLabel("sAiity")
            } compactTrailing: {
                ActivitySignal(state: context.state, compact: true)
            } minimal: {
                ActivitySignal(state: context.state, compact: true)
            }
            .widgetURL(URL(string: "saiity://open"))
            .keylineTint(status.color)
        }
    }
}

/// One state vocabulary for the card, expanded Island and compact signal.
private struct DictationActivityStatus {
    let state: DictusLiveActivityAttributes.ContentState
    var paused: Bool { !state.serviceEnabled || state.detectionMuted }
    var title: String {
        switch state.phase {
        case .standby: return !state.serviceEnabled ? "Dictation is off" : state.detectionMuted ? "Dictation paused" : "Ready to listen"
        case .recording: return "Listening"
        case .transcribing: return "Preparing your text"
        case .processing: return "Finishing your text"
        case .ready: return "Ready to use"
        case .failed: return "Dictation needs attention"
        }
    }
    var detail: String {
        switch state.phase {
        case .standby: return !state.serviceEnabled ? "Turn on when you’re ready" : state.detectionMuted ? "Open sAiity to resume" : "Hold the microphone on your keyboard"
        case .recording: return "Release the microphone to finish"
        case .transcribing: return "Turning speech into text"
        case .processing: return "Following your chosen settings"
        case .ready: return "Return to your text field"
        case .failed: return "Open sAiity to try again"
        }
    }
    var symbol: String {
        switch state.phase {
        case .standby: return paused ? "mic.slash.fill" : "mic.fill"
        case .recording: return "waveform"
        case .transcribing: return "text.bubble.fill"
        case .processing: return "wand.and.stars"
        case .ready: return "checkmark"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }
    var color: Color {
        switch state.phase {
        case .standby: return paused ? .secondary : .saiityAction
        case .failed: return .red
        case .recording, .transcribing, .processing, .ready: return .saiityAction
        }
    }
}

struct DictationActivityCard: View {
    let state: DictusLiveActivityAttributes.ContentState
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                DictusLogo(height: 24, foregroundOnly: true)
                if !typeSize.isAccessibilitySize {
                    Text("sAiity").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                ActivityAction(state: state)
            }
            DictationActivityDetail(state: state)
        }
        .padding(16)
    }
}

private struct DictationActivityDetail: View {
    let state: DictusLiveActivityAttributes.ContentState
    var dark = false
    @Environment(\.dynamicTypeSize) private var typeSize
    private var status: DictationActivityStatus { .init(state: state) }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                ActivitySignal(state: state)
                    .frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 3) {
                    Text(status.title).font(.headline).foregroundStyle(dark ? .white : .primary)
                    if !typeSize.isAccessibilitySize && state.phase != .ready {
                        Text(status.detail).font(.caption.weight(.medium))
                            .foregroundStyle(dark ? .white.opacity(0.7) : .secondary)
                    }
                }
                Spacer(minLength: 0)
                if state.phase == .recording, let start = state.recordingStartDate {
                    Text(start, style: .timer).font(.title3.weight(.semibold)).monospacedDigit()
                        .foregroundStyle(dark ? .white : .primary)
                        .multilineTextAlignment(.trailing).frame(maxWidth: 72)
                }
            }
            if state.phase == .ready, let preview = state.transcriptionPreview, !preview.isEmpty {
                Text(preview).font(.subheadline.weight(.medium)).lineLimit(typeSize.isAccessibilitySize ? 1 : 2)
                    .foregroundStyle(dark ? .white.opacity(0.85) : .primary)
                    .privacySensitive()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint(status.detail)
        // Preserve the status and 44pt actions within ActivityKit's 160pt limit.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }
}

private struct ActivitySignal: View {
    let state: DictusLiveActivityAttributes.ContentState
    var compact = false
    var body: some View {
        let status = DictationActivityStatus(state: state)
        Group {
            if state.phase == .recording {
                SaiityVoiceSignal(level: state.waveformLevels.max() ?? 0, height: compact ? 18 : 24)
            } else if state.phase == .standby && !status.paused {
                DictusLogo(height: compact ? 18 : 24, foregroundOnly: true)
            } else {
                Image(systemName: status.symbol).font(.system(size: compact ? 13 : 16, weight: .semibold))
            }
        }
        .foregroundStyle(status.color)
        .accessibilityLabel(status.title)
    }
}

/// The same single action in expanded and Lock Screen presentations.
private struct ActivityAction: View {
    let state: DictusLiveActivityAttributes.ContentState
    var dark = false
    private var status: DictationActivityStatus { .init(state: state) }
    var body: some View {
        HStack(spacing: 8) {
            if #available(iOS 18.2, *) {
                serviceButton
            } else if state.serviceEnabled {
                serviceButton
            } else if let url = KeyboardDictationBridge.recoveryURL() {
                Link(destination: url) { actionLabel("power", title: "Off") }
                    .accessibilityLabel("Enable keyboard dictation")
            }
            if state.phase == .recording, let url = URL(string: "saiity://stop") {
                Link(destination: url) {
                    actionLabel("stop.fill", title: "Finish")
                }.accessibilityLabel("Finish dictation")
            } else if state.phase == .failed,
                      let url = URL(string: "saiity://dictate?source=keyboard&intent=prepare") {
                Link(destination: url) {
                    actionLabel("arrow.up.forward", title: "Open")
                }.accessibilityLabel("Open sAiity to prepare dictation")
            }
        }
        .buttonStyle(.plain)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }
    private var serviceButton: some View {
        Button(intent: StopStandbyIntent(toggleDetection: true)) {
            actionLabel("power", title: state.serviceEnabled ? "On" : "Off")
        }
        .accessibilityLabel(state.serviceEnabled ? "Disable keyboard dictation" : "Enable keyboard dictation")
        .accessibilityValue(state.serviceEnabled ? "On" : "Off")
    }
    private func actionLabel(_ symbol: String, title: String) -> some View {
        Label(title, systemImage: symbol).font(.caption.weight(.semibold))
            .fixedSize(horizontal: true, vertical: true)
            .foregroundStyle(dark ? .white : .primary)
            .padding(.horizontal, 12).frame(minHeight: 44)
            .background(status.color.opacity(dark ? 0.25 : 0.12), in: Capsule())
    }
}
