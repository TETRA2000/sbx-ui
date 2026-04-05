import SwiftUI

struct EnvVarPanelView: View {
    let sandbox: Sandbox
    @Environment(EnvVarStore.self) private var envVarStore
    @Environment(ToastManager.self) private var toastManager
    @State private var showAddSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Environment Variables")
                    .font(.ui(16, weight: .semibold))
                Spacer()
                Button {
                    showAddSheet = true
                } label: {
                    Label("Add Variable", systemImage: "plus")
                        .font(.ui(11))
                }
                .buttonStyle(.bordered)
                .disabled(sandbox.status != .running)
                .accessibilityIdentifier("addEnvVarButton")
            }

            Text("Managed via /etc/sandbox-persistent.sh")
                .font(.ui(11))
                .foregroundStyle(.tertiary)

            if sandbox.status == .stopped {
                Text("Start the sandbox to manage environment variables.")
                    .font(.ui(11))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            }

            let vars = envVarStore.vars(for: sandbox.name)
            if envVarStore.loading.contains(sandbox.name) && vars.isEmpty {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading\u{2026}")
                        .font(.ui(11))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            } else if vars.isEmpty {
                Text("No environment variables")
                    .font(.ui(12))
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 8)
            } else {
                ForEach(vars) { envVar in
                    EnvVarRow(sandbox: sandbox, envVar: envVar)
                }
            }
        }
        .padding(20)
        .frame(width: 480)
        .background(Color.surfaceContainer)
        .sheet(isPresented: $showAddSheet) {
            AddEnvVarSheet(sandboxName: sandbox.name)
        }
        .task {
            if sandbox.status == .running {
                await envVarStore.fetchEnvVars(for: sandbox.name)
            }
        }
    }
}

struct EnvVarRow: View {
    let sandbox: Sandbox
    let envVar: EnvVar
    @Environment(EnvVarStore.self) private var envVarStore
    @Environment(ToastManager.self) private var toastManager

    private var busyKey: String { "\(sandbox.name):\(envVar.key)" }

    var body: some View {
        HStack {
            Text(envVar.key)
                .font(.code(13, weight: .bold))
                .foregroundStyle(Color.accent)
            Text("=")
                .font(.code(11))
                .foregroundStyle(.secondary)
            Text(envVar.value)
                .font(.code(12))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer()
            Button {
                Task {
                    do {
                        try await envVarStore.removeEnvVar(sandboxName: sandbox.name, key: envVar.key)
                    } catch {
                        toastManager.show(error.localizedDescription)
                    }
                }
            } label: {
                if envVarStore.removingKeys.contains(busyKey) {
                    ProgressView()
                        .controlSize(.mini)
                } else {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.error.opacity(0.7))
                }
            }
            .buttonStyle(.plain)
            .disabled(envVarStore.removingKeys.contains(busyKey) || sandbox.status != .running)
            .accessibilityIdentifier("removeEnvVar-\(envVar.key)")
        }
        .padding(.vertical, 4)
    }
}
