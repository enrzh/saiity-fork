// DictusApp/Views/DiagnosticDetailView.swift
// App Group diagnostic display, extracted from ContentView for reuse in Settings.
import SwiftUI
import SyllivraKernel

/// Displays App Group diagnostic results (read/write health check).
///
/// WHY extracted from ContentView:
/// This view was originally defined inline in ContentView. Now that ContentView is
/// replaced by RootView + HomeView, DiagnosticView moves to its own file so it
/// can be reused in Settings > A propos > Diagnostic (Plan 04-02).
struct DiagnosticDetailView: View {
    let result: DiagnosticResult

    var body: some View {
        List {
            Section {
                SaiityPageHeader(title: "Keyboard connection",
                                 subtitle: "Check the shared space that carries your dictation between apps.")
            }.listRowBackground(Color.clear)
            Section("App Group") {
                diagnosticRow("Container", result.containerExists)
                diagnosticRow("Read", result.canRead)
                diagnosticRow("Write", result.canWrite)
                LabeledContent("Identifier", value: result.appGroupID)
                    .font(.caption.monospaced())
            }
            Section {
                Text(result.isHealthy ? "The shared container is ready for the app and keyboard." : "The shared container needs attention.")
                    .foregroundStyle(.secondary)
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
