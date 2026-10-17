import SwiftUI
import SyllivraKernel

struct OnboardingSuccessView: View {
    let onComplete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label("Dictation received", systemImage: "checkmark.circle")
                .font(.title2.weight(.semibold)).foregroundStyle(.tint)
            Text("Your keyboard is connected. You’re ready to write with your voice.")
                .foregroundStyle(.secondary)
            Button(action: onComplete) {
                Label("Finish setup", systemImage: "checkmark")
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
        }
        .padding(.vertical, 24)
    }
}
