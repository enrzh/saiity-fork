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

    /// Compact leading: logo bars (static in standby, animated heights in recording)
    @ViewBuilder
    private func compactLeading(context: ActivityViewContext<DictusLiveActivityAttributes>) -> some View {
        switch context.state.phase {
        case .standby:
            // Static 3-bar logo at mini size
            MiniLogoBars(levels: [0.43, 1.0, 0.64], animated: false)
                .frame(width: 20, height: 14)
        case .recording:
            // Animated bars driven by waveform data
            let levels = normalizedLevels(context.state.waveformLevels, count: 3)
            MiniLogoBars(levels: levels, animated: true)
                .frame(width: 20, height: 14)
        case .transcribing:
            // Pulsing bars at medium height
            MiniLogoBars(levels: [0.4, 0.6, 0.4], animated: true)
                .frame(width: 20, height: 14)
        case .processing:
            // A pronounced centre peak, echoing the localized peak the keyboard
            // overlay sweeps in this stage (#267). Three bars cannot carry the
            // sweep itself -- ActivityKit's update budget is ~1/s -- so the shape
            // and the colour of the trailing label do the distinguishing here.
            MiniLogoBars(levels: [0.25, 0.85, 0.25], animated: true)
                .frame(width: 20, height: 14)
        case .ready:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.sAiitySuccess)
                .font(.system(size: 14))
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.sAiityRecording)
                .font(.system(size: 14))
        }
    }

    /// Compact trailing: "On" text in standby, timer in recording
    @ViewBuilder
    private func compactTrailing(context: ActivityViewContext<DictusLiveActivityAttributes>) -> some View {
        switch context.state.phase {
        case .standby:
            Text("Ready")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
        case .recording:
            Text("Rec")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.sAiityRecording)
        case .transcribing:
            // Small spinner-like indicator via SF Symbol
            Image(systemName: "ellipsis")
                .foregroundColor(.white.opacity(0.7))
                .font(.system(size: 14))
        case .processing:
            // Different glyph AND different colour from transcribing: at compact
            // size the pill shows one icon, so it has to carry the whole
            // distinction on its own (#267). Purple is the brand's Smart-mode
            // colour, which is where this stage is heading (#79).
            Image(systemName: "sparkles")
                .foregroundStyle(Color.sAiityProcessing)
                .font(.system(size: 14))
        case .ready:
            Text("Done")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.sAiitySuccess)
        case .failed:
            Image(systemName: "xmark")
                .foregroundStyle(Color.sAiityRecording)
                .font(.system(size: 14))
        }
    }

    // MARK: - Minimal View

    @ViewBuilder
    private func minimalView(context: ActivityViewContext<DictusLiveActivityAttributes>) -> some View {
        switch context.state.phase {
        case .standby:
            // Full 3-bar logo even in minimal — single bar was invisible
            MiniLogoBars(levels: [0.43, 1.0, 0.64], animated: false)
                .frame(width: 14, height: 12)
        case .recording:
            let levels = normalizedLevels(context.state.waveformLevels, count: 3)
            MiniLogoBars(levels: levels, animated: true)
                .frame(width: 14, height: 12)
        case .ready:
            Image(systemName: "checkmark")
                .foregroundStyle(Color.sAiitySuccess)
                .font(.system(size: 12, weight: .bold))
        default:
            Image(systemName: "waveform")
                .foregroundColor(.white.opacity(0.7))
                .font(.system(size: 12))
        }
    }

    // MARK: - Expanded Views (long press)

    @ViewBuilder
    private func expandedLeading(context: ActivityViewContext<DictusLiveActivityAttributes>) -> some View {
        HStack(spacing: 8) {
            // Logo bars
            MiniLogoBars(
                levels: context.state.phase == .recording
                    ? normalizedLevels(context.state.waveformLevels, count: 3)
                    : [0.43, 1.0, 0.64],
                animated: context.state.phase == .recording
                    || context.state.phase == .transcribing
                    || context.state.phase == .processing
            )
            .frame(width: 24, height: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text("sAiity")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)

                switch context.state.phase {
                case .standby:
                    Text("Ready")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.6))
                case .recording:
                    Text("Recording...")
                        .font(.system(size: 12))
                        .foregroundColor(Color(hex: 0xEF4444))
                case .transcribing:
                    Text("Transcribing...")
                        .font(.system(size: 12))
                .foregroundStyle(Color.sAiityAccent)
                case .processing:
                    Text("Processing...")
                        .font(.system(size: 12))
                .foregroundStyle(Color.sAiityProcessing)
                case .ready:
                    Text("Transcription ready")
                        .font(.system(size: 12))
                .foregroundStyle(Color.sAiitySuccess)
                case .failed:
                    Text("Error")
                        .font(.system(size: 12))
                .foregroundStyle(Color.sAiityRecording)
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .center)
    }

    @ViewBuilder
    private func expandedTrailing(context: ActivityViewContext<DictusLiveActivityAttributes>) -> some View {
        HStack(spacing: 10) {
            Spacer(minLength: 0) // Push trailing elements to the right edge
            switch context.state.phase {
            case .standby:
                // Power off button — ends Live Activity via LiveActivityIntent (no app open)
                Button(intent: StopStandbyIntent()) {
                    Image(systemName: "power")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white.opacity(0.8))
                        .frame(width: 44, height: 44)
                        .background(Color.white.opacity(0.15))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                // Record button
                Button(intent: StopStandbyIntent(toggleDetection: true)) {
                    Image(systemName: context.state.detectionMuted ? "mic.slash.fill" : "mic.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 44, height: 44)
                        .background(context.state.detectionMuted ? Color.secondary : Color.sAiityAccent)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
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
            // Logo
            MiniLogoBars(
                levels: context.state.phase == .recording
                    ? normalizedLevels(context.state.waveformLevels, count: 3)
                    : [0.43, 1.0, 0.64],
                animated: context.state.phase == .recording
            )
            .frame(width: 28, height: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text("sAiity")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.primary)

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
                HStack(spacing: 8) {
                    Button(intent: StopStandbyIntent()) {
                        Image(systemName: "power")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.secondary)
                            .frame(width: 48, height: 48)
                            .background(Color.white.opacity(0.1))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    Button(intent: StopStandbyIntent(toggleDetection: true)) {
                        Image(systemName: context.state.detectionMuted ? "mic.slash.fill" : "mic.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.primary)
                            .frame(width: 48, height: 48)
                            .background(context.state.detectionMuted ? Color.secondary : Color.sAiityAccent)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
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

    // MARK: - Helpers

    /// Normalize waveform levels to the requested count.
    /// Downsamples by averaging groups if input has more values.
    /// Pads with default values if input has fewer.
    private func normalizedLevels(_ levels: [Float], count: Int) -> [Float] {
        guard !levels.isEmpty else {
            // Default levels matching logo proportions
            return count == 3
                ? [0.43, 1.0, 0.64]
                : Array(repeating: 0.3, count: count)
        }

        if levels.count == count {
            return levels
        }

        if levels.count > count {
            // Downsample: average groups
            let groupSize = levels.count / count
            return (0..<count).map { i in
                let start = i * groupSize
                let end = min(start + groupSize, levels.count)
                let slice = levels[start..<end]
                return slice.reduce(0, +) / Float(slice.count)
            }
        }

        // Pad with last value or 0.3
        var result = levels
        let pad = levels.last ?? 0.3
        while result.count < count {
            result.append(pad)
        }
        return result
    }
}

// MARK: - Mini Logo Bars

/// Compact 3-bar logo for Dynamic Island display.
/// Matches brand proportions: left=43%, center=100% (gradient), right=64%.
///
/// WHY not reusing DictusLogo from DictusCore:
/// DictusLogo uses @ScaledMetric and @Environment(\.colorScheme) which behave
/// differently in Widget extensions. This simplified version uses fixed sizes
/// appropriate for the tiny Dynamic Island space.
struct MiniLogoBars: View {
    let levels: [Float]
    let animated: Bool

    var body: some View {
        GeometryReader { geo in
            let barWidth = max(2.5, geo.size.width / 5)
            let spacing = (geo.size.width - barWidth * 3) / 2
            // Boost side bar opacity in small frames so bars stay visible
            let isSmall = geo.size.width < 16

            HStack(spacing: spacing) {
                ForEach(0..<min(levels.count, 3), id: \.self) { index in
                    let height = CGFloat(levels[index]) * geo.size.height
                    if index == 1 {
                        // Center bar: brand gradient
                        RoundedRectangle(cornerRadius: barWidth / 2)
                            .fill(LinearGradient(
                                colors: [Color(hex: 0x6BA3FF), Color(hex: 0x2563EB)],
                                startPoint: .top, endPoint: .bottom
                            ))
                            .frame(width: barWidth, height: max(2, height))
                    } else {
                        // Side bars: white with brand opacity (boosted when small)
                        let opacity: Double = index == 0
                            ? (isSmall ? 0.60 : 0.45)
                            : (isSmall ? 0.80 : 0.65)
                        RoundedRectangle(cornerRadius: barWidth / 2)
                            .fill(Color.white.opacity(opacity))
                            .frame(width: barWidth, height: max(2, height))
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
            .animation(animated ? .easeInOut(duration: 0.3) : nil, value: levels)
        }
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

// MARK: - Color Extension (Widget-local)

/// WHY duplicate Color(hex:) here instead of importing from DictusCore:
/// Widget extensions have a separate compilation context. While DictusCore
/// is linked, keeping this tiny extension local avoids any import ordering
/// issues with SwiftUI in widget builds.
private extension Color {
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
