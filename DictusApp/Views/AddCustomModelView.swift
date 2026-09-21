import SwiftUI
import DictusCore

struct AddCustomModelView: View {
    @Environment(\.dismiss) private var dismiss

    let onSave: (CustomModel) -> Void

    @State private var name = ""
    @State private var repositoryURL = ""
    @State private var role = CustomModelRole.asr
    @State private var source = CustomModelSource.huggingFace
    @State private var modelName = ""
    @State private var validationMessage: String?
    @State private var isValidating = false

    private var model: CustomModel {
        CustomModel(
            name: name,
            repositoryURL: repositoryURL,
            role: role,
            source: source,
            modelName: modelName.isEmpty ? nil : modelName
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Role", selection: $role) {
                        ForEach(CustomModelRole.allCases, id: \.self) {
                            Text($0.displayName).tag($0)
                        }
                    }
                    Picker("Source", selection: $source) {
                        ForEach(availableSources, id: \.self) {
                            Text($0.displayName).tag($0)
                        }
                    }
                    TextField("Name", text: $name)
                    TextField("Repository URL", text: $repositoryURL)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                    if source == .ollama || (role == .asr && source == .huggingFace) {
                        TextField(source == .ollama ? "Ollama model name" : "WhisperKit variant (optional)", text: $modelName)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                } header: {
                    Text("Custom model")
                } footer: {
                    Text(footerText)
                }

                if let message = validationMessage ?? model.validationError {
                    Section {
                        Label(message, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Add custom model")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(model.validationError != nil || isValidating)
                }
            }
            .onChange(of: role) { _, newRole in
                validationMessage = nil
                if newRole == .asr && source == .ollama { source = .huggingFace }
                if newRole == .cleanup && source == .nvidia { source = .huggingFace }
            }
            .onChange(of: source) { _, _ in validationMessage = nil }
        }
    }

    private var availableSources: [CustomModelSource] {
        role == .asr ? [.huggingFace, .nvidia] : [.huggingFace, .ollama]
    }

    private var footerText: String {
        role == .asr
            ? "Custom speech recognition models are saved as configurations. Only compatible, verified WhisperKit exports can run in the current speech engine."
            : "Ollama cleanup models use the configured local or hosted endpoint."
    }

    private func save() {
        let candidate = model
        isValidating = true
        validationMessage = nil
        Task {
            let remoteError = await candidate.remoteValidationError()
            await MainActor.run {
                isValidating = false
                if let remoteError {
                    validationMessage = remoteError
                } else {
                    var verified = candidate
                    if verified.role == .asr && verified.source == .huggingFace {
                        verified.remoteValidationState = .verified
                    }
                    onSave(verified)
                    dismiss()
                }
            }
        }
    }
}
