// DictusApp/DictationView.swift
import SwiftUI
import DictusCore

/// Shows the current dictation status with icon and label.
struct DictationStatusView: View {
    let status: DictationStatus

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .font(.title2)
                .foregroundColor(iconColor)

            VStack(alignment: .leading) {
                Text(status.recordingLabel)
                    .font(.subheadline.weight(.semibold))
                Text(statusDescription)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var iconName: String {
        switch status {
        case .idle: return "mic.slash"
        case .requested: return "arrow.up.forward"
        case .recording: return "mic.fill"
        case .transcribing: return "text.bubble"
        case .processing: return "sparkles"
        case .ready: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }

    private var iconColor: Color {
        switch status {
        case .idle: return .secondary
        case .requested: return .orange
        case .recording: return .red
        case .transcribing: return .blue
        case .processing: return Color.dictusSmartMode
        case .ready: return .green
        case .failed: return .red
        }
    }

    private var statusDescription: String {
        switch status {
        case .idle: return "Waiting for dictation request"
        case .requested: return "Opening from keyboard"
        case .recording: return "Capturing audio"
        case .transcribing: return "Processing speech"
        case .processing: return "Running the language model"
        case .ready: return "Transcription available"
        case .failed: return "Something went wrong"
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        DictationStatusView(status: .recording)
        DictationStatusView(status: .transcribing)
        DictationStatusView(status: .ready)
        DictationStatusView(status: .failed)
    }
    .padding()
}
