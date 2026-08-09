import Foundation

public protocol SbxServiceProtocol: Sendable {
    // Lifecycle
    func list() async throws -> [Sandbox]
    func run(agent: String, workspace: String, opts: RunOptions?) async throws -> Sandbox
    func stop(name: String) async throws
    func rm(name: String) async throws

    // Network policies
    func policyList() async throws -> [PolicyRule]
    func policyAllow(resources: String) async throws -> PolicyRule
    func policyDeny(resources: String) async throws -> PolicyRule
    func policyRemove(resource: String) async throws
    func policyLog(sandboxName: String?) async throws -> [PolicyLogEntry]

    // Port forwarding
    func portsList(name: String) async throws -> [PortMapping]
    func portsPublish(name: String, hostPort: Int, sbxPort: Int) async throws -> PortMapping
    func portsUnpublish(name: String, hostPort: Int, sbxPort: Int) async throws

    // Environment variables (per-sandbox, via /etc/sandbox-persistent.sh)
    func envVarList(name: String) async throws -> [EnvVar]
    func envVarSync(name: String, vars: [EnvVar]) async throws

    // Exec (generic command execution in sandbox)
    func exec(name: String, command: String, args: [String]) async throws -> CliResult

    // Session messaging
    func sendMessage(name: String, message: String) async throws

    // Diagnostics
    func version() async throws -> SbxVersionInfo
}

public protocol CliExecutorProtocol: Sendable {
    func exec(command: String, args: [String], timeout: Duration?) async throws -> CliResult
    func execJson<T: Decodable & Sendable>(command: String, args: [String], timeout: Duration?) async throws -> T
}

extension CliExecutorProtocol {
    /// Default timeout for every CLI call. The sole exception is the
    /// `sbx run --name` interactive attach, which passes `nil` explicitly.
    nonisolated public func exec(command: String, args: [String]) async throws -> CliResult {
        try await exec(command: command, args: args, timeout: .seconds(30))
    }

    nonisolated public func execJson<T: Decodable & Sendable>(command: String, args: [String]) async throws -> T {
        try await execJson(command: command, args: args, timeout: .seconds(30))
    }
}

public struct CliResult: Sendable {
    public let stdout: String
    public let stderr: String
    public let exitCode: Int32
    /// True when the underlying process output exceeded `ProcessRunner`'s
    /// retention cap and the head was dropped. Callers that act on `stdout`
    /// (e.g. plugins) must treat this as a hard failure rather than silently
    /// consuming truncated output.
    public let outputTruncated: Bool

    nonisolated public init(stdout: String, stderr: String, exitCode: Int32, outputTruncated: Bool = false) {
        self.stdout = stdout; self.stderr = stderr; self.exitCode = exitCode
        self.outputTruncated = outputTruncated
    }
}

// MARK: - JSON Response Types (matching real sbx CLI --json output)

struct SbxLsResponse: Sendable {
    let sandboxes: [SbxSandboxJson]
}

extension SbxLsResponse: Decodable {
    nonisolated init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sandboxes = try c.decode([SbxSandboxJson].self, forKey: .sandboxes)
    }
    enum CodingKeys: String, CodingKey { case sandboxes }
}

struct SbxSandboxJson: Sendable {
    // New in sbx v0.33.0: a stable per-sandbox id, distinct from name.
    // Decoded but not yet used for entity identity — Sandbox.id is still
    // keyed off name (see RealSbxService.list()). Optional/decodable-tolerant
    // so older-shaped JSON (e.g. pre-A2 mock state) still decodes.
    let id: String?
    let name: String
    let agent: String
    let status: String
    let ports: [SbxPortJson]?
    let socketPath: String?
    let workspaces: [String]?
}

extension SbxSandboxJson: Decodable {
    enum CodingKeys: String, CodingKey {
        case id, name, agent, status, ports
        case socketPath = "socket_path"
        case workspaces
    }
    nonisolated init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        agent = try c.decode(String.self, forKey: .agent)
        status = try c.decode(String.self, forKey: .status)
        ports = try c.decodeIfPresent([SbxPortJson].self, forKey: .ports)
        socketPath = try c.decodeIfPresent(String.self, forKey: .socketPath)
        workspaces = try c.decodeIfPresent([String].self, forKey: .workspaces)
    }
}

struct SbxPortJson: Sendable {
    let hostIp: String
    let hostPort: Int
    let sandboxPort: Int
    let `protocol`: String
}

extension SbxPortJson: Decodable {
    enum CodingKeys: String, CodingKey {
        case hostIp = "host_ip"
        case hostPort = "host_port"
        case sandboxPort = "sandbox_port"
        case `protocol`
    }
    nonisolated init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hostIp = try c.decode(String.self, forKey: .hostIp)
        hostPort = try c.decode(Int.self, forKey: .hostPort)
        sandboxPort = try c.decode(Int.self, forKey: .sandboxPort)
        self.protocol = try c.decode(String.self, forKey: .protocol)
    }
}

struct SbxPolicyLogResponse: Sendable {
    let blockedHosts: [SbxPolicyLogEntryJson]
    let allowedHosts: [SbxPolicyLogEntryJson]
}

extension SbxPolicyLogResponse: Decodable {
    enum CodingKeys: String, CodingKey {
        case blockedHosts = "blocked_hosts"
        case allowedHosts = "allowed_hosts"
    }
    nonisolated init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        blockedHosts = try c.decode([SbxPolicyLogEntryJson].self, forKey: .blockedHosts)
        allowedHosts = try c.decode([SbxPolicyLogEntryJson].self, forKey: .allowedHosts)
    }
}

struct SbxPolicyLogEntryJson: Sendable {
    let host: String
    let vmName: String
    let proxyType: String
    let rule: String
    let lastSeen: String
    let since: String
    let countSince: Int
}

extension SbxPolicyLogEntryJson: Decodable {
    enum CodingKeys: String, CodingKey {
        case host
        case vmName = "vm_name"
        case proxyType = "proxy_type"
        case rule
        case lastSeen = "last_seen"
        case since
        case countSince = "count_since"
    }
    nonisolated init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        host = try c.decode(String.self, forKey: .host)
        vmName = try c.decode(String.self, forKey: .vmName)
        proxyType = try c.decode(String.self, forKey: .proxyType)
        rule = try c.decode(String.self, forKey: .rule)
        lastSeen = try c.decode(String.self, forKey: .lastSeen)
        since = try c.decode(String.self, forKey: .since)
        countSince = try c.decode(Int.self, forKey: .countSince)
    }
}
