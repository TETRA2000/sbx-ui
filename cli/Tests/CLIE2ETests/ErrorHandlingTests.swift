// ErrorHandlingTests.swift — Focused exercises on error paths: invalid
// arguments, missing sandboxes, and usage-mode argument parser failures.
// These confirm the CLI writes errors to stderr and exits non-zero.

import Foundation
import Testing

@Suite("CLI: argument parser errors")
struct ArgumentParserErrorTests {
    @Test func createRequiresWorkspace() throws {
        let runner = try CLIRunner()
        let result = try runner.run(["create"])
        expectFailure(result)
        // ArgumentParser prints a usage snippet on missing args.
        #expect(result.cleanStderr.contains("workspace") || result.cleanStderr.contains("Usage"))
    }

    @Test func stopRequiresName() throws {
        let runner = try CLIRunner()
        let result = try runner.run(["stop"])
        expectFailure(result)
        #expect(result.cleanStderr.contains("name") || result.cleanStderr.contains("Usage"))
    }

    @Test func policyAllowRequiresResources() throws {
        let runner = try CLIRunner()
        let result = try runner.run(["policy", "allow"])
        expectFailure(result)
    }

    @Test func portsPublishRequiresSpec() throws {
        let runner = try CLIRunner()
        try runner.createSandbox(name: "ap-sb")
        let result = try runner.run(["ports", "publish", "ap-sb"])
        expectFailure(result)
    }

    @Test func envSetRequiresThreeArguments() throws {
        let runner = try CLIRunner()
        try runner.createSandbox(name: "esa-sb")
        // Missing value argument.
        let result = try runner.run(["env", "set", "esa-sb", "KEY"])
        expectFailure(result)
    }

    @Test func unknownSubcommandFails() throws {
        let runner = try CLIRunner()
        let result = try runner.run(["not-a-command"])
        expectFailure(result)
    }

    @Test func unknownPolicySubcommandFails() throws {
        let runner = try CLIRunner()
        let result = try runner.run(["policy", "wat"])
        expectFailure(result)
    }
}

@Suite("CLI: runtime errors")
struct RuntimeErrorTests {
    @Test func statusOnMissingSandboxShowsName() throws {
        let runner = try CLIRunner()
        let result = try runner.run(["status", "xyz-missing"])
        expectFailure(result)
        #expect(result.cleanStderr.contains("xyz-missing"))
    }

    @Test func execOnMissingSandboxShowsName() throws {
        let runner = try CLIRunner()
        let result = try runner.run(["exec", "xyz-missing", "echo", "x"])
        expectFailure(result)
        #expect(result.cleanStderr.contains("xyz-missing") || result.cleanStderr.contains("not found"))
    }

    @Test func portsUnpublishUnknownSandboxFails() throws {
        let runner = try CLIRunner()
        let result = try runner.run(["ports", "unpublish", "ghost", "8080:3000"])
        expectFailure(result)
    }

    @Test func errorsGoToStderrNotStdout() throws {
        let runner = try CLIRunner()
        let result = try runner.run(["status", "does-not-exist"])
        expectFailure(result)
        // User-facing error should NOT appear on stdout — tools parsing JSON
        // or piping stdout to grep must not see errors mixed into success data.
        #expect(!result.stdout.contains("not found"))
        #expect(!result.stdout.contains("Error:"))
    }

    @Test func exitCodeNonzeroOnError() throws {
        let runner = try CLIRunner()
        let result = try runner.run(["stop", "nonexistent"])
        #expect(result.exitCode != 0)
    }
}

@Suite("CLI: isolation")
struct IsolationTests {
    /// Two CLIRunner instances must not share state even when created back
    /// to back — each gets its own `SBX_MOCK_STATE_DIR`.
    @Test func runnersAreIsolated() throws {
        let a = try CLIRunner()
        let b = try CLIRunner()
        try a.createSandbox(name: "only-in-a")

        let aList = try a.run(["ls", "--json"])
        let bList = try b.run(["ls", "--json"])
        let aArr = try parseJSON(aList.stdout.trimmingCharacters(in: .whitespacesAndNewlines)) as? [[String: Any]] ?? []
        let bArr = try parseJSON(bList.stdout.trimmingCharacters(in: .whitespacesAndNewlines)) as? [Any] ?? []

        #expect(aArr.count == 1)
        #expect(aArr[0]["name"] as? String == "only-in-a")
        #expect(bArr.isEmpty)
    }
}
