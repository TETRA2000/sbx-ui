import Testing
import Foundation
@testable import SBXCore

// Each deadlock repro carries an explicit time limit: against the pre-fix
// code these tests HANG rather than fail, and an unbounded hang wedges CI
// until the outer job timeout.
@Suite struct ProcessRunnerTests {

    /// Writes `byteCount` bytes of 'a' to a temp file and returns its path.
    /// Caller is responsible for cleanup.
    private func makeLargeFile(byteCount: Int) throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("processrunner-\(UUID().uuidString).txt")
        let data = Data(repeating: UInt8(ascii: "a"), count: byteCount)
        try data.write(to: url)
        return url
    }

    @Test(.timeLimit(.minutes(1)))
    func largeStdoutDoesNotDeadlock() async throws {
        let file = try makeLargeFile(byteCount: 1_000_000)
        defer { try? FileManager.default.removeItem(at: file) }

        let out = try await ProcessRunner.run(
            executable: URL(fileURLWithPath: "/bin/cat"),
            arguments: [file.path]
        )

        #expect(out.exitCode == 0)
        #expect(out.stdout.count == 1_000_000)
        #expect(out.outputTruncated == false)
    }

    @Test(.timeLimit(.minutes(1)))
    func largeStderrDoesNotDeadlock() async throws {
        let file = try makeLargeFile(byteCount: 1_000_000)
        defer { try? FileManager.default.removeItem(at: file) }

        let out = try await ProcessRunner.run(
            executable: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "cat \"$1\" >&2", "sh", file.path]
        )

        #expect(out.exitCode == 0)
        #expect(out.stderr.count == 1_000_000)
    }

    @Test(.timeLimit(.minutes(1)))
    func largeStdoutAndStderrSimultaneously() async throws {
        let file = try makeLargeFile(byteCount: 1_000_000)
        defer { try? FileManager.default.removeItem(at: file) }

        let out = try await ProcessRunner.run(
            executable: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "cat \"$1\" >&2 & cat \"$1\"; wait", "sh", file.path]
        )

        #expect(out.exitCode == 0)
        #expect(out.stdout.count == 1_000_000)
        #expect(out.stderr.count == 1_000_000)
    }

    @Test func capturesSmallStdout() async throws {
        let out = try await ProcessRunner.run(
            executable: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "printf hello"]
        )
        #expect(String(data: out.stdout, encoding: .utf8) == "hello")
        #expect(out.exitCode == 0)
    }

    @Test func nonZeroExitCodePropagates() async throws {
        let out = try await ProcessRunner.run(
            executable: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "exit 42"]
        )
        #expect(out.exitCode == 42)
    }

    @Test func launchFailureThrows() async throws {
        do {
            _ = try await ProcessRunner.run(
                executable: URL(fileURLWithPath: "/nonexistent/binary-xyz"),
                arguments: []
            )
            #expect(Bool(false), "Should have thrown")
        } catch let error as ProcessRunnerError {
            guard case .launchFailed = error else {
                #expect(Bool(false), "Wrong error: \(error)")
                return
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func timeoutTerminatesChildAndThrows() async throws {
        let start = Date()
        do {
            _ = try await ProcessRunner.run(
                executable: URL(fileURLWithPath: "/bin/sh"),
                arguments: ["-c", "sleep 30"],
                timeout: .seconds(1)
            )
            #expect(Bool(false), "Should have thrown")
        } catch let error as ProcessRunnerError {
            guard case .timedOut = error else {
                #expect(Bool(false), "Wrong error: \(error)")
                return
            }
        }
        // Must return promptly, not after the child's full 30s sleep.
        #expect(Date().timeIntervalSince(start) < 15)
    }

    @Test(.timeLimit(.minutes(1)))
    func nilTimeoutDoesNotTerminate() async throws {
        let out = try await ProcessRunner.run(
            executable: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "sleep 1; printf done"],
            timeout: nil
        )
        #expect(String(data: out.stdout, encoding: .utf8) == "done")
    }

    @Test(.timeLimit(.minutes(1)))
    func cancellationTerminatesChild() async throws {
        let task = Task {
            try await ProcessRunner.run(
                executable: URL(fileURLWithPath: "/bin/sh"),
                arguments: ["-c", "sleep 30"],
                timeout: nil
            )
        }
        try await Task.sleep(for: .milliseconds(300))
        task.cancel()

        let start = Date()
        do {
            _ = try await task.value
            #expect(Bool(false), "Should have thrown")
        } catch {
            #expect(error is CancellationError)
        }
        #expect(Date().timeIntervalSince(start) < 15)
    }

    @Test(.timeLimit(.minutes(1)))
    func outputCapKeepsTailAndFlagsTruncation() async throws {
        let out = try await ProcessRunner.run(
            executable: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "head -c 4096 /dev/zero | tr '\\0' 'a'; printf END"],
            maxOutputBytes: 1024
        )
        #expect(out.outputTruncated == true)
        #expect(out.stdout.count == 1024)
        let tail = String(data: out.stdout.suffix(3), encoding: .utf8)
        #expect(tail == "END")
    }

    /// True if a process whose command line contains `marker` is currently
    /// running. `ps`'s view of a process's argv is populated at `exec()`
    /// time, before the shell interpreter runs a single statement of the
    /// script — unlike a marker *file* the child would have to write itself,
    /// checking `ps` doesn't race the child's own startup against a kill
    /// signal that (once the fix is in place) can arrive within microseconds
    /// of the process being spawned.
    private func processMatching(_ marker: String) async throws -> Bool {
        let out = try await ProcessRunner.run(
            executable: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "ps ax | grep -F '\(marker)' | grep -v grep"]
        )
        return out.exitCode == 0
    }

    /// Regression test for a leak: cancellation that lands before
    /// `ProcessRunner.run`'s body executes at all (`withTaskCancellationHandler`
    /// invokes `onCancel` immediately for an already-cancelled task) used to be
    /// silently swallowed — the process had not been attached to the session
    /// yet, so there was nothing to `terminate()`, and the later
    /// `Task.isCancelled` recheck (after `process.run()`) was a no-op because
    /// a failure was already recorded. The child ran to completion, orphaned.
    /// `task.cancel()` is called synchronously right after creating `task`,
    /// before it has had a chance to start running, so `Task.isCancelled` is
    /// already `true` when `ProcessRunner.run`'s body begins.
    @Test(.timeLimit(.minutes(1)))
    func cancelBeforeLaunchStillKillsChild() async throws {
        let marker = "processrunner-marker-\(UUID().uuidString)"

        // Two statements (not a single simple command) so `sh` can't
        // tail-call `exec()` straight into `sleep`, which would replace the
        // process's argv — and the marker along with it — before `ps` ever
        // gets to see it.
        let task = Task {
            try await ProcessRunner.run(
                executable: URL(fileURLWithPath: "/bin/sh"),
                arguments: ["-c", ": '\(marker)'; sleep 30"],
                timeout: nil
            )
        }
        task.cancel()

        do {
            _ = try await task.value
            #expect(Bool(false), "Should have thrown")
        } catch {
            #expect(error is CancellationError)
        }

        // Poll for the marked child to disappear rather than sleeping a
        // fixed amount.
        var stillAlive = true
        for _ in 0..<40 {
            stillAlive = try await processMatching(marker)
            if !stillAlive { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(stillAlive == false, "a process matching '\(marker)' is still running")
    }

    /// Exercises the `drainDeadlinePassed` completion path: the direct child
    /// exits almost immediately, but a backgrounded grandchild inherits the
    /// stdout pipe's write end and keeps it open for far longer. Without the
    /// drain deadline, `run` would hang until the grandchild itself exits.
    @Test(.timeLimit(.minutes(1)))
    func grandchildHoldingPipeDoesNotHang() async throws {
        let start = Date()
        let out = try await ProcessRunner.run(
            executable: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "sleep 5 & printf hi"]
        )
        let elapsed = Date().timeIntervalSince(start)

        #expect(out.exitCode == 0)
        #expect(String(data: out.stdout, encoding: .utf8) == "hi")
        #expect(out.outputTruncated == false)
        // Must wait roughly drainGrace (2s) for the backgrounded grandchild's
        // inherited pipe fd, but must return well before its 5s sleep ends.
        #expect(elapsed >= 1.5)
        #expect(elapsed < 4.5)
    }
}
