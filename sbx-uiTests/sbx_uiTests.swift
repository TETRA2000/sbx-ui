import Foundation
import Testing
@testable import sbx_ui

// MARK: - Test Helper: FailingSbxService

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

// MARK: - Async Test Expectation Helper

private final class Expectation: @unchecked Sendable {
    private(set) var isFulfilled = false
    func fulfill() { isFulfilled = true }
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

// MARK: - MockSbxService Tests

struct MockSbxServiceTests {

    // MARK: - Lifecycle Tests

    @Test func createTransitionsToRunning() async throws {
        let service = MockSbxService()
        let sandbox = try await service.run(agent: "claude", workspace: "/tmp/project", opts: nil)
        #expect(sandbox.status == .running)
        #expect(sandbox.name == "claude-project")
        #expect(sandbox.agent == "claude")
    }

    @Test func stopTransitionsToStopped() async throws {
        let service = MockSbxService()
        let sandbox = try await service.run(agent: "claude", workspace: "/tmp/project", opts: nil)
        try await service.stop(name: sandbox.name)
        let list = try await service.list()
        #expect(list.first?.status == .stopped)
    }

    @Test func stoppedCanResume() async throws {
        let service = MockSbxService()
        let sandbox = try await service.run(agent: "claude", workspace: "/tmp/project", opts: nil)
        try await service.stop(name: sandbox.name)
        let resumed = try await service.run(agent: "claude", workspace: "/tmp/project", opts: RunOptions(name: sandbox.name))
        #expect(resumed.status == .running)
    }

    @Test func removeDeletesSandbox() async throws {
        let service = MockSbxService()
        let sandbox = try await service.run(agent: "claude", workspace: "/tmp/project", opts: nil)
        try await service.rm(name: sandbox.name)
        let list = try await service.list()
        #expect(list.isEmpty)
    }

    @Test func duplicateWorkspaceReturnsExisting() async throws {
        let service = MockSbxService()
        let first = try await service.run(agent: "claude", workspace: "/tmp/project", opts: nil)
        let second = try await service.run(agent: "claude", workspace: "/tmp/project", opts: nil)
        #expect(first.id == second.id)
        let list = try await service.list()
        #expect(list.count == 1)
    }

    @Test func invalidNameThrows() async throws {
        let service = MockSbxService()
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
        let service = MockSbxService()
        let sandbox = try await service.run(agent: "claude", workspace: "/tmp/project", opts: RunOptions(name: "my-sandbox"))
        #expect(sandbox.name == "my-sandbox")
    }

    // MARK: - Edge Cases

    @Test func stopNonExistentThrowsNotFound() async throws {
        let service = MockSbxService()
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
        let service = MockSbxService()
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
        let service = MockSbxService()
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
        let service = MockSbxService()
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
        let service = MockSbxService()
        _ = try await service.run(agent: "claude", workspace: "/tmp/project-a", opts: nil)
        _ = try await service.run(agent: "claude", workspace: "/tmp/project-b", opts: nil)
        let list = try await service.list()
        #expect(list.count == 2)
    }

    @Test func portUniquenessAcrossSandboxes() async throws {
        let service = MockSbxService()
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

    @Test func policyLogFilterBySandbox() async throws {
        let service = MockSbxService()
        let all = try await service.policyLog(sandboxName: nil)
        #expect(all.count == 3)
        let filtered = try await service.policyLog(sandboxName: "claude-myproject")
        #expect(filtered.count == 3) // All seeded entries are for claude-myproject
        let empty = try await service.policyLog(sandboxName: "nonexistent")
        #expect(empty.isEmpty)
    }

    @Test func unpublishPortRemovesMapping() async throws {
        let service = MockSbxService()
        let sandbox = try await service.run(agent: "claude", workspace: "/tmp/project", opts: nil)
        _ = try await service.portsPublish(name: sandbox.name, hostPort: 8080, sbxPort: 3000)
        try await service.portsUnpublish(name: sandbox.name, hostPort: 8080, sbxPort: 3000)
        let ports = try await service.portsList(name: sandbox.name)
        #expect(ports.isEmpty)
    }

    // MARK: - Policy Tests

    @Test func balancedDefaultsPresent() async throws {
        let service = MockSbxService()
        let policies = try await service.policyList()
        #expect(policies.count == 10)
        let resources = Set(policies.map(\.resources))
        #expect(resources.contains("api.anthropic.com"))
        #expect(resources.contains("github.com"))
        #expect(resources.contains("*.npmjs.org"))
    }

    @Test func addAllowRule() async throws {
        let service = MockSbxService()
        let rule = try await service.policyAllow(resources: "example.com")
        #expect(rule.decision == .allow)
        #expect(rule.resources == "example.com")
    }

    @Test func addDenyRule() async throws {
        let service = MockSbxService()
        let rule = try await service.policyDeny(resources: "evil.com")
        #expect(rule.decision == .deny)
        #expect(rule.resources == "evil.com")
    }

    @Test func removeRule() async throws {
        let service = MockSbxService()
        let before = try await service.policyList()
        let count = before.count
        try await service.policyRemove(resource: "api.anthropic.com")
        let after = try await service.policyList()
        #expect(after.count == count - 1)
    }

    // MARK: - Port Tests

    @Test func publishPort() async throws {
        let service = MockSbxService()
        let sandbox = try await service.run(agent: "claude", workspace: "/tmp/project", opts: nil)
        let mapping = try await service.portsPublish(name: sandbox.name, hostPort: 8080, sbxPort: 3000)
        #expect(mapping.hostPort == 8080)
        #expect(mapping.sandboxPort == 3000)
    }

    @Test func duplicateHostPortThrows() async throws {
        let service = MockSbxService()
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
        let service = MockSbxService()
        let sandbox = try await service.run(agent: "claude", workspace: "/tmp/project", opts: nil)
        _ = try await service.portsPublish(name: sandbox.name, hostPort: 8080, sbxPort: 3000)
        try await service.stop(name: sandbox.name)
        let ports = try await service.portsList(name: sandbox.name)
        #expect(ports.isEmpty)
    }

    @Test func publishOnStoppedThrows() async throws {
        let service = MockSbxService()
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
}

// MARK: - MockPtyEmitter Tests

struct MockPtyEmitterTests {
    @Test func emitterEmitsStartupSequence() async throws {
        let emitter = MockPtyEmitter()
        var receivedData: [String] = []
        let exp = Expectation()

        emitter.onData { data in
            receivedData.append(data)
            if data.contains(">") {
                exp.fulfill()
            }
        }

        await waitFor(exp, timeout: 3.0)
        #expect(!receivedData.isEmpty)
        let combined = receivedData.joined()
        #expect(combined.contains("Claude Code"))
    }

    @Test func emitterRespondsToWrite() async throws {
        let emitter = MockPtyEmitter()
        var receivedData: [String] = []
        var startupDone = false
        let responseExp = Expectation()

        emitter.onData { data in
            if data.contains(">") && !startupDone {
                startupDone = true
                return
            }
            if startupDone {
                receivedData.append(data)
                if data.contains("Done") || data.contains("✓") {
                    responseExp.fulfill()
                }
            }
        }

        try await Task.sleep(for: .seconds(1.5))
        emitter.write("Hello Claude")

        await waitFor(responseExp, timeout: 5.0)
        #expect(!receivedData.isEmpty)
    }

    private func waitFor(_ expectation: Expectation, timeout: TimeInterval) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !expectation.isFulfilled && Date() < deadline {
            try? await Task.sleep(for: .milliseconds(50))
        }
    }
}

// MARK: - TerminalViewWrapper Coordinator Tests

struct TerminalViewWrapperTests {
    @Test func coordinatorStartsUnfocused() {
        let coordinator = TerminalViewWrapper.Coordinator()
        #expect(coordinator.didFocus == false)
        #expect(coordinator.terminalView == nil)
    }

    @Test func coordinatorDidFocusCanBeSet() {
        let coordinator = TerminalViewWrapper.Coordinator()
        coordinator.didFocus = true
        #expect(coordinator.didFocus == true)
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
        let service = MockSbxService()
        _ = try await service.run(agent: "claude", workspace: "/tmp/project", opts: nil)
        let store = await SandboxStore(service: service)
        await store.fetchSandboxes()
        let count = await store.sandboxes.count
        #expect(count == 1)
    }

    @Test func createReturnsAndRefreshes() async throws {
        let service = MockSbxService()
        let store = await SandboxStore(service: service)
        let sandbox = try await store.createSandbox(workspace: "/tmp/project", name: "test-create")
        #expect(sandbox.status == .running)
        let count = await store.sandboxes.count
        #expect(count == 1)
    }

    @Test func stopUpdatesState() async throws {
        let service = MockSbxService()
        let store = await SandboxStore(service: service)
        _ = try await store.createSandbox(workspace: "/tmp/project", name: "test-stop")
        try await store.stopSandbox(name: "test-stop")
        let status = await store.sandboxes.first?.status
        #expect(status == .stopped)
    }

    @Test func removeRemovesFromList() async throws {
        let service = MockSbxService()
        let store = await SandboxStore(service: service)
        _ = try await store.createSandbox(workspace: "/tmp/project", name: "test-rm")
        try await store.removeSandbox(name: "test-rm")
        let count = await store.sandboxes.count
        #expect(count == 0)
    }

    @Test func publishPortUpdatesStore() async throws {
        let service = MockSbxService()
        let store = await SandboxStore(service: service)
        _ = try await store.createSandbox(workspace: "/tmp/project", name: "test-port")
        try await store.publishPort(name: "test-port", hostPort: 8080, sbxPort: 3000)
        let ports = await store.sandboxes.first?.ports
        #expect(ports?.count == 1)
        #expect(ports?.first?.hostPort == 8080)
    }

    @Test func unpublishPortUpdatesStore() async throws {
        let service = MockSbxService()
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

// MARK: - PolicyStore Tests

struct PolicyStoreTests {
    @Test func fetchPopulatesRules() async throws {
        let service = MockSbxService()
        let store = await PolicyStore(service: service)
        await store.fetchPolicies()
        let count = await store.rules.count
        #expect(count == 10)
    }

    @Test func addAllowCreatesAndRefreshes() async throws {
        let service = MockSbxService()
        let store = await PolicyStore(service: service)
        try await store.addAllow(resources: "test.com")
        let rules = await store.rules
        #expect(rules.contains(where: { $0.resources == "test.com" && $0.decision == .allow }))
    }

    @Test func addDenyCreatesAndRefreshes() async throws {
        let service = MockSbxService()
        let store = await PolicyStore(service: service)
        try await store.addDeny(resources: "evil.com")
        let rules = await store.rules
        #expect(rules.contains(where: { $0.resources == "evil.com" && $0.decision == .deny }))
    }

    @Test func removeRuleDecrementsCount() async throws {
        let service = MockSbxService()
        let store = await PolicyStore(service: service)
        await store.fetchPolicies()
        let before = await store.rules.count
        try await store.removeRule(resource: "api.anthropic.com")
        let after = await store.rules.count
        #expect(after == before - 1)
    }

    @Test func fetchLogPopulatesEntries() async throws {
        let service = MockSbxService()
        let store = await PolicyStore(service: service)
        await store.fetchLog()
        let count = await store.logEntries.count
        #expect(count == 3)
    }

    @Test func filteredLogBySandbox() async throws {
        let service = MockSbxService()
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
        let service = MockSbxService()
        let store = await PolicyStore(service: service)
        await store.fetchLog()
        await MainActor.run { store.logFilter.blockedOnly = true }
        let filtered = await store.filteredLog
        #expect(filtered.count == 1)
        #expect(filtered.first?.blocked == true)
    }
}

// MARK: - SessionStore Tests

struct SessionStoreTests {
    @Test func attachSetsState() async throws {
        let service = MockSbxService()
        let store = await SessionStore(service: service)
        try await store.attach(name: "test")
        let active = await store.activeSandbox
        let connected = await store.connected
        let startTime = await store.connectionStartTime
        #expect(active == "test")
        #expect(connected == true)
        #expect(startTime != nil)
    }

    @Test func detachClearsState() async throws {
        let service = MockSbxService()
        let store = await SessionStore(service: service)
        try await store.attach(name: "test")
        await store.detach()
        let active = await store.activeSandbox
        let connected = await store.connected
        let startTime = await store.connectionStartTime
        #expect(active == nil)
        #expect(connected == false)
        #expect(startTime == nil)
    }

    @Test func attachAutoDetachesPrevious() async throws {
        let service = MockSbxService()
        let store = await SessionStore(service: service)
        try await store.attach(name: "sandbox-a")
        try await store.attach(name: "sandbox-b")
        let active = await store.activeSandbox
        #expect(active == "sandbox-b")
    }

    @Test func sendMessageWhenNotConnectedNoOp() async throws {
        let service = MockSbxService()
        let store = await SessionStore(service: service)
        // Should not throw — guard returns early
        try await store.sendMessage("hello")
    }

    @Test func sendMessageDelegatesToService() async throws {
        let service = MockSbxService()
        _ = try await service.run(agent: "claude", workspace: "/tmp/project", opts: RunOptions(name: "test-session"))
        let store = await SessionStore(service: service)
        try await store.attach(name: "test-session")
        // Should succeed — sandbox exists and is running
        try await store.sendMessage("hello from test")
    }
}
