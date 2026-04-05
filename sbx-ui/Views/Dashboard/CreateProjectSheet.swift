import SwiftUI
import UniformTypeIdentifiers

struct CreateProjectSheet: View {
    @Environment(SandboxStore.self) private var sandboxStore
    @Environment(EnvVarStore.self) private var envVarStore
    @Environment(ToastManager.self) private var toastManager
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPath: URL?
    @State private var customName = ""
    @State private var showFilePicker = false
    @State private var nameError: String?
    @State private var isCreating = false
    @State private var initialEnvVars: [EnvVar] = []
    @State private var showEnvVarSection = false
    @State private var newEnvKey = ""
    @State private var newEnvValue = ""
    @State private var envKeyError: String?

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

            // Environment variables (optional)
            VStack(alignment: .leading, spacing: 8) {
                Button {
                    withAnimation { showEnvVarSection.toggle() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: showEnvVarSection ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10))
                        Text("Environment Variables (optional)")
                            .font(.label(12))
                    }
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("envVarSectionToggle")

                if showEnvVarSection {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(initialEnvVars) { envVar in
                            HStack {
                                Text(envVar.key)
                                    .font(.code(11, weight: .bold))
                                    .foregroundStyle(Color.accent)
                                Text("=")
                                    .font(.code(11))
                                    .foregroundStyle(.secondary)
                                Text(envVar.value)
                                    .font(.code(11))
                                    .lineLimit(1)
                                Spacer()
                                Button {
                                    initialEnvVars.removeAll { $0.key == envVar.key }
                                } label: {
                                    Image(systemName: "xmark.circle")
                                        .font(.system(size: 11))
                                        .foregroundStyle(Color.error.opacity(0.7))
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        HStack(spacing: 8) {
                            TextField("KEY", text: $newEnvKey)
                                .font(.code(11))
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 140)
                                .onChange(of: newEnvKey) { validateEnvKey() }
                                .accessibilityIdentifier("createEnvKeyField")
                            TextField("value", text: $newEnvValue)
                                .font(.code(11))
                                .textFieldStyle(.roundedBorder)
                                .accessibilityIdentifier("createEnvValueField")
                            Button("Add") { addInitialEnvVar() }
                                .disabled(newEnvKey.isEmpty || newEnvValue.isEmpty || envKeyError != nil)
                                .accessibilityIdentifier("createAddEnvVarButton")
                        }

                        if let error = envKeyError {
                            Text(error)
                                .font(.ui(11))
                                .foregroundStyle(Color.error)
                        }
                    }
                    .padding(.top, 4)
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
        .frame(width: 480, height: 440)
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

    private func validateEnvKey() {
        if newEnvKey.isEmpty {
            envKeyError = nil
            return
        }
        if !SbxValidation.isValidEnvKey(newEnvKey) {
            envKeyError = "Letters, digits, and underscores only; must start with letter or underscore"
        } else {
            envKeyError = nil
        }
    }

    private func addInitialEnvVar() {
        guard !newEnvKey.isEmpty, !newEnvValue.isEmpty, envKeyError == nil else { return }
        initialEnvVars.removeAll { $0.key == newEnvKey }  // upsert
        initialEnvVars.append(EnvVar(key: newEnvKey, value: newEnvValue))
        newEnvKey = ""
        newEnvValue = ""
    }

    private func createSandbox() {
        guard let path = selectedPath else { return }
        isCreating = true
        Task {
            do {
                let sandbox = try await sandboxStore.createSandbox(
                    workspace: path.path(percentEncoded: false),
                    name: customName.isEmpty ? nil : customName
                )
                if !initialEnvVars.isEmpty {
                    try await envVarStore.syncInitialEnvVars(
                        sandboxName: sandbox.name,
                        vars: initialEnvVars
                    )
                }
                dismiss()
            } catch {
                toastManager.show(error.localizedDescription)
                isCreating = false
            }
        }
    }
}
