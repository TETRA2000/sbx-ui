import SwiftUI

struct PluginDetailView: View {
    let plugin: PluginManifest
    @Environment(PluginStore.self) private var pluginStore
    @Environment(\.dismiss) private var dismiss

    private var isRunning: Bool {
        pluginStore.isRunning(id: plugin.id)
    }

    private var outputs: [String] {
        pluginStore.pluginOutputs[plugin.id] ?? []
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(plugin.name)
                        .font(.ui(18, weight: .bold))
                    Text(plugin.id)
                        .font(.code(11))
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.bordered)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Metadata
                    GroupBox("Info") {
                        LabeledContent("Version", value: plugin.version)
                        LabeledContent("Entry", value: plugin.entry)
                        if let runtime = plugin.runtime {
                            LabeledContent("Runtime", value: runtime)
                        }
                        LabeledContent("Status", value: isRunning ? "Running" : "Stopped")
                    }
                    .font(.ui(13))

                    // Permissions
                    GroupBox("Permissions") {
                        if plugin.permissions.isEmpty {
                            Text("No permissions required")
                                .font(.ui(12))
                                .foregroundStyle(.secondary)
                        } else {
                            FlowLayout(spacing: 6) {
                                ForEach(plugin.permissions, id: \.rawValue) { perm in
                                    HStack(spacing: 4) {
                                        Image(systemName: iconForPermission(perm))
                                            .font(.system(size: 10))
                                        Text(perm.displayName)
                                            .font(.ui(11))
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.surfaceContainerHigh)
                                    .clipShape(Capsule())
                                }
                            }
                        }
                    }

                    // Triggers
                    GroupBox("Triggers") {
                        if plugin.triggers.isEmpty {
                            Text("No triggers configured")
                                .font(.ui(12))
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(plugin.triggers, id: \.rawValue) { trigger in
                                HStack(spacing: 6) {
                                    Image(systemName: "bolt.fill")
                                        .font(.system(size: 10))
                                        .foregroundStyle(Color.accent)
                                    Text(triggerDescription(trigger))
                                        .font(.ui(12))
                                }
                            }
                        }
                    }

                    // Output log
                    GroupBox("Output") {
                        if outputs.isEmpty {
                            Text("No output yet")
                                .font(.code(11))
                                .foregroundStyle(.secondary)
                        } else {
                            ScrollView {
                                VStack(alignment: .leading, spacing: 2) {
                                    ForEach(Array(outputs.enumerated()), id: \.offset) { _, line in
                                        Text(line)
                                            .font(.code(11))
                                            .textSelection(.enabled)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(maxHeight: 200)
                        }

                        if !outputs.isEmpty {
                            Button("Clear") {
                                pluginStore.clearOutput(pluginId: plugin.id)
                            }
                            .font(.ui(11))
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                        }
                    }

                    // Actions
                    HStack(spacing: 12) {
                        Button {
                            Task {
                                if isRunning {
                                    await pluginStore.stopPlugin(id: plugin.id)
                                } else {
                                    await pluginStore.startPlugin(id: plugin.id)
                                }
                            }
                        } label: {
                            Label(isRunning ? "Stop" : "Start", systemImage: isRunning ? "stop.fill" : "play.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(isRunning ? .red : Color.accent)

                        Button(role: .destructive) {
                            uninstallPlugin()
                        } label: {
                            Label("Uninstall", systemImage: "trash")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding()
            }
        }
        .frame(width: 480, height: 560)
        .background(Color.surface)
    }

    private func iconForPermission(_ perm: PluginPermission) -> String {
        switch perm {
        case .sandboxList, .sandboxExec, .sandboxStop, .sandboxRun: "server.rack"
        case .portsList, .portsPublish, .portsUnpublish: "network"
        case .envVarList, .envVarSync: "list.bullet"
        case .policyList, .policyAllow, .policyDeny, .policyRemove: "shield.lefthalf.filled"
        case .fileRead, .fileWrite: "doc"
        case .uiNotify, .uiLog: "bell"
        }
    }

    private func triggerDescription(_ trigger: PluginTrigger) -> String {
        switch trigger {
        case .manual: "Run manually"
        case .onSandboxCreated: "When a sandbox is created"
        case .onSandboxStopped: "When a sandbox is stopped"
        case .onSandboxRemoved: "When a sandbox is removed"
        case .onAppLaunch: "When the app launches"
        }
    }

    private func uninstallPlugin() {
        Task {
            if isRunning {
                await pluginStore.stopPlugin(id: plugin.id)
            }
            if let dir = plugin.directory {
                try? FileManager.default.removeItem(at: dir)
            }
            try? PluginApprovalStore.revoke(pluginId: plugin.id)
            await pluginStore.refresh()
            dismiss()
        }
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > maxWidth, currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            positions.append(CGPoint(x: currentX, y: currentY))
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
        }

        return (CGSize(width: maxWidth, height: currentY + lineHeight), positions)
    }
}
