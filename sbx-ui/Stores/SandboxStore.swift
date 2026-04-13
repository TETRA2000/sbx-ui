import Foundation
import SwiftUI

enum SandboxOperation: Sendable {
    case creating, resuming, stopping, removing, publishingPort, unpublishingPort
}

@MainActor @Observable final class SandboxStore {
    var sandboxes: [Sandbox] = []
    var isCreating: Bool = false
    var initialLoading: Bool = true
    var busyOperations: [String: SandboxOperation] = [:]
    var error: String?

    func isBusy(_ name: String) -> Bool { busyOperations[name] != nil }

    private let service: any SbxServiceProtocol
    private var pollingTask: Task<Void, Never>?
    nonisolated(unsafe) var onPluginEvent: ((PluginEvent) async -> Void)?

    init(service: any SbxServiceProtocol) {
        self.service = service
    }

    func fetchSandboxes() async {
        do {
            var fetched = try await service.list()
            // Stable sort: running first, then alphabetically by name
            fetched.sort { a, b in
                let aRunning = a.status == .running
                let bRunning = b.status == .running
                if aRunning != bRunning { return aRunning }
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }
            sandboxes = fetched
            // Clear stale busy states (e.g. resume completed while CLI was blocking)
            for (name, op) in busyOperations {
                if op == .resuming, let s = fetched.first(where: { $0.name == name }), s.status == .running {
                    busyOperations.removeValue(forKey: name)
                }
            }
            error = nil
        } catch {
            self.error = error.localizedDescription
            appLog(.error, "SandboxStore", "fetchSandboxes failed", detail: error.localizedDescription)
        }
        if initialLoading { initialLoading = false }
    }

    @discardableResult
    func createSandbox(workspace: String, name: String?, agent: String = "claude") async throws -> Sandbox {
        isCreating = true
        defer { isCreating = false }
        appLog(.info, "SandboxStore", "Creating sandbox", detail: "workspace=\(workspace) name=\(name ?? "<auto>") agent=\(agent)")
        let opts = RunOptions(name: name)
        let sandbox = try await service.run(agent: agent, workspace: workspace, opts: opts)
        appLog(.info, "SandboxStore", "Sandbox created: \(sandbox.name) [\(sandbox.status.rawValue)]")
        await fetchSandboxes()
        await onPluginEvent?(.sandboxCreated(sandbox))
        return sandbox
    }

    func resumeSandbox(name: String) async throws {
        busyOperations[name] = .resuming
        appLog(.info, "SandboxStore", "Resuming sandbox: \(name)")
        // sbx run <name> blocks (attaches to agent), so launch it without waiting.
        // Polling in fetchSandboxes() will detect the running state and clear the busy flag.
        Task {
            do {
                _ = try await service.run(agent: "", workspace: "", opts: RunOptions(name: name))
            } catch {
                appLog(.warn, "SandboxStore", "Resume command ended: \(error.localizedDescription)")
            }
            await MainActor.run { busyOperations.removeValue(forKey: name) }
        }
    }

    func stopSandbox(name: String) async throws {
        busyOperations[name] = .stopping
        defer { busyOperations.removeValue(forKey: name) }
        appLog(.info, "SandboxStore", "Stopping sandbox: \(name)")
        try await service.stop(name: name)
        await fetchSandboxes()
        await onPluginEvent?(.sandboxStopped(name))
    }

    func removeSandbox(name: String) async throws {
        busyOperations[name] = .removing
        defer { busyOperations.removeValue(forKey: name) }
        appLog(.info, "SandboxStore", "Removing sandbox: \(name)")
        try await service.rm(name: name)
        await fetchSandboxes()
        await onPluginEvent?(.sandboxRemoved(name))
    }

    func publishPort(name: String, hostPort: Int, sbxPort: Int) async throws {
        busyOperations[name] = .publishingPort
        defer { busyOperations.removeValue(forKey: name) }
        appLog(.info, "SandboxStore", "Publishing port \(hostPort):\(sbxPort) on \(name)")
        _ = try await service.portsPublish(name: name, hostPort: hostPort, sbxPort: sbxPort)
        await fetchSandboxes()
    }

    func unpublishPort(name: String, hostPort: Int, sbxPort: Int) async throws {
        busyOperations[name] = .unpublishingPort
        defer { busyOperations.removeValue(forKey: name) }
        try await service.portsUnpublish(name: name, hostPort: hostPort, sbxPort: sbxPort)
        await fetchSandboxes()
    }

    func startPolling() {
        stopPolling()
        appLog(.debug, "SandboxStore", "Polling started (3s interval)")
        pollingTask = Task {
            while !Task.isCancelled {
                await fetchSandboxes()
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }
}
