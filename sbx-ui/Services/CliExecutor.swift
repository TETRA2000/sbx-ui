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

    public func exec(command: String, args: [String]) async throws -> CliResult {
        let resolvedCommand = resolveCommand(command)
        let cmdLine = "\(resolvedCommand) \(args.joined(separator: " "))"

        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()

            if resolvedCommand.hasPrefix("/") {
                process.executableURL = URL(fileURLWithPath: resolvedCommand)
                process.arguments = args
            } else {
                process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                process.arguments = [command] + args
            }

            // Ensure child processes can also find commands in common paths
            var env = ProcessInfo.processInfo.environment
            let currentPath = env["PATH"] ?? "/usr/bin:/bin"
            if !currentPath.contains("/opt/homebrew/bin") {
                env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:\(currentPath)"
            }
            process.environment = env

            // Ensure child process gets /dev/null as stdin — GUI apps have
            // no usable stdin, and leaving it inherited can cause bash scripts
            // to hang (e.g. mock-sbx interactive mode detection).
            process.standardInput = FileHandle.nullDevice

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            process.terminationHandler = { [cmdLine] process in
                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
                let stderr = String(data: stderrData, encoding: .utf8) ?? ""

                let result = CliResult(stdout: stdout, stderr: stderr, exitCode: process.terminationStatus)
                DispatchQueue.main.async {
                    if result.exitCode != 0 {
                        appLog(.error, "CLI", "$ \(cmdLine) → exit \(result.exitCode)",
                               detail: "stderr: \(stderr.trimmingCharacters(in: .whitespacesAndNewlines))\nstdout: \(stdout.prefix(500))")
                    } else {
                        appLog(.debug, "CLI", "$ \(cmdLine) → exit 0",
                               detail: stdout.count > 200 ? "\(stdout.prefix(200))..." : (stdout.isEmpty ? nil : stdout.trimmingCharacters(in: .whitespacesAndNewlines)))
                    }
                }
                continuation.resume(returning: result)
            }

            do {
                try process.run()
            } catch {
                DispatchQueue.main.async {
                    appLog(.error, "CLI", "Failed to launch: \(cmdLine)", detail: error.localizedDescription)
                }
                continuation.resume(throwing: SbxServiceError.cliError("Failed to launch process: \(error.localizedDescription)"))
            }
        }
    }

    public func execJson<T: Decodable & Sendable>(command: String, args: [String]) async throws -> T {
        let result = try await exec(command: command, args: args)
        guard result.exitCode == 0 else {
            throw SbxServiceError.cliError(result.stderr.isEmpty ? "Command failed with exit code \(result.exitCode)" : result.stderr)
        }
        guard let data = result.stdout.data(using: .utf8) else {
            throw SbxServiceError.cliError("Failed to decode output")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
