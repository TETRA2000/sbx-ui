// ScenarioTests.swift — Multi-step end-to-end scenarios that mirror realistic
// developer workflows. These round-trips verify that state mutations from
// one subcommand are visible to another (and cleaned up properly).

import Foundation
import Testing

@Suite("CLI: scenarios")
struct ScenarioTests {
    /// Canonical flow: create → publish port → set env → list → stop →
    /// restart-via-exec-error → remove → verify empty.
    @Test func fullLifecycle() throws {
        let runner = try CLIRunner()
        let name = "flow"

        // 1. Create
        try runner.createSandbox(name: name, workspace: "/tmp/flow")

        // 2. Publish ports
        _ = try runner.run(["ports", "publish", name, "8080:3000"])
        _ = try runner.run(["ports", "publish", name, "9090:4000"])
        let portsJson = try runner.run(["ports", "ls", name, "--json"])
        let ports = try parseJSON(portsJson.stdout.trimmingCharacters(in: .whitespacesAndNewlines)) as? [[String: Any]] ?? []
        #expect(ports.count == 2)

        // 3. Set env vars
        _ = try runner.run(["env", "set", name, "API_KEY", "abc"])
        _ = try runner.run(["env", "set", name, "NODE_ENV", "production"])
        let envJson = try runner.run(["env", "ls", name, "--json"])
        let envArr = try parseJSON(envJson.stdout.trimmingCharacters(in: .whitespacesAndNewlines)) as? [[String: Any]] ?? []
        #expect(envArr.count == 2)

        // 4. Status reflects running state with env vars.
        let statusJson = try runner.run(["status", name, "--json"])
        let status = try parseJSON(statusJson.stdout.trimmingCharacters(in: .whitespacesAndNewlines)) as? [String: Any]
        #expect(status?["status"] as? String == "running")
        let statusEnv = status?["env_vars"] as? [[String: Any]] ?? []
        #expect(statusEnv.count == 2)

        // 5. Stop → status flips → ports are cleared.
        _ = try runner.run(["stop", name])
        let statusStopped = try runner.run(["status", name, "--json"])
        let stoppedObj = try parseJSON(statusStopped.stdout.trimmingCharacters(in: .whitespacesAndNewlines)) as? [String: Any]
        #expect(stoppedObj?["status"] as? String == "stopped")

        let clearedPorts = try runner.run(["ports", "ls", name, "--json"])
        let clearedArr = try parseJSON(clearedPorts.stdout.trimmingCharacters(in: .whitespacesAndNewlines)) as? [Any] ?? []
        #expect(clearedArr.isEmpty)

        // 6. Remove → ls is empty.
        _ = try runner.run(["rm", name])
        let finalList = try runner.run(["ls", "--json"])
        let finalArr = try parseJSON(finalList.stdout.trimmingCharacters(in: .whitespacesAndNewlines)) as? [Any] ?? []
        #expect(finalArr.isEmpty)
    }

    /// Network policy management round-trip: default allows → add allow →
    /// add deny → remove both → confirm defaults still present.
    @Test func policyRoundTrip() throws {
        let runner = try CLIRunner()

        // Baseline: capture seeded rule count.
        let baseline = try runner.run(["policy", "ls", "--json"])
        let baseCount = (try parseJSON(baseline.stdout.trimmingCharacters(in: .whitespacesAndNewlines)) as? [Any] ?? []).count
        #expect(baseCount > 0, "mock seeds default allow rules")

        // Add one allow + one deny.
        _ = try runner.run(["policy", "allow", "custom.allowed"])
        _ = try runner.run(["policy", "deny", "custom.blocked"])

        let mid = try runner.run(["policy", "ls", "--json"])
        let midArr = try parseJSON(mid.stdout.trimmingCharacters(in: .whitespacesAndNewlines)) as? [[String: Any]] ?? []
        #expect(midArr.count == baseCount + 2)
        #expect(midArr.contains { ($0["resources"] as? String) == "custom.allowed" && ($0["decision"] as? String) == "allow" })
        #expect(midArr.contains { ($0["resources"] as? String) == "custom.blocked" && ($0["decision"] as? String) == "deny" })

        // Remove only the custom rules.
        _ = try runner.run(["policy", "rm", "custom.allowed"])
        _ = try runner.run(["policy", "rm", "custom.blocked"])

        let after = try runner.run(["policy", "ls", "--json"])
        let afterArr = try parseJSON(after.stdout.trimmingCharacters(in: .whitespacesAndNewlines)) as? [[String: Any]] ?? []
        #expect(afterArr.count == baseCount)
        #expect(!afterArr.contains { ($0["resources"] as? String) == "custom.allowed" })
        #expect(!afterArr.contains { ($0["resources"] as? String) == "custom.blocked" })
        // Defaults survived.
        #expect(afterArr.contains { ($0["resources"] as? String) == "api.anthropic.com" })
    }

    /// Env var mutation sequence exercises upsert / overwrite / final removal.
    @Test func envVarMutationSequence() throws {
        let runner = try CLIRunner()
        let name = "envseq"
        try runner.createSandbox(name: name)

        // Initial set of 3 vars.
        for (k, v) in [("A", "1"), ("B", "2"), ("C", "3")] {
            _ = try runner.run(["env", "set", name, k, v])
        }
        var arr = try parseJSON(
            runner.run(["env", "ls", name, "--json"]).stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        ) as? [[String: Any]] ?? []
        #expect(arr.count == 3)

        // Overwrite B.
        _ = try runner.run(["env", "set", name, "B", "22"])
        arr = try parseJSON(
            runner.run(["env", "ls", name, "--json"]).stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        ) as? [[String: Any]] ?? []
        #expect(arr.count == 3)
        #expect(arr.first { ($0["key"] as? String) == "B" }?["value"] as? String == "22")

        // Remove one by one.
        for key in ["A", "B", "C"] {
            _ = try runner.run(["env", "rm", name, key])
        }
        arr = try parseJSON(
            runner.run(["env", "ls", name, "--json"]).stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        ) as? [[String: Any]] ?? []
        #expect(arr.isEmpty)
    }

    /// Two sandboxes with disjoint ports: deleting one leaves the other's
    /// ports untouched.
    @Test func portsIsolatedBetweenSandboxes() throws {
        let runner = try CLIRunner()
        try runner.createSandbox(name: "iso-a")
        try runner.createSandbox(name: "iso-b")

        _ = try runner.run(["ports", "publish", "iso-a", "8080:3000"])
        _ = try runner.run(["ports", "publish", "iso-b", "9090:4000"])

        _ = try runner.run(["rm", "iso-a"])

        let bPorts = try runner.run(["ports", "ls", "iso-b", "--json"])
        let arr = try parseJSON(bPorts.stdout.trimmingCharacters(in: .whitespacesAndNewlines)) as? [[String: Any]] ?? []
        #expect(arr.count == 1)
        #expect(arr[0]["host_port"] as? Int == 9090)
    }
}
