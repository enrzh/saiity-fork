// DictusApp/Onboarding/MicPermissionPage.swift
// Step 2 of onboarding: request microphone permission.
import SwiftUI
import UIKit
import AVFoundation
import DictusCore

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
        VStack(spacing: 0) {
            Spacer()

            // Mic icon
            Image(systemName: "mic.circle.fill")
                .font(.system(.largeTitle, weight: .semibold))
                .foregroundColor(.dictusAccent)
                .padding(.bottom, 24)

            // Title
            Text("Microphone")
                .font(.dictusHeading)
                .foregroundStyle(.primary)
                .padding(.bottom, 16)

            // Explanation
            Text("sAiity needs the microphone to transcribe your voice. Your recordings stay on your device.")
                .font(.dictusBody)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer()

            // Permission result feedback
            if let granted = permissionGranted {
                if granted {
                    Label("Microphone authorized", systemImage: "checkmark.circle.fill")
                        .font(.dictusBody)
                        .foregroundColor(.dictusSuccess)
                        .padding(.bottom, 16)
                } else {
                    Text("You can enable the microphone later in Settings")
                        .font(.dictusCaption)
                        .foregroundColor(.orange)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .padding(.bottom, 16)
                }
            }

            // Action button
            if permissionGranted == nil {
                // Request permission button.
                // WHY neutral wording ("Continue", not "Allow microphone"):
                // App Review guideline 5.1.1(iv) forbids priming buttons that direct
                // the user toward granting a system permission. The button only advances
                // to the OS prompt — iOS owns the actual allow/deny choice.
                Button(action: requestPermission) {
                    Text("Continue")
                        .frame(maxWidth: .infinity)
                }
                .font(.headline)
                .buttonStyle(.borderedProminent)
                .tint(.accentColor)
                .controlSize(.large)
                .disabled(isRequesting)
                .padding(.horizontal, 32)
                .padding(.bottom, 48)
            } else if permissionGranted == true {
                Button(action: onNext) {
                    Text("Continue after authorization")
                        .frame(maxWidth: .infinity)
                }
                .font(.headline)
                .buttonStyle(.borderedProminent)
                .tint(.accentColor)
                .controlSize(.large)
                .padding(.horizontal, 32)
                .padding(.bottom, 48)
            } else {
                VStack(spacing: 12) {
                    Button(action: openSettings) {
                        Label("Open Settings", systemImage: "arrow.up.right")
                            .frame(maxWidth: .infinity)
                    }
                    .font(.headline)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding(.horizontal, 32)

                    Text("Microphone access is required for dictation")
                        .font(.dictusCaption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                .padding(.bottom, 48)
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            switch AVAudioSession.sharedInstance().recordPermission {
            case .granted: permissionGranted = true
            case .denied: permissionGranted = false
            case .undetermined: permissionGranted = nil
            @unknown default: permissionGranted = false
            }
            UIAccessibility.post(notification: .announcement, argument: permissionGranted == true ? "Microphone authorized" : "Microphone permission still required")
        }
    }

    // MARK: - Private

    private func requestPermission() {
        isRequesting = true

        // Check current status first — if already determined, don't re-prompt
        let session = AVAudioSession.sharedInstance()
        switch session.recordPermission {
        case .granted:
            permissionGranted = true
            autoAdvance()
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
                    if allowed {
                        autoAdvance()
                    }
                }
            }
        @unknown default:
            permissionGranted = false
            isRequesting = false
        }
    }

    private func autoAdvance() {
        // Auto-advance after brief delay to show the checkmark
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            onNext()
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
