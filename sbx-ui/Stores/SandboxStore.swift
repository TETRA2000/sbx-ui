import Foundation
import SwiftUI

@MainActor @Observable final class SandboxStore {
    var sandboxes: [Sandbox] = []
    var loading: Bool = false
    var error: String?

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
        }
    }

    @discardableResult
    func createSandbox(workspace: String, name: String?) async throws -> Sandbox {
        loading = true
        defer { loading = false }
        let opts = RunOptions(name: name)
        let sandbox = try await service.run(agent: "claude", workspace: workspace, opts: opts)
        await fetchSandboxes()
        return sandbox
    }

    func stopSandbox(name: String) async throws {
        try await service.stop(name: name)
        await fetchSandboxes()
    }

    func removeSandbox(name: String) async throws {
        try await service.rm(name: name)
        await fetchSandboxes()
    }

    func publishPort(name: String, hostPort: Int, sbxPort: Int) async throws {
        _ = try await service.portsPublish(name: name, hostPort: hostPort, sbxPort: sbxPort)
        await fetchSandboxes()
    }

    func unpublishPort(name: String, hostPort: Int, sbxPort: Int) async throws {
        try await service.portsUnpublish(name: name, hostPort: hostPort, sbxPort: sbxPort)
        await fetchSandboxes()
    }

    func startPolling() {
        stopPolling()
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
