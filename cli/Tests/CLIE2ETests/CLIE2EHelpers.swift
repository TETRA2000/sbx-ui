// CLIE2EHelpers.swift — Utilities for end-to-end testing of the Linux
// `sbx-ui-cli` binary. Tests spawn the compiled CLI as a subprocess with an
// isolated mock-sbx state directory and tools/ injected into PATH, then assert
// against captured stdout/stderr/exit code.

import Foundation
import Testing

// MARK: - Result

/// The result of invoking `sbx-ui-cli` as a subprocess.
struct CLIResult: Sendable {
    let stdout: String
    let stderr: String
    let exitCode: Int32

    var succeeded: Bool { exitCode == 0 }

    /// Strip noisy `[DEBUG] [CLI]` / `[ERROR] [CLI]` logging lines produced
    /// by `CliExecutor` in debug builds, so assertions can focus on the
    /// user-facing output.
    var cleanStderr: String {
        stderr.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { line in
                !(line.hasPrefix("[DEBUG] [CLI]")
                  || line.hasPrefix("[ERROR] [CLI]")
                  || line.hasPrefix("[INFO] [CLI]")
                  || line.hasPrefix("[WARN] [CLI]"))
            }
            .joined(separator: "\n")
    }
}

// MARK: - Runner

/// A runner for the `sbx-ui-cli` binary. Each runner owns an isolated
/// mock-sbx state directory that is cleaned up on deinit, so tests can run
/// in parallel without sharing sandbox/policy/port state.
final class CLIRunner: @unchecked Sendable {
    let binaryPath: String
    let toolsDir: String
    let stateDir: String

    init() throws {
        self.binaryPath = try Self.resolveBinary()
        self.toolsDir = Self.projectRoot + "/tools"
        self.stateDir = NSTemporaryDirectory() + "sbxui-e2e-\(UUID().uuidString)"
        try FileManager.default.createDirectory(
            atPath: self.stateDir,
            withIntermediateDirectories: true
        )
        // Sanity: the mock CLI must be executable.
        let sbxPath = toolsDir + "/sbx"
        guard FileManager.default.isExecutableFile(atPath: sbxPath) else {
            throw CLIRunnerError.mockMissing(sbxPath)
        }
    }

    deinit {
        try? FileManager.default.removeItem(atPath: stateDir)
    }

    // MARK: - Path resolution

    /// Project root, derived from this file's location.
    /// File is at `<root>/cli/Tests/CLIE2ETests/CLIE2EHelpers.swift`.
    static var projectRoot: String {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // CLIE2ETests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // cli
            .deletingLastPathComponent() // <root>
            .path
    }

    /// Locate the compiled `sbx-ui-cli`. Prefers the debug build (what
    /// `swift test` produces), falls back to release.
    static func resolveBinary() throws -> String {
        let root = projectRoot
        let candidates = [
            "\(root)/cli/.build/debug/sbx-ui-cli",
            "\(root)/cli/.build/release/sbx-ui-cli",
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        throw CLIRunnerError.binaryNotBuilt(candidates)
    }

    // MARK: - Running

    /// Invoke the CLI with the given argument list.
    /// - Parameters:
    ///   - args: Arguments after the executable name.
    ///   - stdin: Optional stdin text; if nil, stdin is /dev/null.
    ///   - extraEnv: Additional environment variables (override defaults).
    ///   - colorMode: `.none` passes NO_COLOR=1 (default for easy parsing);
    ///     `.forced` passes FORCE_COLOR=1; `.inherit` leaves both unset.
    @discardableResult
    func run(
        _ args: [String],
        stdin: String? = nil,
        extraEnv: [String: String] = [:],
        colorMode: ColorMode = .none
    ) throws -> CLIResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.arguments = args

        var env = ProcessInfo.processInfo.environment
        env["SBX_CLI_MOCK"] = "1"
        env["SBX_MOCK_STATE_DIR"] = stateDir
        let currentPath = env["PATH"] ?? "/usr/bin:/bin"
        env["PATH"] = "\(toolsDir):\(currentPath)"

        switch colorMode {
        case .none:
            env["NO_COLOR"] = "1"
            env.removeValue(forKey: "FORCE_COLOR")
        case .forced:
            env["FORCE_COLOR"] = "1"
            env.removeValue(forKey: "NO_COLOR")
        case .inherit:
            env.removeValue(forKey: "NO_COLOR")
            env.removeValue(forKey: "FORCE_COLOR")
        }
        for (k, v) in extraEnv { env[k] = v }
        process.environment = env

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        if let stdin = stdin {
            let inPipe = Pipe()
            process.standardInput = inPipe
            try process.run()
            inPipe.fileHandleForWriting.write(Data(stdin.utf8))
            try? inPipe.fileHandleForWriting.close()
        } else {
            process.standardInput = FileHandle(forReadingAtPath: "/dev/null")
            try process.run()
        }

        // Drain pipes concurrently with waitUntilExit to avoid deadlocks on
        // large outputs.
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return CLIResult(
            stdout: String(data: outData, encoding: .utf8) ?? "",
            stderr: String(data: errData, encoding: .utf8) ?? "",
            exitCode: process.terminationStatus
        )
    }

    // MARK: - High-level helpers

    /// Convenience: create a sandbox, fail the test on any CLI error.
    @discardableResult
    func createSandbox(
        name: String,
        workspace: String = "/tmp/e2e-workspace",
        agent: String = "claude",
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws -> CLIResult {
        let result = try run(["create", workspace, "--name", name, "--agent", agent])
        expectSuccess(result, "creating \(name)", sourceLocation: sourceLocation)
        return result
    }

    enum ColorMode {
        case none     // NO_COLOR=1
        case forced   // FORCE_COLOR=1
        case inherit  // neither set (TTY detection wins)
    }
}

// MARK: - Errors

enum CLIRunnerError: Error, CustomStringConvertible {
    case binaryNotBuilt([String])
    case mockMissing(String)

    var description: String {
        switch self {
        case .binaryNotBuilt(let paths):
            return "sbx-ui-cli binary not built. Run `swift build` first. Tried: \(paths)"
        case .mockMissing(let p):
            return "mock-sbx not executable at \(p). Ensure tools/sbx symlink and +x bits."
        }
    }
}

// MARK: - Test-scoped helpers

extension String {
    /// Lines with leading/trailing whitespace trimmed on each, skipping blanks.
    var nonBlankLines: [String] {
        self.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

/// Parse JSON output into an `Any` via JSONSerialization. Fails the test with
/// a helpful message if the output is not valid JSON.
func parseJSON(_ text: String, sourceLocation: SourceLocation = #_sourceLocation) throws -> Any {
    guard let data = text.data(using: .utf8) else {
        Issue.record("output not UTF-8", sourceLocation: sourceLocation)
        throw CLIRunnerError.mockMissing("<non-utf8>")
    }
    return try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
}

/// Record a failure if the result's exit code is non-zero, including stderr
/// in the message. Swift Testing's `#expect(_:_:)` comment parameter is a
/// `Comment?` that only accepts string literals, so runtime failure context
/// (like a subprocess's stderr) has to be recorded via `Issue.record`.
func expectSuccess(
    _ result: CLIResult,
    _ context: @autoclosure () -> String = "",
    sourceLocation: SourceLocation = #_sourceLocation
) {
    if !result.succeeded {
        let extra = context()
        let suffix = extra.isEmpty ? "" : " (\(extra))"
        Issue.record(
            "CLI exited \(result.exitCode)\(suffix) — stderr: \(result.cleanStderr)",
            sourceLocation: sourceLocation
        )
    }
}

/// Record a failure if the result's exit code is zero when we expect it to fail.
func expectFailure(
    _ result: CLIResult,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    if result.succeeded {
        Issue.record(
            "expected non-zero exit; got 0 with stdout: \(result.stdout)",
            sourceLocation: sourceLocation
        )
    }
}
