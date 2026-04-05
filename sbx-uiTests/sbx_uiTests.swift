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
    nonisolated func sendMessage(name: String, message: String) async throws { throw SbxServiceError.cliError("test error") }
}

/// Minimal in-memory stub for unit testing stores. No delays, no complex logic.
actor StubSbxService: SbxServiceProtocol {
    private var sandboxes: [String: Sandbox] = [:]
    private var policies: [String: PolicyRule] = [:]
    private var portMappings: [String: [PortMapping]] = [:]
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
        let ops = await store.busyOperations
        #expect(ops.isEmpty)
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
