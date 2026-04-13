import Testing
import Foundation
@testable import SBXCore

// MARK: - Validation Tests

@Suite struct ValidationTests {
    @Test func validSandboxNames() {
        #expect(SbxValidation.isValidName("my-sandbox"))
        #expect(SbxValidation.isValidName("claude-project"))
        #expect(SbxValidation.isValidName("test123"))
        #expect(SbxValidation.isValidName("a"))
    }

    @Test func invalidSandboxNames() {
        #expect(!SbxValidation.isValidName(""))
        #expect(!SbxValidation.isValidName("-leading-hyphen"))
        #expect(!SbxValidation.isValidName("UPPERCASE"))
        #expect(!SbxValidation.isValidName("has spaces"))
        #expect(!SbxValidation.isValidName("has_underscore"))
    }

    @Test func validEnvKeys() {
        #expect(SbxValidation.isValidEnvKey("MY_VAR"))
        #expect(SbxValidation.isValidEnvKey("_PRIVATE"))
        #expect(SbxValidation.isValidEnvKey("API_KEY_2"))
        #expect(SbxValidation.isValidEnvKey("a"))
    }

    @Test func invalidEnvKeys() {
        #expect(!SbxValidation.isValidEnvKey(""))
        #expect(!SbxValidation.isValidEnvKey("2STARTS_WITH_NUM"))
        #expect(!SbxValidation.isValidEnvKey("has-hyphen"))
        #expect(!SbxValidation.isValidEnvKey("has space"))
    }
}

// MARK: - Model Tests

@Suite struct ModelTests {
    @Test func sandboxId() {
        let s = Sandbox(
            id: "test", name: "test", agent: "claude",
            status: .running, workspace: "/tmp", ports: [], createdAt: Date()
        )
        #expect(s.id == "test")
    }

    @Test func portMappingId() {
        let p = PortMapping(hostPort: 8080, sandboxPort: 3000, protocolType: "tcp")
        #expect(p.id == "8080-3000")
    }

    @Test func envVarId() {
        let v = EnvVar(key: "MY_KEY", value: "my_value")
        #expect(v.id == "MY_KEY")
    }

    @Test func sandboxStatusValues() {
        #expect(SandboxStatus(rawValue: "running") == .running)
        #expect(SandboxStatus(rawValue: "stopped") == .stopped)
        #expect(SandboxStatus(rawValue: "creating") == .creating)
    }

    @Test func errorDescriptions() {
        let e1 = SbxServiceError.notFound("test-sb")
        #expect(e1.errorDescription?.contains("test-sb") == true)

        let e2 = SbxServiceError.invalidName("BAD")
        #expect(e2.errorDescription?.contains("BAD") == true)

        let e3 = SbxServiceError.dockerNotRunning
        #expect(e3.errorDescription?.contains("Docker") == true)
    }
}

// MARK: - Parser Tests

@Suite struct ParserTests {
    @Test func parsePolicyList() {
        let output = """
            NAME                                         TYPE      DECISION   RESOURCES
            default-allow-all                            network   allow      **
            local:abc-123                                network   deny       evil.com
            """
        let rules = SbxOutputParser.parsePolicyList(output)
        #expect(rules.count == 2)
        #expect(rules[0].id == "default-allow-all")
        #expect(rules[0].decision == .allow)
        #expect(rules[0].resources == "**")
        #expect(rules[1].decision == .deny)
        #expect(rules[1].resources == "evil.com")
    }

    @Test func parsePolicyListWithBlankLines() {
        let output = """
            NAME                                         TYPE      DECISION   RESOURCES
            default-allow-all                            network   allow      **

            local:abc-123                                network   deny       evil.com
            """
        let rules = SbxOutputParser.parsePolicyList(output)
        #expect(rules.count == 2)
    }

    @Test func parsePolicyListEmpty() {
        #expect(SbxOutputParser.parsePolicyList("").isEmpty)
    }

    @Test func parseManagedEnvVars() {
        let content = """
            # user stuff
            export PATH=/usr/bin

            # --- sbx-ui managed (DO NOT EDIT) ---
            export MY_KEY=my_value
            export API_KEY=secret123
            # --- end sbx-ui managed ---

            # more user stuff
            """
        let vars = SbxOutputParser.parseManagedEnvVars(content)
        #expect(vars.count == 2)
        #expect(vars[0].key == "MY_KEY")
        #expect(vars[0].value == "my_value")
        #expect(vars[1].key == "API_KEY")
        #expect(vars[1].value == "secret123")
    }

    @Test func parseManagedEnvVarsEmpty() {
        #expect(SbxOutputParser.parseManagedEnvVars("").isEmpty)
        #expect(SbxOutputParser.parseManagedEnvVars("export PATH=/usr/bin\n").isEmpty)
    }

    @Test func rebuildPersistentSh() {
        let existing = """
            # user content
            export PATH=/usr/bin

            # --- sbx-ui managed (DO NOT EDIT) ---
            export OLD_VAR=old
            # --- end sbx-ui managed ---

            # after content
            """
        let newVars = [EnvVar(key: "NEW_VAR", value: "new")]
        let result = SbxOutputParser.rebuildPersistentSh(
            existingContent: existing, managedVars: newVars
        )
        #expect(result.contains("# user content"))
        #expect(result.contains("export PATH=/usr/bin"))
        #expect(result.contains("export NEW_VAR=new"))
        #expect(!result.contains("OLD_VAR"))
        #expect(result.contains("# after content"))
    }

    @Test func rebuildPersistentShEmptyVars() {
        let existing = """
            # --- sbx-ui managed (DO NOT EDIT) ---
            export KEY=val
            # --- end sbx-ui managed ---
            """
        let result = SbxOutputParser.rebuildPersistentSh(
            existingContent: existing, managedVars: []
        )
        #expect(result.isEmpty)
    }
}

// MARK: - Integration Tests (with mock-sbx)

@Suite(.serialized) struct IntegrationTests {
    private func makeTestService() throws -> (RealSbxService, String) {
        let stateDir = NSTemporaryDirectory() + "mock-sbx-test-\(UUID().uuidString)"
        // Find the tools directory relative to this test file
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // SBXCoreTests/
            .deletingLastPathComponent()  // Tests/
            .deletingLastPathComponent()  // project root
        let toolsDir = projectRoot.appendingPathComponent("tools").path

        // Inject mock-sbx via environment
        let sbxPath = "\(toolsDir)/sbx"
        guard FileManager.default.isExecutableFile(atPath: sbxPath) else {
            throw SbxServiceError.cliError("mock-sbx not found at \(sbxPath)")
        }
        setenv("SBX_MOCK_STATE_DIR", stateDir, 1)
        setenv("PATH", "\(toolsDir):\(ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin")", 1)

        let cli = CliExecutor()
        let svc = RealSbxService(cli: cli)
        return (svc, stateDir)
    }

    private func cleanup(_ stateDir: String) {
        try? FileManager.default.removeItem(atPath: stateDir)
    }

    @Test func listEmpty() async throws {
        let (svc, stateDir) = try makeTestService()
        defer { cleanup(stateDir) }
        let sandboxes = try await svc.list()
        #expect(sandboxes.isEmpty)
    }

    @Test func createAndList() async throws {
        let (svc, stateDir) = try makeTestService()
        defer { cleanup(stateDir) }

        let opts = RunOptions(name: "test-sb")
        let sb = try await svc.run(agent: "claude", workspace: "/tmp/test", opts: opts)
        #expect(sb.name == "test-sb")
        #expect(sb.status == .running)

        let sandboxes = try await svc.list()
        #expect(sandboxes.count == 1)
    }

    @Test func stopSandbox() async throws {
        let (svc, stateDir) = try makeTestService()
        defer { cleanup(stateDir) }

        let opts = RunOptions(name: "stop-test")
        _ = try await svc.run(agent: "claude", workspace: "/tmp/test", opts: opts)
        try await svc.stop(name: "stop-test")

        let sandboxes = try await svc.list()
        let stopped = sandboxes.first { $0.name == "stop-test" }
        #expect(stopped?.status == .stopped)
    }

    @Test func removeSandbox() async throws {
        let (svc, stateDir) = try makeTestService()
        defer { cleanup(stateDir) }

        let opts = RunOptions(name: "rm-test")
        _ = try await svc.run(agent: "claude", workspace: "/tmp/test", opts: opts)
        try await svc.rm(name: "rm-test")

        let sandboxes = try await svc.list()
        #expect(sandboxes.isEmpty)
    }

    @Test func policyList() async throws {
        let (svc, stateDir) = try makeTestService()
        defer { cleanup(stateDir) }

        let rules = try await svc.policyList()
        #expect(!rules.isEmpty)  // mock-sbx seeds default rules
    }

    @Test func policyAllowAndDeny() async throws {
        let (svc, stateDir) = try makeTestService()
        defer { cleanup(stateDir) }

        let allow = try await svc.policyAllow(resources: "example.com")
        #expect(allow.resources == "example.com")
        #expect(allow.decision == .allow)

        let deny = try await svc.policyDeny(resources: "evil.com")
        #expect(deny.resources == "evil.com")
        #expect(deny.decision == .deny)
    }

    @Test func policyLog() async throws {
        let (svc, stateDir) = try makeTestService()
        defer { cleanup(stateDir) }

        let entries = try await svc.policyLog(sandboxName: nil)
        #expect(!entries.isEmpty)

        let blocked = entries.filter { $0.blocked }
        let allowed = entries.filter { !$0.blocked }
        #expect(!blocked.isEmpty)
        #expect(!allowed.isEmpty)
    }

    @Test func portsPublishAndList() async throws {
        let (svc, stateDir) = try makeTestService()
        defer { cleanup(stateDir) }

        let opts = RunOptions(name: "port-test")
        _ = try await svc.run(agent: "claude", workspace: "/tmp/test", opts: opts)

        let mapping = try await svc.portsPublish(name: "port-test", hostPort: 8080, sbxPort: 3000)
        #expect(mapping.hostPort == 8080)
        #expect(mapping.sandboxPort == 3000)

        let ports = try await svc.portsList(name: "port-test")
        #expect(ports.count == 1)
    }

    @Test func envVarSetAndList() async throws {
        let (svc, stateDir) = try makeTestService()
        defer { cleanup(stateDir) }

        let opts = RunOptions(name: "env-test")
        _ = try await svc.run(agent: "claude", workspace: "/tmp/test", opts: opts)

        // Set a var via sync
        let newVars = [EnvVar(key: "MY_KEY", value: "my_value")]
        try await svc.envVarSync(name: "env-test", vars: newVars)

        let vars = try await svc.envVarList(name: "env-test")
        #expect(vars.count == 1)
        #expect(vars[0].key == "MY_KEY")
        #expect(vars[0].value == "my_value")
    }
}
