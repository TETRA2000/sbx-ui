import Foundation

actor RealSbxService: SbxServiceProtocol {
    private let cli: CliExecutorProtocol

    init(cli: CliExecutorProtocol = CliExecutor()) {
        self.cli = cli
    }

    // MARK: - Lifecycle

    func list() async throws -> [Sandbox] {
        let result = try await cli.exec(command: "sbx", args: ["ls"])
        try checkCli(result)
        return SbxOutputParser.parseSandboxList(result.stdout)
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
        let targetName = opts?.name ?? "claude-\(URL(fileURLWithPath: workspace).lastPathComponent)"
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
        let result = try await cli.exec(command: "sbx", args: ["rm", name])
        try checkCli(result)
    }

    // MARK: - Network Policies

    func policyList() async throws -> [PolicyRule] {
        let result = try await cli.exec(command: "sbx", args: ["policy", "list"])
        try checkCli(result)
        return SbxOutputParser.parsePolicyList(result.stdout)
    }

    func policyAllow(resources: String) async throws -> PolicyRule {
        let result = try await cli.exec(command: "sbx", args: ["policy", "allow", resources])
        try checkCli(result)
        let rules = try await policyList()
        return rules.first { $0.resources == resources && $0.decision == .allow }
            ?? PolicyRule(id: UUID().uuidString, type: "network", decision: .allow, resources: resources)
    }

    func policyDeny(resources: String) async throws -> PolicyRule {
        let result = try await cli.exec(command: "sbx", args: ["policy", "deny", resources])
        try checkCli(result)
        let rules = try await policyList()
        return rules.first { $0.resources == resources && $0.decision == .deny }
            ?? PolicyRule(id: UUID().uuidString, type: "network", decision: .deny, resources: resources)
    }

    func policyRemove(resource: String) async throws {
        let result = try await cli.exec(command: "sbx", args: ["policy", "remove", resource])
        try checkCli(result)
    }

    func policyLog(sandboxName: String?) async throws -> [PolicyLogEntry] {
        var args = ["policy", "log"]
        if let name = sandboxName {
            args += ["--sandbox", name]
        }
        let result = try await cli.exec(command: "sbx", args: args)
        try checkCli(result)
        return SbxOutputParser.parsePolicyLog(result.stdout)
    }

    // MARK: - Port Forwarding

    func portsList(name: String) async throws -> [PortMapping] {
        let result = try await cli.exec(command: "sbx", args: ["ports", "list", name])
        try checkCli(result)
        return SbxOutputParser.parsePortsList(result.stdout)
    }

    func portsPublish(name: String, hostPort: Int, sbxPort: Int) async throws -> PortMapping {
        let result = try await cli.exec(command: "sbx", args: ["ports", "publish", name, "\(hostPort):\(sbxPort)"])
        try checkCli(result)
        return PortMapping(hostPort: hostPort, sandboxPort: sbxPort, protocolType: "tcp")
    }

    func portsUnpublish(name: String, hostPort: Int, sbxPort: Int) async throws {
        let result = try await cli.exec(command: "sbx", args: ["ports", "unpublish", name, "\(hostPort):\(sbxPort)"])
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
            if stderr.contains("docker") && (stderr.contains("not running") || stderr.contains("Cannot connect")) {
                throw SbxServiceError.dockerNotRunning
            }
            if stderr.contains("not found") || stderr.contains("No such") {
                let name = stderr.components(separatedBy: "'").dropFirst().first ?? "unknown"
                throw SbxServiceError.notFound(String(name))
            }
            throw SbxServiceError.cliError(stderr.isEmpty ? "Command failed with exit code \(result.exitCode)" : stderr)
        }
    }
}
