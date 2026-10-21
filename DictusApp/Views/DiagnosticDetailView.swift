// DictusApp/Views/DiagnosticDetailView.swift
// Shared-container health and the optional cleanup event log, reached from Help.
import SwiftUI
import SyllivraKernel

/// Displays App Group diagnostic results (read/write health check).
struct DiagnosticDetailView: View {
    let result: DiagnosticResult

    var body: some View {
        List {
            Section {
                diagnosticRow("Container", result.containerExists)
                diagnosticRow("Read", result.canRead)
                diagnosticRow("Write", result.canWrite)
                LabeledContent("Identifier", value: result.appGroupID)
                    .font(.caption.monospaced())
            } header: {
                Text("Keyboard Connection")
            } footer: {
                Text(result.isHealthy ? "The app and keyboard can share dictation." : "The shared container needs attention.")
            }
            Section {
                NavigationLink("Cleanup Events") { PolishDebugView() }
            }
        }
        .navigationTitle("Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func diagnosticRow(_ label: String, _ passed: Bool) -> some View {
        Label {
            Text(label)
        } icon: {
            Image(systemName: passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(passed ? .green : .red)
        }
        .accessibilityValue(passed ? "OK" : "Failed")
    }
}
