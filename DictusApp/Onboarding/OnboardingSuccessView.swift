import SwiftUI
import DictusCore

struct OnboardingSuccessView: View {
    let onComplete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label("Your first words. Delivered.", systemImage: "checkmark.seal.fill")
                .font(.title2.weight(.semibold)).foregroundStyle(.tint)
            Text("Your keyboard is connected. You’re ready to write with your voice.")
                .foregroundStyle(.secondary)
            Button(action: onComplete) {
                HStack { Text("Make yourself heard"); Spacer(); Image(systemName: "arrow.right") }
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
        }
        .padding(24)
        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 28))
    }
}
