# Process Execution Deadlock Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate the subprocess pipe deadlock that hangs every `sbx` CLI call and every `git status` call once output exceeds the ~64KB pipe buffer.

**Architecture:** Extract one `ProcessRunner` component that drains stdout and stderr concurrently via `readabilityHandler` while the child runs, then route both existing deadlock sites (`CliExecutor.exec`, `DefaultEditorDocumentProvider.listChangedFiles`) through it. Timeout and cancellation are enforced by terminating the child, which closes the pipes and completes the call through the same path as a normal exit.

**Tech Stack:** Swift 6, Foundation `Process`/`Pipe`/`FileHandle`, Swift Testing (`@Test`/`#expect`), SwiftPM (`cli/Package.swift`) for the Linux CI target, Xcode for the macOS target.

**Spec:** `docs/superpowers/specs/2026-08-09-process-exec-deadlock-design.md`

## Global Constraints

- The Xcode project sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`. Every explicit `init` and `static` member on a `Sendable` type MUST be marked `nonisolated`, or the macOS build breaks while the SPM build still passes.
- Code under `sbx-ui/Models/` and `sbx-ui/Services/` compiles for BOTH macOS and Linux. Platform-specific API needs `#if canImport(...)` guards.
- `cli/Package.swift` lists SBXCore sources **explicitly**. A new file under `sbx-ui/Services/` is invisible to the Linux build until added to that `sources:` array.
- The Xcode project uses `PBXFileSystemSynchronizedRootGroup` (objectVersion 77). New `.swift` files under `sbx-ui/` and `sbx-uiTests/` are picked up automatically — do NOT hand-edit `project.pbxproj`.
- `DefaultEditorDocumentProvider.swift` is NOT in `Package.swift`'s `sources:` list. It is macOS-only; its tests belong in `sbx-uiTests/`, not `cli/Tests/`.
- Default CLI timeout is `.seconds(30)`. The ONLY `nil`-timeout call path is `sbx run --name <name>` in `RealSbxService.run()`.
- Every deadlock-repro test MUST carry `.timeLimit(.minutes(1))`. Without it, a failing run hangs instead of failing.
- Do not push. Work stays on branch `fix/process-exec-deadlock`.

---

### Task 1: ProcessRunner

**Files:**
- Create: `sbx-ui/Services/ProcessRunner.swift`
- Modify: `cli/Package.swift:18-30` (add source to the `sources:` array)
- Test: `cli/Tests/SBXCoreTests/ProcessRunnerTests.swift`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces:
  - `public struct ProcessOutput: Sendable` with `stdout: Data`, `stderr: Data`, `exitCode: Int32`, `outputTruncated: Bool`
  - `public enum ProcessRunnerError: Error, Sendable, Equatable` with cases `launchFailed(String)`, `timedOut(Duration)`
  - `nonisolated public static func ProcessRunner.run(executable: URL, arguments: [String], currentDirectory: URL? = nil, environment: [String: String]? = nil, standardInput: FileHandle? = FileHandle.nullDevice, timeout: Duration? = .seconds(30), maxOutputBytes: Int = ProcessRunner.defaultMaxOutputBytes) async throws -> ProcessOutput`
  - `nonisolated public static var ProcessRunner.defaultMaxOutputBytes: Int` (4 MiB)

- [ ] **Step 1: Write the failing tests**

Create `cli/Tests/SBXCoreTests/ProcessRunnerTests.swift`:

```swift
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
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --package-path cli --filter ProcessRunnerTests`

Expected: FAIL to compile — `cannot find 'ProcessRunner' in scope`. This is the correct red state for a component that does not exist yet.

- [ ] **Step 3: Create the ProcessRunner implementation**

Create `sbx-ui/Services/ProcessRunner.swift`:

```swift
import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// Result of a completed subprocess run.
public struct ProcessOutput: Sendable {
    public let stdout: Data
    public let stderr: Data
    public let exitCode: Int32
    /// True when output exceeded `maxOutputBytes` and the head was dropped.
    public let outputTruncated: Bool

    nonisolated public init(stdout: Data, stderr: Data, exitCode: Int32, outputTruncated: Bool) {
        self.stdout = stdout
        self.stderr = stderr
        self.exitCode = exitCode
        self.outputTruncated = outputTruncated
    }
}

public enum ProcessRunnerError: Error, Sendable, Equatable {
    case launchFailed(String)
    case timedOut(Duration)
}

/// Spawns a subprocess and drains stdout/stderr *concurrently with execution*.
///
/// Reading the pipes only after the process exits deadlocks: a pipe holds
/// roughly 64KB, so a child writing more than that blocks in `write(2)`,
/// never exits, and the reader never runs. This drains via
/// `readabilityHandler` while the child is still alive — the same pattern
/// `PluginHost.startReadLoop` uses.
public enum ProcessRunner {
    /// Retained output cap. Beyond this the head is dropped and the tail kept,
    /// so an unbounded (`timeout: nil`) run cannot grow without limit.
    nonisolated public static let defaultMaxOutputBytes: Int = 4 * 1024 * 1024

    /// How long to keep draining after the child exits before giving up on EOF.
    /// A grandchild that inherited the pipe write end can keep it open after
    /// the direct child dies; without this bound that would hang forever.
    nonisolated public static let drainGrace: Duration = .seconds(2)

    /// How long to wait after SIGTERM before escalating to SIGKILL.
    nonisolated public static let terminateGrace: Duration = .seconds(2)

    nonisolated public static func run(
        executable: URL,
        arguments: [String],
        currentDirectory: URL? = nil,
        environment: [String: String]? = nil,
        standardInput: FileHandle? = FileHandle.nullDevice,
        timeout: Duration? = .seconds(30),
        maxOutputBytes: Int = ProcessRunner.defaultMaxOutputBytes
    ) async throws -> ProcessOutput {
        let session = RunSession(maxBytes: maxOutputBytes)

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                session.attach(continuation: continuation)

                let process = Process()
                process.executableURL = executable
                process.arguments = arguments
                if let currentDirectory { process.currentDirectoryURL = currentDirectory }
                if let environment { process.environment = environment }
                if let standardInput { process.standardInput = standardInput }

                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe

                session.attach(
                    process: process,
                    stdout: stdoutPipe.fileHandleForReading,
                    stderr: stderrPipe.fileHandleForReading
                )

                stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    if data.isEmpty {
                        handle.readabilityHandler = nil
                        session.markEOF(isStdout: true)
                    } else {
                        session.append(data, isStdout: true)
                    }
                }
                stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    if data.isEmpty {
                        handle.readabilityHandler = nil
                        session.markEOF(isStdout: false)
                    } else {
                        session.append(data, isStdout: false)
                    }
                }

                process.terminationHandler = { proc in
                    session.markExited(code: proc.terminationStatus)
                }

                do {
                    try process.run()
                } catch {
                    session.failImmediately(.launchFailed(error.localizedDescription))
                    return
                }

                // A cancel that landed before `run()` still has to kill the child.
                if Task.isCancelled {
                    session.beginFailure(CancellationError())
                }

                if let timeout {
                    DispatchQueue.global().asyncAfter(deadline: .now() + Self.asSeconds(timeout)) {
                        session.beginFailure(ProcessRunnerError.timedOut(timeout))
                    }
                }
            }
        } onCancel: {
            session.beginFailure(CancellationError())
        }
    }

    nonisolated static func asSeconds(_ duration: Duration) -> Double {
        let c = duration.components
        return Double(c.seconds) + Double(c.attoseconds) / 1e18
    }
}

/// Mutable state shared between the readability handlers, the termination
/// handler, the timeout timer and the cancellation handler — each of which
/// runs on a different queue. All access is guarded by one lock, and the
/// continuation is resumed exactly once.
private final class RunSession: @unchecked Sendable {
    private let lock = NSLock()
    private let maxBytes: Int

    private var continuation: CheckedContinuation<ProcessOutput, Error>?
    private var process: Process?
    private var stdoutHandle: FileHandle?
    private var stderrHandle: FileHandle?

    private var stdoutData = Data()
    private var stderrData = Data()
    private var truncated = false

    private var stdoutAtEOF = false
    private var stderrAtEOF = false
    private var exited = false
    private var exitCode: Int32 = 0
    private var drainDeadlinePassed = false

    private var pendingFailure: Error?
    private var forced = false
    private var finished = false

    init(maxBytes: Int) {
        self.maxBytes = maxBytes
    }

    func attach(continuation: CheckedContinuation<ProcessOutput, Error>) {
        lock.lock()
        self.continuation = continuation
        lock.unlock()
        tryFinish()
    }

    func attach(process: Process, stdout: FileHandle, stderr: FileHandle) {
        lock.lock()
        self.process = process
        self.stdoutHandle = stdout
        self.stderrHandle = stderr
        lock.unlock()
    }

    func append(_ data: Data, isStdout: Bool) {
        lock.lock()
        if isStdout {
            Self.appendCapped(&stdoutData, data, maxBytes: maxBytes, truncated: &truncated)
        } else {
            Self.appendCapped(&stderrData, data, maxBytes: maxBytes, truncated: &truncated)
        }
        lock.unlock()
    }

    private static func appendCapped(_ buffer: inout Data, _ data: Data, maxBytes: Int, truncated: inout Bool) {
        buffer.append(data)
        if buffer.count > maxBytes {
            buffer.removeFirst(buffer.count - maxBytes)
            truncated = true
        }
    }

    func markEOF(isStdout: Bool) {
        lock.lock()
        if isStdout { stdoutAtEOF = true } else { stderrAtEOF = true }
        lock.unlock()
        tryFinish()
    }

    func markExited(code: Int32) {
        lock.lock()
        exited = true
        exitCode = code
        lock.unlock()

        // Bound the post-exit wait for EOF (grandchild may hold the write end).
        DispatchQueue.global().asyncAfter(deadline: .now() + ProcessRunner.asSeconds(ProcessRunner.drainGrace)) { [weak self] in
            guard let self else { return }
            self.lock.lock()
            self.drainDeadlinePassed = true
            self.lock.unlock()
            self.tryFinish()
        }

        tryFinish()
    }

    /// Launch failed — there is no process to reap, so resume right away.
    func failImmediately(_ error: Error) {
        lock.lock()
        if pendingFailure == nil { pendingFailure = error }
        forced = true
        lock.unlock()
        tryFinish()
    }

    /// Timeout or cancellation: kill the child, then resume with `error` once
    /// it has been reaped (or once the hard backstop fires).
    func beginFailure(_ error: Error) {
        lock.lock()
        let alreadyFailing = pendingFailure != nil || finished
        if pendingFailure == nil { pendingFailure = error }
        let proc = process
        lock.unlock()

        guard !alreadyFailing else { return }

        if let proc, proc.isRunning {
            proc.terminate()
            let pid = proc.processIdentifier
            DispatchQueue.global().asyncAfter(deadline: .now() + ProcessRunner.asSeconds(ProcessRunner.terminateGrace)) {
                if proc.isRunning { kill(pid, SIGKILL) }
            }
        }

        // Hard backstop: resume even if the child never reports exit.
        let backstop = ProcessRunner.asSeconds(ProcessRunner.terminateGrace)
            + ProcessRunner.asSeconds(ProcessRunner.drainGrace)
        DispatchQueue.global().asyncAfter(deadline: .now() + backstop) { [weak self] in
            guard let self else { return }
            self.lock.lock()
            self.forced = true
            self.lock.unlock()
            self.tryFinish()
        }

        tryFinish()
    }

    private func tryFinish() {
        var resumption: (CheckedContinuation<ProcessOutput, Error>, Result<ProcessOutput, Error>)?

        lock.lock()
        if !finished, let cont = continuation {
            if let failure = pendingFailure, exited || forced {
                finished = true
                resumption = (cont, .failure(failure))
            } else if exited && ((stdoutAtEOF && stderrAtEOF) || drainDeadlinePassed) {
                finished = true
                let output = ProcessOutput(
                    stdout: stdoutData,
                    stderr: stderrData,
                    exitCode: exitCode,
                    outputTruncated: truncated
                )
                resumption = (cont, .success(output))
            }
            if resumption != nil { continuation = nil }
        }
        lock.unlock()

        guard let (cont, result) = resumption else { return }
        releaseHandles()
        cont.resume(with: result)
    }

    /// Clear the readability handlers BEFORE closing the descriptors — closing
    /// a handle that still has a live dispatch source raises a bad-fd error.
    private func releaseHandles() {
        lock.lock()
        let out = stdoutHandle
        let err = stderrHandle
        stdoutHandle = nil
        stderrHandle = nil
        process?.terminationHandler = nil
        lock.unlock()

        out?.readabilityHandler = nil
        err?.readabilityHandler = nil
        try? out?.close()
        try? err?.close()
    }
}
```

- [ ] **Step 4: Register the new file with the Linux build**

In `cli/Package.swift`, add one line to the `SBXCore` target's `sources:` array, immediately after `"Services/CliExecutor.swift",`:

```swift
                "Services/ProcessRunner.swift",
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --package-path cli --filter ProcessRunnerTests`

Expected: PASS, 10 tests. If `largeStdoutDoesNotDeadlock` times out at 1 minute, the draining is wrong — do not proceed.

- [ ] **Step 6: Commit**

```bash
git add sbx-ui/Services/ProcessRunner.swift cli/Package.swift cli/Tests/SBXCoreTests/ProcessRunnerTests.swift
git commit -m "Add ProcessRunner with concurrent pipe draining

Drains stdout and stderr via readabilityHandler while the child runs,
so output past the ~64KB pipe buffer can no longer block the child in
write(2). Bounds the post-exit wait for EOF so a grandchild holding the
write end cannot hang the call, and caps retained output so an
unbounded run cannot grow without limit.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Route CliExecutor through ProcessRunner

**Files:**
- Modify: `sbx-ui/Services/SbxServiceProtocol.swift:36-39` (protocol + new extension)
- Modify: `sbx-ui/Services/CliExecutor.swift:39-118` (replace `exec` and `execJson`)
- Modify: `cli/Tests/SBXCoreTests/SBXCoreTests.swift:406-424` (`SpyCliExecutor` conformance)
- Test: `cli/Tests/SBXCoreTests/CliExecutorTests.swift` (create)

**Interfaces:**
- Consumes: `ProcessRunner.run(executable:arguments:currentDirectory:environment:standardInput:timeout:maxOutputBytes:)`, `ProcessOutput`, `ProcessRunnerError` from Task 1.
- Produces:
  - `CliExecutorProtocol.exec(command: String, args: [String], timeout: Duration?) async throws -> CliResult`
  - `CliExecutorProtocol.execJson<T>(command: String, args: [String], timeout: Duration?) async throws -> T`
  - Defaulted 2-argument convenience forms in a protocol extension, so all 18 existing call sites compile unchanged.
  - `SpyCliExecutor.calls` becomes `[(command: String, args: [String], timeout: Duration?)]` — the `.args` and `.command` labels are unchanged, so existing assertions keep working.

- [ ] **Step 1: Write the failing test**

Create `cli/Tests/SBXCoreTests/CliExecutorTests.swift`:

```swift
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
}
```

These two tests use only the existing 2-argument `exec`, so the target still
compiles and the deadlock is genuinely demonstrated against current code. The
timeout test is added in Step 5, after the parameter exists — putting it here
would break compilation and prevent the deadlock test from ever running.

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path cli --filter CliExecutorTests`

Expected: `largeStdoutDoesNotDeadlock` FAILS by hitting its 1-minute time limit — the pre-fix `CliExecutor` drains its pipes only in `terminationHandler`, so 300KB of output blocks the child forever. `exitCodeAndStderrPropagate` passes (its output is tiny). This is the fail-first demonstration for this task; do not proceed until you have seen it.

- [ ] **Step 3: Update the protocol**

In `sbx-ui/Services/SbxServiceProtocol.swift`, replace lines 36-39:

```swift
public protocol CliExecutorProtocol: Sendable {
    func exec(command: String, args: [String], timeout: Duration?) async throws -> CliResult
    func execJson<T: Decodable & Sendable>(command: String, args: [String], timeout: Duration?) async throws -> T
}

extension CliExecutorProtocol {
    /// Default timeout for every CLI call. The sole exception is the
    /// `sbx run --name` interactive attach, which passes `nil` explicitly.
    nonisolated public func exec(command: String, args: [String]) async throws -> CliResult {
        try await exec(command: command, args: args, timeout: .seconds(30))
    }

    nonisolated public func execJson<T: Decodable & Sendable>(command: String, args: [String]) async throws -> T {
        try await execJson(command: command, args: args, timeout: .seconds(30))
    }
}
```

- [ ] **Step 4: Rewrite CliExecutor.exec and execJson**

In `sbx-ui/Services/CliExecutor.swift`, replace everything from `public func exec(command:` (line 39) through the end of `execJson` with:

```swift
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
```

- [ ] **Step 5: Add the timeout test**

Now that `exec` accepts `timeout:`, add this test to the `CliExecutorTests` suite in `cli/Tests/SBXCoreTests/CliExecutorTests.swift`:

```swift
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
```

- [ ] **Step 6: Update SpyCliExecutor**

In `cli/Tests/SBXCoreTests/SBXCoreTests.swift`, replace the `SpyCliExecutor` body (lines 406-424) with:

```swift
actor SpyCliExecutor: CliExecutorProtocol {
    private(set) var calls: [(command: String, args: [String], timeout: Duration?)] = []
    private var stubbedResults: [String: CliResult] = [:]
    private let defaultResult = CliResult(stdout: "", stderr: "", exitCode: 0)

    func stub(argsKey: String, result: CliResult) {
        stubbedResults[argsKey] = result
    }

    func exec(command: String, args: [String], timeout: Duration?) async throws -> CliResult {
        calls.append((command, args, timeout))
        return stubbedResults[args.joined(separator: " ")] ?? defaultResult
    }

    func execJson<T: Decodable & Sendable>(command: String, args: [String], timeout: Duration?) async throws -> T {
        fatalError("unused by RealSbxService")
    }
}
```

- [ ] **Step 7: Run the full SPM suite to verify it passes**

Run: `swift test --package-path cli`

Expected: PASS. `CliExecutorTests` (3 tests) and `ProcessRunnerTests` (10 tests) pass, and the pre-existing `ServiceArgumentTests` still pass unchanged — they read `.args` and `.command`, whose labels did not move.

- [ ] **Step 8: Commit**

```bash
git add sbx-ui/Services/SbxServiceProtocol.swift sbx-ui/Services/CliExecutor.swift cli/Tests/SBXCoreTests/SBXCoreTests.swift cli/Tests/SBXCoreTests/CliExecutorTests.swift
git commit -m "Route CliExecutor through ProcessRunner and add a 30s default timeout

Replaces the terminationHandler-based pipe draining that deadlocked on
any output past the ~64KB pipe buffer. The timeout is a new protocol
parameter with a defaulted convenience overload, so existing call sites
are unchanged.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Exempt the interactive attach from the timeout

**Files:**
- Modify: `sbx-ui/Services/RealSbxService.swift:31-60` (the `run` method)
- Test: `cli/Tests/SBXCoreTests/SBXCoreTests.swift` (add to `ServiceArgumentTests`)

**Interfaces:**
- Consumes: `SpyCliExecutor.calls` tuple with the `timeout` element, from Task 2.
- Produces: no new API. `RealSbxService.run` passes `timeout: nil` on the resume branch and `.seconds(30)` on the create branch.

**Why this exists:** `SandboxStore.resumeSandbox` (`sbx-ui/Stores/SandboxStore.swift:64-75`) fires `sbx run --name <name>` as a deliberately never-returning call — it attaches to the agent interactively, and polling in `fetchSandboxes()` clears the busy flag. The 30-second default from Task 2 would start killing that attach.

- [ ] **Step 1: Write the failing test**

Add to the `ServiceArgumentTests` suite in `cli/Tests/SBXCoreTests/SBXCoreTests.swift`:

```swift
    @Test func runResumePassesNilTimeout() async throws {
        let spy = SpyCliExecutor()
        let json = """
            {"sandboxes":[{"id":"sbx_1","name":"foo","agent":"claude","status":"running","socket_path":"/tmp/x","workspaces":["/tmp/foo"]}]}
            """
        await spy.stub(argsKey: "ls --json", result: CliResult(stdout: json, stderr: "", exitCode: 0))
        let svc = RealSbxService(cli: spy)
        _ = try await svc.run(agent: "", workspace: "", opts: RunOptions(name: "foo"))
        let calls = await spy.calls
        // Bind first: `calls.first?.timeout` is Duration??, so comparing it to
        // nil would also pass when no call was recorded at all.
        let first = try #require(calls.first)
        #expect(first.args == ["run", "--name", "foo"])
        // The interactive attach must not be killed by the default timeout.
        #expect(first.timeout == nil)
    }

    @Test func runCreateUsesDefaultTimeout() async throws {
        let spy = SpyCliExecutor()
        let json = """
            {"sandboxes":[{"id":"sbx_1","name":"bar","agent":"claude","status":"running","socket_path":"/tmp/x","workspaces":["/tmp/bar"]}]}
            """
        await spy.stub(argsKey: "ls --json", result: CliResult(stdout: json, stderr: "", exitCode: 0))
        let svc = RealSbxService(cli: spy)
        _ = try await svc.run(agent: "claude", workspace: "/tmp/bar", opts: RunOptions(name: "bar"))
        let calls = await spy.calls
        let first = try #require(calls.first)
        #expect(first.timeout == .seconds(30))
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --package-path cli --filter ServiceArgumentTests`

Expected: FAIL — `runResumePassesNilTimeout` reports `.seconds(30)` instead of `nil`, because `run` currently uses the defaulted 2-argument `exec`.

- [ ] **Step 3: Thread the timeout through RealSbxService.run**

In `sbx-ui/Services/RealSbxService.swift`, replace the body of `run` from `var args: [String]` down to and including the `let result = try await cli.exec(...)` line:

```swift
        var args: [String]
        let timeout: Duration?

        if agent.isEmpty, let name = opts?.name, !name.isEmpty {
            // Resume mode: sbx run --name <name> (attaches to agent interactively).
            // sbx v0.33.0+ deprecated the bare-positional resume form in favor of
            // --name; see docs/sbx-cli-reference.md.
            args = ["run", "--name", name]
            // This attach is intentionally long-running: SandboxStore.resumeSandbox
            // fires it without awaiting and clears the busy flag by polling. A
            // timeout here would terminate the user's interactive session.
            timeout = nil
        } else {
            // Create mode: sbx create <agent> <workspace> [--name <name>]
            // Uses `create` (non-blocking) instead of `run` (which attaches interactively).
            // The terminal session is started separately by TerminalSessionStore.
            args = ["create", agent, workspace]
            if let name = opts?.name, !name.isEmpty {
                guard SbxValidation.isValidName(name) else {
                    throw SbxServiceError.invalidName(name)
                }
                args += ["--name", name]
            }
            timeout = .seconds(30)
        }
        let result = try await cli.exec(command: "sbx", args: args, timeout: timeout)
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --package-path cli`

Expected: PASS, all suites.

- [ ] **Step 5: Commit**

```bash
git add sbx-ui/Services/RealSbxService.swift cli/Tests/SBXCoreTests/SBXCoreTests.swift
git commit -m "Exempt the sbx run --name attach from the CLI timeout

The interactive attach is fired without awaiting and is expected never
to return, so the 30s default would terminate a live agent session. The
exception is explicit at the branch it applies to.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Fix the git status deadlock

**Files:**
- Modify: `sbx-ui/Services/DefaultEditorDocumentProvider.swift:41-96` (`listChangedFiles`)
- Test: `sbx-uiTests/EditorProviderTests.swift` (append a new suite)

**Interfaces:**
- Consumes: `ProcessRunner.run(...)`, `ProcessOutput`, `ProcessRunnerError` from Task 1.
- Produces: no API change. `listChangedFiles(in:) async throws -> [ChangedFileEntry]` keeps its signature and its existing error contract (`EditorErrorCode.gitUnavailable`, `EditorErrorCode.notGitRepository`).

**Note:** This file is macOS-only — it is deliberately absent from `cli/Package.swift`'s `sources:` list — so its test lives in the Xcode `sbx-uiTests` target. That target uses Swift Testing (see the existing `EditorPathTests`), so the hang guard is `.timeLimit(.minutes(1))`, not `executionTimeAllowance`.

- [ ] **Step 1: Write the failing test**

Append to `sbx-uiTests/EditorProviderTests.swift`:

```swift
// MARK: - listChangedFiles Large Output Regression

@Suite struct EditorProviderLargeOutputTests {

    /// Builds a temp git repo whose `git status --porcelain=v1 -z` output
    /// comfortably exceeds the ~64KB pipe buffer.
    private func makeRepoWithManyChanges(fileCount: Int) throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("editor-bigstatus-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        // Long names so ~900 files clear 64KB of porcelain output.
        let padding = String(repeating: "n", count: 100)
        for i in 0..<fileCount {
            let file = root.appendingPathComponent("file-\(padding)-\(i).txt")
            try Data("x".utf8).write(to: file)
        }

        func git(_ args: [String]) throws {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            p.arguments = args
            p.currentDirectoryURL = root
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            try p.run()
            p.waitUntilExit()
        }
        try git(["init"])
        // Staged additions list one porcelain record per file.
        try git(["add", "-A"])

        return root
    }

    @Test(.timeLimit(.minutes(1)))
    func listChangedFilesHandlesOutputBeyondPipeBuffer() async throws {
        let fileCount = 900
        let root = try makeRepoWithManyChanges(fileCount: fileCount)
        defer { try? FileManager.default.removeItem(at: root) }

        let provider = DefaultEditorDocumentProvider()
        let entries = try await provider.listChangedFiles(in: root)

        #expect(entries.count == fileCount)
    }

    @Test(.timeLimit(.minutes(1)))
    func listChangedFilesThrowsOutsideGitRepository() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("editor-nogit-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        do {
            _ = try await DefaultEditorDocumentProvider().listChangedFiles(in: root)
            #expect(Bool(false), "Should have thrown")
        } catch let error as NSError {
            #expect(error.code == EditorErrorCode.notGitRepository.rawValue)
        }
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run in Xcode via the Xcode MCP tools (`RunSomeTests` with target `sbx-uiTests`, identifier `EditorProviderLargeOutputTests`). CLI equivalent:

```bash
xcodebuild test -project sbx-ui.xcodeproj -scheme "sbx-ui Canary" \
  -destination 'platform=macOS' \
  -only-testing:sbx-uiTests/EditorProviderLargeOutputTests
```

Expected: `listChangedFilesHandlesOutputBeyondPipeBuffer` hits the 1-minute time limit. That hang IS the bug — `waitUntilExit()` runs before the pipes are drained.

- [ ] **Step 3: Rewrite listChangedFiles**

In `sbx-ui/Services/DefaultEditorDocumentProvider.swift`, replace the whole `listChangedFiles` method (lines 41-96) with:

```swift
    nonisolated public func listChangedFiles(in workspaceRoot: URL) async throws -> [ChangedFileEntry] {
        let root = workspaceRoot.standardizedFileURL

        // Resolve git via PATH; fall back to /usr/bin/git.
        guard let gitURL = Self.resolveGitBinary() else {
            await Self.log(.error, "listChangedFiles git not found", detail: root.path)
            throw NSError(
                domain: EditorErrorDomain,
                code: EditorErrorCode.gitUnavailable.rawValue,
                userInfo: [NSLocalizedDescriptionKey: EditorError.gitUnavailable.errorDescription ?? "git unavailable"]
            )
        }

        let output: ProcessOutput
        do {
            output = try await ProcessRunner.run(
                executable: gitURL,
                arguments: ["status", "--porcelain=v1", "-z"],
                currentDirectory: root,
                timeout: .seconds(30)
            )
        } catch let error as ProcessRunnerError {
            switch error {
            case .launchFailed(let message):
                await Self.log(.error, "listChangedFiles launch failed \(root.path)", detail: message)
                throw NSError(
                    domain: EditorErrorDomain,
                    code: EditorErrorCode.gitUnavailable.rawValue,
                    userInfo: [NSLocalizedDescriptionKey: EditorError.gitUnavailable.errorDescription ?? "git unavailable"]
                )
            case .timedOut(let duration):
                await Self.log(.error, "listChangedFiles timed out \(root.path)", detail: "after \(duration)")
                throw NSError(
                    domain: EditorErrorDomain,
                    code: EditorErrorCode.gitUnavailable.rawValue,
                    userInfo: [NSLocalizedDescriptionKey: "git status timed out after \(duration)"]
                )
            }
        }

        if output.exitCode == 128 {
            await Self.log(.info, "listChangedFiles not a git repo \(root.path)")
            throw NSError(
                domain: EditorErrorDomain,
                code: EditorErrorCode.notGitRepository.rawValue,
                userInfo: [NSLocalizedDescriptionKey: EditorError.notGitRepository.errorDescription ?? "not a git repo"]
            )
        }
        if output.exitCode != 0 {
            let msg = String(data: output.stderr, encoding: .utf8) ?? "git status failed (exit \(output.exitCode))"
            await Self.log(.error, "listChangedFiles \(root.path)", detail: msg)
            throw NSError(
                domain: EditorErrorDomain,
                code: Int(output.exitCode),
                userInfo: [NSLocalizedDescriptionKey: msg]
            )
        }

        let entries = Self.parsePorcelain(data: output.stdout, root: root)
        await Self.log(.info, "listChangedFiles \(root.path)", detail: "\(entries.count) entries")
        return entries
    }
```

- [ ] **Step 4: Run the test to verify it passes**

Run: same command as Step 2.

Expected: PASS, 2 tests. `entries.count == 900`.

- [ ] **Step 5: Commit**

```bash
git add sbx-ui/Services/DefaultEditorDocumentProvider.swift sbx-uiTests/EditorProviderTests.swift
git commit -m "Fix git status deadlock in listChangedFiles

waitUntilExit() ran before the pipes were drained, so any repo with more
than ~64KB of porcelain output hung every time. It also blocked a Swift
cooperative thread pool thread from an async method. Both go away by
routing through ProcessRunner.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: Full regression verification

**Files:**
- Modify: `CLAUDE.md` (Testing Guide test counts)
- No source changes.

**Interfaces:**
- Consumes: everything from Tasks 1-4.
- Produces: a verified green suite.

- [ ] **Step 1: Run the CLI mock suite**

Run: `bash tools/mock-sbx-tests.sh`

Expected: 47 passing.

- [ ] **Step 2: Run the full SPM suite**

Run: `swift test --package-path cli`

Expected: PASS. Previously 119 tests (39 SBXCore + 80 CLIE2E); now 134 (Task 1 adds 10, Task 2 adds 3, Task 3 adds 2 — all land in the SBXCore count).

- [ ] **Step 3: Verify the release build still compiles on the SPM path**

Run: `swift build --package-path cli -c release`

Expected: no errors. This is the closest local proxy for the Linux CI job; it catches a missing `nonisolated` or an unguarded platform import.

- [ ] **Step 4: Run the full macOS suite**

Prefer the Xcode MCP tools (`RunAllTests`). CLI equivalent:

```bash
xcodebuild test -project sbx-ui.xcodeproj -scheme "sbx-ui Canary" \
  -destination 'platform=macOS'
```

Expected: PASS. Previously 370 (322 unit + 48 UI); Task 4 adds 2 unit tests, so 324 unit + 48 UI = 372 total.

- [ ] **Step 5: Update the documented test counts**

In `CLAUDE.md`, under "Testing Guide", update these lines to match what Step 2 and Step 4 actually printed — use the real numbers, not the estimates above:
- `**SPM tests**: cli/Tests/SBXCoreTests/SBXCoreTests.swift — Swift Testing (39 tests: ...)` → new count, and mention `ProcessRunnerTests.swift` and `CliExecutorTests.swift` as additional SBXCore test files.
- `- Xcode: Product → Test (Cmd+U) runs all 370 tests (322 unit + 48 UI)` → new count.
- `- Linux/SPM: swift test --package-path cli runs all 119 SBXCore + CLIE2E tests` → new count.

- [ ] **Step 6: Commit**

```bash
git add CLAUDE.md
git commit -m "Update documented test counts after ProcessRunner work

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

- [ ] **Step 7: Report results**

State the actual pass/fail counts from Steps 1-4. If anything failed, report it with the output rather than claiming completion.

---

## Out of Scope

Recorded in the spec's "Out of scope" section and deliberately NOT addressed here: fabricated `createdAt` timestamps in `RealSbxService.list()`, synthesized `PolicyRule`s in `policyAllow`/`policyDeny`, the `$0.workspace == workspace` fallback in `run()`, missing name validation on the resume path, `KanbanPersistence.loadBoards` failing wholesale on one corrupt file, absent lint tooling, oversized `sbx_uiTests.swift` and `EditorStore.swift`, and `.DS_Store` not being gitignored.
