import Testing
import Foundation
@testable import SBXCore

@Suite struct CliExecutorTests {

    @Test(.timeLimit(.minutes(1)))
    func largeStdoutDoesNotDeadlock() async throws {
        let executor = CliExecutor()
        // /bin/sh is an absolute path, so resolveCommand returns it unchanged.
        let result = try await executor.exec(
            command: "/bin/sh",
            args: ["-c", "head -c 300000 /dev/zero | tr '\\0' 'a'"]
        )
        #expect(result.exitCode == 0)
        #expect(result.stdout.count == 300_000)
    }

    @Test func exitCodeAndStderrPropagate() async throws {
        let executor = CliExecutor()
        let result = try await executor.exec(
            command: "/bin/sh",
            args: ["-c", "printf oops >&2; exit 3"]
        )
        #expect(result.exitCode == 3)
        #expect(result.stderr == "oops")
    }

    @Test(.timeLimit(.minutes(1)))
    func timeoutSurfacesAsCliError() async throws {
        let executor = CliExecutor()
        do {
            _ = try await executor.exec(
                command: "/bin/sh",
                args: ["-c", "sleep 30"],
                timeout: .seconds(1)
            )
            #expect(Bool(false), "Should have thrown")
        } catch let error as SbxServiceError {
            guard case .cliError(let message) = error else {
                #expect(Bool(false), "Wrong error: \(error)")
                return
            }
            #expect(message.contains("timed out"))
        }
    }
}
