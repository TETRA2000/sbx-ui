import Foundation
import Testing
@testable import sbx_ui

// MARK: - Test Helpers

struct StubProcessLauncher: TerminalProcessLauncher {
    func launch(on terminalView: FocusableTerminalView, sandboxName: String, sessionType: SessionType) {}
}

actor FailingSbxService: SbxServiceProtocol {
    nonisolated func list() async throws -> [Sandbox] { throw SbxServiceError.cliError("test error") }
    nonisolated func run(agent: String, workspace: String, opts: RunOptions?) async throws -> Sandbox { throw SbxServiceError.cliError("test error") }
    nonisolated func stop(name: String) async throws { throw SbxServiceError.cliError("test error") }
    nonisolated func rm(name: String) async throws { throw SbxServiceError.cliError("test error") }
    nonisolated func policyList() async throws -> [PolicyRule] { throw SbxServiceError.cliError("test error") }
    nonisolated func policyAllow(resources: String) async throws -> PolicyRule { throw SbxServiceError.cliError("test error") }
    nonisolated func policyDeny(resources: String) async throws -> PolicyRule { throw SbxServiceError.cliError("test error") }
    nonisolated func policyRemove(resource: String) async throws { throw SbxServiceError.cliError("test error") }
    nonisolated func policyLog(sandboxName: String?) async throws -> [PolicyLogEntry] { throw SbxServiceError.cliError("test error") }
    nonisolated func portsList(name: String) async throws -> [PortMapping] { throw SbxServiceError.cliError("test error") }
    nonisolated func portsPublish(name: String, hostPort: Int, sbxPort: Int) async throws -> PortMapping { throw SbxServiceError.cliError("test error") }
    nonisolated func portsUnpublish(name: String, hostPort: Int, sbxPort: Int) async throws { throw SbxServiceError.cliError("test error") }
    nonisolated func envVarList(name: String) async throws -> [EnvVar] { throw SbxServiceError.cliError("test error") }
    nonisolated func envVarSync(name: String, vars: [EnvVar]) async throws { throw SbxServiceError.cliError("test error") }
    nonisolated func exec(name: String, command: String, args: [String]) async throws -> CliResult { throw SbxServiceError.cliError("test error") }
    nonisolated func sendMessage(name: String, message: String) async throws { throw SbxServiceError.cliError("test error") }
}

/// Minimal in-memory stub for unit testing stores. No delays, no complex logic.
actor StubSbxService: SbxServiceProtocol {
    private var sandboxes: [String: Sandbox] = [:]
    private var policies: [String: PolicyRule] = [:]
    private var portMappings: [String: [PortMapping]] = [:]
    private var envVars: [String: [EnvVar]] = [:]
    private var policyLogs: [PolicyLogEntry] = []

    init() {
        let defaults = [
            "api.anthropic.com", "*.npmjs.org", "github.com", "*.github.com",
            "registry.hub.docker.com", "*.docker.io", "*.googleapis.com",
            "api.openai.com", "*.pypi.org", "files.pythonhosted.org",
        ]
        for domain in defaults {
            let rule = PolicyRule(id: UUID().uuidString, type: "network", decision: .allow, resources: domain)
            policies[rule.id] = rule
        }
        policyLogs = [
            PolicyLogEntry(sandbox: "claude-myproject", type: "network", host: "api.anthropic.com", proxy: "forward", rule: "allow", lastSeen: Date(), count: 42, blocked: false),
            PolicyLogEntry(sandbox: "claude-myproject", type: "network", host: "registry.npmjs.org", proxy: "transparent", rule: "allow", lastSeen: Date(), count: 15, blocked: false),
            PolicyLogEntry(sandbox: "claude-myproject", type: "network", host: "evil.example.com", proxy: "network", rule: "deny", lastSeen: Date(), count: 3, blocked: true),
        ]
    }

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
        let name: String
        if let customName = opts?.name, !customName.isEmpty {
            name = customName
        } else {
            let dirname = URL(fileURLWithPath: workspace).lastPathComponent
            name = "claude-\(dirname)"
        }

        guard SbxValidation.isValidName(name) else {
            throw SbxServiceError.invalidName(name)
        }

        // Return existing running sandbox for same workspace
        if let existing = sandboxes.values.first(where: { $0.workspace == workspace && $0.status == .running }) {
            return existing
        }

        // Resume stopped sandbox with same name
        if var existing = sandboxes[name], existing.status == .stopped {
            existing.status = .running
            sandboxes[name] = existing
            return existing
        }

        let sandbox = Sandbox(id: UUID().uuidString, name: name, agent: agent, status: .running, workspace: workspace, ports: [], createdAt: Date())
        sandboxes[name] = sandbox
        return sandbox
    }

    func stop(name: String) async throws {
        guard var sandbox = sandboxes[name] else { throw SbxServiceError.notFound(name) }
        sandbox.status = .stopped
        sandboxes[name] = sandbox
        portMappings[name] = []
    }

    func rm(name: String) async throws {
        guard sandboxes[name] != nil else { throw SbxServiceError.notFound(name) }
        sandboxes.removeValue(forKey: name)
        portMappings.removeValue(forKey: name)
        envVars.removeValue(forKey: name)
    }

    func policyList() async throws -> [PolicyRule] {
        Array(policies.values).sorted { $0.id < $1.id }
    }

    func policyAllow(resources: String) async throws -> PolicyRule {
        let rule = PolicyRule(id: UUID().uuidString, type: "network", decision: .allow, resources: resources)
        policies[rule.id] = rule
        return rule
    }

    func policyDeny(resources: String) async throws -> PolicyRule {
        let rule = PolicyRule(id: UUID().uuidString, type: "network", decision: .deny, resources: resources)
        policies[rule.id] = rule
        return rule
    }

    func policyRemove(resource: String) async throws {
        guard let rule = policies.values.first(where: { $0.resources == resource }) else {
            throw SbxServiceError.notFound(resource)
        }
        policies.removeValue(forKey: rule.id)
    }

    func policyLog(sandboxName: String?) async throws -> [PolicyLogEntry] {
        if let name = sandboxName { return policyLogs.filter { $0.sandbox == name } }
        return policyLogs
    }

    func portsList(name: String) async throws -> [PortMapping] {
        guard sandboxes[name] != nil else { throw SbxServiceError.notFound(name) }
        return portMappings[name] ?? []
    }

    func portsPublish(name: String, hostPort: Int, sbxPort: Int) async throws -> PortMapping {
        guard let sandbox = sandboxes[name] else { throw SbxServiceError.notFound(name) }
        guard sandbox.status == .running else { throw SbxServiceError.notRunning(name) }

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
        guard sandboxes[name] != nil else { throw SbxServiceError.notFound(name) }
        portMappings[name]?.removeAll { $0.hostPort == hostPort && $0.sandboxPort == sbxPort }
    }

    func envVarList(name: String) async throws -> [EnvVar] {
        guard sandboxes[name] != nil else { throw SbxServiceError.notFound(name) }
        return envVars[name] ?? []
    }

    func envVarSync(name: String, vars: [EnvVar]) async throws {
        guard let sandbox = sandboxes[name] else { throw SbxServiceError.notFound(name) }
        guard sandbox.status == .running else { throw SbxServiceError.notRunning(name) }
        envVars[name] = vars
    }

    func exec(name: String, command: String, args: [String]) async throws -> CliResult {
        guard let sandbox = sandboxes[name] else { throw SbxServiceError.notFound(name) }
        guard sandbox.status == .running else { throw SbxServiceError.notRunning(name) }
        let output = "mock exec: \(command) \(args.joined(separator: " "))"
        return CliResult(stdout: output, stderr: "", exitCode: 0)
    }

    func sendMessage(name: String, message: String) async throws {
        guard let sandbox = sandboxes[name] else { throw SbxServiceError.notFound(name) }
        guard sandbox.status == .running else { throw SbxServiceError.notRunning(name) }
    }
}

// MARK: - SbxValidation Tests

struct SbxValidationTests {
    @Test func validNames() {
        #expect(SbxValidation.isValidName("my-sandbox"))
        #expect(SbxValidation.isValidName("a"))
        #expect(SbxValidation.isValidName("abc123"))
        #expect(SbxValidation.isValidName("test-1-2"))
    }

    @Test func invalidLeadingHyphen() {
        #expect(!SbxValidation.isValidName("-leading"))
    }

    @Test func invalidUppercase() {
        #expect(!SbxValidation.isValidName("UPPER"))
    }

    @Test func invalidWithSpace() {
        #expect(!SbxValidation.isValidName("has space"))
    }

    @Test func invalidSpecialChar() {
        #expect(!SbxValidation.isValidName("special!"))
    }

    @Test func invalidEmpty() {
        #expect(!SbxValidation.isValidName(""))
    }
}

// MARK: - StubSbxService Behavioral Tests

struct StubSbxServiceTests {

    // MARK: - Lifecycle

    @Test func createTransitionsToRunning() async throws {
        let service = StubSbxService()
        let sandbox = try await service.run(agent: "claude", workspace: "/tmp/project", opts: nil)
        #expect(sandbox.status == .running)
        #expect(sandbox.name == "claude-project")
        #expect(sandbox.agent == "claude")
    }

    @Test func stopTransitionsToStopped() async throws {
        let service = StubSbxService()
        let sandbox = try await service.run(agent: "claude", workspace: "/tmp/project", opts: nil)
        try await service.stop(name: sandbox.name)
        let list = try await service.list()
        #expect(list.first?.status == .stopped)
    }

    @Test func stoppedCanResume() async throws {
        let service = StubSbxService()
        let sandbox = try await service.run(agent: "claude", workspace: "/tmp/project", opts: nil)
        try await service.stop(name: sandbox.name)
        let resumed = try await service.run(agent: "claude", workspace: "/tmp/project", opts: RunOptions(name: sandbox.name))
        #expect(resumed.status == .running)
    }

    @Test func removeDeletesSandbox() async throws {
        let service = StubSbxService()
        let sandbox = try await service.run(agent: "claude", workspace: "/tmp/project", opts: nil)
        try await service.rm(name: sandbox.name)
        let list = try await service.list()
        #expect(list.isEmpty)
    }

    @Test func duplicateWorkspaceReturnsExisting() async throws {
        let service = StubSbxService()
        let first = try await service.run(agent: "claude", workspace: "/tmp/project", opts: nil)
        let second = try await service.run(agent: "claude", workspace: "/tmp/project", opts: nil)
        #expect(first.id == second.id)
        let list = try await service.list()
        #expect(list.count == 1)
    }

    @Test func invalidNameThrows() async throws {
        let service = StubSbxService()
        do {
            _ = try await service.run(agent: "claude", workspace: "/tmp/project", opts: RunOptions(name: "-invalid"))
            #expect(Bool(false), "Should have thrown")
        } catch let error as SbxServiceError {
            if case .invalidName = error {
                // Expected
            } else {
                #expect(Bool(false), "Wrong error type: \(error)")
            }
        }
    }

    @Test func customNameIsUsed() async throws {
        let service = StubSbxService()
        let sandbox = try await service.run(agent: "claude", workspace: "/tmp/project", opts: RunOptions(name: "my-sandbox"))
        #expect(sandbox.name == "my-sandbox")
    }

    // MARK: - Edge Cases

    @Test func stopNonExistentThrowsNotFound() async throws {
        let service = StubSbxService()
        do {
            try await service.stop(name: "ghost")
            #expect(Bool(false), "Should have thrown")
        } catch let error as SbxServiceError {
            if case .notFound("ghost") = error {} else {
                #expect(Bool(false), "Wrong error: \(error)")
            }
        }
    }

    @Test func rmNonExistentThrowsNotFound() async throws {
        let service = StubSbxService()
        do {
            try await service.rm(name: "ghost")
            #expect(Bool(false), "Should have thrown")
        } catch let error as SbxServiceError {
            if case .notFound = error {} else {
                #expect(Bool(false), "Wrong error: \(error)")
            }
        }
    }

    @Test func sendMessageNonExistentThrows() async throws {
        let service = StubSbxService()
        do {
            try await service.sendMessage(name: "ghost", message: "hi")
            #expect(Bool(false), "Should have thrown")
        } catch let error as SbxServiceError {
            if case .notFound = error {} else {
                #expect(Bool(false), "Wrong error: \(error)")
            }
        }
    }

    @Test func sendMessageStoppedThrows() async throws {
        let service = StubSbxService()
        let sandbox = try await service.run(agent: "claude", workspace: "/tmp/project", opts: nil)
        try await service.stop(name: sandbox.name)
        do {
            try await service.sendMessage(name: sandbox.name, message: "hi")
            #expect(Bool(false), "Should have thrown")
        } catch let error as SbxServiceError {
            if case .notRunning = error {} else {
                #expect(Bool(false), "Wrong error: \(error)")
            }
        }
    }

    @Test func multipleSandboxesCoexist() async throws {
        let service = StubSbxService()
        _ = try await service.run(agent: "claude", workspace: "/tmp/project-a", opts: nil)
        _ = try await service.run(agent: "claude", workspace: "/tmp/project-b", opts: nil)
        let list = try await service.list()
        #expect(list.count == 2)
    }

    // MARK: - Policy Tests

    @Test func balancedDefaultsPresent() async throws {
        let service = StubSbxService()
        let policies = try await service.policyList()
        #expect(policies.count == 10)
        let resources = Set(policies.map(\.resources))
        #expect(resources.contains("api.anthropic.com"))
        #expect(resources.contains("github.com"))
        #expect(resources.contains("*.npmjs.org"))
    }

    @Test func addAllowRule() async throws {
        let service = StubSbxService()
        let rule = try await service.policyAllow(resources: "example.com")
        #expect(rule.decision == .allow)
        #expect(rule.resources == "example.com")
    }

    @Test func addDenyRule() async throws {
        let service = StubSbxService()
        let rule = try await service.policyDeny(resources: "evil.com")
        #expect(rule.decision == .deny)
        #expect(rule.resources == "evil.com")
    }

    @Test func removeRule() async throws {
        let service = StubSbxService()
        let before = try await service.policyList()
        let count = before.count
        try await service.policyRemove(resource: "api.anthropic.com")
        let after = try await service.policyList()
        #expect(after.count == count - 1)
    }

    @Test func policyLogFilterBySandbox() async throws {
        let service = StubSbxService()
        let all = try await service.policyLog(sandboxName: nil)
        #expect(all.count == 3)
        let filtered = try await service.policyLog(sandboxName: "claude-myproject")
        #expect(filtered.count == 3)
        let empty = try await service.policyLog(sandboxName: "nonexistent")
        #expect(empty.isEmpty)
    }

    // MARK: - Port Tests

    @Test func publishPort() async throws {
        let service = StubSbxService()
        let sandbox = try await service.run(agent: "claude", workspace: "/tmp/project", opts: nil)
        let mapping = try await service.portsPublish(name: sandbox.name, hostPort: 8080, sbxPort: 3000)
        #expect(mapping.hostPort == 8080)
        #expect(mapping.sandboxPort == 3000)
    }

    @Test func duplicateHostPortThrows() async throws {
        let service = StubSbxService()
        let sandbox = try await service.run(agent: "claude", workspace: "/tmp/project", opts: nil)
        _ = try await service.portsPublish(name: sandbox.name, hostPort: 8080, sbxPort: 3000)
        do {
            _ = try await service.portsPublish(name: sandbox.name, hostPort: 8080, sbxPort: 4000)
            #expect(Bool(false), "Should have thrown")
        } catch let error as SbxServiceError {
            if case .portConflict(8080) = error {} else {
                #expect(Bool(false), "Wrong error: \(error)")
            }
        }
    }

    @Test func portsClearedOnStop() async throws {
        let service = StubSbxService()
        let sandbox = try await service.run(agent: "claude", workspace: "/tmp/project", opts: nil)
        _ = try await service.portsPublish(name: sandbox.name, hostPort: 8080, sbxPort: 3000)
        try await service.stop(name: sandbox.name)
        let ports = try await service.portsList(name: sandbox.name)
        #expect(ports.isEmpty)
    }

    @Test func publishOnStoppedThrows() async throws {
        let service = StubSbxService()
        let sandbox = try await service.run(agent: "claude", workspace: "/tmp/project", opts: nil)
        try await service.stop(name: sandbox.name)
        do {
            _ = try await service.portsPublish(name: sandbox.name, hostPort: 8080, sbxPort: 3000)
            #expect(Bool(false), "Should have thrown")
        } catch let error as SbxServiceError {
            if case .notRunning = error {} else {
                #expect(Bool(false), "Wrong error: \(error)")
            }
        }
    }

    @Test func portUniquenessAcrossSandboxes() async throws {
        let service = StubSbxService()
        let a = try await service.run(agent: "claude", workspace: "/tmp/a", opts: RunOptions(name: "sandbox-a"))
        let b = try await service.run(agent: "claude", workspace: "/tmp/b", opts: RunOptions(name: "sandbox-b"))
        _ = try await service.portsPublish(name: a.name, hostPort: 8080, sbxPort: 3000)
        do {
            _ = try await service.portsPublish(name: b.name, hostPort: 8080, sbxPort: 4000)
            #expect(Bool(false), "Should have thrown")
        } catch let error as SbxServiceError {
            if case .portConflict(8080) = error {} else {
                #expect(Bool(false), "Wrong error: \(error)")
            }
        }
    }

    @Test func unpublishPortRemovesMapping() async throws {
        let service = StubSbxService()
        let sandbox = try await service.run(agent: "claude", workspace: "/tmp/project", opts: nil)
        _ = try await service.portsPublish(name: sandbox.name, hostPort: 8080, sbxPort: 3000)
        try await service.portsUnpublish(name: sandbox.name, hostPort: 8080, sbxPort: 3000)
        let ports = try await service.portsList(name: sandbox.name)
        #expect(ports.isEmpty)
    }
}

// MARK: - SbxOutputParser Tests

struct SbxOutputParserTests {
    // Real sbx CLI output format (verified against v0.23.0)

    @Test func parseSandboxList() {
        let output = """
        SANDBOX       AGENT    STATUS    PORTS   WORKSPACE
        sbx-ui        claude   stopped           /Users/dev/project
        test-verify   claude   running           /Users/dev/other
        """
        let sandboxes = SbxOutputParser.parseSandboxList(output)
        #expect(sandboxes.count == 2)
        #expect(sandboxes[0].name == "sbx-ui")
        #expect(sandboxes[0].status == .stopped)
        #expect(sandboxes[1].name == "test-verify")
        #expect(sandboxes[1].status == .running)
    }

    @Test func parsePolicyList() {
        // Real format: NAME column (not ID), blank lines between rules
        let output = """
        NAME                                         TYPE      DECISION   RESOURCES
        default-allow-all                            network   allow      **

        local:e8b2eb34-972b-4b2c-9d2d-d30edd7612e6   network   allow      test.example.com

        local:6b0dfb29-a64e-48cc-8a3a-6e35a40704ba   network   deny       evil.example.com
        """
        let rules = SbxOutputParser.parsePolicyList(output)
        #expect(rules.count == 3)
        #expect(rules[0].id == "default-allow-all")
        #expect(rules[0].decision == .allow)
        #expect(rules[2].decision == .deny)
    }

    @Test func parsePortsList() {
        // Port parser matches digit->digit patterns in any format
        let output = """
        127.0.0.1:8080->3000/tcp
        127.0.0.1:9090->4000/tcp
        """
        let ports = SbxOutputParser.parsePortsList(output)
        #expect(ports.count == 2)
        guard ports.count == 2 else { return }
        #expect(ports[0].hostPort == 8080)
        #expect(ports[0].sandboxPort == 3000)
    }

    @Test func parseEmptyOutput() {
        let sandboxes = SbxOutputParser.parseSandboxList("")
        #expect(sandboxes.isEmpty)

        let policies = SbxOutputParser.parsePolicyList("")
        #expect(policies.isEmpty)
    }

    @Test func parseHeaderOnly() {
        let output = "SANDBOX  AGENT  STATUS  PORTS  WORKSPACE\n"
        let sandboxes = SbxOutputParser.parseSandboxList(output)
        #expect(sandboxes.isEmpty)
    }

    @Test func parsePolicyLog() {
        // Real format: grouped by "Allowed requests:" and "Blocked requests:" sections
        let output = """
        Allowed requests:
        SANDBOX       TYPE      HOST                      PROXY            RULE             LAST SEEN        COUNT
        test-verify   network   ports.ubuntu.com:80       forward          domain-allowed   18:55:49 4-Apr   1

        Blocked requests:
        SANDBOX       TYPE      HOST                PROXY     RULE          LAST SEEN        COUNT
        test-verify   network   evil.example.com    forward   user-denied   18:56:01 4-Apr   3
        """
        let entries = SbxOutputParser.parsePolicyLog(output)
        #expect(entries.count == 2)
        #expect(entries[0].host == "ports.ubuntu.com:80")
        #expect(!entries[0].blocked)
        #expect(entries[1].host == "evil.example.com")
        #expect(entries[1].blocked)
    }

    @Test func parseSandboxListWithMultiplePorts() {
        // Real format: "127.0.0.1:8080->3000/tcp, 127.0.0.1:9090->4000/tcp"
        let output = """
        SANDBOX      AGENT    STATUS    PORTS                                                WORKSPACE
        test-ports   claude   running   127.0.0.1:8080->3000/tcp, 127.0.0.1:9090->4000/tcp   /Users/dev/project
        """
        let sandboxes = SbxOutputParser.parseSandboxList(output)
        #expect(sandboxes.count == 1)
        #expect(sandboxes[0].ports.count == 2)
        #expect(sandboxes[0].ports[0].hostPort == 8080)
        #expect(sandboxes[0].ports[1].hostPort == 9090)
    }
}

// MARK: - SandboxStore Tests

struct SandboxStoreTests {
    @Test func fetchPopulatesStore() async throws {
        let service = StubSbxService()
        _ = try await service.run(agent: "claude", workspace: "/tmp/project", opts: nil)
        let store = await SandboxStore(service: service)
        await store.fetchSandboxes()
        let count = await store.sandboxes.count
        #expect(count == 1)
    }

    @Test func createReturnsAndRefreshes() async throws {
        let service = StubSbxService()
        let store = await SandboxStore(service: service)
        let sandbox = try await store.createSandbox(workspace: "/tmp/project", name: "test-create")
        #expect(sandbox.status == .running)
        let count = await store.sandboxes.count
        #expect(count == 1)
    }

    @Test func stopUpdatesState() async throws {
        let service = StubSbxService()
        let store = await SandboxStore(service: service)
        _ = try await store.createSandbox(workspace: "/tmp/project", name: "test-stop")
        try await store.stopSandbox(name: "test-stop")
        let status = await store.sandboxes.first?.status
        #expect(status == .stopped)
    }

    @Test func removeRemovesFromList() async throws {
        let service = StubSbxService()
        let store = await SandboxStore(service: service)
        _ = try await store.createSandbox(workspace: "/tmp/project", name: "test-rm")
        try await store.removeSandbox(name: "test-rm")
        let count = await store.sandboxes.count
        #expect(count == 0)
    }

    @Test func publishPortUpdatesStore() async throws {
        let service = StubSbxService()
        let store = await SandboxStore(service: service)
        _ = try await store.createSandbox(workspace: "/tmp/project", name: "test-port")
        try await store.publishPort(name: "test-port", hostPort: 8080, sbxPort: 3000)
        let ports = await store.sandboxes.first?.ports
        #expect(ports?.count == 1)
        #expect(ports?.first?.hostPort == 8080)
    }

    @Test func unpublishPortUpdatesStore() async throws {
        let service = StubSbxService()
        let store = await SandboxStore(service: service)
        _ = try await store.createSandbox(workspace: "/tmp/project", name: "test-unport")
        try await store.publishPort(name: "test-unport", hostPort: 8080, sbxPort: 3000)
        try await store.unpublishPort(name: "test-unport", hostPort: 8080, sbxPort: 3000)
        let ports = await store.sandboxes.first?.ports
        #expect(ports?.isEmpty == true)
    }

    @Test func fetchErrorSetsErrorProperty() async throws {
        let service = FailingSbxService()
        let store = await SandboxStore(service: service)
        await store.fetchSandboxes()
        let error = await store.error
        #expect(error != nil)
    }
}

// MARK: - SandboxStore busyOperations Tests

struct SandboxStoreBusyOperationsTests {
    @Test func busyOperationsClearedAfterStop() async throws {
        let service = StubSbxService()
        let store = await SandboxStore(service: service)
        _ = try await store.createSandbox(workspace: "/tmp/project", name: "test-busy-stop")
        try await store.stopSandbox(name: "test-busy-stop")
        let busy = await store.isBusy("test-busy-stop")
        #expect(!busy)
        let ops = await store.busyOperations
        #expect(ops.isEmpty)
    }

    @Test func busyOperationsClearedAfterRemove() async throws {
        let service = StubSbxService()
        let store = await SandboxStore(service: service)
        _ = try await store.createSandbox(workspace: "/tmp/project", name: "test-busy-rm")
        try await store.removeSandbox(name: "test-busy-rm")
        let ops = await store.busyOperations
        #expect(ops.isEmpty)
    }

    @Test func busyOperationsClearedAfterResume() async throws {
        let service = StubSbxService()
        let store = await SandboxStore(service: service)
        _ = try await store.createSandbox(workspace: "/tmp/project", name: "test-busy-resume")
        try await store.stopSandbox(name: "test-busy-resume")
        try await store.resumeSandbox(name: "test-busy-resume")
        // Resume is non-blocking — busy state is set immediately
        let ops = await store.busyOperations
        #expect(ops["test-busy-resume"] == .resuming)
        // Yield to let background resume Task complete (changes sandbox to running)
        try await Task.sleep(for: .milliseconds(100))
        // Polling clears it once sandbox shows as running
        await store.fetchSandboxes()
        let opsAfterPoll = await store.busyOperations
        #expect(opsAfterPoll.isEmpty)
    }

    @Test func busyOperationsClearedAfterPublishPort() async throws {
        let service = StubSbxService()
        let store = await SandboxStore(service: service)
        _ = try await store.createSandbox(workspace: "/tmp/project", name: "test-busy-port")
        try await store.publishPort(name: "test-busy-port", hostPort: 9090, sbxPort: 3000)
        let ops = await store.busyOperations
        #expect(ops.isEmpty)
    }

    @Test func busyOperationsClearedAfterUnpublishPort() async throws {
        let service = StubSbxService()
        let store = await SandboxStore(service: service)
        _ = try await store.createSandbox(workspace: "/tmp/project", name: "test-busy-unport")
        try await store.publishPort(name: "test-busy-unport", hostPort: 9091, sbxPort: 3000)
        try await store.unpublishPort(name: "test-busy-unport", hostPort: 9091, sbxPort: 3000)
        let ops = await store.busyOperations
        #expect(ops.isEmpty)
    }

    @Test func isCreatingClearedAfterCreate() async throws {
        let service = StubSbxService()
        let store = await SandboxStore(service: service)
        _ = try await store.createSandbox(workspace: "/tmp/project", name: "test-busy-create")
        let creating = await store.isCreating
        #expect(!creating)
    }

    @Test func busyOperationsClearedOnError() async throws {
        let service = FailingSbxService()
        let store = await SandboxStore(service: service)
        do {
            try await store.stopSandbox(name: "nonexistent")
        } catch {
            // Expected
        }
        let ops = await store.busyOperations
        #expect(ops.isEmpty)
    }

    @Test func isCreatingClearedOnError() async throws {
        let service = FailingSbxService()
        let store = await SandboxStore(service: service)
        do {
            try await store.createSandbox(workspace: "/tmp/project", name: "fail")
        } catch {
            // Expected
        }
        let creating = await store.isCreating
        #expect(!creating)
    }

    @Test func initialLoadingTrueBeforeFetch() async throws {
        let service = StubSbxService()
        let store = await SandboxStore(service: service)
        let loading = await store.initialLoading
        #expect(loading)
    }

    @Test func initialLoadingFalseAfterFetch() async throws {
        let service = StubSbxService()
        let store = await SandboxStore(service: service)
        await store.fetchSandboxes()
        let loading = await store.initialLoading
        #expect(!loading)
    }

    @Test func initialLoadingFalseAfterFetchError() async throws {
        let service = FailingSbxService()
        let store = await SandboxStore(service: service)
        await store.fetchSandboxes()
        let loading = await store.initialLoading
        #expect(!loading)
    }
}

// MARK: - PolicyStore Tests

struct PolicyStoreTests {
    @Test func fetchPopulatesRules() async throws {
        let service = StubSbxService()
        let store = await PolicyStore(service: service)
        await store.fetchPolicies()
        let count = await store.rules.count
        #expect(count == 10)
    }

    @Test func addAllowCreatesAndRefreshes() async throws {
        let service = StubSbxService()
        let store = await PolicyStore(service: service)
        try await store.addAllow(resources: "test.com")
        let rules = await store.rules
        #expect(rules.contains(where: { $0.resources == "test.com" && $0.decision == .allow }))
    }

    @Test func addDenyCreatesAndRefreshes() async throws {
        let service = StubSbxService()
        let store = await PolicyStore(service: service)
        try await store.addDeny(resources: "evil.com")
        let rules = await store.rules
        #expect(rules.contains(where: { $0.resources == "evil.com" && $0.decision == .deny }))
    }

    @Test func removeRuleDecrementsCount() async throws {
        let service = StubSbxService()
        let store = await PolicyStore(service: service)
        await store.fetchPolicies()
        let before = await store.rules.count
        try await store.removeRule(resource: "api.anthropic.com")
        let after = await store.rules.count
        #expect(after == before - 1)
    }

    @Test func fetchLogPopulatesEntries() async throws {
        let service = StubSbxService()
        let store = await PolicyStore(service: service)
        await store.fetchLog()
        let count = await store.logEntries.count
        #expect(count == 3)
    }

    @Test func filteredLogBySandbox() async throws {
        let service = StubSbxService()
        let store = await PolicyStore(service: service)
        await store.fetchLog()
        await MainActor.run { store.logFilter.sandboxName = "claude-myproject" }
        let filtered = await store.filteredLog
        #expect(filtered.count == 3)
        await MainActor.run { store.logFilter.sandboxName = "nonexistent" }
        let empty = await store.filteredLog
        #expect(empty.isEmpty)
    }

    @Test func filteredLogBlockedOnly() async throws {
        let service = StubSbxService()
        let store = await PolicyStore(service: service)
        await store.fetchLog()
        await MainActor.run { store.logFilter.blockedOnly = true }
        let filtered = await store.filteredLog
        #expect(filtered.count == 1)
        #expect(filtered.first?.blocked == true)
    }
}

// MARK: - PolicyStore Loading State Tests

struct PolicyStoreLoadingStateTests {
    @Test func removingResourcesClearedAfterRemove() async throws {
        let service = StubSbxService()
        let store = await PolicyStore(service: service)
        await store.fetchPolicies()
        try await store.removeRule(resource: "api.anthropic.com")
        let removing = await store.removingResources
        #expect(removing.isEmpty)
    }

    @Test func removingResourcesClearedOnError() async throws {
        let service = StubSbxService()
        let store = await PolicyStore(service: service)
        do {
            try await store.removeRule(resource: "nonexistent.com")
        } catch {
            // Expected
        }
        let removing = await store.removingResources
        #expect(removing.isEmpty)
    }

    @Test func loadingLogClearedAfterFetch() async throws {
        let service = StubSbxService()
        let store = await PolicyStore(service: service)
        await store.fetchLog()
        let loading = await store.loadingLog
        #expect(!loading)
    }

    @Test func loadingClearedAfterFetchPolicies() async throws {
        let service = StubSbxService()
        let store = await PolicyStore(service: service)
        await store.fetchPolicies()
        let loading = await store.loading
        #expect(!loading)
    }
}

// MARK: - TerminalSessionStore Tests

struct TerminalSessionStoreTests {
    @Test func initialStateIsEmpty() async {
        let service = StubSbxService()
        let store = await TerminalSessionStore(service: service, processLauncher: StubProcessLauncher())
        let count = await store.activeSessionCount
        let ids = await store.activeSessionIDs
        #expect(count == 0)
        #expect(ids.isEmpty)
    }

    @Test func hasAnySessionReturnsFalseForUnknown() async {
        let service = StubSbxService()
        let store = await TerminalSessionStore(service: service, processLauncher: StubProcessLauncher())
        let active = await store.hasAnySession(sandboxName: "nonexistent")
        #expect(active == false)
    }

    @Test func sessionLookupReturnsNilForUnknown() async {
        let service = StubSbxService()
        let store = await TerminalSessionStore(service: service, processLauncher: StubProcessLauncher())
        let session = await store.session(for: "nonexistent-id")
        #expect(session == nil)
    }

    @Test func disconnectNoOpForUnknown() async {
        let service = StubSbxService()
        let store = await TerminalSessionStore(service: service, processLauncher: StubProcessLauncher())
        await store.disconnect(sessionID: "nonexistent-id")
        let count = await store.activeSessionCount
        #expect(count == 0)
    }

    @Test func disconnectAllClearsEverything() async {
        let service = StubSbxService()
        let store = await TerminalSessionStore(service: service, processLauncher: StubProcessLauncher())
        await store.disconnectAll()
        let count = await store.activeSessionCount
        #expect(count == 0)
    }

    @Test func cleanupStaleSessions() async {
        let service = StubSbxService()
        let store = await TerminalSessionStore(service: service, processLauncher: StubProcessLauncher())

        _ = await store.startSession(sandboxName: "sandbox-a", type: .agent)
        let countBefore = await store.activeSessionCount
        #expect(countBefore == 1)

        await store.cleanupStaleSessions(sandboxes: [])
        let countAfter = await store.activeSessionCount
        #expect(countAfter == 0)
    }

    @Test func cleanupKeepsRunningSessions() async {
        let service = StubSbxService()
        let store = await TerminalSessionStore(service: service, processLauncher: StubProcessLauncher())

        _ = await store.startSession(sandboxName: "sandbox-a", type: .agent)
        let runningSandbox = Sandbox(
            id: "sandbox-a", name: "sandbox-a", agent: "claude",
            status: .running, workspace: "/tmp", ports: [], createdAt: Date()
        )
        await store.cleanupStaleSessions(sandboxes: [runningSandbox])
        let count = await store.activeSessionCount
        #expect(count == 1)
    }

    @Test func agentSessionIsIdempotent() async {
        let service = StubSbxService()
        let store = await TerminalSessionStore(service: service, processLauncher: StubProcessLauncher())

        let (id1, view1) = await store.startSession(sandboxName: "test", type: .agent)
        let (id2, view2) = await store.startSession(sandboxName: "test", type: .agent)
        #expect(id1 == id2)
        #expect(view1 === view2)
        let count = await store.activeSessionCount
        #expect(count == 1)
    }

    @Test func shellSessionAlwaysCreatesNew() async {
        let service = StubSbxService()
        let store = await TerminalSessionStore(service: service, processLauncher: StubProcessLauncher())

        let (id1, _) = await store.startSession(sandboxName: "test", type: .shell)
        let (id2, _) = await store.startSession(sandboxName: "test", type: .shell)
        #expect(id1 != id2)
        let count = await store.activeSessionCount
        #expect(count == 2)
    }

    @Test func agentAndShellCoexist() async {
        let service = StubSbxService()
        let store = await TerminalSessionStore(service: service, processLauncher: StubProcessLauncher())

        let (agentID, _) = await store.startSession(sandboxName: "test", type: .agent)
        let (shellID, _) = await store.startSession(sandboxName: "test", type: .shell)
        #expect(agentID != shellID)
        let count = await store.activeSessionCount
        #expect(count == 2)

        let foundAgentID = await store.agentSessionID(for: "test")
        #expect(foundAgentID == agentID)

        let sessions = await store.sessions(for: "test")
        #expect(sessions.count == 2)
    }

    @Test func disconnectShellPreservesAgent() async {
        let service = StubSbxService()
        let store = await TerminalSessionStore(service: service, processLauncher: StubProcessLauncher())

        _ = await store.startSession(sandboxName: "test", type: .agent)
        let (shellID, _) = await store.startSession(sandboxName: "test", type: .shell)
        await store.disconnect(sessionID: shellID)

        let count = await store.activeSessionCount
        #expect(count == 1)
        let hasAgent = await store.agentSessionID(for: "test")
        #expect(hasAgent != nil)
    }

    @Test func shellLabelsIncrement() async {
        let service = StubSbxService()
        let store = await TerminalSessionStore(service: service, processLauncher: StubProcessLauncher())

        let (id1, _) = await store.startSession(sandboxName: "test", type: .shell)
        let (id2, _) = await store.startSession(sandboxName: "test", type: .shell)
        let s1 = await store.session(for: id1)
        let s2 = await store.session(for: id2)
        #expect(s1?.label == "test (shell 1)")
        #expect(s2?.label == "test (shell 2)")
    }

    @Test func multipleAgentSessionsTrackedIndependently() async {
        let service = StubSbxService()
        let store = await TerminalSessionStore(service: service, processLauncher: StubProcessLauncher())

        let (idA, _) = await store.startSession(sandboxName: "alpha", type: .agent)
        let (idB, _) = await store.startSession(sandboxName: "beta", type: .agent)
        let count = await store.activeSessionCount
        #expect(count == 2)

        await store.disconnect(sessionID: idA)
        let countAfter = await store.activeSessionCount
        let activeAlpha = await store.hasAnySession(sandboxName: "alpha")
        let activeBeta = await store.hasAnySession(sandboxName: "beta")
        #expect(countAfter == 1)
        #expect(activeAlpha == false)
        #expect(activeBeta == true)
    }

    @Test func sendMessageWhenNoSessionNoOp() async throws {
        let service = StubSbxService()
        let store = await TerminalSessionStore(service: service, processLauncher: StubProcessLauncher())
        try await store.sendMessage("hello", to: "nonexistent")
    }

    @Test func captureSnapshotsDoesNotCrash() async {
        let service = StubSbxService()
        let store = await TerminalSessionStore(service: service, processLauncher: StubProcessLauncher())

        _ = await store.startSession(sandboxName: "snap-test", type: .agent)
        await store.captureSnapshots()
    }

    @Test func disconnectClearsThumbnail() async {
        let service = StubSbxService()
        let store = await TerminalSessionStore(service: service, processLauncher: StubProcessLauncher())

        let (id, _) = await store.startSession(sandboxName: "snap-cleanup", type: .agent)
        await store.captureSnapshots()

        await store.disconnect(sessionID: id)
        let after = await store.thumbnails[id]
        #expect(after == nil)
    }

    @Test func cleanupStaleSessionsClearsThumbnails() async {
        let service = StubSbxService()
        let store = await TerminalSessionStore(service: service, processLauncher: StubProcessLauncher())

        let (id, _) = await store.startSession(sandboxName: "snap-stale", type: .agent)
        await store.captureSnapshots()

        await store.cleanupStaleSessions(sandboxes: [])
        let after = await store.thumbnails[id]
        #expect(after == nil)
        let count = await store.activeSessionCount
        #expect(count == 0)
    }

    @Test func captureSnapshotsEmptyNoOp() async {
        let service = StubSbxService()
        let store = await TerminalSessionStore(service: service, processLauncher: StubProcessLauncher())
        await store.captureSnapshots()
        let thumbnails = await store.thumbnails
        #expect(thumbnails.isEmpty)
    }

    // MARK: - Multi-Session Switching

    @Test func switchBetweenThreeAgentSessions() async {
        let service = StubSbxService()
        let store = await TerminalSessionStore(service: service, processLauncher: StubProcessLauncher())

        let (_, viewA) = await store.startSession(sandboxName: "session-a", type: .agent)
        let (_, viewB) = await store.startSession(sandboxName: "session-b", type: .agent)
        let (_, viewC) = await store.startSession(sandboxName: "session-c", type: .agent)

        let count = await store.activeSessionCount
        #expect(count == 3)

        // Reattach to session-a — should return same view (idempotent)
        let (_, viewA2) = await store.startSession(sandboxName: "session-a", type: .agent)
        #expect(viewA === viewA2)

        // Views are distinct instances
        #expect(viewA !== viewB)
        #expect(viewB !== viewC)
        #expect(viewA !== viewC)
    }

    @Test func disconnectMiddleSessionPreservesOthers() async {
        let service = StubSbxService()
        let store = await TerminalSessionStore(service: service, processLauncher: StubProcessLauncher())

        let (idFirst, _) = await store.startSession(sandboxName: "first", type: .agent)
        let (idMiddle, _) = await store.startSession(sandboxName: "middle", type: .agent)
        _ = await store.startSession(sandboxName: "last", type: .agent)

        await store.disconnect(sessionID: idMiddle)

        let count = await store.activeSessionCount
        #expect(count == 2)
        #expect(await store.hasAnySession(sandboxName: "first") == true)
        #expect(await store.hasAnySession(sandboxName: "middle") == false)
        #expect(await store.hasAnySession(sandboxName: "last") == true)

        let sessionFirst = await store.session(for: idFirst)
        #expect(sessionFirst?.sandboxName == "first")
    }

    @Test func disconnectAllWithMultipleSessions() async {
        let service = StubSbxService()
        let store = await TerminalSessionStore(service: service, processLauncher: StubProcessLauncher())

        _ = await store.startSession(sandboxName: "a", type: .agent)
        _ = await store.startSession(sandboxName: "b", type: .agent)
        _ = await store.startSession(sandboxName: "c", type: .agent)
        await store.captureSnapshots()

        #expect(await store.activeSessionCount == 3)

        await store.disconnectAll()

        #expect(await store.activeSessionCount == 0)
        #expect(await store.thumbnails.isEmpty)
    }

    @Test func cleanupRemovesOnlyStaleFromMultiple() async {
        let service = StubSbxService()
        let store = await TerminalSessionStore(service: service, processLauncher: StubProcessLauncher())

        _ = await store.startSession(sandboxName: "running-1", type: .agent)
        _ = await store.startSession(sandboxName: "running-2", type: .agent)
        _ = await store.startSession(sandboxName: "stopped-1", type: .agent)
        _ = await store.startSession(sandboxName: "stopped-2", type: .agent)

        let runningSandboxes = [
            Sandbox(id: "running-1", name: "running-1", agent: "claude",
                    status: .running, workspace: "/tmp", ports: [], createdAt: Date()),
            Sandbox(id: "running-2", name: "running-2", agent: "claude",
                    status: .running, workspace: "/tmp", ports: [], createdAt: Date()),
        ]

        await store.cleanupStaleSessions(sandboxes: runningSandboxes)

        #expect(await store.activeSessionCount == 2)
        #expect(await store.hasAnySession(sandboxName: "running-1") == true)
        #expect(await store.hasAnySession(sandboxName: "running-2") == true)
        #expect(await store.hasAnySession(sandboxName: "stopped-1") == false)
        #expect(await store.hasAnySession(sandboxName: "stopped-2") == false)
    }

    @Test func restartAgentSessionAfterDisconnect() async {
        let service = StubSbxService()
        let store = await TerminalSessionStore(service: service, processLauncher: StubProcessLauncher())

        let (id1, view1) = await store.startSession(sandboxName: "restart-test", type: .agent)
        let session1 = await store.session(for: id1)
        let startTime1 = session1?.startTime

        await store.disconnect(sessionID: id1)
        #expect(await store.hasAnySession(sandboxName: "restart-test") == false)

        let (id2, view2) = await store.startSession(sandboxName: "restart-test", type: .agent)
        let session2 = await store.session(for: id2)

        #expect(id1 != id2)
        #expect(view1 !== view2)
        #expect(await store.hasAnySession(sandboxName: "restart-test") == true)
        if let t1 = startTime1, let t2 = session2?.startTime {
            #expect(t2 >= t1)
        }
    }

    @Test func processExitDisconnectsSession() async throws {
        let service = StubSbxService()
        let store = await TerminalSessionStore(service: service, processLauncher: StubProcessLauncher())

        let (_, view) = await store.startSession(sandboxName: "exit-test", type: .agent)
        #expect(await store.hasAnySession(sandboxName: "exit-test") == true)

        await view.onProcessExit?(0)
        try await Task.sleep(for: .milliseconds(100))

        #expect(await store.hasAnySession(sandboxName: "exit-test") == false)
        #expect(await store.activeSessionCount == 0)
    }

    @Test func processExitClearsThumbnail() async throws {
        let service = StubSbxService()
        let store = await TerminalSessionStore(service: service, processLauncher: StubProcessLauncher())

        let (id, view) = await store.startSession(sandboxName: "exit-thumb", type: .agent)
        await store.captureSnapshots()

        await view.onProcessExit?(0)
        try await Task.sleep(for: .milliseconds(100))

        let thumb = await store.thumbnails[id]
        #expect(thumb == nil)
    }

    @Test func processExitPreservesOtherSessions() async throws {
        let service = StubSbxService()
        let store = await TerminalSessionStore(service: service, processLauncher: StubProcessLauncher())

        _ = await store.startSession(sandboxName: "alive", type: .agent)
        let (_, viewB) = await store.startSession(sandboxName: "exiting", type: .agent)

        await viewB.onProcessExit?(0)
        try await Task.sleep(for: .milliseconds(100))

        #expect(await store.hasAnySession(sandboxName: "alive") == true)
        #expect(await store.hasAnySession(sandboxName: "exiting") == false)
        #expect(await store.activeSessionCount == 1)
    }

    @Test func sessionMetadataPerSession() async {
        let service = StubSbxService()
        let store = await TerminalSessionStore(service: service, processLauncher: StubProcessLauncher())

        let (idA, _) = await store.startSession(sandboxName: "alpha", type: .agent)
        try? await Task.sleep(for: .milliseconds(10))
        let (idB, _) = await store.startSession(sandboxName: "beta", type: .agent)

        let sessionA = await store.session(for: idA)
        let sessionB = await store.session(for: idB)

        #expect(sessionA?.sandboxName == "alpha")
        #expect(sessionB?.sandboxName == "beta")
        #expect(sessionA?.connected == true)
        #expect(sessionB?.connected == true)
        #expect(sessionA?.sessionType == .agent)

        if let tA = sessionA?.startTime, let tB = sessionB?.startTime {
            #expect(tB >= tA)
        }
    }

    @Test func agentAndShellHaveDistinctTerminalViews() async {
        let service = StubSbxService()
        let store = await TerminalSessionStore(service: service, processLauncher: StubProcessLauncher())

        let (agentID, agentView) = await store.startSession(sandboxName: "test", type: .agent)
        let (shellID, shellView) = await store.startSession(sandboxName: "test", type: .shell)

        // Different session IDs
        #expect(agentID != shellID)
        // Different terminal view instances — critical for session switching
        #expect(agentView !== shellView)

        // Each session lookup returns the correct view
        let agentSession = await store.session(for: agentID)
        let shellSession = await store.session(for: shellID)
        #expect(agentSession?.terminalView === agentView)
        #expect(shellSession?.terminalView === shellView)
    }

    @Test func cleanupClearsAllSessionTypesForSandbox() async {
        let service = StubSbxService()
        let store = await TerminalSessionStore(service: service, processLauncher: StubProcessLauncher())

        _ = await store.startSession(sandboxName: "sandbox-a", type: .agent)
        _ = await store.startSession(sandboxName: "sandbox-a", type: .shell)
        _ = await store.startSession(sandboxName: "sandbox-a", type: .shell)
        #expect(await store.activeSessionCount == 3)

        await store.cleanupStaleSessions(sandboxes: [])
        #expect(await store.activeSessionCount == 0)
    }
}

// MARK: - EnvVar Validation Tests

struct EnvVarValidationTests {
    @Test func validEnvKeys() {
        #expect(SbxValidation.isValidEnvKey("MY_VAR"))
        #expect(SbxValidation.isValidEnvKey("API_KEY"))
        #expect(SbxValidation.isValidEnvKey("_private"))
        #expect(SbxValidation.isValidEnvKey("a"))
        #expect(SbxValidation.isValidEnvKey("FOO123"))
        #expect(SbxValidation.isValidEnvKey("camelCase"))
    }

    @Test func invalidEnvKeyStartsWithDigit() {
        #expect(!SbxValidation.isValidEnvKey("1BAD"))
        #expect(!SbxValidation.isValidEnvKey("123"))
    }

    @Test func invalidEnvKeyWithSpecialChars() {
        #expect(!SbxValidation.isValidEnvKey("MY-VAR"))
        #expect(!SbxValidation.isValidEnvKey("MY VAR"))
        #expect(!SbxValidation.isValidEnvKey("MY.VAR"))
        #expect(!SbxValidation.isValidEnvKey("$VAR"))
    }

    @Test func emptyKeyInvalid() {
        #expect(!SbxValidation.isValidEnvKey(""))
    }
}

// MARK: - StubSbxService EnvVar Tests

struct StubSbxServiceEnvVarTests {
    @Test func setEnvVarOnRunningSandbox() async throws {
        let service = StubSbxService()
        _ = try await service.run(agent: "claude", workspace: "/tmp/proj", opts: RunOptions(name: "test"))
        try await service.envVarSync(name: "test", vars: [EnvVar(key: "FOO", value: "bar")])
        let vars = try await service.envVarList(name: "test")
        #expect(vars.count == 1)
        #expect(vars[0].key == "FOO")
        #expect(vars[0].value == "bar")
    }

    @Test func setEnvVarOnStoppedThrows() async throws {
        let service = StubSbxService()
        _ = try await service.run(agent: "claude", workspace: "/tmp/proj", opts: RunOptions(name: "test"))
        try await service.stop(name: "test")
        do {
            try await service.envVarSync(name: "test", vars: [EnvVar(key: "FOO", value: "bar")])
            #expect(Bool(false), "Expected error")
        } catch let error as SbxServiceError {
            if case .notRunning = error {} else {
                #expect(Bool(false), "Expected notRunning error, got \(error)")
            }
        }
    }

    @Test func setEnvVarOnNonExistentThrows() async throws {
        let service = StubSbxService()
        do {
            try await service.envVarSync(name: "ghost", vars: [EnvVar(key: "X", value: "1")])
            #expect(Bool(false), "Expected error")
        } catch let error as SbxServiceError {
            if case .notFound = error {} else {
                #expect(Bool(false), "Expected notFound error, got \(error)")
            }
        }
    }

    @Test func envVarListReturnsEmpty() async throws {
        let service = StubSbxService()
        _ = try await service.run(agent: "claude", workspace: "/tmp/proj", opts: RunOptions(name: "test"))
        let vars = try await service.envVarList(name: "test")
        #expect(vars.isEmpty)
    }

    @Test func envVarSyncOverwritesPrevious() async throws {
        let service = StubSbxService()
        _ = try await service.run(agent: "claude", workspace: "/tmp/proj", opts: RunOptions(name: "test"))
        try await service.envVarSync(name: "test", vars: [EnvVar(key: "A", value: "1")])
        try await service.envVarSync(name: "test", vars: [EnvVar(key: "B", value: "2")])
        let vars = try await service.envVarList(name: "test")
        #expect(vars.count == 1)
        #expect(vars[0].key == "B")
    }

    @Test func envVarListPreservesOrder() async throws {
        let service = StubSbxService()
        _ = try await service.run(agent: "claude", workspace: "/tmp/proj", opts: RunOptions(name: "test"))
        let ordered = [EnvVar(key: "Z", value: "3"), EnvVar(key: "A", value: "1"), EnvVar(key: "M", value: "2")]
        try await service.envVarSync(name: "test", vars: ordered)
        let vars = try await service.envVarList(name: "test")
        #expect(vars.map(\.key) == ["Z", "A", "M"])
    }

    @Test func envVarsCleanedOnRemove() async throws {
        let service = StubSbxService()
        _ = try await service.run(agent: "claude", workspace: "/tmp/proj", opts: RunOptions(name: "test"))
        try await service.envVarSync(name: "test", vars: [EnvVar(key: "X", value: "1")])
        try await service.rm(name: "test")
        do {
            _ = try await service.envVarList(name: "test")
            #expect(Bool(false), "Expected error")
        } catch let error as SbxServiceError {
            if case .notFound = error {} else {
                #expect(Bool(false), "Expected notFound error")
            }
        }
    }
}

// MARK: - SbxOutputParser EnvVar Tests

struct SbxOutputParserEnvVarTests {
    @Test func parseManagedSectionOnly() {
        let content = """
        export USER_VAR=outside
        # --- sbx-ui managed (DO NOT EDIT) ---
        export API_KEY=sk-123
        export MY_VAR=hello
        # --- end sbx-ui managed ---
        export AFTER_VAR=below
        """
        let vars = SbxOutputParser.parseManagedEnvVars(content)
        #expect(vars.count == 2)
        #expect(vars[0].key == "API_KEY")
        #expect(vars[0].value == "sk-123")
        #expect(vars[1].key == "MY_VAR")
        #expect(vars[1].value == "hello")
    }

    @Test func parseIgnoresUserContentOutsideMarkers() {
        let content = """
        export MANUAL=yes
        export OTHER=value
        """
        let vars = SbxOutputParser.parseManagedEnvVars(content)
        #expect(vars.isEmpty)
    }

    @Test func parseEmptyWhenNoMarkers() {
        let vars = SbxOutputParser.parseManagedEnvVars("")
        #expect(vars.isEmpty)
    }

    @Test func parseSkipsCommentsAndBlankLines() {
        let content = """
        # --- sbx-ui managed (DO NOT EDIT) ---
        # This is a comment

        export VALID=yes
        # --- end sbx-ui managed ---
        """
        let vars = SbxOutputParser.parseManagedEnvVars(content)
        #expect(vars.count == 1)
        #expect(vars[0].key == "VALID")
    }

    @Test func parseSkipsInvalidKeys() {
        let content = """
        # --- sbx-ui managed (DO NOT EDIT) ---
        export 1BAD=value
        export GOOD=value
        export MY-VAR=bad
        # --- end sbx-ui managed ---
        """
        let vars = SbxOutputParser.parseManagedEnvVars(content)
        #expect(vars.count == 1)
        #expect(vars[0].key == "GOOD")
    }

    @Test func parseWithoutExportPrefix() {
        let content = """
        # --- sbx-ui managed (DO NOT EDIT) ---
        FOO=bar
        # --- end sbx-ui managed ---
        """
        let vars = SbxOutputParser.parseManagedEnvVars(content)
        #expect(vars.count == 1)
        #expect(vars[0].key == "FOO")
        #expect(vars[0].value == "bar")
    }

    // MARK: - rebuildPersistentSh Tests

    @Test func rebuildInsertsBlockWhenNoMarkers() {
        let existing = "export USER_VAR=hello\n"
        let result = SbxOutputParser.rebuildPersistentSh(
            existingContent: existing,
            managedVars: [EnvVar(key: "API_KEY", value: "sk-123")]
        )
        #expect(result.contains("export USER_VAR=hello"))
        #expect(result.contains("# --- sbx-ui managed (DO NOT EDIT) ---"))
        #expect(result.contains("export API_KEY=sk-123"))
        #expect(result.contains("# --- end sbx-ui managed ---"))
    }

    @Test func rebuildReplacesExistingManagedBlock() {
        let existing = """
        export BEFORE=yes
        # --- sbx-ui managed (DO NOT EDIT) ---
        export OLD=value
        # --- end sbx-ui managed ---
        export AFTER=yes
        """
        let result = SbxOutputParser.rebuildPersistentSh(
            existingContent: existing,
            managedVars: [EnvVar(key: "NEW", value: "fresh")]
        )
        #expect(result.contains("export BEFORE=yes"))
        #expect(result.contains("export NEW=fresh"))
        #expect(result.contains("export AFTER=yes"))
        #expect(!result.contains("export OLD=value"))
    }

    @Test func rebuildRemovesManagedBlockWhenEmpty() {
        let existing = """
        export KEEP=yes
        # --- sbx-ui managed (DO NOT EDIT) ---
        export REMOVE=me
        # --- end sbx-ui managed ---
        export ALSO_KEEP=yes
        """
        let result = SbxOutputParser.rebuildPersistentSh(
            existingContent: existing,
            managedVars: []
        )
        #expect(result.contains("export KEEP=yes"))
        #expect(result.contains("export ALSO_KEEP=yes"))
        #expect(!result.contains("sbx-ui managed"))
        #expect(!result.contains("export REMOVE=me"))
    }

    @Test func rebuildHandlesEmptyExistingFile() {
        let result = SbxOutputParser.rebuildPersistentSh(
            existingContent: "",
            managedVars: [EnvVar(key: "NEW", value: "val")]
        )
        #expect(result.contains("# --- sbx-ui managed (DO NOT EDIT) ---"))
        #expect(result.contains("export NEW=val"))
        #expect(result.contains("# --- end sbx-ui managed ---"))
    }

    @Test func rebuildEmptyVarsOnEmptyFileReturnsEmpty() {
        let result = SbxOutputParser.rebuildPersistentSh(
            existingContent: "",
            managedVars: []
        )
        #expect(result.isEmpty)
    }

    @Test func rebuildPreservesUserContentSurroundingMarkers() {
        let existing = """
        #!/bin/bash
        # My custom setup
        export PATH=$PATH:/custom/bin

        # --- sbx-ui managed (DO NOT EDIT) ---
        export OLD_KEY=old
        # --- end sbx-ui managed ---

        # Post-setup
        echo "loaded"
        """
        let result = SbxOutputParser.rebuildPersistentSh(
            existingContent: existing,
            managedVars: [EnvVar(key: "A", value: "1"), EnvVar(key: "B", value: "2")]
        )
        #expect(result.contains("#!/bin/bash"))
        #expect(result.contains("export PATH=$PATH:/custom/bin"))
        #expect(result.contains("export A=1"))
        #expect(result.contains("export B=2"))
        #expect(result.contains("echo \"loaded\""))
        #expect(!result.contains("export OLD_KEY=old"))
    }
}

// MARK: - EnvVarStore Tests

struct EnvVarStoreTests {
    @Test func fetchPopulatesForSandbox() async throws {
        let service = StubSbxService()
        _ = try await service.run(agent: "claude", workspace: "/tmp/proj", opts: RunOptions(name: "test"))
        try await service.envVarSync(name: "test", vars: [EnvVar(key: "A", value: "1")])
        let store = await EnvVarStore(service: service)
        await store.fetchEnvVars(for: "test")
        let vars = await store.vars(for: "test")
        #expect(vars.count == 1)
        #expect(vars[0].key == "A")
    }

    @Test func addEnvVarSyncsAndUpdatesState() async throws {
        let service = StubSbxService()
        _ = try await service.run(agent: "claude", workspace: "/tmp/proj", opts: RunOptions(name: "test"))
        let store = await EnvVarStore(service: service)
        try await store.addEnvVar(sandboxName: "test", key: "FOO", value: "bar")
        let vars = await store.vars(for: "test")
        #expect(vars.count == 1)
        #expect(vars[0].key == "FOO")
        // Verify it was actually synced to the service
        let serviceVars = try await service.envVarList(name: "test")
        #expect(serviceVars.count == 1)
    }

    @Test func removeEnvVarSyncsAndUpdatesState() async throws {
        let service = StubSbxService()
        _ = try await service.run(agent: "claude", workspace: "/tmp/proj", opts: RunOptions(name: "test"))
        let store = await EnvVarStore(service: service)
        try await store.addEnvVar(sandboxName: "test", key: "A", value: "1")
        try await store.addEnvVar(sandboxName: "test", key: "B", value: "2")
        try await store.removeEnvVar(sandboxName: "test", key: "A")
        let vars = await store.vars(for: "test")
        #expect(vars.count == 1)
        #expect(vars[0].key == "B")
    }

    @Test func addExistingKeyOverwrites() async throws {
        let service = StubSbxService()
        _ = try await service.run(agent: "claude", workspace: "/tmp/proj", opts: RunOptions(name: "test"))
        let store = await EnvVarStore(service: service)
        try await store.addEnvVar(sandboxName: "test", key: "X", value: "old")
        try await store.addEnvVar(sandboxName: "test", key: "X", value: "new")
        let vars = await store.vars(for: "test")
        #expect(vars.count == 1)
        #expect(vars[0].value == "new")
    }

    @Test func syncInitialEnvVarsWritesAll() async throws {
        let service = StubSbxService()
        _ = try await service.run(agent: "claude", workspace: "/tmp/proj", opts: RunOptions(name: "test"))
        let store = await EnvVarStore(service: service)
        try await store.syncInitialEnvVars(
            sandboxName: "test",
            vars: [EnvVar(key: "A", value: "1"), EnvVar(key: "B", value: "2")]
        )
        let vars = await store.vars(for: "test")
        #expect(vars.count == 2)
    }

    @Test func syncInitialSkipsEmpty() async throws {
        let service = StubSbxService()
        _ = try await service.run(agent: "claude", workspace: "/tmp/proj", opts: RunOptions(name: "test"))
        let store = await EnvVarStore(service: service)
        try await store.syncInitialEnvVars(sandboxName: "test", vars: [])
        let vars = await store.vars(for: "test")
        #expect(vars.isEmpty)
    }

    @Test func fetchErrorSetsErrorProperty() async {
        let service = FailingSbxService()
        let store = await EnvVarStore(service: service)
        await store.fetchEnvVars(for: "nonexistent")
        let error = await store.error
        #expect(error != nil)
    }
}

// MARK: - JSON-RPC Protocol Tests

struct JsonRpcProtocolTests {
    @Test func encodeDecodeRequest() throws {
        let request = JsonRpcRequest(id: .int(1), method: "sandbox/list", params: ["filter": .string("running")])
        let data = try JsonRpcCodec.encode(.request(request))
        let decoded = try JsonRpcCodec.decode(data)
        guard case .request(let r) = decoded else {
            Issue.record("Expected request")
            return
        }
        #expect(r.id == .int(1))
        #expect(r.method == "sandbox/list")
        #expect(r.params?["filter"]?.stringValue == "running")
    }

    @Test func encodeDecodeResponse() throws {
        let response = JsonRpcResponse.success(id: .int(42), result: .object(["name": .string("test")]))
        let data = try JsonRpcCodec.encode(.response(response))
        let decoded = try JsonRpcCodec.decode(data)
        guard case .response(let r) = decoded else {
            Issue.record("Expected response")
            return
        }
        #expect(r.id == .int(42))
        #expect(r.result?.objectValue?["name"]?.stringValue == "test")
        #expect(r.error == nil)
    }

    @Test func encodeDecodeErrorResponse() throws {
        let response = JsonRpcResponse.error(
            id: .string("abc"),
            error: JsonRpcError(code: -32601, message: "Method not found")
        )
        let data = try JsonRpcCodec.encode(.response(response))
        let decoded = try JsonRpcCodec.decode(data)
        guard case .response(let r) = decoded else {
            Issue.record("Expected response")
            return
        }
        #expect(r.id == .string("abc"))
        #expect(r.error?.code == -32601)
        #expect(r.error?.message == "Method not found")
        #expect(r.result == nil)
    }

    @Test func encodeDecodeNotification() throws {
        let notification = JsonRpcNotification(method: "initialize", params: ["pluginId": .string("test")])
        let data = try JsonRpcCodec.encode(.notification(notification))
        let decoded = try JsonRpcCodec.decode(data)
        guard case .notification(let n) = decoded else {
            Issue.record("Expected notification")
            return
        }
        #expect(n.method == "initialize")
        #expect(n.params?["pluginId"]?.stringValue == "test")
    }

    @Test func requestWithStringId() throws {
        let request = JsonRpcRequest(id: .string("req-1"), method: "test")
        let data = try JsonRpcCodec.encodeRequest(request)
        let decoded = try JsonRpcCodec.decode(data)
        guard case .request(let r) = decoded else {
            Issue.record("Expected request")
            return
        }
        #expect(r.id == .string("req-1"))
    }

    @Test func anyCodableRoundTrips() throws {
        let values: [AnyCodable] = [
            .null, .bool(true), .int(42), .double(3.14), .string("hello"),
            .array([.int(1), .string("two")]),
            .object(["key": .bool(false)]),
        ]
        for value in values {
            let data = try JSONEncoder().encode(value)
            let decoded = try JSONDecoder().decode(AnyCodable.self, from: data)
            // Verify round-trip produces valid data (no crash)
            let reEncoded = try JSONEncoder().encode(decoded)
            #expect(!reEncoded.isEmpty)
        }
    }

    @Test func invalidJsonThrows() {
        let data = "not json".data(using: .utf8)!
        #expect(throws: (any Error).self) {
            _ = try JsonRpcCodec.decode(data)
        }
    }
}

// MARK: - Plugin Manifest Tests

struct PluginManifestTests {
    @Test func loadValidManifest() throws {
        let dir = createTempPluginDir(manifest: """
        {
            "id": "com.test.plugin",
            "name": "Test Plugin",
            "version": "1.0.0",
            "description": "A test plugin",
            "entry": "main.sh",
            "runtime": "bash",
            "permissions": ["sandbox.list", "ui.log"],
            "triggers": ["manual"]
        }
        """, entryContent: "#!/bin/bash\necho hello")

        let manifest = try PluginManifest.load(from: dir)
        #expect(manifest.id == "com.test.plugin")
        #expect(manifest.name == "Test Plugin")
        #expect(manifest.version == "1.0.0")
        #expect(manifest.permissions.count == 2)
        #expect(manifest.triggers.contains(.manual))
        #expect(manifest.directory == dir)
    }

    @Test func missingFileThrows() {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        #expect(throws: PluginManifestError.self) {
            _ = try PluginManifest.load(from: dir)
        }
    }

    @Test func invalidIdThrows() throws {
        let dir = createTempPluginDir(manifest: """
        {
            "id": "noDots",
            "name": "Test",
            "version": "1.0.0",
            "description": "test",
            "entry": "main.sh",
            "permissions": [],
            "triggers": []
        }
        """, entryContent: "#!/bin/bash")
        #expect(throws: PluginManifestError.self) {
            _ = try PluginManifest.load(from: dir)
        }
    }

    @Test func missingEntryFileThrows() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let manifest = """
        {
            "id": "com.test.no-entry",
            "name": "Test",
            "version": "1.0.0",
            "description": "test",
            "entry": "nonexistent.sh",
            "permissions": [],
            "triggers": []
        }
        """
        try manifest.write(to: dir.appendingPathComponent("plugin.json"), atomically: true, encoding: .utf8)
        #expect(throws: PluginManifestError.self) {
            _ = try PluginManifest.load(from: dir)
        }
    }

    private func createTempPluginDir(manifest: String, entryContent: String) -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try! manifest.write(to: dir.appendingPathComponent("plugin.json"), atomically: true, encoding: .utf8)
        try! entryContent.write(to: dir.appendingPathComponent("main.sh"), atomically: true, encoding: .utf8)
        return dir
    }
}

// MARK: - Plugin Permission Tests

struct PluginPermissionTests {
    @Test func grantedPermissionPasses() throws {
        let checker = PluginPermissionChecker(granted: [.sandboxList, .uiLog])
        try checker.check(.sandboxList)
        try checker.check(.uiLog)
    }

    @Test func deniedPermissionThrows() {
        let checker = PluginPermissionChecker(granted: [.sandboxList])
        #expect(throws: PluginPermissionError.self) {
            try checker.check(.sandboxExec)
        }
    }

    @Test func methodToPermissionMapping() {
        #expect(PluginPermissionChecker.permissionRequired(for: "sandbox/list") == .sandboxList)
        #expect(PluginPermissionChecker.permissionRequired(for: "sandbox/exec") == .sandboxExec)
        #expect(PluginPermissionChecker.permissionRequired(for: "sandbox/stop") == .sandboxStop)
        #expect(PluginPermissionChecker.permissionRequired(for: "sandbox/run") == .sandboxRun)
        #expect(PluginPermissionChecker.permissionRequired(for: "sandbox/ports/list") == .portsList)
        #expect(PluginPermissionChecker.permissionRequired(for: "sandbox/ports/publish") == .portsPublish)
        #expect(PluginPermissionChecker.permissionRequired(for: "sandbox/envVars/list") == .envVarList)
        #expect(PluginPermissionChecker.permissionRequired(for: "sandbox/envVars/set") == .envVarSync)
        #expect(PluginPermissionChecker.permissionRequired(for: "policy/list") == .policyList)
        #expect(PluginPermissionChecker.permissionRequired(for: "policy/allow") == .policyAllow)
        #expect(PluginPermissionChecker.permissionRequired(for: "file/read") == .fileRead)
        #expect(PluginPermissionChecker.permissionRequired(for: "file/write") == .fileWrite)
        #expect(PluginPermissionChecker.permissionRequired(for: "ui/notify") == .uiNotify)
        #expect(PluginPermissionChecker.permissionRequired(for: "ui/log") == .uiLog)
        #expect(PluginPermissionChecker.permissionRequired(for: "unknown/method") == nil)
    }

    @Test func emptyGrantDeniesAll() {
        let checker = PluginPermissionChecker(granted: [])
        for perm in PluginPermission.allCases {
            #expect(throws: PluginPermissionError.self) {
                try checker.check(perm)
            }
        }
    }
}

// MARK: - Plugin API Handler Tests

struct PluginApiHandlerTests {
    @Test func sandboxListReturnsResults() async throws {
        let service = StubSbxService()
        _ = try await service.run(agent: "claude", workspace: "/tmp/project", opts: RunOptions(name: "test-sb"))
        let handler = PluginApiHandler(
            service: service,
            permissionChecker: PluginPermissionChecker(granted: Set(PluginPermission.allCases)),
            pluginDirectory: URL(fileURLWithPath: NSTemporaryDirectory())
        )
        let request = JsonRpcRequest(id: .int(1), method: "sandbox/list")
        let response = await handler.handle(request: request)
        #expect(response.error == nil)
        let sandboxes = response.result?.arrayValue
        #expect(sandboxes?.count == 1)
    }

    @Test func sandboxExecReturnsOutput() async throws {
        let service = StubSbxService()
        _ = try await service.run(agent: "claude", workspace: "/tmp/project", opts: RunOptions(name: "test-sb"))
        let handler = PluginApiHandler(
            service: service,
            permissionChecker: PluginPermissionChecker(granted: Set(PluginPermission.allCases)),
            pluginDirectory: URL(fileURLWithPath: NSTemporaryDirectory())
        )
        let request = JsonRpcRequest(
            id: .int(2),
            method: "sandbox/exec",
            params: ["name": .string("test-sb"), "command": .string("ls"), "args": .array([.string("-la")])]
        )
        let response = await handler.handle(request: request)
        #expect(response.error == nil)
        let stdout = response.result?.objectValue?["stdout"]?.stringValue
        #expect(stdout?.contains("mock exec") == true)
    }

    @Test func permissionDeniedReturnsError() async {
        let service = StubSbxService()
        let handler = PluginApiHandler(
            service: service,
            permissionChecker: PluginPermissionChecker(granted: [.uiLog]),
            pluginDirectory: URL(fileURLWithPath: NSTemporaryDirectory())
        )
        let request = JsonRpcRequest(id: .int(3), method: "sandbox/list")
        let response = await handler.handle(request: request)
        #expect(response.error?.code == JsonRpcErrorCode.permissionDenied)
    }

    @Test func unknownMethodReturnsError() async {
        let service = StubSbxService()
        let handler = PluginApiHandler(
            service: service,
            permissionChecker: PluginPermissionChecker(granted: Set(PluginPermission.allCases)),
            pluginDirectory: URL(fileURLWithPath: NSTemporaryDirectory())
        )
        let request = JsonRpcRequest(id: .int(4), method: "unknown/method")
        let response = await handler.handle(request: request)
        #expect(response.error?.code == JsonRpcErrorCode.methodNotFound)
    }

    @Test func missingParamsReturnsInvalidParams() async {
        let service = StubSbxService()
        let handler = PluginApiHandler(
            service: service,
            permissionChecker: PluginPermissionChecker(granted: Set(PluginPermission.allCases)),
            pluginDirectory: URL(fileURLWithPath: NSTemporaryDirectory())
        )
        let request = JsonRpcRequest(id: .int(5), method: "sandbox/exec")  // missing name, command
        let response = await handler.handle(request: request)
        #expect(response.error?.code == JsonRpcErrorCode.invalidParams)
    }

    @Test func sandboxStopWorks() async throws {
        let service = StubSbxService()
        _ = try await service.run(agent: "claude", workspace: "/tmp/project", opts: RunOptions(name: "test-sb"))
        let handler = PluginApiHandler(
            service: service,
            permissionChecker: PluginPermissionChecker(granted: Set(PluginPermission.allCases)),
            pluginDirectory: URL(fileURLWithPath: NSTemporaryDirectory())
        )
        let request = JsonRpcRequest(id: .int(6), method: "sandbox/stop", params: ["name": .string("test-sb")])
        let response = await handler.handle(request: request)
        #expect(response.error == nil)
        #expect(response.result?.objectValue?["ok"]?.boolValue == true)
    }

    @Test func portsPublishAndList() async throws {
        let service = StubSbxService()
        _ = try await service.run(agent: "claude", workspace: "/tmp/project", opts: RunOptions(name: "test-sb"))
        let handler = PluginApiHandler(
            service: service,
            permissionChecker: PluginPermissionChecker(granted: Set(PluginPermission.allCases)),
            pluginDirectory: URL(fileURLWithPath: NSTemporaryDirectory())
        )

        // Publish
        let pubRequest = JsonRpcRequest(
            id: .int(7),
            method: "sandbox/ports/publish",
            params: ["name": .string("test-sb"), "hostPort": .int(8080), "sbxPort": .int(3000)]
        )
        let pubResponse = await handler.handle(request: pubRequest)
        #expect(pubResponse.error == nil)
        #expect(pubResponse.result?.objectValue?["hostPort"]?.intValue == 8080)

        // List
        let listRequest = JsonRpcRequest(
            id: .int(8),
            method: "sandbox/ports/list",
            params: ["name": .string("test-sb")]
        )
        let listResponse = await handler.handle(request: listRequest)
        #expect(listResponse.error == nil)
        #expect(listResponse.result?.arrayValue?.count == 1)
    }

    @Test func policyListReturnsDefaults() async {
        let service = StubSbxService()
        let handler = PluginApiHandler(
            service: service,
            permissionChecker: PluginPermissionChecker(granted: Set(PluginPermission.allCases)),
            pluginDirectory: URL(fileURLWithPath: NSTemporaryDirectory())
        )
        let request = JsonRpcRequest(id: .int(9), method: "policy/list")
        let response = await handler.handle(request: request)
        #expect(response.error == nil)
        #expect((response.result?.arrayValue?.count ?? 0) >= 10)
    }

    @Test func fileReadAndWrite() async throws {
        let dir = NSTemporaryDirectory() + "plugin-test-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let filePath = "\(dir)/test.txt"

        let service = StubSbxService()
        let handler = PluginApiHandler(
            service: service,
            permissionChecker: PluginPermissionChecker(granted: Set(PluginPermission.allCases)),
            pluginDirectory: URL(fileURLWithPath: NSTemporaryDirectory())
        )

        // Write
        let writeRequest = JsonRpcRequest(
            id: .int(10),
            method: "file/write",
            params: ["path": .string(filePath), "content": .string("hello world")]
        )
        let writeResponse = await handler.handle(request: writeRequest)
        #expect(writeResponse.error == nil)

        // Read
        let readRequest = JsonRpcRequest(
            id: .int(11),
            method: "file/read",
            params: ["path": .string(filePath)]
        )
        let readResponse = await handler.handle(request: readRequest)
        #expect(readResponse.error == nil)
        #expect(readResponse.result?.objectValue?["content"]?.stringValue == "hello world")

        try? FileManager.default.removeItem(atPath: dir)
    }

    @Test func fileReadOutsidePluginDirDenied() async {
        let dir = NSTemporaryDirectory() + "plugin-scope-\(UUID().uuidString)"
        try! FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        let service = StubSbxService()
        let handler = PluginApiHandler(
            service: service,
            permissionChecker: PluginPermissionChecker(granted: Set(PluginPermission.allCases)),
            pluginDirectory: URL(fileURLWithPath: dir)
        )

        // Try to read /etc/passwd — should be denied
        let request = JsonRpcRequest(
            id: .int(20),
            method: "file/read",
            params: ["path": .string("/etc/passwd")]
        )
        let response = await handler.handle(request: request)
        #expect(response.error?.code == JsonRpcErrorCode.permissionDenied)

        try? FileManager.default.removeItem(atPath: dir)
    }

    @Test func fileWriteOutsidePluginDirDenied() async {
        let dir = NSTemporaryDirectory() + "plugin-scope-\(UUID().uuidString)"
        try! FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        let service = StubSbxService()
        let handler = PluginApiHandler(
            service: service,
            permissionChecker: PluginPermissionChecker(granted: Set(PluginPermission.allCases)),
            pluginDirectory: URL(fileURLWithPath: dir)
        )

        let request = JsonRpcRequest(
            id: .int(21),
            method: "file/write",
            params: ["path": .string("/tmp/evil.txt"), "content": .string("bad")]
        )
        let response = await handler.handle(request: request)
        #expect(response.error?.code == JsonRpcErrorCode.permissionDenied)

        try? FileManager.default.removeItem(atPath: dir)
    }

    @Test func uiLogWorks() async {
        let service = StubSbxService()
        let handler = PluginApiHandler(
            service: service,
            permissionChecker: PluginPermissionChecker(granted: Set(PluginPermission.allCases)),
            pluginDirectory: URL(fileURLWithPath: NSTemporaryDirectory())
        )
        let request = JsonRpcRequest(
            id: .int(12),
            method: "ui/log",
            params: ["message": .string("test log"), "level": .string("info")]
        )
        let response = await handler.handle(request: request)
        #expect(response.error == nil)
    }

    @Test func portRangeValidation() async throws {
        let service = StubSbxService()
        _ = try await service.run(agent: "claude", workspace: "/tmp/project", opts: RunOptions(name: "test-sb"))
        let handler = PluginApiHandler(
            service: service,
            permissionChecker: PluginPermissionChecker(granted: Set(PluginPermission.allCases)),
            pluginDirectory: URL(fileURLWithPath: NSTemporaryDirectory())
        )
        let request = JsonRpcRequest(
            id: .int(13),
            method: "sandbox/ports/publish",
            params: ["name": .string("test-sb"), "hostPort": .int(99999), "sbxPort": .int(3000)]
        )
        let response = await handler.handle(request: request)
        #expect(response.error?.code == JsonRpcErrorCode.invalidParams)
    }
}

// MARK: - Plugin Store Tests

struct PluginStoreTests {
    @Test func refreshDiscoversPlugins() async throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("plugins-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        // Create a valid plugin
        let pluginDir = dir.appendingPathComponent("com.test.store-test")
        try FileManager.default.createDirectory(at: pluginDir, withIntermediateDirectories: true)
        let manifest = """
        {"id":"com.test.store-test","name":"Store Test","version":"1.0.0","description":"test","entry":"main.sh","runtime":"bash","permissions":[],"triggers":[]}
        """
        try manifest.write(to: pluginDir.appendingPathComponent("plugin.json"), atomically: true, encoding: .utf8)
        try "#!/bin/bash".write(to: pluginDir.appendingPathComponent("main.sh"), atomically: true, encoding: .utf8)

        let service = StubSbxService()
        let manager = PluginManager(service: service, pluginsDirectory: dir)
        let store = await PluginStore(manager: manager)
        await store.refresh()
        let plugins = await store.plugins
        #expect(plugins.count == 1)
        #expect(plugins.first?.id == "com.test.store-test")

        try? FileManager.default.removeItem(at: dir)
    }

    @Test func emptyDirectoryReturnsNoPlugins() async {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("plugins-empty-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let service = StubSbxService()
        let manager = PluginManager(service: service, pluginsDirectory: dir)
        let store = await PluginStore(manager: manager)
        await store.refresh()
        let plugins = await store.plugins
        #expect(plugins.isEmpty)

        try? FileManager.default.removeItem(at: dir)
    }

    @Test func nonexistentDirectoryReturnsEmpty() async {
        let dir = URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)")
        let service = StubSbxService()
        let manager = PluginManager(service: service, pluginsDirectory: dir)
        let store = await PluginStore(manager: manager)
        await store.refresh()
        let plugins = await store.plugins
        #expect(plugins.isEmpty)
    }
}

// MARK: - Plugin Manager Tests

struct PluginManagerTests {
    @Test func discoverPluginsFindsValidManifests() async throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("pm-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        // Create two plugins
        for i in 1...2 {
            let pluginDir = dir.appendingPathComponent("com.test.plugin\(i)")
            try FileManager.default.createDirectory(at: pluginDir, withIntermediateDirectories: true)
            let manifest = """
            {"id":"com.test.plugin\(i)","name":"Plugin \(i)","version":"1.0.0","description":"test","entry":"main.sh","permissions":[],"triggers":[]}
            """
            try manifest.write(to: pluginDir.appendingPathComponent("plugin.json"), atomically: true, encoding: .utf8)
            try "#!/bin/bash".write(to: pluginDir.appendingPathComponent("main.sh"), atomically: true, encoding: .utf8)
        }

        let service = StubSbxService()
        let manager = PluginManager(service: service, pluginsDirectory: dir)
        let manifests = await manager.discoverPlugins()
        #expect(manifests.count == 2)

        try? FileManager.default.removeItem(at: dir)
    }

    @Test func skipsInvalidManifests() async throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("pm-invalid-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        // Valid plugin
        let validDir = dir.appendingPathComponent("com.test.valid")
        try FileManager.default.createDirectory(at: validDir, withIntermediateDirectories: true)
        try """
        {"id":"com.test.valid","name":"Valid","version":"1.0.0","description":"test","entry":"main.sh","permissions":[],"triggers":[]}
        """.write(to: validDir.appendingPathComponent("plugin.json"), atomically: true, encoding: .utf8)
        try "#!/bin/bash".write(to: validDir.appendingPathComponent("main.sh"), atomically: true, encoding: .utf8)

        // Invalid plugin (bad JSON)
        let invalidDir = dir.appendingPathComponent("com.test.invalid")
        try FileManager.default.createDirectory(at: invalidDir, withIntermediateDirectories: true)
        try "not json".write(to: invalidDir.appendingPathComponent("plugin.json"), atomically: true, encoding: .utf8)

        let service = StubSbxService()
        let manager = PluginManager(service: service, pluginsDirectory: dir)
        let manifests = await manager.discoverPlugins()
        #expect(manifests.count == 1)
        #expect(manifests.first?.id == "com.test.valid")

        try? FileManager.default.removeItem(at: dir)
    }

    @Test func isRunningReturnsFalseByDefault() async {
        let service = StubSbxService()
        let manager = PluginManager(service: service)
        let running = await manager.isRunning(id: "nonexistent")
        #expect(!running)
    }
}

// MARK: - Plugin Execution Tests (real process)

@Suite(.timeLimit(.minutes(1)))
struct PluginExecutionTests {
    /// Path to the mock-plugin script in tools/
    private static let mockPluginPath: String = {
        // Derive from the test file path: sbx-uiTests/ → project root → tools/mock-plugin
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // sbx-uiTests/
            .deletingLastPathComponent()  // project root
            .appendingPathComponent("tools/mock-plugin")
            .path
    }()

    /// Create a temp plugin directory with plugin.json pointing to mock-plugin.
    private func createMockPluginDir(
        id: String = "com.test.exec",
        permissions: [String] = ["sandbox.list", "ui.log"]
    ) -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("plugin-exec-\(UUID().uuidString)")
            .appendingPathComponent(id)
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        // Copy mock-plugin into the plugin directory
        let destScript = dir.appendingPathComponent("run.sh")
        try! FileManager.default.copyItem(
            atPath: Self.mockPluginPath,
            toPath: destScript.path
        )

        // Write plugin.json
        let permsJson = permissions.map { "\"\($0)\"" }.joined(separator: ",")
        let manifest = """
        {
            "id": "\(id)",
            "name": "Exec Test Plugin",
            "version": "1.0.0",
            "description": "Test plugin that exercises the JSON-RPC pipeline",
            "entry": "run.sh",
            "runtime": "bash",
            "permissions": [\(permsJson)],
            "triggers": ["manual"]
        }
        """
        try! manifest.write(to: dir.appendingPathComponent("plugin.json"), atomically: true, encoding: .utf8)
        return dir
    }

    @Test func pluginHostStartsAndStopsProcess() async throws {
        let pluginDir = createMockPluginDir()
        defer { try? FileManager.default.removeItem(at: pluginDir.deletingLastPathComponent()) }

        let manifest = try PluginManifest.load(from: pluginDir)
        let service = StubSbxService()

        let host = PluginHost(manifest: manifest, pluginDirectory: pluginDir)
        try await host.start(service: service)

        let running = await host.isRunning
        #expect(running)

        await host.stop()

        // Allow process termination
        try await Task.sleep(for: .milliseconds(200))

        let stoppedRunning = await host.isRunning
        #expect(!stoppedRunning)
    }

    @Test func pluginManagerStartAndStopPlugin() async throws {
        let pluginDir = createMockPluginDir()
        let parentDir = pluginDir.deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at: parentDir) }

        let service = StubSbxService()
        let manager = PluginManager(service: service, pluginsDirectory: parentDir)

        let manifests = await manager.discoverPlugins()
        #expect(manifests.count == 1)

        let manifest = manifests.first!
        try await manager.startPlugin(manifest: manifest)

        let running = await manager.isRunning(id: manifest.id)
        #expect(running)

        let ids = await manager.runningPluginIds()
        #expect(ids.contains(manifest.id))

        await manager.stopPlugin(id: manifest.id)
        try await Task.sleep(for: .milliseconds(500))

        let afterStop = await manager.isRunning(id: manifest.id)
        #expect(!afterStop)
    }

    @Test func pluginStopAllCleansUp() async throws {
        let pluginDir = createMockPluginDir()
        let parentDir = pluginDir.deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at: parentDir) }

        let service = StubSbxService()
        let manager = PluginManager(service: service, pluginsDirectory: parentDir)

        let manifests = await manager.discoverPlugins()
        try await manager.startPlugin(manifest: manifests.first!)

        let running = await manager.runningPluginIds()
        #expect(running.count == 1)

        await manager.stopAll()
        try await Task.sleep(for: .milliseconds(200))

        let afterStopAll = await manager.runningPluginIds()
        #expect(afterStopAll.isEmpty)
    }

    @Test func duplicateStartThrows() async throws {
        let pluginDir = createMockPluginDir()
        let parentDir = pluginDir.deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at: parentDir) }

        let service = StubSbxService()
        let manager = PluginManager(service: service, pluginsDirectory: parentDir)

        let manifests = await manager.discoverPlugins()
        try await manager.startPlugin(manifest: manifests.first!)

        // Starting again should throw alreadyRunning
        do {
            try await manager.startPlugin(manifest: manifests.first!)
            Issue.record("Expected alreadyRunning error")
        } catch is PluginError {
            // Expected
        }

        await manager.stopAll()
        try await Task.sleep(for: .milliseconds(200))
    }
}

// MARK: - Sandbox Profile Tests

struct SandboxProfileTests {
    private let testDir = URL(fileURLWithPath: "/tmp/test-plugin")
    private let testRuntime = "/usr/bin/bash"

    private func makeManifest(permissions: [PluginPermission]) -> PluginManifest {
        PluginManifest(
            id: "com.test.sandbox",
            name: "Test",
            version: "1.0.0",
            description: "test",
            entry: "main.sh",
            runtime: "bash",
            permissions: permissions,
            triggers: [.manual]
        )
    }

    @Test func generateBaseProfile() {
        let manifest = makeManifest(permissions: [])
        let profile = SandboxProfile.generate(for: manifest, pluginDirectory: testDir, runtimePath: testRuntime)
        #expect(profile.contains("(version 1)"))
        #expect(profile.contains("(deny default)"))
        #expect(profile.contains("(allow file-ioctl)"))
        #expect(profile.contains("(allow sysctl-read)"))
        #expect(profile.contains("(allow process-fork)"))
        #expect(profile.contains("(allow signal (target self))"))
    }

    @Test func generateScopesFileReadToPluginDir() {
        let manifest = makeManifest(permissions: [])
        let profile = SandboxProfile.generate(for: manifest, pluginDirectory: testDir, runtimePath: testRuntime)
        #expect(profile.contains("(allow file-read* (subpath \"/tmp/test-plugin\"))"))
        // Must NOT contain blanket file-read*
        #expect(!profile.contains("(allow file-read*)"))  // all file-read* rules are scoped with (subpath ...)
    }

    @Test func generateScopesExecToRuntime() {
        let manifest = makeManifest(permissions: [])
        let profile = SandboxProfile.generate(for: manifest, pluginDirectory: testDir, runtimePath: testRuntime)
        #expect(profile.contains("(allow process-exec (literal \"/usr/bin/bash\"))"))
    }

    @Test func generateScopesMachLookup() {
        let manifest = makeManifest(permissions: [])
        let profile = SandboxProfile.generate(for: manifest, pluginDirectory: testDir, runtimePath: testRuntime)
        // Base profile should have scoped mach-lookup, not blanket
        #expect(profile.contains("(allow mach-lookup (global-name"))
    }

    @Test func generateWithFileWriteScopedToPluginDir() {
        let manifest = makeManifest(permissions: [.fileWrite])
        let profile = SandboxProfile.generate(for: manifest, pluginDirectory: testDir, runtimePath: testRuntime)
        #expect(profile.contains("(allow file-write* (subpath \"/tmp/test-plugin\"))"))
    }

    @Test func generateWithoutFileWritePermission() {
        let manifest = makeManifest(permissions: [.sandboxList, .uiLog])
        let profile = SandboxProfile.generate(for: manifest, pluginDirectory: testDir, runtimePath: testRuntime)
        #expect(!profile.contains("(allow file-write*"))
    }

    @Test func generateWithNetworkPermissions() {
        let manifest = makeManifest(permissions: [.policyAllow])
        let profile = SandboxProfile.generate(for: manifest, pluginDirectory: testDir, runtimePath: testRuntime)
        #expect(profile.contains("(allow network*)"))
    }

    @Test func generateWithoutNetworkPermissions() {
        let manifest = makeManifest(permissions: [.sandboxList, .fileRead])
        let profile = SandboxProfile.generate(for: manifest, pluginDirectory: testDir, runtimePath: testRuntime)
        #expect(!profile.contains("(allow network*)"))
    }

    @Test func generateEmptyPermissionsHasNoWriteOrNetwork() {
        let manifest = makeManifest(permissions: [])
        let profile = SandboxProfile.generate(for: manifest, pluginDirectory: testDir, runtimePath: testRuntime)
        #expect(!profile.contains("(allow file-write*"))
        #expect(!profile.contains("(allow network*)"))
        #expect(profile.contains("(deny default)"))
    }

    @Test func generateWithAllPermissions() {
        let manifest = makeManifest(permissions: Array(PluginPermission.allCases))
        let profile = SandboxProfile.generate(for: manifest, pluginDirectory: testDir, runtimePath: testRuntime)
        #expect(profile.contains("(allow file-write*"))
        #expect(profile.contains("(allow network*)"))
    }

    @Test func generateMultipleNetworkPermsTriggerNetwork() {
        for perm in [PluginPermission.policyAllow, .policyDeny, .policyRemove, .policyList] {
            let manifest = makeManifest(permissions: [perm])
            let profile = SandboxProfile.generate(for: manifest, pluginDirectory: testDir, runtimePath: testRuntime)
            #expect(profile.contains("(allow network*)"), "Network should be allowed for \(perm.rawValue)")
        }
    }
}

// MARK: - Manifest Path Traversal Tests

struct PluginManifestSecurityTests {
    @Test func entryWithDotsRejected() {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let manifest = """
        {"id":"com.test.traverse","name":"T","version":"1.0.0","description":"t","entry":"../../etc/passwd","permissions":[],"triggers":[]}
        """
        try! manifest.write(to: dir.appendingPathComponent("plugin.json"), atomically: true, encoding: .utf8)
        #expect(throws: PluginManifestError.self) {
            _ = try PluginManifest.load(from: dir)
        }
        try? FileManager.default.removeItem(at: dir)
    }

    @Test func entryWithAbsolutePathRejected() {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let manifest = """
        {"id":"com.test.abs","name":"T","version":"1.0.0","description":"t","entry":"/usr/bin/osascript","permissions":[],"triggers":[]}
        """
        try! manifest.write(to: dir.appendingPathComponent("plugin.json"), atomically: true, encoding: .utf8)
        #expect(throws: PluginManifestError.self) {
            _ = try PluginManifest.load(from: dir)
        }
        try? FileManager.default.removeItem(at: dir)
    }

    @Test func validEntryInSubdirAllowed() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let subdir = dir.appendingPathComponent("src")
        try FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: true)
        try "#!/bin/bash".write(to: subdir.appendingPathComponent("main.sh"), atomically: true, encoding: .utf8)
        let manifest = """
        {"id":"com.test.subdir","name":"T","version":"1.0.0","description":"t","entry":"src/main.sh","permissions":[],"triggers":[]}
        """
        try manifest.write(to: dir.appendingPathComponent("plugin.json"), atomically: true, encoding: .utf8)
        let loaded = try PluginManifest.load(from: dir)
        #expect(loaded.entry == "src/main.sh")
        try? FileManager.default.removeItem(at: dir)
    }
}
