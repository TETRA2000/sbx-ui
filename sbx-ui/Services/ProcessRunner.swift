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
                    session.failImmediately(ProcessRunnerError.launchFailed(error.localizedDescription))
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
