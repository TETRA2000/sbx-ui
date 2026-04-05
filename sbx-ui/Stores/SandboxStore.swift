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

    init(service: any SbxServiceProtocol) {
        self.service = service
    }

    func fetchSandboxes() async {
        do {
            sandboxes = try await service.list()
            error = nil
        } catch {
            self.error = error.localizedDescription
            appLog(.error, "SandboxStore", "fetchSandboxes failed", detail: error.localizedDescription)
        }
        if initialLoading { initialLoading = false }
    }

    @discardableResult
    func createSandbox(workspace: String, name: String?) async throws -> Sandbox {
        isCreating = true
        defer { isCreating = false }
        appLog(.info, "SandboxStore", "Creating sandbox", detail: "workspace=\(workspace) name=\(name ?? "<auto>")")
        let opts = RunOptions(name: name)
        let sandbox = try await service.run(agent: "claude", workspace: workspace, opts: opts)
        appLog(.info, "SandboxStore", "Sandbox created: \(sandbox.name) [\(sandbox.status.rawValue)]")
        await fetchSandboxes()
        return sandbox
    }

    func resumeSandbox(name: String) async throws {
        busyOperations[name] = .resuming
        defer { busyOperations.removeValue(forKey: name) }
        appLog(.info, "SandboxStore", "Resuming sandbox: \(name)")
        _ = try await service.run(agent: "", workspace: "", opts: RunOptions(name: name))
        await fetchSandboxes()
    }

    func stopSandbox(name: String) async throws {
        busyOperations[name] = .stopping
        defer { busyOperations.removeValue(forKey: name) }
        appLog(.info, "SandboxStore", "Stopping sandbox: \(name)")
        try await service.stop(name: name)
        await fetchSandboxes()
    }

    func removeSandbox(name: String) async throws {
        busyOperations[name] = .removing
        defer { busyOperations.removeValue(forKey: name) }
        appLog(.info, "SandboxStore", "Removing sandbox: \(name)")
        try await service.rm(name: name)
        await fetchSandboxes()
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
