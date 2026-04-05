import SwiftUI

struct AddPolicySheet: View {
    @Environment(PolicyStore.self) private var policyStore
    @Environment(ToastManager.self) private var toastManager
    @Environment(\.dismiss) private var dismiss
    @State private var domains = ""
    @State private var decision: PolicyDecision = .allow
    @State private var domainError: String?
    @State private var isSubmitting = false

    var body: some View {
        VStack(spacing: 20) {
            Text("Add Policy Rule")
                .font(.ui(18, weight: .semibold))

            VStack(alignment: .leading, spacing: 8) {
                Text("Domains (comma-separated)")
                    .font(.label(12))
                    .foregroundStyle(.secondary)

                TextField("api.example.com, *.example.org", text: $domains)
                    .font(.code(12))
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: domains) {
                        validateDomains()
                    }
                    .accessibilityIdentifier("domainInput")

                if let error = domainError {
                    Text(error)
                        .font(.ui(11))
                        .foregroundStyle(Color.error)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Decision")
                    .font(.label(12))
                    .foregroundStyle(.secondary)

                Picker("Decision", selection: $decision) {
                    Text("Allow").tag(PolicyDecision.allow)
                    Text("Deny").tag(PolicyDecision.deny)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("decisionPicker")
            }

            Spacer()

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button {
                    submitPolicy()
                } label: {
                    if isSubmitting {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Adding\u{2026}")
                        }
                    } else {
                        Text("Add Rule")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(decision == .allow ? Color.secondary : Color.error)
                .disabled(domains.trimmingCharacters(in: .whitespaces).isEmpty || domainError != nil || isSubmitting)
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("submitPolicyButton")
            }
        }
        .padding(24)
        .frame(width: 420, height: 280)
        .background(Color.surfaceContainer)
    }

    private func validateDomains() {
        let trimmed = domains.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            domainError = nil
            return
        }
        if trimmed == "*" {
            domainError = "Catch-all patterns are not allowed"
            return
        }
        domainError = nil
    }

    private func submitPolicy() {
        let trimmed = domains.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        isSubmitting = true
        Task {
            do {
                switch decision {
                case .allow:
                    try await policyStore.addAllow(resources: trimmed)
                case .deny:
                    try await policyStore.addDeny(resources: trimmed)
                }
                dismiss()
            } catch {
                toastManager.show(error.localizedDescription)
                isSubmitting = false
            }
        }
    }
}
