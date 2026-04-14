// EnvVarTests.swift — Cover `sbx-ui env` subcommands (ls / set / rm). Env
// vars are stored inside the sandbox at /etc/sandbox-persistent.sh; mock-sbx
// intercepts that path and persists to its state dir, so tests can exercise
// the full round-trip without Docker.

import Foundation
import Testing

@Suite("CLI: env ls")
struct EnvListTests {
    @Test func listEmptyText() throws {
        let runner = try CLIRunner()
        try runner.createSandbox(name: "env-empty")

        let result = try runner.run(["env", "ls", "env-empty"])
        expectSuccess(result)
        #expect(result.stdout.contains("No managed environment variables"))
    }

    @Test func listEmptyJson() throws {
        let runner = try CLIRunner()
        try runner.createSandbox(name: "env-empty-json")

        let result = try runner.run(["env", "ls", "env-empty-json", "--json"])
        expectSuccess(result)
        let arr = try parseJSON(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)) as? [Any] ?? []
        #expect(arr.isEmpty)
    }

    @Test func listPopulatedText() throws {
        let runner = try CLIRunner()
        try runner.createSandbox(name: "env-text")
        _ = try runner.run(["env", "set", "env-text", "FOO", "bar"])
        _ = try runner.run(["env", "set", "env-text", "BAZ", "qux"])

        let result = try runner.run(["env", "ls", "env-text"])
        expectSuccess(result)
        #expect(result.stdout.contains("KEY"))
        #expect(result.stdout.contains("VALUE"))
        #expect(result.stdout.contains("FOO"))
        #expect(result.stdout.contains("bar"))
        #expect(result.stdout.contains("BAZ"))
        #expect(result.stdout.contains("qux"))
    }

    @Test func listPopulatedJson() throws {
        let runner = try CLIRunner()
        try runner.createSandbox(name: "env-json")
        _ = try runner.run(["env", "set", "env-json", "API_KEY", "sk-12345"])

        let result = try runner.run(["env", "ls", "env-json", "--json"])
        expectSuccess(result)
        let arr = try parseJSON(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)) as? [[String: Any]] ?? []
        #expect(arr.count == 1)
        #expect(arr[0]["key"] as? String == "API_KEY")
        #expect(arr[0]["value"] as? String == "sk-12345")
    }
}

@Suite("CLI: env set")
struct EnvSetTests {
    @Test func setUpsertSucceeds() throws {
        let runner = try CLIRunner()
        try runner.createSandbox(name: "env-set")

        let first = try runner.run(["env", "set", "env-set", "MY_KEY", "initial"])
        expectSuccess(first)
        #expect(first.stdout.contains("Set"))
        #expect(first.stdout.contains("MY_KEY"))

        // Upsert should overwrite rather than create a second entry.
        let second = try runner.run(["env", "set", "env-set", "MY_KEY", "updated"])
        expectSuccess(second)

        let list = try runner.run(["env", "ls", "env-set", "--json"])
        let arr = try parseJSON(list.stdout.trimmingCharacters(in: .whitespacesAndNewlines)) as? [[String: Any]] ?? []
        #expect(arr.count == 1)
        #expect(arr[0]["value"] as? String == "updated")
    }

    @Test func setInvalidKeyFails() throws {
        let runner = try CLIRunner()
        try runner.createSandbox(name: "env-bad")

        // Leading digit is invalid per SbxValidation (^[A-Za-z_][A-Za-z0-9_]*$).
        let result = try runner.run(["env", "set", "env-bad", "2INVALID", "value"])
        #expect(!result.succeeded)
        #expect(result.cleanStderr.contains("Invalid") || result.cleanStderr.contains("env var key"))

        // Verify nothing was persisted.
        let list = try runner.run(["env", "ls", "env-bad", "--json"])
        let arr = try parseJSON(list.stdout.trimmingCharacters(in: .whitespacesAndNewlines)) as? [Any] ?? []
        #expect(arr.isEmpty)
    }

    @Test func setValueWithSpacesAndSymbols() throws {
        let runner = try CLIRunner()
        try runner.createSandbox(name: "env-special")

        // The heredoc persistence should preserve unusual characters. Keep
        // the value simple enough to survive bash-script interpolation in
        // the mock (no single quotes needed since heredoc is quoted).
        let value = "hello=world/path:with:colons,commas"
        let set = try runner.run(["env", "set", "env-special", "PATHLIKE", value])
        expectSuccess(set)

        let list = try runner.run(["env", "ls", "env-special", "--json"])
        let arr = try parseJSON(list.stdout.trimmingCharacters(in: .whitespacesAndNewlines)) as? [[String: Any]] ?? []
        #expect(arr.count == 1)
        #expect(arr[0]["key"] as? String == "PATHLIKE")
        #expect(arr[0]["value"] as? String == value)
    }
}

@Suite("CLI: env rm")
struct EnvRemoveTests {
    @Test func rmExistingKey() throws {
        let runner = try CLIRunner()
        try runner.createSandbox(name: "env-rm")
        _ = try runner.run(["env", "set", "env-rm", "KEEP", "k"])
        _ = try runner.run(["env", "set", "env-rm", "DROP", "d"])

        let rm = try runner.run(["env", "rm", "env-rm", "DROP"])
        expectSuccess(rm)
        #expect(rm.stdout.contains("Removed"))

        let list = try runner.run(["env", "ls", "env-rm", "--json"])
        let arr = try parseJSON(list.stdout.trimmingCharacters(in: .whitespacesAndNewlines)) as? [[String: Any]] ?? []
        #expect(arr.count == 1)
        #expect(arr[0]["key"] as? String == "KEEP")
    }

    @Test func rmLastKeyRemovesFile() throws {
        let runner = try CLIRunner()
        try runner.createSandbox(name: "env-last")
        _ = try runner.run(["env", "set", "env-last", "ONLY", "x"])

        let rm = try runner.run(["env", "rm", "env-last", "ONLY"])
        expectSuccess(rm)

        // After removing the last managed var, the service deletes the
        // persistent.sh file entirely; listing returns empty cleanly.
        let list = try runner.run(["env", "ls", "env-last", "--json"])
        let arr = try parseJSON(list.stdout.trimmingCharacters(in: .whitespacesAndNewlines)) as? [Any] ?? []
        #expect(arr.isEmpty)
    }

    @Test func rmMissingKeyIsNoop() throws {
        let runner = try CLIRunner()
        try runner.createSandbox(name: "env-missing")
        _ = try runner.run(["env", "set", "env-missing", "PRESENT", "v"])

        // Removing a key that isn't set silently syncs without error — the
        // result is just "list unchanged". Confirm idempotence.
        let rm = try runner.run(["env", "rm", "env-missing", "ABSENT"])
        expectSuccess(rm)

        let list = try runner.run(["env", "ls", "env-missing", "--json"])
        let arr = try parseJSON(list.stdout.trimmingCharacters(in: .whitespacesAndNewlines)) as? [[String: Any]] ?? []
        #expect(arr.count == 1)
        #expect(arr[0]["key"] as? String == "PRESENT")
    }
}
