// PolicyTests.swift — Cover `sbx-ui policy` subcommands:
// ls / allow / deny / rm / log (text & JSON). Each test uses its own mock-sbx
// state, and mock-sbx seeds a default set of allow rules plus a handful of
// policy-log entries on first use.

import Foundation
import Testing

@Suite("CLI: policy ls")
struct PolicyListTests {
    @Test func listDefaultRulesText() throws {
        let runner = try CLIRunner()
        let result = try runner.run(["policy", "ls"])
        expectSuccess(result)
        // Mock seeds these domains on first access.
        #expect(result.stdout.contains("NAME"))
        #expect(result.stdout.contains("DECISION"))
        #expect(result.stdout.contains("allow"))
        #expect(result.stdout.contains("api.anthropic.com"))
        #expect(result.stdout.contains("github.com"))
    }

    @Test func listDefaultRulesJson() throws {
        let runner = try CLIRunner()
        let result = try runner.run(["policy", "ls", "--json"])
        expectSuccess(result)
        let parsed = try parseJSON(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines))
        guard let arr = parsed as? [[String: Any]] else {
            Issue.record("expected array of objects, got \(type(of: parsed))")
            return
        }
        #expect(arr.count >= 5, "mock seeds several default allow rules")
        for rule in arr {
            #expect(rule["type"] as? String == "network")
            #expect(["allow", "deny"].contains(rule["decision"] as? String ?? ""))
            #expect(rule["id"] as? String != nil)
            #expect(rule["resources"] as? String != nil)
        }
        let resources = Set(arr.compactMap { $0["resources"] as? String })
        #expect(resources.contains("api.anthropic.com"))
    }
}

@Suite("CLI: policy allow / deny / rm")
struct PolicyMutationTests {
    @Test func allowAddsRule() throws {
        let runner = try CLIRunner()

        let before = try runner.run(["policy", "ls", "--json"])
        let beforeArr = try parseJSON(before.stdout.trimmingCharacters(in: .whitespacesAndNewlines)) as? [[String: Any]] ?? []
        let beforeCount = beforeArr.count

        let add = try runner.run(["policy", "allow", "example.test"])
        expectSuccess(add)
        #expect(add.stdout.contains("Policy added"))
        #expect(add.stdout.contains("example.test"))

        let after = try runner.run(["policy", "ls", "--json"])
        let afterArr = try parseJSON(after.stdout.trimmingCharacters(in: .whitespacesAndNewlines)) as? [[String: Any]] ?? []
        #expect(afterArr.count == beforeCount + 1)

        let match = afterArr.first { $0["resources"] as? String == "example.test" }
        #expect(match?["decision"] as? String == "allow")
    }

    @Test func denyAddsRule() throws {
        let runner = try CLIRunner()
        let add = try runner.run(["policy", "deny", "evil.test"])
        expectSuccess(add)
        #expect(add.stdout.contains("Policy added"))
        #expect(add.stdout.contains("evil.test"))

        let list = try runner.run(["policy", "ls", "--json"])
        let arr = try parseJSON(list.stdout.trimmingCharacters(in: .whitespacesAndNewlines)) as? [[String: Any]] ?? []
        let match = arr.first { $0["resources"] as? String == "evil.test" }
        #expect(match?["decision"] as? String == "deny")
    }

    @Test func rmDeletesRule() throws {
        let runner = try CLIRunner()
        _ = try runner.run(["policy", "allow", "temp.test"])

        let before = try runner.run(["policy", "ls", "--json"])
        let beforeArr = try parseJSON(before.stdout.trimmingCharacters(in: .whitespacesAndNewlines)) as? [[String: Any]] ?? []
        #expect(beforeArr.contains { $0["resources"] as? String == "temp.test" })

        let rm = try runner.run(["policy", "rm", "temp.test"])
        expectSuccess(rm)
        #expect(rm.stdout.contains("Policy removed"))

        let after = try runner.run(["policy", "ls", "--json"])
        let afterArr = try parseJSON(after.stdout.trimmingCharacters(in: .whitespacesAndNewlines)) as? [[String: Any]] ?? []
        #expect(!afterArr.contains { $0["resources"] as? String == "temp.test" })
    }

    @Test func rmUnknownFails() throws {
        let runner = try CLIRunner()
        let result = try runner.run(["policy", "rm", "never-added.test"])
        #expect(!result.succeeded)
    }
}

@Suite("CLI: policy log")
struct PolicyLogTests {
    @Test func logJsonContainsSeededEntries() throws {
        let runner = try CLIRunner()
        // The service layer always adds --json to the underlying sbx call,
        // so the `--json` flag on the CLI just changes how results are rendered.
        let result = try runner.run(["policy", "log", "--json"])
        expectSuccess(result)
        let parsed = try parseJSON(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines))
        guard let arr = parsed as? [[String: Any]] else {
            Issue.record("expected array, got \(type(of: parsed))")
            return
        }
        #expect(!arr.isEmpty)

        // Mock seeds at least one blocked and one allowed entry.
        let hosts = Set(arr.compactMap { $0["host"] as? String })
        #expect(hosts.contains("api.anthropic.com"))
        #expect(hosts.contains("evil.example.com"))
        #expect(hosts.contains("registry.npmjs.org"))

        let hasBlocked = arr.contains { ($0["blocked"] as? String) == "true" }
        let hasAllowed = arr.contains { ($0["blocked"] as? String) == "false" }
        #expect(hasBlocked)
        #expect(hasAllowed)
    }

    @Test func logBlockedFlagFiltersEntries() throws {
        let runner = try CLIRunner()
        let result = try runner.run(["policy", "log", "--blocked", "--json"])
        expectSuccess(result)
        let arr = try parseJSON(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)) as? [[String: Any]] ?? []
        #expect(!arr.isEmpty, "seeded log always has at least one blocked entry")
        for entry in arr {
            #expect(entry["blocked"] as? String == "true")
        }
    }

    @Test func logTextOutputHasSections() throws {
        let runner = try CLIRunner()
        let result = try runner.run(["policy", "log"])
        expectSuccess(result)
        // Section headers are emitted when respective arrays are non-empty.
        #expect(result.stdout.contains("Allowed requests"))
        #expect(result.stdout.contains("Blocked requests"))
        // Seeded hosts should appear.
        #expect(result.stdout.contains("api.anthropic.com"))
        #expect(result.stdout.contains("evil.example.com"))
    }

    @Test func logTextBlockedOnly() throws {
        let runner = try CLIRunner()
        let result = try runner.run(["policy", "log", "--blocked"])
        expectSuccess(result)
        #expect(result.stdout.contains("Blocked requests"))
        // "Allowed requests" section must be omitted when --blocked is set.
        #expect(!result.stdout.contains("Allowed requests"))
    }
}
