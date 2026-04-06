import SwiftUI
import AppKit

struct SandboxCardView: View {
    let sandbox: Sandbox
    var onSelect: (Sandbox) -> Void
    var onOpenShellSession: (String) -> Void
    @Environment(SandboxStore.self) private var sandboxStore
    @Environment(TerminalSessionStore.self) private var sessionStore
    @Environment(EnvVarStore.self) private var envVarStore
    @Environment(ToastManager.self) private var toastManager
    @State private var isHovered = false
    @State private var showTerminateConfirm = false
    @State private var showEnvVarSheet = false

    private var isTransient: Bool {
        sandbox.status == .creating || sandbox.status == .removing || sandboxStore.isBusy(sandbox.name)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Tappable content area (click to open session or resume)
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
                    if sessionStore.hasAnySession(sandboxName: sandbox.name) {
                        HStack(spacing: 3) {
                            Image(systemName: "terminal.fill")
                                .font(.system(size: 9))
                            Text("SESSION")
                                .font(.label(9))
                        }
                        .foregroundStyle(Color.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .accessibilityIdentifier("sessionBadge-\(sandbox.name)")
                    }
                    StatusChipView(status: sandbox.status)
                }

                // Workspace path
                Text(sandbox.workspace)
                    .font(.code(11))
                    .foregroundStyle(Color.surfaceContainerHighest)
                    .lineLimit(1)
                    .truncationMode(.middle)

                // Terminal thumbnail (show agent session thumbnail)
                if let agentID = sessionStore.agentSessionID(for: sandbox.name) {
                    Group {
                        if let thumbnail = sessionStore.thumbnails[agentID] {
                            Image(nsImage: thumbnail)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(maxWidth: .infinity)
                                .frame(height: 120)
                                .clipped()
                        } else {
                            HStack(spacing: 8) {
                                Image(systemName: "terminal")
                                    .font(.system(size: 16))
                                    .foregroundStyle(.tertiary)
                                Text("Connecting...")
                                    .font(.code(11))
                                    .foregroundStyle(.tertiary)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 120)
                        }
                    }
                    .background(Color.surfaceLowest)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .accessibilityIdentifier("sessionThumbnail-\(sandbox.name)")
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if sandbox.status == .running {
                    onSelect(sandbox)
                } else if sandbox.status == .stopped && !sandboxStore.isBusy(sandbox.name) {
                    Task {
                        do {
                            try await sandboxStore.resumeSandbox(name: sandbox.name)
                        } catch {
                            toastManager.show(error.localizedDescription)
                        }
                    }
                }
            }

            // Port chips + ENV chip (outside tap gesture area)
            HStack(spacing: 6) {
                ForEach(sandbox.ports) { port in
                    Text("\(port.hostPort)\u{2192}\(port.sandboxPort)")
                        .font(.code(10))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.surfaceContainerHigh)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }

                Button {
                    showEnvVarSheet = true
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "key.fill")
                            .font(.system(size: 9))
                        Text("ENV")
                            .font(.label(9))
                        let count = envVarStore.vars(for: sandbox.name).count
                        if count > 0 {
                            Text("\(count)")
                                .font(.code(9, weight: .bold))
                        }
                    }
                    .foregroundStyle(Color.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("envVarButton-\(sandbox.name)")
            }

            // Actions (outside tap gesture area)
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
                        if sandboxStore.busyOperations[sandbox.name] == .stopping {
                            ProgressView()
                                .controlSize(.mini)
                        } else {
                            Image(systemName: "pause.fill")
                                .font(.system(size: 11))
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(isTransient)
                    .accessibilityIdentifier("stopButton-\(sandbox.name)")

                    // Open in-app shell session
                    Button {
                        let (id, _) = sessionStore.startSession(sandboxName: sandbox.name, type: .shell)
                        onOpenShellSession(id)
                    } label: {
                        Image(systemName: "terminal")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("openShellButton-\(sandbox.name)")

                    // Copy exec command to clipboard
                    Button {
                        let command = "sbx exec -it \(sandbox.name) bash"
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(command, forType: .string)
                        toastManager.show("Copied: \(command)", isError: false)
                    } label: {
                        Image(systemName: "doc.on.clipboard")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("copyCommandButton-\(sandbox.name)")
                }

                Spacer()

                Button(role: .destructive) {
                    showTerminateConfirm = true
                } label: {
                    if sandboxStore.busyOperations[sandbox.name] == .removing {
                        HStack(spacing: 4) {
                            ProgressView()
                                .controlSize(.mini)
                            Text("Removing\u{2026}")
                                .font(.ui(11))
                        }
                    } else {
                        Text("Terminate")
                            .font(.ui(11))
                    }
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
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .overlay {
            if sandboxStore.busyOperations[sandbox.name] == .resuming {
                RoundedRectangle(cornerRadius: DesignSystem.cornerRadius)
                    .fill(Color.surfaceLowest.opacity(0.6))
                    .overlay {
                        VStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.regular)
                            Text("Resuming\u{2026}")
                                .font(.ui(12))
                                .foregroundStyle(.secondary)
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
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sandboxCard-\(sandbox.name)")
        .sheet(isPresented: $showEnvVarSheet) {
            EnvVarPanelView(sandbox: sandbox)
        }
    }
}
