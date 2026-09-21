import SwiftUI
import DictusCore

struct WelcomePage: View {
    let onNext: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            DictusLogo(height: 48)
            SaiityPageHeader(eyebrow: "HELLO, SAIITY", title: "Think it.\nSay it.\nSend it.",
                             subtitle: "A private voice keyboard for everything you want to say.")
            VStack(alignment: .leading, spacing: 16) {
                benefit("Stay in your flow", detail: "Dictate into the apps you already use.", icon: "keyboard")
                benefit("Keep your languages", detail: "Multilingual models keep your words in their spoken language.", icon: "globe")
                benefit("Make it yours", detail: "Choose a local voice model. Audio stays on your iPhone.", icon: "iphone")
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 28))
            Button(action: onNext) {
                HStack { Text("Let’s set you up"); Spacer(); Image(systemName: "arrow.right") }
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
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
