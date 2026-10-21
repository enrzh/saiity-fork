import SwiftUI
import UIKit
import Combine
import SyllivraKernel

/// One observer owns setup permission state across all onboarding pages.
@MainActor final class KeyboardSetupModel: ObservableObject {
    static let shared = KeyboardSetupModel()
    @Published private(set) var keyboardInstalled = false
    @Published private(set) var fullAccessVerified = false
    @Published private(set) var fullAccessDenied = false

    private init() {
        DarwinNotificationCenter.addObserver(for: DarwinNotificationName.keyboardFullAccessChanged) {
            DispatchQueue.main.async { Self.shared.refresh() }
        }
        DarwinNotificationCenter.addObserver(for: DarwinNotificationName.keyboardFullAccessDenied) {
            DispatchQueue.main.async {
                let model = Self.shared
                model.keyboardInstalled = true
                model.fullAccessVerified = false
                model.fullAccessDenied = true
                AppGroup.defaults.set(false, forKey: SharedKeys.onboardingFullAccessVerified)
                AppGroup.defaults.synchronize()
            }
        }
        refresh()
    }

    func refresh() {
        AppGroup.defaults.synchronize()
        let installed = UITextInputMode.activeInputModes.contains {
            KeyboardSetupStatus.isDictusKeyboardIdentifier($0.value(forKey: "identifier") as? String)
        }
        let verified = KeyboardSetupStatus.isCurrentFullAccessHandshake(
            verified: AppGroup.defaults.bool(forKey: SharedKeys.onboardingFullAccessVerified),
            probe: AppGroup.defaults.string(forKey: SharedKeys.onboardingFullAccessProbe),
            acknowledgedProbe: AppGroup.defaults.string(forKey: SharedKeys.onboardingFullAccessAcknowledgedProbe))
        keyboardInstalled = installed || verified
        fullAccessVerified = verified
        if verified { fullAccessDenied = false }
    }

    func beginVerification() {
        AppGroup.defaults.set(UUID().uuidString, forKey: SharedKeys.onboardingFullAccessProbe)
        AppGroup.defaults.removeObject(forKey: SharedKeys.onboardingFullAccessAcknowledgedProbe)
        AppGroup.defaults.synchronize()
        fullAccessVerified = false
        fullAccessDenied = false
    }

    func requestProbe() {
        DarwinNotificationCenter.post(DarwinNotificationName.keyboardFullAccessProbeRequested)
        refresh()
    }
}

struct KeyboardSetupCard: View {
    @ObservedObject private var setup = KeyboardSetupModel.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var returningFromSettings = false
    @State private var testText = ""
    @FocusState private var checkingKeyboard: Bool

    var body: some View {
        GroupBox {
        VStack(alignment: .leading, spacing: 16) {
            status("Syllivra keyboard", done: setup.keyboardInstalled, detail: "Add it in iPhone Settings")
            status("Full Access", done: setup.fullAccessVerified,
                   detail: setup.fullAccessDenied ? "Off · enable Allow Full Access in Settings" : "Choose Syllivra below to verify the current permission")
            Text("In Settings, tap Keyboards, then turn on Syllivra and Allow Full Access.")
                .font(.subheadline).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Open Settings") {
                setup.beginVerification()
                checkingKeyboard = false
                returningFromSettings = true
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }.buttonStyle(.borderedProminent).controlSize(.large)
            TextField("Tap here, then choose Syllivra with the globe", text: $testText)
                .textFieldStyle(.roundedBorder).autocorrectionDisabled().focused($checkingKeyboard)
                .accessibilityIdentifier("setup.keyboard-check")
            Text("The keyboard confirms Full Access itself. Nothing is recorded for this check.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        }
        .onAppear { setup.beginVerification(); setup.refresh() }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            setup.refresh()
            if returningFromSettings { checkingKeyboard = true; returningFromSettings = false }
        }
        .task(id: checkingKeyboard && scenePhase == .active) {
            guard checkingKeyboard, scenePhase == .active else { return }
            while !Task.isCancelled && !setup.fullAccessVerified {
                setup.requestProbe()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func status(_ title: String, done: Bool, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle").foregroundStyle(done ? Color.accentColor : .secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(done ? "Verified" : detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }.accessibilityElement(children: .combine)
    }
}

struct KeyboardSetupPage: View {
    var body: some View {
        ScrollView {
            KeyboardSetupCard().fullWidthButtons().padding(20).frame(maxWidth: 560)
        }
        .navigationTitle("Keyboard Setup")
        .navigationBarTitleDisplayMode(.inline)
    }
}
