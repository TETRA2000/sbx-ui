// HelpAndVersionTests.swift — Verify the CLI's top-level and subcommand
// help screens and --version output. These exercises do not touch mock-sbx
// state; they confirm ArgumentParser wiring stays intact.

import Foundation
import Testing

@Suite("CLI: help & version")
struct HelpAndVersionTests {
    @Test func versionFlag() throws {
        let runner = try CLIRunner()
        let result = try runner.run(["--version"])
        #expect(result.succeeded)
        #expect(result.stdout.contains("0.1.0"))
    }

    @Test func topLevelHelp() throws {
        let runner = try CLIRunner()
        let result = try runner.run(["--help"])
        #expect(result.succeeded)
        #expect(result.stdout.contains("sbx-ui"))
        #expect(result.stdout.contains("CLI for Docker Sandbox management"))

        // All subcommands should be listed on the help screen.
        let subcommands = [
            "ls", "create", "stop", "rm", "run", "exec",
            "policy", "ports", "env", "status",
        ]
        for sub in subcommands {
            #expect(result.stdout.contains(sub), "help should list '\(sub)'")
        }
    }

    @Test func noArgumentsShowsLsByDefault() throws {
        let runner = try CLIRunner()
        // `ls` is the default subcommand; with an empty mock state dir it
        // prints an informative "no sandboxes" message.
        let result = try runner.run([])
        #expect(result.succeeded)
        #expect(result.stdout.contains("No sandboxes found"))
    }

    @Test(arguments: [
        "ls", "create", "stop", "rm", "run", "exec", "status",
    ])
    func subcommandHelp(sub: String) throws {
        let runner = try CLIRunner()
        let result = try runner.run([sub, "--help"])
        #expect(result.succeeded, "\(sub) --help failed: \(result.stderr)")
        #expect(result.stdout.contains("USAGE:"))
    }

    @Test(arguments: [
        ["policy", "--help"],
        ["policy", "ls", "--help"],
        ["policy", "allow", "--help"],
        ["policy", "deny", "--help"],
        ["policy", "rm", "--help"],
        ["policy", "log", "--help"],
        ["ports", "--help"],
        ["ports", "ls", "--help"],
        ["ports", "publish", "--help"],
        ["ports", "unpublish", "--help"],
        ["env", "--help"],
        ["env", "ls", "--help"],
        ["env", "set", "--help"],
        ["env", "rm", "--help"],
    ])
    func nestedSubcommandHelp(args: [String]) throws {
        let runner = try CLIRunner()
        let result = try runner.run(args)
        #expect(result.succeeded, "\(args.joined(separator: " ")) --help failed")
        #expect(result.stdout.contains("USAGE:"))
    }

    @Test func unknownCommandFails() throws {
        let runner = try CLIRunner()
        let result = try runner.run(["this-is-not-a-subcommand"])
        #expect(!result.succeeded)
        // ArgumentParser emits "Error:" on usage errors.
        #expect(result.stderr.contains("Error") || result.stderr.contains("Usage"))
    }
}
