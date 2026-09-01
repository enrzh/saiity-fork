// DictusApp/Onboarding/KeyboardSetupPage.swift
// Step 3 of onboarding: guide the user to add the sAiity keyboard.
import SwiftUI
import UIKit
import DictusCore

/// Guides the user through adding the sAiity keyboard in iOS Settings.
struct KeyboardSetupPage: View {
    let onNext: () -> Void

    @Environment(\.scenePhase) private var scenePhase

    @State private var keyboardDetected = false
    @AppStorage(SharedKeys.onboardingFullAccessVerified, store: AppGroup.defaults)
    private var fullAccessHandshake = false

    /// Guard to prevent concurrent keyboard checks while returning from Settings.
    @State private var isCheckingKeyboard = false

    /// Cancels delayed checks when this page disappears.
    @State private var keyboardCheckTask: Task<Void, Never>?

    private var setupStatus: KeyboardSetupStatus {
        KeyboardSetupStatus(
            keyboardInstalled: keyboardDetected,
            fullAccessHandshake: fullAccessHandshake
        )
    }

    // The following stage performs the first real keyboard interaction and can
    // establish the handshake when the user switches to sAiity.
    private var canContinue: Bool { keyboardDetected }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Label("Set up the sAiity keyboard", systemImage: "keyboard")
                    .font(.title2.weight(.semibold))

                Text("Add sAiity in iPhone Settings. Full Access is confirmed only after the keyboard appears with its real permission state.")
                    .font(.body)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 16) {
                    statusRow(
                        title: "Keyboard installed",
                        detail: keyboardDetected ? "Installed" : "Not detected yet",
                        done: keyboardDetected
                    )
                    statusRow(
                        title: "Full Access",
                        detail: fullAccessDetail,
                        done: setupStatus.fullAccessVerified
                    )
                }

                Button(action: openSettings) {
                    Label("Open Keyboard Settings", systemImage: "gearshape")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Text("In Settings, open General > Keyboard > Keyboards, add sAiity, and enable Allow Full Access.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if setupStatus.fullAccessVerified {
                    Label("Full Access verified by the sAiity keyboard", systemImage: "checkmark.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.green)
                }

                Button("Continue", action: onNext)
                    .frame(maxWidth: .infinity)
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(!canContinue)
                    .accessibilityHint(canContinue ? "Continue to the first dictation" : "Add the sAiity keyboard first")
            }
            .frame(maxWidth: 560)
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .onAppear {
            checkKeyboardInstalled()
        }
        .onDisappear {
            keyboardCheckTask?.cancel()
            keyboardCheckTask = nil
        }
        .onChange(of: scenePhase) { newPhase in
            // Returning from Settings can publish .active before iOS updates the
            // active input mode list, so use one guarded delayed check and retry.
            PersistentLog.log(.onboardingScenePhaseChanged(phase: "\(newPhase)"))

            if newPhase != .active {
                keyboardCheckTask?.cancel()
                keyboardCheckTask = nil
                isCheckingKeyboard = false
                return
            }

            guard !isCheckingKeyboard else {
                PersistentLog.log(.onboardingKeyboardCheckSkipped(reason: "alreadyChecking"))
                return
            }
            isCheckingKeyboard = true

            keyboardCheckTask?.cancel()
            keyboardCheckTask = Task {
                try? await Task.sleep(for: .milliseconds(800))
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard !Task.isCancelled else { return }
                    checkKeyboardInstalled()
                }

                if !keyboardDetected && !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(1200))
                    guard !Task.isCancelled else { return }
                    await MainActor.run {
                        guard !Task.isCancelled else { return }
                        PersistentLog.log(.onboardingKeyboardRetry)
                        checkKeyboardInstalled()
                        isCheckingKeyboard = false
                    }
                } else {
                    await MainActor.run {
                        isCheckingKeyboard = false
                    }
                }
            }
        }
    }

    private var fullAccessDetail: String {
        if setupStatus.fullAccessVerified {
            return "Verified by the sAiity keyboard"
        }
        if setupStatus.keyboardInstalled {
            return "Not verified yet. Enable Full Access, then use sAiity once."
        }
        return "Add sAiity first. Full Access is verified when the keyboard appears."
    }

    private func statusRow(title: String, detail: String, done: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(done ? .green : .secondary)
                .font(.title3)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body.weight(.medium))
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(done ? "Complete" : detail)
    }

    /// Checks installation through the public active-input-mode list. Full Access
    /// comes only from the keyboard extension's real `hasFullAccess` handshake.
    private func checkKeyboardInstalled() {
        let modes = UITextInputMode.activeInputModes
        PersistentLog.log(.onboardingKeyboardCheckStarted(modeCount: modes.count))

        let identifier = modes.compactMap { $0.value(forKey: "identifier") as? String }
            .first { $0.contains("de.aiity.saiity.ios") }
        let inputModeInstalled = identifier != nil
        // The extension's handshake is the only real Full Access signal. iOS
        // can temporarily omit a third-party keyboard from activeInputModes
        // while it refreshes Settings, so do not erase a valid handshake here.
        let handshake = AppGroup.defaults.bool(forKey: SharedKeys.onboardingFullAccessVerified)
        let installed = inputModeInstalled || handshake

        keyboardDetected = installed
        fullAccessHandshake = handshake

        if let identifier {
            PersistentLog.log(.onboardingKeyboardDetected(identifier: identifier))
        } else {
            PersistentLog.log(.onboardingKeyboardNotFound(modeCount: modes.count))
        }

        let status = KeyboardSetupStatus(keyboardInstalled: installed, fullAccessHandshake: handshake)
        let announcement: String
        if status.fullAccessVerified {
            announcement = "sAiity keyboard and Full Access verified"
        } else if status.keyboardInstalled {
            announcement = "sAiity keyboard detected; Full Access is not verified yet"
        } else {
            announcement = "sAiity keyboard not detected"
        }
        UIAccessibility.post(notification: .announcement, argument: announcement)
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
