import SwiftUI

struct AddPortSheet: View {
    let sandboxName: String
    @Environment(SandboxStore.self) private var sandboxStore
    @Environment(ToastManager.self) private var toastManager
    @Environment(\.dismiss) private var dismiss
    @State private var hostPortText = ""
    @State private var sbxPortText = ""
    @State private var portError: String?
    @State private var isSubmitting = false

    var body: some View {
        VStack(spacing: 20) {
            Text("Publish Port")
                .font(.ui(18, weight: .semibold))

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Host Port")
                        .font(.label(12))
                        .foregroundStyle(.secondary)
                    TextField("8080", text: $hostPortText)
                        .font(.code(14))
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: hostPortText) { validatePorts() }
                        .accessibilityIdentifier("hostPortField")
                }

                Image(systemName: "arrow.right")
                    .foregroundStyle(.secondary)
                    .padding(.top, 20)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Sandbox Port")
                        .font(.label(12))
                        .foregroundStyle(.secondary)
                    TextField("3000", text: $sbxPortText)
                        .font(.code(14))
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: sbxPortText) { validatePorts() }
                        .accessibilityIdentifier("sbxPortField")
                }
            }

            if let error = portError {
                Text(error)
                    .font(.ui(11))
                    .foregroundStyle(Color.error)
            }

            Spacer()

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Publish") { publishPort() }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.accent)
                    .disabled(!isValid || isSubmitting)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("publishPortButton")
            }
        }
        .padding(24)
        .frame(width: 400, height: 240)
        .background(Color.surfaceContainer)
    }

    private var isValid: Bool {
        guard let host = Int(hostPortText), let sbx = Int(sbxPortText) else { return false }
        return host >= 1 && host <= 65535 && sbx >= 1 && sbx <= 65535 && portError == nil
    }

    private func validatePorts() {
        portError = nil
        if let h = Int(hostPortText), (h < 1 || h > 65535) {
            portError = "Host port must be between 1 and 65535"
        }
        if let s = Int(sbxPortText), (s < 1 || s > 65535) {
            portError = "Sandbox port must be between 1 and 65535"
        }
        if !hostPortText.isEmpty, Int(hostPortText) == nil {
            portError = "Port must be a number"
        }
        if !sbxPortText.isEmpty, Int(sbxPortText) == nil {
            portError = "Port must be a number"
        }
    }

    private func publishPort() {
        guard let host = Int(hostPortText), let sbx = Int(sbxPortText) else { return }
        isSubmitting = true
        Task {
            do {
                try await sandboxStore.publishPort(name: sandboxName, hostPort: host, sbxPort: sbx)
                dismiss()
            } catch {
                toastManager.show(error.localizedDescription)
                isSubmitting = false
            }
        }
    }
}
