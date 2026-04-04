import Foundation

protocol PtyHandle: Sendable {
    func onData(_ callback: @escaping @Sendable (String) -> Void)
    func write(_ data: String)
    func dispose()
}

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

    // Session messaging
    func sendMessage(name: String, message: String) async throws
}

protocol ExternalTerminalProtocol: Sendable {
    func detectAvailable() async -> [TerminalApp]
    func openShell(sandboxName: String, app: TerminalApp) async throws
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
