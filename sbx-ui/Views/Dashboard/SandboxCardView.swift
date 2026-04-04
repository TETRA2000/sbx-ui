import SwiftUI

struct SandboxCardView: View {
    let sandbox: Sandbox
    var onSelect: (Sandbox) -> Void
    @Environment(SandboxStore.self) private var sandboxStore
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(ToastManager.self) private var toastManager
    @State private var isHovered = false
    @State private var showTerminateConfirm = false

    private var isTransient: Bool {
        sandbox.status == .creating || sandbox.status == .removing
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(sandbox.name)
                        .font(.ui(15, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(sandbox.agent)
                        .font(.code(11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                StatusChipView(status: sandbox.status)
            }

            // Workspace path
            Text(sandbox.workspace)
                .font(.code(11))
                .foregroundStyle(Color.surfaceContainerHighest)
                .lineLimit(1)
                .truncationMode(.middle)

            // Port chips
            if !sandbox.ports.isEmpty {
                HStack(spacing: 6) {
                    ForEach(sandbox.ports) { port in
                        Text("\(port.hostPort)\u{2192}\(port.sandboxPort)")
                            .font(.code(10))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.surfaceContainerHigh)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
            }

            // Actions
            HStack(spacing: 8) {
                if sandbox.status == .running {
                    Button {
                        Task {
                            do {
                                try await sandboxStore.stopSandbox(name: sandbox.name)
                            } catch {
                                toastManager.show(error.localizedDescription)
                            }
                        }
                    } label: {
                        Image(systemName: "pause.fill")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.bordered)
                    .disabled(isTransient)
                    .accessibilityIdentifier("stopButton-\(sandbox.name)")

                    Button {
                        let launcher = ExternalTerminalLauncher()
                        Task {
                            do {
                                try await launcher.openShell(
                                    sandboxName: sandbox.name,
                                    app: settingsStore.preferredTerminal ?? .terminal
                                )
                            } catch {
                                toastManager.show(error.localizedDescription)
                            }
                        }
                    } label: {
                        Image(systemName: "terminal")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("openShellButton-\(sandbox.name)")
                }

                Spacer()

                Button(role: .destructive) {
                    showTerminateConfirm = true
                } label: {
                    Text("Terminate")
                        .font(.ui(11))
                }
                .buttonStyle(.bordered)
                .tint(Color.error)
                .disabled(isTransient)
                .accessibilityIdentifier("terminateButton-\(sandbox.name)")
            }
        }
        .padding(16)
        .background(isHovered ? Color.surfaceContainerHigh : Color.surfaceContainer)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.cornerRadius))
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .onTapGesture {
            if sandbox.status == .running {
                onSelect(sandbox)
            } else if sandbox.status == .stopped {
                Task {
                    do {
                        try await sandboxStore.resumeSandbox(name: sandbox.name)
                    } catch {
                        toastManager.show(error.localizedDescription)
                    }
                }
            }
        }
        .confirmationDialog("Terminate \(sandbox.name)?", isPresented: $showTerminateConfirm) {
            Button("Terminate Agent", role: .destructive) {
                Task {
                    do {
                        try await sandboxStore.removeSandbox(name: sandbox.name)
                    } catch {
                        toastManager.show(error.localizedDescription)
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently remove the sandbox and all its data.")
        }
        .accessibilityIdentifier("sandboxCard-\(sandbox.name)")
    }
}
