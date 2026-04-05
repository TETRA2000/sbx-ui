import Foundation

enum SandboxStatus: String, Sendable, Codable {
    case running, stopped, creating, removing
}

enum SessionType: String, Sendable {
    case agent   // sbx run <name>
    case shell   // sbx exec -it <name> bash
}

struct Sandbox: Identifiable, Sendable {
    let id: String
    let name: String
    let agent: String  // "claude"
    var status: SandboxStatus
    let workspace: String
    var ports: [PortMapping]
    let createdAt: Date
}

struct PolicyRule: Identifiable, Sendable {
    let id: String
    let type: String  // "network"
    let decision: PolicyDecision
    let resources: String
}

enum PolicyDecision: String, Sendable, Codable {
    case allow, deny
}

struct PolicyLogEntry: Sendable, Identifiable {
    var id: String { "\(sandbox)-\(host)-\(proxy)" }
    let sandbox: String
    let type: String  // "network"
    let host: String
    let proxy: String  // "forward", "transparent", "network"
    let rule: String
    let lastSeen: Date
    let count: Int
    let blocked: Bool
}

struct PortMapping: Sendable, Identifiable, Equatable {
    var id: String { "\(hostPort)-\(sandboxPort)" }
    let hostPort: Int
    let sandboxPort: Int
    let protocolType: String  // "tcp"
}

struct RunOptions: Sendable {
    var name: String?
    var prompt: String?
}

enum SbxServiceError: Error, Sendable, LocalizedError {
    case notFound(String)
    case alreadyExists(String)
    case portConflict(Int)
    case notRunning(String)
    case cliError(String)
    case dockerNotRunning
    case invalidName(String)

    var errorDescription: String? {
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

enum SbxValidation {
    nonisolated static func isValidName(_ name: String) -> Bool {
        name.range(of: #"^[a-z0-9][a-z0-9-]*$"#, options: .regularExpression) != nil
    }
}

