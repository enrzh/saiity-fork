import SwiftUI
import SyllivraKernel
import UIKit

/// Opt-in last-dictation issue report. The user previews the exact export,
/// chooses whether transcript text is included, and shares through the system
/// share sheet. Nothing is sent automatically.
struct LastDictationIssueReportView: View {
    @State private var snapshot = LastDictationIssueReport.load(from: AppGroup.defaults)
    @State private var includeText = false

    var body: some View {
        List {
            if let snapshot {
                Section {
                    Text("The report includes model, engine, stage, and timing. Transcript text is included only if you turn that on, and nothing is sent unless you use Share.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Section("Last dictation") {
                    LabeledContent("Model", value: snapshot.modelIdentifier)
                    LabeledContent("Engine", value: snapshot.engineName)
                    LabeledContent("Output", value: snapshot.outputMode)
                    LabeledContent("Language mode", value: snapshot.transcriptionMode)
                    LabeledContent("Stage", value: snapshot.stage)
                    if let failure = snapshot.failureStage {
                        LabeledContent("Failure stage", value: failure)
                    }
                    if let error = snapshot.errorSummary, !error.isEmpty {
                        LabeledContent("Error", value: error)
                    }
                    if let ms = snapshot.recordingDurationMs {
                        LabeledContent("Recording", value: "\(ms) ms")
                    }
                    if let ms = snapshot.transcribeMs {
                        LabeledContent("Transcription", value: "\(ms) ms")
                    }
                    if let ms = snapshot.polishMs {
                        LabeledContent("Cleanup", value: "\(ms) ms")
                    }
                }
                Section {
                    Toggle("Include transcript text", isOn: $includeText)
                    if includeText {
                        if let raw = snapshot.rawText, !raw.isEmpty {
                            LabeledContent("Raw", value: raw)
                        }
                        if let cleaned = snapshot.cleanedText, !cleaned.isEmpty {
                            LabeledContent("Cleaned", value: cleaned)
                        }
                        if LastDictationIssueReport.recoverableRawText(from: AppGroup.defaults) != nil {
                            Button("Copy raw transcript") {
                                UIPasteboard.general.string = snapshot.rawText
                            }
                        }
                    } else {
                        Text("Transcript text is omitted from the export until you turn this on.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Section("Export preview") {
                    Text(LastDictationIssueReport.previewString(snapshot, includeText: includeText))
                        .font(.system(.footnote, design: .monospaced))
                        .textSelection(.enabled)
                }
                Section {
                    ShareLink(item: LastDictationIssueReport.previewString(snapshot, includeText: includeText)) {
                        Label("Share report", systemImage: "square.and.arrow.up")
                    }
                }
            } else {
                Section {
                    Text("No recent dictation to report. Dictate once, then return here.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Report Last Dictation")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            snapshot = LastDictationIssueReport.load(from: AppGroup.defaults)
        }
    }
}
