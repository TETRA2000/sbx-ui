import SwiftUI
import UniformTypeIdentifiers

struct PluginListView: View {
    @Environment(PluginStore.self) private var pluginStore
    @State private var selectedPlugin: PluginManifest?
    @State private var showInstallPicker = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Plugins")
                        .font(.ui(20, weight: .bold))
                    Text("\(pluginStore.plugins.count) installed")
                        .font(.ui(12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    showInstallPicker = true
                } label: {
                    Label("Install Plugin", systemImage: "plus")
                        .font(.ui(12, weight: .medium))
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.accent)
                .accessibilityIdentifier("installPluginButton")
            }
            .padding()

            Divider()

            if pluginStore.plugins.isEmpty {
                ContentUnavailableView {
                    Label("No Plugins Installed", systemImage: "puzzlepiece.extension")
                } description: {
                    Text("Install plugins to extend sbx-ui with custom commands, automation, and integrations.")
                        .font(.ui(13))
                } actions: {
                    Button("Install Plugin") {
                        showInstallPicker = true
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.accent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(pluginStore.plugins) { plugin in
                            PluginCardView(plugin: plugin, selectedPlugin: $selectedPlugin)
                                .accessibilityIdentifier("pluginCard-\(plugin.id)")
                        }
                    }
                    .padding()
                }
            }
        }
        .background(Color.surface)
        .sheet(item: $selectedPlugin) { plugin in
            PluginDetailView(plugin: plugin)
        }
        .fileImporter(
            isPresented: $showInstallPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            handleInstall(result)
        }
        .alert(
            "Approve Plugin Permissions",
            isPresented: Binding(
                get: { pluginStore.pendingApproval != nil },
                set: { if !$0 { pluginStore.denyApproval() } }
            )
        ) {
            Button("Deny", role: .cancel) {
                pluginStore.denyApproval()
            }
            Button("Approve & Start") {
                if let id = pluginStore.pendingApproval?.id {
                    Task { await pluginStore.approveAndStart(id: id) }
                }
            }
        } message: {
            if let plugin = pluginStore.pendingApproval {
                Text("\"\(plugin.name)\" requests these permissions:\n\n\(plugin.permissions.map(\.displayName).joined(separator: "\n"))\n\nAllow this plugin to run?")
            }
        }
        .task {
            await pluginStore.refresh()
        }
    }

    private func handleInstall(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let sourceURL = urls.first else { return }

        let pluginsDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("sbx-ui/plugins")

        let destURL = pluginsDir.appendingPathComponent(sourceURL.lastPathComponent)
        do {
            try FileManager.default.createDirectory(at: pluginsDir, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: destURL.path) {
                try FileManager.default.removeItem(at: destURL)
            }
            try FileManager.default.copyItem(at: sourceURL, to: destURL)
            Task { await pluginStore.refresh() }
            appLog(.info, "Plugin", "Installed plugin from \(sourceURL.lastPathComponent)")
        } catch {
            pluginStore.error = "Failed to install plugin: \(error.localizedDescription)"
        }
    }
}

// MARK: - Plugin Card

struct PluginCardView: View {
    let plugin: PluginManifest
    @Binding var selectedPlugin: PluginManifest?
    @Environment(PluginStore.self) private var pluginStore

    private var isRunning: Bool {
        pluginStore.isRunning(id: plugin.id)
    }

    var body: some View {
        HStack(spacing: 12) {
            // Status indicator
            Circle()
                .fill(isRunning ? Color.secondary : Color.surfaceContainerHighest)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(plugin.name)
                        .font(.ui(14, weight: .semibold))
                    Text("v\(plugin.version)")
                        .font(.code(11))
                        .foregroundStyle(.tertiary)
                }
                Text(plugin.description)
                    .font(.ui(12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Trigger badges
            HStack(spacing: 4) {
                ForEach(plugin.triggers, id: \.rawValue) { trigger in
                    Text(trigger.rawValue)
                        .font(.code(9))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.surfaceContainerHigh)
                        .clipShape(Capsule())
                }
            }

            // Start/Stop button
            Button {
                Task {
                    if isRunning {
                        await pluginStore.stopPlugin(id: plugin.id)
                    } else {
                        await pluginStore.startPlugin(id: plugin.id)
                    }
                }
            } label: {
                Image(systemName: isRunning ? "stop.fill" : "play.fill")
                    .font(.system(size: 12))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier(isRunning ? "stopPlugin-\(plugin.id)" : "startPlugin-\(plugin.id)")

            // Info button
            Button {
                selectedPlugin = plugin
            } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 14))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("pluginInfo-\(plugin.id)")
        }
        .padding(12)
        .background(Color.surfaceContainer)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.cornerRadius))
    }
}
