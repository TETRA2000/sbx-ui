import SwiftUI

struct PortPanelView: View {
    let sandbox: Sandbox
    @Environment(SandboxStore.self) private var sandboxStore
    @Environment(ToastManager.self) private var toastManager
    @State private var showAddSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Port Forwarding")
                    .font(.ui(14, weight: .semibold))
                Spacer()
                Button {
                    showAddSheet = true
                } label: {
                    Label("Add Port", systemImage: "plus")
                        .font(.ui(11))
                }
                .buttonStyle(.bordered)
                .disabled(sandbox.status != .running)
                .accessibilityIdentifier("addPortButton")
            }

            if sandbox.status == .stopped {
                Text("Ports are cleared when sandbox stops.")
                    .font(.ui(11))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            }

            if sandbox.ports.isEmpty {
                Text("No port mappings")
                    .font(.ui(12))
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 8)
            } else {
                ForEach(sandbox.ports) { port in
                    PortMappingRow(sandbox: sandbox, port: port)
                }
            }
        }
        .padding(16)
        .background(Color.surfaceContainer)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.cornerRadius))
        .sheet(isPresented: $showAddSheet) {
            AddPortSheet(sandboxName: sandbox.name)
        }
    }
}

struct PortMappingRow: View {
    let sandbox: Sandbox
    let port: PortMapping
    @Environment(SandboxStore.self) private var sandboxStore
    @Environment(ToastManager.self) private var toastManager

    var body: some View {
        HStack {
            Text("\(port.hostPort)")
                .font(.code(13, weight: .bold))
                .foregroundStyle(Color.accent)
            Image(systemName: "arrow.right")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Text("\(port.sandboxPort)")
                .font(.code(13))
            Text(port.protocolType.uppercased())
                .font(.label(9))
                .foregroundStyle(.tertiary)
            Spacer()
            Button {
                Task {
                    do {
                        try await sandboxStore.unpublishPort(
                            name: sandbox.name,
                            hostPort: port.hostPort,
                            sbxPort: port.sandboxPort
                        )
                    } catch {
                        toastManager.show(error.localizedDescription)
                    }
                }
            } label: {
                if sandboxStore.busyOperations[sandbox.name] == .unpublishingPort {
                    ProgressView()
                        .controlSize(.mini)
                } else {
                    Image(systemName: "xmark.circle")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.error.opacity(0.7))
                }
            }
            .buttonStyle(.plain)
            .disabled(sandboxStore.busyOperations[sandbox.name] == .unpublishingPort)
            .accessibilityIdentifier("unpublishPort-\(port.hostPort)")
        }
        .padding(.vertical, 4)
    }
}
