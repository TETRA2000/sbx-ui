// FormattingTests.swift — Verify ANSI color escape handling. The CLI honors
// NO_COLOR and FORCE_COLOR environment variables (see Formatting.swift);
// TTY detection is skipped in subprocess mode because stdout is a pipe.

import Foundation
import Testing

@Suite("CLI: formatting & color")
struct FormattingTests {
    /// ANSI CSI prefix — any coloring sequence starts with this.
    private let csi = "\u{001B}["

    @Test func noColorStripsAnsi() throws {
        let runner = try CLIRunner()
        try runner.createSandbox(name: "color-test")

        // Default runner already sets NO_COLOR=1 — confirm no escape codes.
        let result = try runner.run(["ls"], colorMode: .none)
        expectSuccess(result)
        #expect(!result.stdout.contains(csi), "NO_COLOR=1 must suppress ANSI codes")
    }

    @Test func forceColorEmitsAnsi() throws {
        let runner = try CLIRunner()
        try runner.createSandbox(name: "color-on")

        let result = try runner.run(["ls"], colorMode: .forced)
        expectSuccess(result)
        #expect(result.stdout.contains(csi), "FORCE_COLOR=1 must enable ANSI codes")
        // Status "running" is colored bright green (\u001B[92m) per Formatting.swift.
        #expect(result.stdout.contains("\u{001B}[92m"))
    }

    @Test func noColorWinsOverDefaultPipeTty() throws {
        // Explicitly pipe stdout (which subprocess always does) and ensure
        // that absent any env hint the CLI still produces parseable output.
        // Piped stdout means isatty(STDOUT_FILENO)=0, so colors should be off.
        let runner = try CLIRunner()
        try runner.createSandbox(name: "color-default")
        let result = try runner.run(["ls"], colorMode: .inherit)
        expectSuccess(result)
        #expect(!result.stdout.contains(csi), "piped stdout without FORCE_COLOR must be plain")
    }

    @Test func jsonOutputIsAlwaysPlain() throws {
        // JSON output never includes ANSI codes regardless of color mode.
        let runner = try CLIRunner()
        try runner.createSandbox(name: "color-json")

        let result = try runner.run(["ls", "--json"], colorMode: .forced)
        expectSuccess(result)
        #expect(!result.stdout.contains(csi), "JSON output must be ANSI-free")
    }
}
