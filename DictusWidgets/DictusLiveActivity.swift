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
        case .standby: return paused ? "Dictation paused" : "Ready to dictate"
        case .recording: return "Listening"
        case .transcribing: return "Transcribing"
        case .processing: return "Refining your words"
        case .ready: return "Your text is ready"
        case .failed: return "Dictation needs attention"
        }
    }
    var detail: String {
        switch state.phase {
        case .standby: return paused ? "Open sAiity to resume" : "Hold the microphone on your keyboard"
        case .recording: return "Release the microphone to finish"
        case .transcribing: return "Turning speech into text"
        case .processing: return "Cleaning up punctuation and grammar"
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
        case .standby: return paused ? .gray : .cyan
        case .recording, .failed: return .red
        case .transcribing: return .blue
        case .processing: return .purple
        case .ready: return .green
        }
    }
}

struct DictationActivityCard: View {
    let state: DictusLiveActivityAttributes.ContentState
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                DictusLogo(height: 24, foregroundOnly: true)
                Text("sAiity").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
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
    private var status: DictationActivityStatus { .init(state: state) }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                ActivitySignal(state: state)
                    .frame(width: 32, height: 32)
                    .background(status.color.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 3) {
                    Text(status.title).font(.headline).foregroundStyle(dark ? .white : .primary)
                    Text(status.detail).font(.caption.weight(.medium))
                        .foregroundStyle(dark ? .white.opacity(0.7) : .secondary)
                }
                Spacer(minLength: 0)
                if state.phase == .recording, let start = state.recordingStartDate {
                    Text(start, style: .timer).font(.title3.weight(.semibold)).monospacedDigit()
                        .foregroundStyle(dark ? .white : .primary)
                        .multilineTextAlignment(.trailing).frame(maxWidth: 72)
                }
            }
            if state.phase == .transcribing || state.phase == .processing {
                HStack(spacing: 8) {
                    Label("Speech", systemImage: "checkmark.circle.fill")
                    Image(systemName: "chevron.right").accessibilityHidden(true)
                    Label("Text", systemImage: state.phase == .processing ? "checkmark.circle.fill" : "text.bubble")
                    if state.phase == .processing {
                        Image(systemName: "chevron.right").accessibilityHidden(true)
                        Label("Refine", systemImage: "wand.and.stars")
                    }
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(dark ? .white.opacity(0.5) : .secondary)
            }
            if state.phase == .ready, let preview = state.transcriptionPreview, !preview.isEmpty {
                Text(preview).font(.subheadline.weight(.medium)).lineLimit(2)
                    .foregroundStyle(dark ? .white.opacity(0.85) : .primary)
                    .privacySensitive()
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct ActivitySignal: View {
    let state: DictusLiveActivityAttributes.ContentState
    var compact = false
    var body: some View {
        let status = DictationActivityStatus(state: state)
        Group {
            if state.phase == .recording {
                HStack(spacing: 2) {
                    ForEach(0..<5) { index in
                        let level = state.waveformLevels.indices.contains(index) ? state.waveformLevels[index] : 0
                        Capsule().frame(width: 3, height: 4 + CGFloat(min(1, max(0, level.isFinite ? level : 0))) * 16)
                    }
                }.frame(width: 23, height: 22)
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
        Group {
            if state.phase == .standby, !status.paused {
                Button(intent: StopStandbyIntent(toggleDetection: true)) {
                    actionLabel("mic.slash", title: "Pause")
                }.accessibilityLabel("Pause keyboard dictation")
            } else if state.phase == .recording, let url = URL(string: "saiity://stop") {
                Link(destination: url) {
                    actionLabel("stop.fill", title: "Finish")
                }.accessibilityLabel("Finish dictation")
            } else if state.phase == .standby || state.phase == .failed,
                      let url = URL(string: "saiity://dictate?source=keyboard&intent=prepare") {
                Link(destination: url) {
                    actionLabel("arrow.up.forward", title: state.phase == .failed ? "Open" : "Resume")
                }.accessibilityLabel("Open sAiity to prepare dictation")
            }
        }
        .buttonStyle(.plain)
    }
    private func actionLabel(_ symbol: String, title: String) -> some View {
        Label(title, systemImage: symbol).font(.caption.weight(.semibold))
            .foregroundStyle(dark ? .white : .primary)
            .padding(.horizontal, 12).frame(minHeight: 44)
            .background(status.color.opacity(dark ? 0.25 : 0.12), in: Capsule())
    }
}
