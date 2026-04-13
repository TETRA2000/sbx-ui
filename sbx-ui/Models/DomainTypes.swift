import Foundation

public enum SandboxStatus: String, Sendable, Codable {
    case running, stopped, creating, removing
}

public enum SessionType: String, Sendable {
    case agent   // sbx run <name>
    case shell   // sbx exec -it <name> bash
}

public struct Sandbox: Identifiable, Sendable, Encodable {
    public let id: String
    public let name: String
    public let agent: String  // "claude"
    public var status: SandboxStatus
    public let workspace: String
    public var ports: [PortMapping]
    public let createdAt: Date

    public init(id: String, name: String, agent: String, status: SandboxStatus, workspace: String, ports: [PortMapping], createdAt: Date) {
        self.id = id; self.name = name; self.agent = agent; self.status = status
        self.workspace = workspace; self.ports = ports; self.createdAt = createdAt
    }
}

public struct PolicyRule: Identifiable, Sendable, Encodable {
    public let id: String
    public let type: String  // "network"
    public let decision: PolicyDecision
    public let resources: String

    public init(id: String, type: String, decision: PolicyDecision, resources: String) {
        self.id = id; self.type = type; self.decision = decision; self.resources = resources
    }
}

public enum PolicyDecision: String, Sendable, Codable {
    case allow, deny
}

public struct PolicyLogEntry: Sendable, Identifiable {
    public var id: String { "\(sandbox)-\(host)-\(proxy)" }
    public let sandbox: String
    public let type: String  // "network"
    public let host: String
    public let proxy: String  // "forward", "transparent", "network"
    public let rule: String
    public let lastSeen: Date
    public let count: Int
    public let blocked: Bool

    public init(sandbox: String, type: String, host: String, proxy: String, rule: String, lastSeen: Date, count: Int, blocked: Bool) {
        self.sandbox = sandbox; self.type = type; self.host = host; self.proxy = proxy
        self.rule = rule; self.lastSeen = lastSeen; self.count = count; self.blocked = blocked
    }
}

public struct PortMapping: Sendable, Identifiable, Equatable, Encodable {
    public var id: String { "\(hostPort)-\(sandboxPort)" }
    public let hostPort: Int
    public let sandboxPort: Int
    public let protocolType: String  // "tcp"

    public init(hostPort: Int, sandboxPort: Int, protocolType: String) {
        self.hostPort = hostPort; self.sandboxPort = sandboxPort; self.protocolType = protocolType
    }
}

public struct RunOptions: Sendable {
    public var name: String?
    public var prompt: String?

    public init(name: String? = nil, prompt: String? = nil) {
        self.name = name; self.prompt = prompt
    }
}

public enum SbxServiceError: Error, Sendable, LocalizedError {
    case notFound(String)
    case alreadyExists(String)
    case portConflict(Int)
    case notRunning(String)
    case cliError(String)
    case dockerNotRunning
    case invalidName(String)

    public var errorDescription: String? {
        switch self {
        case .notFound(let name): "Sandbox '\(name)' not found"
        case .alreadyExists(let name): "Sandbox '\(name)' already exists"
        case .portConflict(let port): "Port \(port) is already in use"
        case .notRunning(let name): "Sandbox '\(name)' is not running"
        case .cliError(let msg): "CLI error: \(msg)"
        case .dockerNotRunning: "Docker Desktop is not running. Please start Docker Desktop and try again."
        case .invalidName(let name): "Invalid sandbox name '\(name)'. Names must be lowercase alphanumeric with hyphens, no leading hyphen."
        }
    }
}

public struct EnvVar: Identifiable, Sendable, Equatable, Encodable {
    public var id: String { key }
    public let key: String
    public let value: String

    public init(key: String, value: String) {
        self.key = key; self.value = value
    }
}

public enum SbxValidation {
    nonisolated public static func isValidName(_ name: String) -> Bool {
        name.range(of: #"^[a-z0-9][a-z0-9-]*$"#, options: .regularExpression) != nil
    }

    nonisolated public static func isValidEnvKey(_ key: String) -> Bool {
        key.range(of: #"^[A-Za-z_][A-Za-z0-9_]*$"#, options: .regularExpression) != nil
    }
}

