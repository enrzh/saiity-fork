// DictusApp/Onboarding/MicPermissionPage.swift
// Step 2 of onboarding: request microphone permission.
import SwiftUI
import UIKit
import AVFoundation
import SyllivraKernel

/// Requests microphone permission with clear explanation of privacy.
///
/// WHY we don't block on denial:
/// Apple's HIG and research best practices recommend against blocking progress
/// on a denied permission. The user can still set up the keyboard and download
/// a model — they just won't be able to record until they grant mic access later.
struct MicPermissionPage: View {
    let onNext: () -> Void
    @Environment(\.scenePhase) private var scenePhase

    /// nil = not yet requested, true = granted, false = denied
    @State private var permissionGranted: Bool?
    @State private var isRequesting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            SaiityPageHeader(title: "Allow microphone access", subtitle: subtitle)
            if permissionGranted == true {
                Label("Microphone allowed", systemImage: "checkmark.circle.fill").foregroundStyle(.tint)
            }
            if permissionGranted == nil {
                Button("Allow Microphone", action: requestPermission)
                    .buttonStyle(.borderedProminent).controlSize(.large).disabled(isRequesting)
            } else if permissionGranted == true {
                Button("Continue", action: onNext)
                    .buttonStyle(.borderedProminent).controlSize(.large)
            } else {
                Button("Open Settings", action: openSettings)
                    .buttonStyle(.borderedProminent).controlSize(.large)
                Button("Continue Without Microphone", action: onNext)
                    .buttonStyle(.bordered).controlSize(.large)
            }
        }
        .onAppear(perform: refreshPermission)
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            refreshPermission()
            UIAccessibility.post(notification: .announcement, argument: permissionGranted == true ? "Microphone allowed" : "Microphone permission still required")
        }
    }

    private var subtitle: LocalizedStringKey {
        permissionGranted == false
            ? "Dictation needs the microphone. Turn it on in Settings now, or later when you’re ready."
            : "Syllivra listens only while you dictate. You can change this at any time in Settings."
    }

    // MARK: - Private

    private func requestPermission() {
        isRequesting = true

        // Check current status first — if already determined, don't re-prompt
        let session = AVAudioSession.sharedInstance()
        switch session.recordPermission {
        case .granted:
            permissionGranted = true
            isRequesting = false
        case .denied:
            permissionGranted = false
            isRequesting = false
        case .undetermined:
            // Bridge the completion-handler API to async-friendly code.
            //
            // WHY not async/await wrapper here:
            // requestRecordPermission uses a completion handler callback (pre-async API).
            // We could use withCheckedContinuation, but since we're updating @State
            // on main thread anyway, a simple DispatchQueue.main.async in the callback
            // is simpler and avoids the continuation overhead.
            session.requestRecordPermission { allowed in
                DispatchQueue.main.async {
                    permissionGranted = allowed
                    isRequesting = false
                }
            }
        @unknown default:
            permissionGranted = false
            isRequesting = false
        }
    }

    private func refreshPermission() {
        switch AVAudioSession.sharedInstance().recordPermission {
        case .granted: permissionGranted = true
        case .denied: permissionGranted = false
        case .undetermined: permissionGranted = nil
        @unknown default: permissionGranted = false
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
