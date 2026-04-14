// LifecycleTests.swift — Cover the sandbox lifecycle subcommands:
// `ls`, `create`, `stop`, `rm`, `exec`, `status`. Each test uses its own
// isolated mock-sbx state directory via CLIRunner.

import Foundation
import Testing

// MARK: - ls

@Suite("CLI: ls")
struct ListTests {
    @Test func listEmptyText() throws {
        let runner = try CLIRunner()
        let result = try runner.run(["ls"])
        #expect(result.succeeded)
        #expect(result.stdout.contains("No sandboxes found"))
    }

    @Test func listEmptyJson() throws {
        let runner = try CLIRunner()
        let result = try runner.run(["ls", "--json"])
        #expect(result.succeeded)
        // Trim trailing newline then parse.
        let parsed = try parseJSON(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines))
        guard let arr = parsed as? [Any] else {
            Issue.record("expected JSON array, got \(type(of: parsed))")
            return
        }
        #expect(arr.isEmpty)
    }

    @Test func listAfterCreateText() throws {
        let runner = try CLIRunner()
        try runner.createSandbox(name: "alpha", workspace: "/tmp/alpha")

        let result = try runner.run(["ls"])
        #expect(result.succeeded)
        // Table header + row should be present.
        #expect(result.stdout.contains("SANDBOX"))
        #expect(result.stdout.contains("AGENT"))
        #expect(result.stdout.contains("STATUS"))
        #expect(result.stdout.contains("alpha"))
        #expect(result.stdout.contains("claude"))
        #expect(result.stdout.contains("running"))
        #expect(result.stdout.contains("/tmp/alpha"))
    }

    @Test func listAfterCreateJson() throws {
        let runner = try CLIRunner()
        try runner.createSandbox(name: "bravo", workspace: "/tmp/bravo")
        try runner.createSandbox(name: "charlie", workspace: "/tmp/charlie")

        let result = try runner.run(["ls", "--json"])
        #expect(result.succeeded)

        let parsed = try parseJSON(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines))
        guard let arr = parsed as? [[String: Any]] else {
            Issue.record("expected array of objects")
            return
        }
        #expect(arr.count == 2)
        let names = Set(arr.compactMap { $0["name"] as? String })
        #expect(names == ["bravo", "charlie"])
        for entry in arr {
            #expect(entry["agent"] as? String == "claude")
            #expect(entry["status"] as? String == "running")
            #expect((entry["workspace"] as? String)?.hasPrefix("/tmp/") == true)
        }
    }
}

// MARK: - create

@Suite("CLI: create")
struct CreateTests {
    @Test func createSucceedsWithDefaults() throws {
        let runner = try CLIRunner()
        let result = try runner.run(["create", "/tmp/proj", "--name", "sb1"])
        expectSuccess(result)
        #expect(result.stdout.contains("Created sandbox 'sb1'"))
        #expect(result.stdout.contains("Workspace: /tmp/proj"))
        #expect(result.stdout.contains("Agent: claude"))
        #expect(result.stdout.contains("Status:"))
        #expect(result.stdout.contains("running"))
    }

    @Test func createWithCustomAgent() throws {
        let runner = try CLIRunner()
        let result = try runner.run([
            "create", "/tmp/proj2",
            "--agent", "demo",
            "--name", "sb2",
        ])
        expectSuccess(result)
        #expect(result.stdout.contains("Agent: demo"))

        // The listing should reflect the custom agent.
        let listJson = try runner.run(["ls", "--json"])
        let parsed = try parseJSON(listJson.stdout.trimmingCharacters(in: .whitespacesAndNewlines))
        let arr = (parsed as? [[String: Any]]) ?? []
        #expect(arr.first?["agent"] as? String == "demo")
    }

    @Test func createJsonOutput() throws {
        let runner = try CLIRunner()
        let result = try runner.run([
            "create", "/tmp/json-proj",
            "--name", "json-sb",
            "--json",
        ])
        expectSuccess(result)
        // JSON mode still prints a single JSON object. The informational
        // "Creating sandbox..." line is also printed; skip until we see '{'.
        guard let braceIdx = result.stdout.firstIndex(of: "{") else {
            Issue.record("no JSON object in stdout: \(result.stdout)")
            return
        }
        let jsonSlice = String(result.stdout[braceIdx...]).trimmingCharacters(in: .whitespacesAndNewlines)
        let parsed = try parseJSON(jsonSlice) as? [String: Any]
        #expect(parsed?["name"] as? String == "json-sb")
        #expect(parsed?["agent"] as? String == "claude")
        #expect(parsed?["status"] as? String == "running")
        #expect(parsed?["workspace"] as? String == "/tmp/json-proj")
    }

    @Test func createInvalidNameFails() throws {
        let runner = try CLIRunner()
        // Uppercase is invalid per SbxValidation (^[a-z0-9][a-z0-9-]*$).
        let result = try runner.run(["create", "/tmp/bad", "--name", "BadName"])
        #expect(!result.succeeded)
        #expect(result.cleanStderr.contains("Invalid") || result.cleanStderr.contains("invalid"))
    }

    @Test func createMultipleSandboxes() throws {
        let runner = try CLIRunner()
        for i in 1...3 {
            try runner.createSandbox(name: "multi-\(i)", workspace: "/tmp/multi-\(i)")
        }
        let list = try runner.run(["ls", "--json"])
        let arr = try parseJSON(list.stdout.trimmingCharacters(in: .whitespacesAndNewlines)) as? [[String: Any]] ?? []
        #expect(arr.count == 3)
    }
}

// MARK: - stop / rm

@Suite("CLI: stop & rm")
struct StopAndRemoveTests {
    @Test func stopFlipsStatus() throws {
        let runner = try CLIRunner()
        try runner.createSandbox(name: "to-stop")

        let stopResult = try runner.run(["stop", "to-stop"])
        expectSuccess(stopResult)
        #expect(stopResult.stdout.contains("Stopped sandbox 'to-stop'"))

        let list = try runner.run(["ls", "--json"])
        let arr = try parseJSON(list.stdout.trimmingCharacters(in: .whitespacesAndNewlines)) as? [[String: Any]] ?? []
        #expect(arr.first?["status"] as? String == "stopped")
    }

    @Test func rmDeletesSandbox() throws {
        let runner = try CLIRunner()
        try runner.createSandbox(name: "to-remove")

        let rmResult = try runner.run(["rm", "to-remove"])
        expectSuccess(rmResult)
        #expect(rmResult.stdout.contains("Removed sandbox 'to-remove'"))

        let list = try runner.run(["ls", "--json"])
        let arr = try parseJSON(list.stdout.trimmingCharacters(in: .whitespacesAndNewlines)) as? [Any] ?? []
        #expect(arr.isEmpty)
    }

    @Test func rmNonexistentFails() throws {
        let runner = try CLIRunner()
        let result = try runner.run(["rm", "ghost"])
        #expect(!result.succeeded)
        #expect(result.cleanStderr.contains("ghost") || result.cleanStderr.contains("not found"))
    }

    @Test func stopNonexistentFails() throws {
        let runner = try CLIRunner()
        let result = try runner.run(["stop", "phantom"])
        #expect(!result.succeeded)
    }

    @Test func rmWhileStoppedStillWorks() throws {
        let runner = try CLIRunner()
        try runner.createSandbox(name: "stop-then-rm")
        _ = try runner.run(["stop", "stop-then-rm"])
        let rm = try runner.run(["rm", "stop-then-rm"])
        expectSuccess(rm)
    }
}

// MARK: - exec

@Suite("CLI: exec")
struct ExecTests {
    @Test func execPassesThroughStdout() throws {
        let runner = try CLIRunner()
        try runner.createSandbox(name: "exec-sb")

        let result = try runner.run(["exec", "exec-sb", "echo", "hello-e2e"])
        expectSuccess(result)
        #expect(result.stdout.contains("hello-e2e"))
    }

    @Test func execForwardsCommandArgs() throws {
        let runner = try CLIRunner()
        try runner.createSandbox(name: "exec-sb")

        // mock-sbx `exec` execs the command, so `printf "%s\n" a b` works.
        let result = try runner.run(["exec", "exec-sb", "printf", "%s\n", "alpha", "beta"])
        expectSuccess(result)
        #expect(result.stdout.contains("alpha"))
        #expect(result.stdout.contains("beta"))
    }

    @Test func execNonexistentFails() throws {
        let runner = try CLIRunner()
        let result = try runner.run(["exec", "nobody", "echo", "oops"])
        #expect(!result.succeeded)
    }

    @Test func execOnStoppedFails() throws {
        let runner = try CLIRunner()
        try runner.createSandbox(name: "stopped-exec")
        _ = try runner.run(["stop", "stopped-exec"])

        let result = try runner.run(["exec", "stopped-exec", "echo", "x"])
        #expect(!result.succeeded)
    }
}

// MARK: - status

@Suite("CLI: status")
struct StatusTests {
    @Test func statusTextFormat() throws {
        let runner = try CLIRunner()
        try runner.createSandbox(name: "info-sb", workspace: "/tmp/info")

        let result = try runner.run(["status", "info-sb"])
        expectSuccess(result)
        #expect(result.stdout.contains("Sandbox: info-sb"))
        #expect(result.stdout.contains("Agent:"))
        #expect(result.stdout.contains("claude"))
        #expect(result.stdout.contains("Status:"))
        #expect(result.stdout.contains("running"))
        #expect(result.stdout.contains("Workspace:"))
        #expect(result.stdout.contains("/tmp/info"))
    }

    @Test func statusJsonSchema() throws {
        let runner = try CLIRunner()
        try runner.createSandbox(name: "json-info", workspace: "/tmp/jinfo")

        let result = try runner.run(["status", "json-info", "--json"])
        expectSuccess(result)
        let parsed = try parseJSON(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)) as? [String: Any]
        #expect(parsed != nil)
        #expect(parsed?["name"] as? String == "json-info")
        #expect(parsed?["agent"] as? String == "claude")
        #expect(parsed?["status"] as? String == "running")
        #expect(parsed?["workspace"] as? String == "/tmp/jinfo")
        // `ports` key is always present; may be empty.
        #expect(parsed?["ports"] != nil)
        // Running sandboxes include env_vars (empty array by default).
        #expect(parsed?["env_vars"] != nil)
    }

    @Test func statusNonexistentFails() throws {
        let runner = try CLIRunner()
        let result = try runner.run(["status", "missing"])
        #expect(!result.succeeded)
        #expect(result.cleanStderr.contains("missing") || result.cleanStderr.contains("not found"))
    }

    @Test func statusStoppedOmitsEnvVars() throws {
        let runner = try CLIRunner()
        try runner.createSandbox(name: "stopped-status")
        _ = try runner.run(["stop", "stopped-status"])

        let result = try runner.run(["status", "stopped-status", "--json"])
        expectSuccess(result)
        let parsed = try parseJSON(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)) as? [String: Any]
        #expect(parsed?["status"] as? String == "stopped")
        // env_vars is not emitted for non-running sandboxes.
        #expect(parsed?["env_vars"] == nil)
    }
}
