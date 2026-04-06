import SwiftUI

struct AddEnvVarSheet: View {
    let sandboxName: String
    @Environment(EnvVarStore.self) private var envVarStore
    @Environment(ToastManager.self) private var toastManager
    @Environment(\.dismiss) private var dismiss
    @State private var key = ""
    @State private var value = ""
    @State private var keyError: String?
    @State private var isSubmitting = false

    var body: some View {
        VStack(spacing: 20) {
            Text("Add Environment Variable")
                .font(.ui(18, weight: .semibold))

            VStack(alignment: .leading, spacing: 8) {
                Text("Key")
                    .font(.label(12))
                    .foregroundStyle(.secondary)
                TextField("API_KEY", text: $key)
                    .font(.code(14))
                    .textFieldStyle(.roundedBorder)
                    .disableAutocorrection(true)
                    .onChange(of: key) { validateKey() }
                    .accessibilityIdentifier("envVarKeyField")

                if let error = keyError {
                    Text(error)
                        .font(.ui(11))
                        .foregroundStyle(Color.error)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Value")
                    .font(.label(12))
                    .foregroundStyle(.secondary)
                TextField("sk-...", text: $value)
                    .font(.code(14))
                    .textFieldStyle(.roundedBorder)
                    .disableAutocorrection(true)
                    .accessibilityIdentifier("envVarValueField")
            }

            Spacer()

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button {
                    submit()
                } label: {
                    if isSubmitting {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Adding\u{2026}")
                        }
                    } else {
                        Text("Add")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.accent)
                .disabled(!isValid || isSubmitting)
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("submitEnvVarButton")
            }
        }
        .padding(24)
        .frame(width: 420, height: 280)
        .background(Color.surfaceContainer)
    }

    private var isValid: Bool {
        !key.isEmpty && !value.isEmpty && keyError == nil
    }

    private func validateKey() {
        if key.isEmpty {
            keyError = nil
            return
        }
        if !SbxValidation.isValidEnvKey(key) {
            keyError = "Must start with a letter or underscore, then letters, digits, or underscores"
        } else {
            keyError = nil
        }
    }

    private func submit() {
        isSubmitting = true
        Task {
            do {
                try await envVarStore.addEnvVar(sandboxName: sandboxName, key: key, value: value)
                dismiss()
            } catch {
                toastManager.show(error.localizedDescription)
                isSubmitting = false
            }
        }
    }
}
