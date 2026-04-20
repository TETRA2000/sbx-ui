// PortsTests.swift — Cover `sbx-ui ports` subcommands:
// ls / publish / unpublish. Port state is tracked per sandbox in mock-sbx's
// state dir, so each runner sees a fresh, empty port set.

import Foundation
import Testing

@Suite("CLI: ports ls")
struct PortsListTests {
    @Test func listEmptyText() throws {
        let runner = try CLIRunner()
        try runner.createSandbox(name: "p-empty")

        let result = try runner.run(["ports", "ls", "p-empty"])
        expectSuccess(result)
        #expect(result.stdout.contains("No published ports"))
    }

    @Test func listEmptyJson() throws {
        let runner = try CLIRunner()
        try runner.createSandbox(name: "p-empty-json")

        let result = try runner.run(["ports", "ls", "p-empty-json", "--json"])
        expectSuccess(result)
        let parsed = try parseJSON(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines))
        let arr = parsed as? [Any] ?? []
        #expect(arr.isEmpty)
    }

    @Test func listPopulatedText() throws {
        let runner = try CLIRunner()
        try runner.createSandbox(name: "p-text")
        _ = try runner.run(["ports", "publish", "p-text", "8080:3000"])
        _ = try runner.run(["ports", "publish", "p-text", "9090:4000"])

        let result = try runner.run(["ports", "ls", "p-text"])
        expectSuccess(result)
        #expect(result.stdout.contains("HOST PORT"))
        #expect(result.stdout.contains("SANDBOX PORT"))
        #expect(result.stdout.contains("PROTOCOL"))
        #expect(result.stdout.contains("8080"))
        #expect(result.stdout.contains("3000"))
        #expect(result.stdout.contains("9090"))
        #expect(result.stdout.contains("4000"))
        #expect(result.stdout.contains("tcp"))
    }

    @Test func listPopulatedJson() throws {
        let runner = try CLIRunner()
        try runner.createSandbox(name: "p-json")
        _ = try runner.run(["ports", "publish", "p-json", "8080:3000"])

        let result = try runner.run(["ports", "ls", "p-json", "--json"])
        expectSuccess(result)
        let parsed = try parseJSON(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines))
        guard let arr = parsed as? [[String: Any]] else {
            Issue.record("expected array of objects")
            return
        }
        #expect(arr.count == 1)
        #expect(arr[0]["host_port"] as? Int == 8080)
        #expect(arr[0]["sandbox_port"] as? Int == 3000)
        #expect(arr[0]["protocol"] as? String == "tcp")
    }
}

@Suite("CLI: ports publish / unpublish")
struct PortsPublishTests {
    @Test func publishAndUnpublishRoundtrip() throws {
        let runner = try CLIRunner()
        try runner.createSandbox(name: "p-round")

        let publish = try runner.run(["ports", "publish", "p-round", "8080:3000"])
        expectSuccess(publish)
        #expect(publish.stdout.contains("Published"))
        #expect(publish.stdout.contains("8080"))
        #expect(publish.stdout.contains("3000"))

        let unpublish = try runner.run(["ports", "unpublish", "p-round", "8080:3000"])
        expectSuccess(unpublish)
        #expect(unpublish.stdout.contains("Unpublished"))

        // After unpublish, listing should be empty again.
        let list = try runner.run(["ports", "ls", "p-round", "--json"])
        let arr = try parseJSON(list.stdout.trimmingCharacters(in: .whitespacesAndNewlines)) as? [Any] ?? []
        #expect(arr.isEmpty)
    }

    @Test func publishDuplicateHostPortFails() throws {
        let runner = try CLIRunner()
        try runner.createSandbox(name: "p-dup-a")
        try runner.createSandbox(name: "p-dup-b")

        let first = try runner.run(["ports", "publish", "p-dup-a", "8080:3000"])
        expectSuccess(first)

        // Duplicate host-port across any sandbox should fail in mock-sbx.
        let second = try runner.run(["ports", "publish", "p-dup-b", "8080:4000"])
        #expect(!second.succeeded)
    }

    @Test func publishInvalidSpecFails() throws {
        let runner = try CLIRunner()
        try runner.createSandbox(name: "p-bad")
        let result = try runner.run(["ports", "publish", "p-bad", "not-a-spec"])
        #expect(!result.succeeded)
        #expect(result.cleanStderr.contains("Invalid port spec")
                || result.cleanStderr.contains("HOST_PORT"))
    }

    @Test func publishNonexistentSandboxFails() throws {
        let runner = try CLIRunner()
        let result = try runner.run(["ports", "publish", "ghost-sb", "8080:3000"])
        #expect(!result.succeeded)
    }

    @Test func stopClearsPorts() throws {
        let runner = try CLIRunner()
        try runner.createSandbox(name: "p-stop")
        _ = try runner.run(["ports", "publish", "p-stop", "8080:3000"])

        _ = try runner.run(["stop", "p-stop"])
        // mock-sbx clears ports on stop; confirm listing is empty.
        let list = try runner.run(["ports", "ls", "p-stop", "--json"])
        let arr = try parseJSON(list.stdout.trimmingCharacters(in: .whitespacesAndNewlines)) as? [Any] ?? []
        #expect(arr.isEmpty)
    }
}
