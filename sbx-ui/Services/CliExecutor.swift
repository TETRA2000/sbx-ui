import Foundation
import os

struct CliExecutor: CliExecutorProtocol, Sendable {
    private let logger = Logger(subsystem: "com.sbx-ui", category: "CliExecutor")

    nonisolated init() {}

    func exec(command: String, args: [String]) async throws -> CliResult {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [command] + args

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
