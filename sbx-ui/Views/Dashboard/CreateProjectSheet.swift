import SwiftUI
import UniformTypeIdentifiers

struct CreateProjectSheet: View {
    @Environment(SandboxStore.self) private var sandboxStore
    @Environment(ToastManager.self) private var toastManager
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPath: URL?
    @State private var customName = ""
    @State private var showFilePicker = false
    @State private var nameError: String?
    @State private var isCreating = false

    // Name validation uses SbxValidation.isValidName()

    var body: some View {
        VStack(spacing: 20) {
            Text("Deploy Agent")
                .font(.ui(18, weight: .semibold))

            // Directory picker
            VStack(alignment: .leading, spacing: 8) {
                Text("Workspace Directory")
                    .font(.label(12))
                    .foregroundStyle(.secondary)

                HStack {
                    if let path = selectedPath {
                        Text(path.path(percentEncoded: false))
                            .font(.code(12))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text("Select a directory...")
                            .font(.code(12))
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Button("Browse") {
                        showFilePicker = true
                    }
                    .accessibilityIdentifier("browseButton")
                }
                .padding(10)
                .background(Color.surfaceContainerHigh)
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.cornerRadius))
            }

            // Optional name
            VStack(alignment: .leading, spacing: 8) {
                Text("Name (optional)")
                    .font(.label(12))
                    .foregroundStyle(.secondary)

                TextField("claude-<dirname>", text: $customName)
                    .font(.code(12))
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: customName) {
                        validateName()
                    }
                    .accessibilityIdentifier("sandboxNameField")

                if let error = nameError {
                    Text(error)
                        .font(.ui(11))
                        .foregroundStyle(Color.error)
                }
            }

            Spacer()

            // Actions
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button {
                    createSandbox()
                } label: {
                    if isCreating {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Deploying\u{2026}")
                        }
                    } else {
                        Text("Deploy")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.accent)
                .disabled(selectedPath == nil || nameError != nil || isCreating)
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("deployButton")
            }
        }
        .padding(24)
        .frame(width: 480, height: 320)
        .background(Color.surfaceContainer)
        .onAppear {
            if ProcessInfo.processInfo.environment["SBX_CLI_MOCK"] == "1" {
                selectedPath = URL(fileURLWithPath: "/tmp/mock-project")
            }
        }
        .fileImporter(isPresented: $showFilePicker, allowedContentTypes: [.folder]) { result in
            switch result {
            case .success(let url):
                selectedPath = url
            case .failure:
                break
            }
        }
    }

    private func validateName() {
        if customName.isEmpty {
            nameError = nil
            return
        }
        if !SbxValidation.isValidName(customName) {
            nameError = "Lowercase alphanumeric and hyphens only, no leading hyphen"
        } else {
            nameError = nil
        }
    }

    private func createSandbox() {
        guard let path = selectedPath else { return }
        isCreating = true
        Task {
            do {
                try await sandboxStore.createSandbox(
                    workspace: path.path(percentEncoded: false),
                    name: customName.isEmpty ? nil : customName
                )
                dismiss()
            } catch {
                toastManager.show(error.localizedDescription)
                isCreating = false
            }
        }
    }
}
