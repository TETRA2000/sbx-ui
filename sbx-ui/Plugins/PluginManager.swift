import Foundation

// MARK: - Plugin Events

enum PluginEvent: Sendable {
    case sandboxCreated(Sandbox)
    case sandboxStopped(String)
    case sandboxRemoved(String)
}

// MARK: - Plugin Manager

/// Discovers, starts, stops, and manages plugin lifecycle.
actor PluginManager {
    private let service: any SbxServiceProtocol
    let pluginsDirectory: URL
    private var hosts: [String: PluginHost] = [:]

    /// Callback invoked on the main actor when plugin state changes.
    nonisolated let onStateChanged: @Sendable () -> Void
    /// Callback invoked on the main actor for plugin output.
    nonisolated let onPluginOutput: @Sendable (String, String) -> Void  // (pluginId, message)

    init(
        service: any SbxServiceProtocol,
        pluginsDirectory: URL? = nil,
        onStateChanged: @escaping @Sendable () -> Void = {},
        onPluginOutput: @escaping @Sendable (String, String) -> Void = { _, _ in }
    ) {
        self.service = service
        self.onStateChanged = onStateChanged
        self.onPluginOutput = onPluginOutput

        if let dir = pluginsDirectory {
            self.pluginsDirectory = dir
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            self.pluginsDirectory = appSupport.appendingPathComponent("sbx-ui/plugins")
        }
    }

    // MARK: - Discovery

    func discoverPlugins() -> [PluginManifest] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: pluginsDirectory.path) else { return [] }

        guard let contents = try? fm.contentsOfDirectory(
            at: pluginsDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var manifests: [PluginManifest] = []
        for itemURL in contents {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: itemURL.path, isDirectory: &isDir), isDir.boolValue else { continue }

            do {
                let manifest = try PluginManifest.load(from: itemURL)
                manifests.append(manifest)
            } catch {
                DispatchQueue.main.async {
                    appLog(.warn, "Plugin", "Failed to load manifest from \(itemURL.lastPathComponent): \(error.localizedDescription)")
                }
            }
        }

        return manifests.sorted { $0.name < $1.name }
    }

    // MARK: - Lifecycle

    func startPlugin(manifest: PluginManifest) async throws {
        guard hosts[manifest.id] == nil else {
            throw PluginError.alreadyRunning(manifest.id)
        }
        guard let directory = manifest.directory else {
            throw PluginError.manifestError("Plugin directory not set for \(manifest.id)")
        }

        let stateChanged = onStateChanged
        let outputCallback = onPluginOutput

        let host = PluginHost(
            manifest: manifest,
            pluginDirectory: directory,
            onOutput: { pluginId, message in
                outputCallback(pluginId, message)
            },
            onTerminated: { [weak self] pluginId in
                Task { [weak self] in
                    await self?.handlePluginTerminated(pluginId: pluginId)
                    stateChanged()
                }
            }
        )

        try await host.start(service: service)
        hosts[manifest.id] = host
        DispatchQueue.main.async {
            appLog(.info, "Plugin", "Plugin '\(manifest.name)' started")
        }
        onStateChanged()
    }

    func stopPlugin(id: String) async {
        guard let host = hosts.removeValue(forKey: id) else { return }
        await host.stop()
        DispatchQueue.main.async {
            appLog(.info, "Plugin", "Plugin '\(id)' stopped")
        }
        onStateChanged()
    }

    func stopAll() async {
        for (id, host) in hosts {
            await host.stop()
            DispatchQueue.main.async {
                appLog(.info, "Plugin", "Plugin '\(id)' stopped")
            }
        }
        hosts.removeAll()
        onStateChanged()
    }

    func isRunning(id: String) -> Bool {
        hosts[id] != nil
    }

    func runningPluginIds() -> Set<String> {
        Set(hosts.keys)
    }

    // MARK: - Event Dispatch

    func dispatchEvent(_ event: PluginEvent) async {
        let triggerType: PluginTrigger
        let params: [String: AnyCodable]

        switch event {
        case .sandboxCreated(let sandbox):
            triggerType = .onSandboxCreated
            params = ["name": .string(sandbox.name), "workspace": .string(sandbox.workspace)]
        case .sandboxStopped(let name):
            triggerType = .onSandboxStopped
            params = ["name": .string(name)]
        case .sandboxRemoved(let name):
            triggerType = .onSandboxRemoved
            params = ["name": .string(name)]
        }

        let method = "event/\(triggerType.rawValue)"
        for (_, host) in hosts {
            guard host.manifest.triggers.contains(triggerType) else { continue }
            do {
                try await host.sendNotification(method, params: params)
            } catch {
                DispatchQueue.main.async {
                    appLog(.warn, "Plugin", "Failed to dispatch event to \(host.manifest.id): \(error)")
                }
            }
        }
    }

    // MARK: - Internal

    private func handlePluginTerminated(pluginId: String) {
        hosts.removeValue(forKey: pluginId)
        DispatchQueue.main.async {
            appLog(.info, "Plugin", "Plugin '\(pluginId)' terminated, removed from active hosts")
        }
    }
}
