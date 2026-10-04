import SwiftUI
import DictusCore

struct WelcomePage: View {
    let onNext: () -> Void
    var onKeyboardSetup: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            DictusLogo(height: 40, foregroundOnly: true)
            SaiityPageHeader(title: "Write with your voice",
                             subtitle: "Dictate into the apps you use, with voice recognition on your iPhone.")
            VStack(alignment: .leading, spacing: 16) {
                benefit("Your keyboard", detail: "Speak where you would normally type.", icon: "keyboard")
                benefit("Your languages", detail: "Choose a model that supports the languages you speak.", icon: "globe")
                benefit("On your iPhone", detail: "Download a voice model once to use it offline.", icon: "iphone")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onNext) {
                SaiityVoiceActionLabel("Speak here", systemImage: "arrow.right")
            }
            .buttonStyle(SaiityPrimaryActionStyle())
            if let onKeyboardSetup {
                Button("Use in other apps", action: onKeyboardSetup)
                    .buttonStyle(.bordered).controlSize(.large)
                    .accessibilityIdentifier("onboarding.keyboardPath")
            }
        }
    }

    private func benefit(_ title: LocalizedStringKey, detail: LocalizedStringKey, icon: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon).font(.title3).foregroundStyle(.tint).frame(width: 28)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}
