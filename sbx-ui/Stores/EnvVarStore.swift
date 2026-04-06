import Foundation

@MainActor @Observable final class EnvVarStore {
    var envVars: [String: [EnvVar]] = [:]  // keyed by sandbox name
    var loading: Set<String> = []
    var syncing: Set<String> = []
    var removingKeys: Set<String> = []  // format: "sandboxName:key"
    var error: String?

    private let service: any SbxServiceProtocol

    init(service: any SbxServiceProtocol) {
        self.service = service
    }

    func fetchEnvVars(for sandboxName: String) async {
        loading.insert(sandboxName)
        defer { loading.remove(sandboxName) }
        do {
            envVars[sandboxName] = try await service.envVarList(name: sandboxName)
            error = nil
        } catch {
            self.error = error.localizedDescription
            appLog(.error, "EnvVarStore", "fetchEnvVars failed for \(sandboxName)", detail: error.localizedDescription)
        }
    }

    func addEnvVar(sandboxName: String, key: String, value: String) async throws {
        var current = envVars[sandboxName] ?? []
        current.removeAll { $0.key == key }  // upsert
        current.append(EnvVar(key: key, value: value))
        syncing.insert(sandboxName)
        defer { syncing.remove(sandboxName) }
        try await service.envVarSync(name: sandboxName, vars: current)
        envVars[sandboxName] = current
        appLog(.info, "EnvVarStore", "Added env var \(key) to \(sandboxName)")
    }

    func removeEnvVar(sandboxName: String, key: String) async throws {
        let busyKey = "\(sandboxName):\(key)"
        removingKeys.insert(busyKey)
        defer { removingKeys.remove(busyKey) }
        var current = envVars[sandboxName] ?? []
        current.removeAll { $0.key == key }
        try await service.envVarSync(name: sandboxName, vars: current)
        envVars[sandboxName] = current
        appLog(.info, "EnvVarStore", "Removed env var \(key) from \(sandboxName)")
    }

    func syncInitialEnvVars(sandboxName: String, vars: [EnvVar]) async throws {
        guard !vars.isEmpty else { return }
        syncing.insert(sandboxName)
        defer { syncing.remove(sandboxName) }
        try await service.envVarSync(name: sandboxName, vars: vars)
        envVars[sandboxName] = vars
        appLog(.info, "EnvVarStore", "Set \(vars.count) initial env vars for \(sandboxName)")
    }

    func vars(for sandboxName: String) -> [EnvVar] {
        envVars[sandboxName] ?? []
    }
}
