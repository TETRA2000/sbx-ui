import Foundation
import os

struct CliExecutor: CliExecutorProtocol, Sendable {
    private let logger = Logger(subsystem: "com.sbx-ui", category: "CliExecutor")

    nonisolated init() {}

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

    func exec(command: String, args: [String]) async throws -> CliResult {
        let resolvedCommand = resolveCommand(command)

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

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            process.terminationHandler = { process in
                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
                let stderr = String(data: stderrData, encoding: .utf8) ?? ""

                continuation.resume(returning: CliResult(
                    stdout: stdout,
                    stderr: stderr,
                    exitCode: process.terminationStatus
                ))
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: SbxServiceError.cliError("Failed to launch process: \(error.localizedDescription)"))
            }
        }
    }

    func execJson<T: Decodable & Sendable>(command: String, args: [String]) async throws -> T {
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
