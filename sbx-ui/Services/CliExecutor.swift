import Foundation
#if canImport(os)
import os
#endif

public struct CliExecutor: CliExecutorProtocol, Sendable {
    #if canImport(os)
    private let logger = Logger(subsystem: "com.sbx-ui", category: "CliExecutor")
    #endif

    nonisolated public init() {}

    /// Resolves the full path of a command by searching PATH and common install locations.
    /// macOS GUI apps don't inherit the shell's PATH, so /opt/homebrew/bin etc. are missing.
    private nonisolated func resolveCommand(_ command: String) -> String {
        // Check if already a full path
        if command.hasPrefix("/") { return command }

        // Build search paths: process PATH + common install locations
        let processPath = ProcessInfo.processInfo.environment["PATH"] ?? ""
        let extraPaths = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
        ]
        let allPaths = processPath.split(separator: ":").map(String.init) + extraPaths

        for dir in allPaths {
            let fullPath = "\(dir)/\(command)"
            if FileManager.default.isExecutableFile(atPath: fullPath) {
                return fullPath
            }
        }

        // Fallback: let /usr/bin/env try to find it (will fail with clear error)
        return command
    }

    public func exec(command: String, args: [String], timeout: Duration?) async throws -> CliResult {
        let resolvedCommand = resolveCommand(command)
        let cmdLine = "\(resolvedCommand) \(args.joined(separator: " "))"

        let executable: URL
        let finalArgs: [String]
        if resolvedCommand.hasPrefix("/") {
            executable = URL(fileURLWithPath: resolvedCommand)
            finalArgs = args
        } else {
            // Fall back to env, which will fail with a clear error.
            executable = URL(fileURLWithPath: "/usr/bin/env")
            finalArgs = [command] + args
        }

        // Ensure child processes can also find commands in common paths.
        var env = ProcessInfo.processInfo.environment
        let currentPath = env["PATH"] ?? "/usr/bin:/bin"
        if !currentPath.contains("/opt/homebrew/bin") {
            env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:\(currentPath)"
        }

        let output: ProcessOutput
        do {
            output = try await ProcessRunner.run(
                executable: executable,
                arguments: finalArgs,
                environment: env,
                // GUI apps have no usable stdin; leaving it inherited can hang
                // bash scripts (e.g. mock-sbx interactive mode detection).
                standardInput: FileHandle.nullDevice,
                timeout: timeout
            )
        } catch let error as ProcessRunnerError {
            switch error {
            case .launchFailed(let message):
                DispatchQueue.main.async {
                    appLog(.error, "CLI", "Failed to launch: \(cmdLine)", detail: message)
                }
                throw SbxServiceError.cliError("Failed to launch process: \(message)")
            case .timedOut(let duration):
                DispatchQueue.main.async {
                    appLog(.error, "CLI", "$ \(cmdLine) → timed out", detail: "after \(duration)")
                }
                throw SbxServiceError.cliError("Command timed out after \(duration): \(cmdLine)")
            }
        }

        let stdout = String(data: output.stdout, encoding: .utf8) ?? ""
        let stderr = String(data: output.stderr, encoding: .utf8) ?? ""
        let result = CliResult(stdout: stdout, stderr: stderr, exitCode: output.exitCode)

        DispatchQueue.main.async {
            if result.exitCode != 0 {
                appLog(.error, "CLI", "$ \(cmdLine) → exit \(result.exitCode)",
                       detail: "stderr: \(stderr.trimmingCharacters(in: .whitespacesAndNewlines))\nstdout: \(stdout.prefix(500))")
            } else {
                appLog(.debug, "CLI", "$ \(cmdLine) → exit 0",
                       detail: stdout.count > 200 ? "\(stdout.prefix(200))..." : (stdout.isEmpty ? nil : stdout.trimmingCharacters(in: .whitespacesAndNewlines)))
            }
        }
        return result
    }

    public func execJson<T: Decodable & Sendable>(command: String, args: [String], timeout: Duration?) async throws -> T {
        let result = try await exec(command: command, args: args, timeout: timeout)
        guard result.exitCode == 0 else {
            throw SbxServiceError.cliError(result.stderr.isEmpty ? "Command failed with exit code \(result.exitCode)" : result.stderr)
        }
        guard let data = result.stdout.data(using: .utf8) else {
            throw SbxServiceError.cliError("Failed to decode output")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
