import Foundation

protocol SbxServiceProtocol: Sendable {
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

    // Session messaging
    func sendMessage(name: String, message: String) async throws
}

protocol CliExecutorProtocol: Sendable {
    func exec(command: String, args: [String]) async throws -> CliResult
    func execJson<T: Decodable & Sendable>(command: String, args: [String]) async throws -> T
}

struct CliResult: Sendable {
    let stdout: String
    let stderr: String
    let exitCode: Int32
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
    let name: String
    let agent: String
    let status: String
    let ports: [SbxPortJson]?
    let socketPath: String?
    let workspaces: [String]?
}

extension SbxSandboxJson: Decodable {
    enum CodingKeys: String, CodingKey {
        case name, agent, status, ports
        case socketPath = "socket_path"
        case workspaces
    }
    nonisolated init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
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
