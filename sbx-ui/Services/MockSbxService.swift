import Foundation

enum SbxValidation {
    nonisolated static func isValidName(_ name: String) -> Bool {
        name.range(of: #"^[a-z0-9][a-z0-9-]*$"#, options: .regularExpression) != nil
    }
}

actor MockSbxService: SbxServiceProtocol {
    private var sandboxes: [String: Sandbox] = [:]
    private var policies: [String: PolicyRule] = [:]
    private var portMappings: [String: [PortMapping]] = [:]
    private var policyLogs: [PolicyLogEntry] = []

    init() {
        let defaults = [
            "api.anthropic.com",
            "*.npmjs.org",
            "github.com",
            "*.github.com",
            "registry.hub.docker.com",
            "*.docker.io",
            "*.googleapis.com",
            "api.openai.com",
            "*.pypi.org",
            "files.pythonhosted.org",
        ]

        for domain in defaults {
            let rule = PolicyRule(
                id: UUID().uuidString,
                type: "network",
                decision: .allow,
                resources: domain
            )
            policies[rule.id] = rule
        }

        policyLogs = [
            PolicyLogEntry(sandbox: "claude-myproject", type: "network", host: "api.anthropic.com", proxy: "forward", rule: "allow", lastSeen: Date().addingTimeInterval(-60), count: 42, blocked: false),
            PolicyLogEntry(sandbox: "claude-myproject", type: "network", host: "registry.npmjs.org", proxy: "transparent", rule: "allow", lastSeen: Date().addingTimeInterval(-120), count: 15, blocked: false),
            PolicyLogEntry(sandbox: "claude-myproject", type: "network", host: "evil.example.com", proxy: "network", rule: "deny", lastSeen: Date().addingTimeInterval(-30), count: 3, blocked: true),
        ]
    }

    // MARK: - Lifecycle

    func list() async throws -> [Sandbox] {
        var result: [Sandbox] = []
        for (name, sandbox) in sandboxes {
            var s = sandbox
            s.ports = portMappings[name] ?? []
            result.append(s)
        }
        return result.sorted { $0.createdAt < $1.createdAt }
    }

    func run(agent: String, workspace: String, opts: RunOptions?) async throws -> Sandbox {
        // Resume mode: empty agent means resume by name
        if agent.isEmpty, let resumeName = opts?.name, !resumeName.isEmpty {
            if var existing = sandboxes[resumeName] {
                existing.status = .creating
                sandboxes[resumeName] = existing
                try await Task.sleep(for: .milliseconds(800))
                existing.status = .running
                sandboxes[resumeName] = existing
                return existing
            }
            throw SbxServiceError.notFound(resumeName)
        }

        // Check for existing sandbox with same workspace
        if let existing = sandboxes.values.first(where: { $0.workspace == workspace && $0.status == .running }) {
            return existing
        }

        let name: String
        if let customName = opts?.name, !customName.isEmpty {
            name = customName
        } else {
            let dirname = URL(fileURLWithPath: workspace).lastPathComponent
            name = "claude-\(dirname)"
        }

        // Validate name
        guard SbxValidation.isValidName(name) else {
            throw SbxServiceError.invalidName(name)
        }

        // Check for stopped sandbox with same name (resume)
        if var existing = sandboxes[name], existing.status == .stopped {
            existing.status = .creating
            sandboxes[name] = existing
            try await Task.sleep(for: .milliseconds(800))
            existing.status = .running
            sandboxes[name] = existing
            return existing
        }

        let sandbox = Sandbox(
            id: UUID().uuidString,
            name: name,
            agent: agent,
            status: .creating,
            workspace: workspace,
            ports: [],
            createdAt: Date()
        )
        sandboxes[name] = sandbox

        try await Task.sleep(for: .milliseconds(800))

        var running = sandbox
        running.status = .running
        sandboxes[name] = running
        return running
    }

    func stop(name: String) async throws {
        guard var sandbox = sandboxes[name] else {
            throw SbxServiceError.notFound(name)
        }
        try await Task.sleep(for: .milliseconds(300))
        sandbox.status = .stopped
        sandboxes[name] = sandbox
        portMappings[name] = []
    }

    func rm(name: String) async throws {
        guard sandboxes[name] != nil else {
            throw SbxServiceError.notFound(name)
        }
        var sandbox = sandboxes[name]!
        sandbox.status = .removing
        sandboxes[name] = sandbox
        try await Task.sleep(for: .milliseconds(200))
        sandboxes.removeValue(forKey: name)
        portMappings.removeValue(forKey: name)
        policyLogs.removeAll { $0.sandbox == name }
    }

    // MARK: - Network Policies

    func policyList() async throws -> [PolicyRule] {
        Array(policies.values).sorted { $0.id < $1.id }
    }

    func policyAllow(resources: String) async throws -> PolicyRule {
        let rule = PolicyRule(
            id: UUID().uuidString,
            type: "network",
            decision: .allow,
            resources: resources
        )
        policies[rule.id] = rule
        return rule
    }

    func policyDeny(resources: String) async throws -> PolicyRule {
        let rule = PolicyRule(
            id: UUID().uuidString,
            type: "network",
            decision: .deny,
            resources: resources
        )
        policies[rule.id] = rule
        return rule
    }

    func policyRemove(resource: String) async throws {
        let toRemove = policies.values.first { $0.resources == resource }
        guard let rule = toRemove else {
            throw SbxServiceError.notFound(resource)
        }
        policies.removeValue(forKey: rule.id)
    }

    func policyLog(sandboxName: String?) async throws -> [PolicyLogEntry] {
        if let name = sandboxName {
            return policyLogs.filter { $0.sandbox == name }
        }
        return policyLogs
    }

    // MARK: - Port Forwarding

    func portsList(name: String) async throws -> [PortMapping] {
        guard sandboxes[name] != nil else {
            throw SbxServiceError.notFound(name)
        }
        return portMappings[name] ?? []
    }

    func portsPublish(name: String, hostPort: Int, sbxPort: Int) async throws -> PortMapping {
        guard let sandbox = sandboxes[name] else {
            throw SbxServiceError.notFound(name)
        }
        guard sandbox.status == .running else {
            throw SbxServiceError.notRunning(name)
        }

        // Check for duplicate host port across all sandboxes
        for (_, mappings) in portMappings {
            if mappings.contains(where: { $0.hostPort == hostPort }) {
                throw SbxServiceError.portConflict(hostPort)
            }
        }

        let mapping = PortMapping(hostPort: hostPort, sandboxPort: sbxPort, protocolType: "tcp")
        portMappings[name, default: []].append(mapping)
        return mapping
    }

    func portsUnpublish(name: String, hostPort: Int, sbxPort: Int) async throws {
        guard sandboxes[name] != nil else {
            throw SbxServiceError.notFound(name)
        }
        portMappings[name]?.removeAll { $0.hostPort == hostPort && $0.sandboxPort == sbxPort }
    }

    // MARK: - Session

    func sendMessage(name: String, message: String) async throws {
        guard let sandbox = sandboxes[name] else {
            throw SbxServiceError.notFound(name)
        }
        guard sandbox.status == .running else {
            throw SbxServiceError.notRunning(name)
        }
        // In mock mode, message handling is done by PtySessionManager/MockPtyEmitter
    }
}
