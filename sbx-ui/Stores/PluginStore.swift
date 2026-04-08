import Foundation

// MARK: - Plugin Store

@MainActor @Observable final class PluginStore {
    var plugins: [PluginManifest] = []
    var runningPlugins: Set<String> = []
    var pluginOutputs: [String: [String]] = [:]
    var error: String?
    /// Plugin awaiting user approval before starting.
    var pendingApproval: PluginManifest?

    private let manager: PluginManager

    init(manager: PluginManager) {
        self.manager = manager
    }

    func refresh() async {
        let discovered = await manager.discoverPlugins()
        plugins = discovered
        runningPlugins = await manager.runningPluginIds()
    }

    func startPlugin(id: String) async {
        guard let manifest = plugins.first(where: { $0.id == id }) else {
            error = "Plugin not found: \(id)"
            return
        }

        // Require user approval before first run
        if !PluginApprovalStore.isApproved(pluginId: id, permissions: manifest.permissions) {
            pendingApproval = manifest
            return
        }

        await launchPlugin(manifest: manifest)
    }

    /// Called after user confirms the approval dialog.
    func approveAndStart(id: String) async {
        guard let manifest = plugins.first(where: { $0.id == id }) else { return }
        do {
            try PluginApprovalStore.approve(pluginId: id, permissions: manifest.permissions)
        } catch {
            self.error = "Failed to save approval: \(error.localizedDescription)"
            return
        }
        pendingApproval = nil
        await launchPlugin(manifest: manifest)
    }

    /// Called when user dismisses the approval dialog.
    func denyApproval() {
        pendingApproval = nil
    }

    private func launchPlugin(manifest: PluginManifest) async {
        do {
            try await manager.startPlugin(manifest: manifest)
            runningPlugins = await manager.runningPluginIds()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func stopPlugin(id: String) async {
        await manager.stopPlugin(id: id)
        runningPlugins = await manager.runningPluginIds()
    }

    func stopAll() async {
        await manager.stopAll()
        runningPlugins.removeAll()
    }

    func isRunning(id: String) -> Bool {
        runningPlugins.contains(id)
    }

    func appendOutput(pluginId: String, message: String) {
        var outputs = pluginOutputs[pluginId] ?? []
        outputs.append(message)
        if outputs.count > 200 {
            outputs = Array(outputs.suffix(200))
        }
        pluginOutputs[pluginId] = outputs
    }

    func clearOutput(pluginId: String) {
        pluginOutputs.removeValue(forKey: pluginId)
    }

    /// Dispatch a sandbox event to all running plugins.
    func dispatchEvent(_ event: PluginEvent) async {
        await manager.dispatchEvent(event)
    }
}
