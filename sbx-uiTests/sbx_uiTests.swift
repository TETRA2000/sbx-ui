import Foundation
import Testing
@testable import sbx_ui

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
            if case .portConflict(8080) = error {
                // Expected
            } else {
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
            if case .notRunning = error {
                // Expected
            } else {
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
        let expectation = expectation()

        emitter.onData { data in
            receivedData.append(data)
            // Startup sequence ends with prompt character
            if data.contains(">") {
                expectation.fulfill()
            }
        }

        await waitFor(expectation, timeout: 3.0)
        #expect(!receivedData.isEmpty)
        let combined = receivedData.joined()
        #expect(combined.contains("Claude Code"))
    }

    @Test func emitterRespondsToWrite() async throws {
        let emitter = MockPtyEmitter()
        var receivedData: [String] = []
        var startupDone = false
        let responseExpectation = expectation()

        emitter.onData { data in
            if data.contains(">") && !startupDone {
                startupDone = true
                return
            }
            if startupDone {
                receivedData.append(data)
                if data.contains("Done") || data.contains("✓") {
                    responseExpectation.fulfill()
                }
            }
        }

        // Wait for startup to complete
        try await Task.sleep(for: .seconds(1.5))
        emitter.write("Hello Claude")

        await waitFor(responseExpectation, timeout: 5.0)
        #expect(!receivedData.isEmpty)
    }

    // Helper to create async expectations
    private func expectation() -> Expectation {
        Expectation()
    }

    private func waitFor(_ expectation: Expectation, timeout: TimeInterval) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !expectation.isFulfilled && Date() < deadline {
            try? await Task.sleep(for: .milliseconds(50))
        }
    }
}

private final class Expectation: @unchecked Sendable {
    private(set) var isFulfilled = false
    func fulfill() { isFulfilled = true }
}

// MARK: - SbxOutputParser Tests

struct SbxOutputParserTests {
    @Test func parseSandboxList() {
        let output = """
        NAME             AGENT   STATUS    PORTS         WORKSPACE
        claude-myproject claude  running   8080->3000    /Users/dev/project
        claude-other     claude  stopped   -             /Users/dev/other
        """
        let sandboxes = SbxOutputParser.parseSandboxList(output)
        #expect(sandboxes.count == 2)
        #expect(sandboxes[0].name == "claude-myproject")
        #expect(sandboxes[0].status == .running)
        #expect(sandboxes[1].name == "claude-other")
        #expect(sandboxes[1].status == .stopped)
    }

    @Test func parsePolicyList() {
        let output = """
        ID    TYPE      DECISION  RESOURCES
        1     network   allow     api.anthropic.com
        2     network   deny      evil.com
        """
        let rules = SbxOutputParser.parsePolicyList(output)
        #expect(rules.count == 2)
        #expect(rules[0].decision == .allow)
        #expect(rules[1].decision == .deny)
    }

    @Test func parsePortsList() {
        let output = """
        8080->3000
        9090->4000
        """
        let ports = SbxOutputParser.parsePortsList(output)
        #expect(ports.count == 2)
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
        let output = "NAME  AGENT  STATUS  PORTS  WORKSPACE\n"
        let sandboxes = SbxOutputParser.parseSandboxList(output)
        #expect(sandboxes.isEmpty)
    }
}
