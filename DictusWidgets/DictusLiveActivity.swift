// DictusWidgets/DictusLiveActivity.swift
// Live Activity views for Dynamic Island + Lock Screen banner.
import ActivityKit
import SwiftUI
import WidgetKit
import DictusCore

/// Live Activity configuration for sAiity.
///
/// WHY all views in one file:
/// Widget extensions should minimize file count. The compact/expanded/lock screen
/// views are tightly coupled — they share the same ContentState and brand assets.
/// Splitting them would add complexity without benefit.
struct DictusLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DictusLiveActivityAttributes.self) { context in
            // Lock Screen / StandBy banner
            lockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded view (long press on Dynamic Island)
                DynamicIslandExpandedRegion(.leading) {
                    expandedLeading(context: context)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    expandedTrailing(context: context)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    expandedBottom(context: context)
                }
            } compactLeading: {
                compactLeading(context: context)
            } compactTrailing: {
                compactTrailing(context: context)
            } minimal: {
                // Minimal view when multiple Live Activities compete for space
                minimalView(context: context)
            }
            .widgetURL(URL(string: "saiity://open"))
        }
    }

    // MARK: - Compact Views (Dynamic Island pill)

    /// Compact leading carries the compact sAiity mark.
    @ViewBuilder
    private func compactLeading(context: ActivityViewContext<DictusLiveActivityAttributes>) -> some View {
        SaiityMark(size: 20)
    }

    /// Compact trailing uses the same status language as the expanded surface.
    @ViewBuilder
    private func compactTrailing(context: ActivityViewContext<DictusLiveActivityAttributes>) -> some View {
        Image(systemName: statusSymbol(for: context.state.phase))
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(statusColor(for: context.state.phase))
            .accessibilityLabel(statusLabel(for: context.state.phase))
    }

    // MARK: - Minimal View

    @ViewBuilder
    private func minimalView(context: ActivityViewContext<DictusLiveActivityAttributes>) -> some View {
        SaiityMark(size: 24)
    }

    // MARK: - Expanded Views (long press)

    @ViewBuilder
    private func expandedLeading(context: ActivityViewContext<DictusLiveActivityAttributes>) -> some View {
        HStack(spacing: 8) {
            SaiityMark(size: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text("sAiity")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Text(statusLabel(for: context.state.phase))
                    .font(.system(size: 12))
                    .foregroundStyle(statusColor(for: context.state.phase))
            }
        }
        .frame(maxHeight: .infinity, alignment: .center)
    }

    private func statusLabel(for phase: DictusLiveActivityAttributes.Phase) -> String {
        switch phase {
        case .standby: return "Ready"
        case .recording: return "Listening"
        case .transcribing: return "Transcribing"
        case .processing: return "Polishing"
        case .ready: return "Ready to use"
        case .failed: return "Needs attention"
        }
    }

    private func statusSymbol(for phase: DictusLiveActivityAttributes.Phase) -> String {
        switch phase {
        case .standby: return "mic"
        case .recording: return "waveform"
        case .transcribing: return "ellipsis"
        case .processing: return "wand.and.stars"
        case .ready: return "checkmark"
        case .failed: return "exclamationmark.triangle"
        }
    }

    private func statusColor(for phase: DictusLiveActivityAttributes.Phase) -> Color {
        switch phase {
        case .standby: return .white.opacity(0.7)
        case .recording: return .sAiityRecording
        case .transcribing: return .sAiityAccent
        case .processing: return .sAiityProcessing
        case .ready: return .sAiitySuccess
        case .failed: return .sAiityRecording
        }
    }

    @ViewBuilder
    private func serviceControl(enabled: Bool, size: CGFloat) -> some View {
        let label = Image(systemName: enabled ? "power" : "power.circle")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.primary)
            .frame(width: size, height: size)
            .background(Color.primary.opacity(0.15), in: Circle())
        if enabled {
            Button(intent: StopStandbyIntent(toggleDetection: true)) { label }
                .buttonStyle(.plain)
                .accessibilityLabel("Disable keyboard dictation")
        } else if let url = URL(string: "saiity://dictate?source=keyboard&intent=prepare") {
            // Starting a cold microphone requires foreground activation; the
            // keyboard holds themselves never open the app.
            Link(destination: url) { label }
                .buttonStyle(.plain)
                .accessibilityLabel("Enable keyboard dictation in sAiity")
        }
    }

    @ViewBuilder
    private func expandedTrailing(context: ActivityViewContext<DictusLiveActivityAttributes>) -> some View {
        HStack(spacing: 10) {
            Spacer(minLength: 0) // Push trailing elements to the right edge
            switch context.state.phase {
            case .standby:
                serviceControl(enabled: context.state.serviceEnabled, size: 44)

            case .recording:
                // Stop button (left side)
                if let stopURL = URL(string: "saiity://stop") {
                    Link(destination: stopURL) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 32, height: 32)
                            .background(Color.sAiityRecording)
                            .clipShape(Circle())
                    }
                }

                // Timer (right, naturally trailing — aligns with compact trailing)
                if let startDate = context.state.recordingStartDate {
                    Text(startDate, style: .timer)
                        .font(.system(size: 16, weight: .medium, design: .monospaced))
                        .foregroundColor(.white)
                        .monospacedDigit()
                }
            case .transcribing:
                ProgressView()
                    .tint(.white)
            case .processing:
                ProgressView()
                    .tint(Color(hex: 0x8B5CF6))
            case .ready, .failed:
                EmptyView()
            }
        }
        .frame(maxHeight: .infinity, alignment: .center)
    }

    @ViewBuilder
    private func expandedBottom(context: ActivityViewContext<DictusLiveActivityAttributes>) -> some View {
        switch context.state.phase {
        case .recording:
            EmptyView()
        case .ready:
            if let preview = context.state.transcriptionPreview {
                Text(preview)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.8))
                    .lineLimit(2)
                    .padding(.horizontal, 8)
            }
        default:
            EmptyView()
        }
    }

    // MARK: - Lock Screen Banner

    @ViewBuilder
    private func lockScreenView(context: ActivityViewContext<DictusLiveActivityAttributes>) -> some View {
        HStack(spacing: 12) {
            SaiityMark(size: 40)

            VStack(alignment: .leading, spacing: 2) {
                switch context.state.phase {
                case .standby:
                    Text("Ready")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                case .recording:
                    if let startDate = context.state.recordingStartDate {
                        HStack(spacing: 4) {
                            Circle()
                            .fill(Color.sAiityRecording)
                                .frame(width: 6, height: 6)
                            Text(startDate, style: .timer)
                                .font(.system(size: 13, design: .monospaced))
                                .foregroundColor(.secondary)
                                .monospacedDigit()
                        }
                    }
                case .transcribing:
                    Text("Transcribing...")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.sAiityAccent)
                case .processing:
                    Text("Processing...")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.sAiityProcessing)
                case .ready:
                    Text(context.state.transcriptionPreview ?? "Transcription ready")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.sAiitySuccess)
                        .lineLimit(1)
                case .failed:
                    Text("Error")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.sAiityRecording)
                }
            }

            Spacer()

            // Action buttons
            switch context.state.phase {
            case .standby:
                serviceControl(enabled: context.state.serviceEnabled, size: 48)
            case .recording:
                if let stopURL = URL(string: "saiity://stop") {
                    Link(destination: stopURL) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.primary)
                            .frame(width: 48, height: 48)
                            .background(Color.sAiityRecording)
                            .clipShape(Circle())
                    }
                }
            default:
                EmptyView()
            }
        }
        .padding(16)
        .background(Color(uiColor: .systemBackground))
    }

}

// MARK: - Waveform Bars (Expanded View)

/// 5-bar waveform for the expanded Dynamic Island view.
struct WaveformBars: View {
    let levels: [Float]

    var body: some View {
        GeometryReader { geo in
            let barWidth: CGFloat = 6
            let spacing: CGFloat = 4  // Fixed tight spacing

            HStack(spacing: spacing) {
                ForEach(0..<min(levels.count, 5), id: \.self) { index in
                    let height = max(4, CGFloat(levels[index]) * geo.size.height)

                    RoundedRectangle(cornerRadius: barWidth / 2)
                        .fill(LinearGradient(
                            colors: [Color(hex: 0x6BA3FF), Color(hex: 0x3D7EFF)],
                            startPoint: .top, endPoint: .bottom
                        ))
                        .frame(width: barWidth, height: height)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
            .animation(.easeInOut(duration: 0.3), value: levels)
        }
    }
}

/// Compact sAiity mark for WidgetKit surfaces where the app icon asset is not
/// available to the extension bundle.
private struct SaiityMark: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.sAiityBrand)

            Text(verbatim: "sAi")
                .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
                .tracking(-size * 0.025)
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityLabel("sAiity")
    }
}

// MARK: - Color Extension (Widget-local)

/// WHY duplicate Color(hex:) here instead of importing from DictusCore:
/// Widget extensions have a separate compilation context. While DictusCore
/// is linked, keeping this tiny extension local avoids any import ordering
/// issues with SwiftUI in widget builds.
private extension Color {
    static let sAiityBrand = Color(hex: 0x16A6AA)
    static let sAiityAccent = Color.accentColor
    static let sAiityRecording = Color.red
    static let sAiitySuccess = Color.green
    static let sAiityProcessing = Color.indigo

    init(hex: UInt, opacity: Double = 1.0) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: opacity
        )
    }
}
