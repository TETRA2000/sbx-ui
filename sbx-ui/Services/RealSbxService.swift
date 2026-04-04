import Foundation

actor RealSbxService: SbxServiceProtocol {
    private let cli: CliExecutorProtocol

    init(cli: CliExecutorProtocol = CliExecutor()) {
        self.cli = cli
    }

    // MARK: - Lifecycle

    func list() async throws -> [Sandbox] {
        let result = try await cli.exec(command: "sbx", args: ["ls", "--json"])
        try checkCli(result)
        guard let data = result.stdout.data(using: .utf8) else { return [] }
        let response = try JSONDecoder().decode(SbxLsResponse.self, from: data)
        return response.sandboxes.map { json in
            Sandbox(
                id: json.name,
                name: json.name,
                agent: json.agent,
                status: SandboxStatus(rawValue: json.status) ?? .stopped,
                workspace: json.workspaces?.first ?? "",
                ports: (json.ports ?? []).map { p in
                    PortMapping(hostPort: p.hostPort, sandboxPort: p.sandboxPort, protocolType: p.protocol)
                },
                createdAt: Date()
            )
        }
    }

    func run(agent: String, workspace: String, opts: RunOptions?) async throws -> Sandbox {
        var args = ["run", agent, workspace]
        if let name = opts?.name, !name.isEmpty {
            guard SbxValidation.isValidName(name) else {
                throw SbxServiceError.invalidName(name)
            }
            args += ["--name", name]
        }
        let result = try await cli.exec(command: "sbx", args: args)
        try checkCli(result)
        // Re-fetch to get the updated sandbox
        let sandboxes = try await list()
        let targetName = opts?.name ?? "\(agent)-\(URL(fileURLWithPath: workspace).lastPathComponent)"
        guard let sandbox = sandboxes.first(where: { $0.name == targetName || $0.workspace == workspace }) else {
            throw SbxServiceError.cliError("Sandbox not found after creation")
        }
        return sandbox
    }

    func stop(name: String) async throws {
        let result = try await cli.exec(command: "sbx", args: ["stop", name])
        try checkCli(result)
    }

    func rm(name: String) async throws {
        let result = try await cli.exec(command: "sbx", args: ["rm", "-f", name])
        try checkCli(result)
    }

    // MARK: - Network Policies

    func policyList() async throws -> [PolicyRule] {
        let result = try await cli.exec(command: "sbx", args: ["policy", "ls"])
        try checkCli(result)
        return SbxOutputParser.parsePolicyList(result.stdout)
    }

    func policyAllow(resources: String) async throws -> PolicyRule {
        let result = try await cli.exec(command: "sbx", args: ["policy", "allow", "network", resources])
        try checkCli(result)
        let rules = try await policyList()
        return rules.first { $0.resources == resources && $0.decision == .allow }
            ?? PolicyRule(id: UUID().uuidString, type: "network", decision: .allow, resources: resources)
    }

    func policyDeny(resources: String) async throws -> PolicyRule {
        let result = try await cli.exec(command: "sbx", args: ["policy", "deny", "network", resources])
        try checkCli(result)
        let rules = try await policyList()
        return rules.first { $0.resources == resources && $0.decision == .deny }
            ?? PolicyRule(id: UUID().uuidString, type: "network", decision: .deny, resources: resources)
    }

    func policyRemove(resource: String) async throws {
        let result = try await cli.exec(command: "sbx", args: ["policy", "rm", "network", "--resource", resource])
        try checkCli(result)
    }

    func policyLog(sandboxName: String?) async throws -> [PolicyLogEntry] {
        var args = ["policy", "log", "--json"]
        if let name = sandboxName {
            args.insert(name, at: 2) // sbx policy log <sandbox> --json
        }
        let result = try await cli.exec(command: "sbx", args: args)
        try checkCli(result)

        guard let data = result.stdout.data(using: .utf8),
              let response = try? JSONDecoder().decode(SbxPolicyLogResponse.self, from: data) else {
            return []
        }

        let allowed = response.allowedHosts.map { entry in
            PolicyLogEntry(
                sandbox: entry.vmName, type: "network", host: entry.host,
                proxy: entry.proxyType, rule: entry.rule,
                lastSeen: ISO8601DateFormatter().date(from: entry.lastSeen) ?? Date(),
                count: entry.countSince, blocked: false
            )
        }
        let blocked = response.blockedHosts.map { entry in
            PolicyLogEntry(
                sandbox: entry.vmName, type: "network", host: entry.host,
                proxy: entry.proxyType, rule: entry.rule,
                lastSeen: ISO8601DateFormatter().date(from: entry.lastSeen) ?? Date(),
                count: entry.countSince, blocked: true
            )
        }
        return allowed + blocked
    }

    // MARK: - Port Forwarding

    func portsList(name: String) async throws -> [PortMapping] {
        let result = try await cli.exec(command: "sbx", args: ["ports", name, "--json"])
        try checkCli(result)
        guard let data = result.stdout.data(using: .utf8),
              let ports = try? JSONDecoder().decode([SbxPortJson].self, from: data) else {
            return []
        }
        return ports.map { PortMapping(hostPort: $0.hostPort, sandboxPort: $0.sandboxPort, protocolType: $0.protocol) }
    }

    func portsPublish(name: String, hostPort: Int, sbxPort: Int) async throws -> PortMapping {
        let result = try await cli.exec(command: "sbx", args: ["ports", name, "--publish", "\(hostPort):\(sbxPort)"])
        try checkCli(result)
        return PortMapping(hostPort: hostPort, sandboxPort: sbxPort, protocolType: "tcp")
    }

    func portsUnpublish(name: String, hostPort: Int, sbxPort: Int) async throws {
        let result = try await cli.exec(command: "sbx", args: ["ports", name, "--unpublish", "\(hostPort):\(sbxPort)"])
        try checkCli(result)
    }

    // MARK: - Session

    func sendMessage(name: String, message: String) async throws {
        // Delegated to PtySessionManager in practice
    }

    // MARK: - Private

    private func checkCli(_ result: CliResult) throws {
        if result.exitCode != 0 {
            let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            let stdout = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            let errorText = stderr.isEmpty ? stdout : stderr

            if errorText.contains("docker") && (errorText.contains("not running") || errorText.contains("Cannot connect")) {
                throw SbxServiceError.dockerNotRunning
            }
            if errorText.contains("not found") {
                let name = errorText.components(separatedBy: "'").dropFirst().first ?? "unknown"
                throw SbxServiceError.notFound(String(name))
            }
            if errorText.contains("already published") {
                // Extract port number from "port 127.0.0.1:8080/tcp is already published"
                if let match = errorText.firstMatch(of: /(\d+)\/tcp is already published/),
                   let port = Int(match.1) {
                    throw SbxServiceError.portConflict(port)
                }
            }
            throw SbxServiceError.cliError(errorText.isEmpty ? "Command failed with exit code \(result.exitCode)" : errorText)
        }
    }
}
