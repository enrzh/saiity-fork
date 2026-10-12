import SwiftUI
import DictusCore

struct WelcomePage: View {
    let onNext: () -> Void
    var onKeyboardSetup: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            DictusLogo(height: 40, foregroundOnly: true)
            SaiityPageHeader(title: "Write with your voice",
                             subtitle: "Speak here, or use sAiity wherever you type.")
            VStack(alignment: .leading, spacing: 16) {
                benefit("Edit your words", detail: "Review, copy or recover the original text.", icon: "text.cursor")
                benefit("Your languages", detail: "Choose the languages you speak.", icon: "globe")
                benefit("On your iPhone", detail: "Download once for offline voice recognition.", icon: "iphone")
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
