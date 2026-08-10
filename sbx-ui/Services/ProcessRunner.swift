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

                stdoutPipe.fileHandleForReading.readabilityHandler = Self.drainingHandler(
                    for: stdoutPipe.fileHandleForReading, session: session, isStdout: true
                )
                stderrPipe.fileHandleForReading.readabilityHandler = Self.drainingHandler(
                    for: stderrPipe.fileHandleForReading, session: session, isStdout: false
                )

                process.terminationHandler = { proc in
                    session.markExited(code: proc.terminationStatus)
                }

                do {
                    try process.run()
                } catch {
                    session.failImmediately(ProcessRunnerError.launchFailed(error.localizedDescription))
                    return
                }

                #if os(Linux)
                Self.startExitWatcher(pid: process.processIdentifier, session: session)
                #endif

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

    /// Size of a single `read(2)`; matches the default pipe capacity so a full
    /// pipe is normally emptied in one syscall.
    nonisolated static let readChunkSize: Int = 64 * 1024

    /// Switches `handle` to non-blocking and returns a readability handler that
    /// drains it to `EAGAIN` on every event.
    ///
    /// Draining fully — rather than taking a single `availableData` per event —
    /// is load-bearing on Linux, and the reason this is not the obvious
    /// one-read-per-callback loop:
    ///
    /// * swift-corelibs-foundation's `FileHandle.availableData` reads at most
    ///   8KB from a pipe, so one call per event cannot keep up with a child
    ///   that writes faster than we are woken.
    /// * libdispatch's Linux (epoll) read source is edge-triggered: it fires on
    ///   the *transition* to readable, not while data merely remains buffered.
    ///   Leaving bytes behind is therefore permanent — once the writer stops
    ///   producing new data there is no further edge, the handler is never
    ///   called again, and no EOF is ever delivered either.
    ///
    /// Together those silently truncated output: a `cat` of 1MB reliably
    /// stranded ~40KB in the pipe forever, and the run only completed via the
    /// post-exit drain deadline, with short data and no error. Darwin's kqueue
    /// read source is level-triggered, which is why every macOS suite passed.
    ///
    /// Using raw `read(2)` rather than `availableData` also removes an
    /// ambiguity: on a non-blocking descriptor `availableData` reports EAGAIN
    /// as empty `Data`, indistinguishable from EOF. `read` returning 0 is
    /// unambiguously EOF; `EAGAIN` just means "drained for now".
    nonisolated fileprivate static func drainingHandler(
        for handle: FileHandle,
        session: RunSession,
        isStdout: Bool
    ) -> @Sendable (FileHandle) -> Void {
        let flags = fcntl(handle.fileDescriptor, F_GETFL)
        if flags != -1 { _ = fcntl(handle.fileDescriptor, F_SETFL, flags | O_NONBLOCK) }

        return { handle in
            // Allocated per event rather than captured: the closure escapes,
            // and a shared mutable buffer would need its own synchronisation.
            var buffer = [UInt8](repeating: 0, count: ProcessRunner.readChunkSize)
            while true {
                let count = buffer.withUnsafeMutableBytes {
                    read(handle.fileDescriptor, $0.baseAddress, $0.count)
                }
                if count > 0 {
                    session.append(Data(buffer.prefix(count)), isStdout: isStdout)
                    continue
                }
                if count == 0 {
                    handle.readabilityHandler = nil
                    session.markEOF(isStdout: isStdout)
                    return
                }
                switch errno {
                case EINTR:
                    continue
                case EAGAIN, EWOULDBLOCK:
                    return  // Drained; the next write wakes us again.
                default:
                    // Nothing further will be readable from this descriptor —
                    // treat it as EOF so the run can still complete.
                    handle.readabilityHandler = nil
                    session.markEOF(isStdout: isStdout)
                    return
                }
            }
        }
    }

    #if os(Linux)
    /// Reports the child's exit to `session` as soon as the kernel knows it,
    /// independently of `Process.terminationHandler`.
    ///
    /// swift-corelibs-foundation does not learn a child's exit status from
    /// `waitpid`. It watches a socketpair the child inherits and treats EOF on
    /// it as "the child is gone" — but every *descendant* inherits that
    /// descriptor too, so a backgrounded grandchild holds it open long after
    /// the direct child is a zombie, and until it closes neither
    /// `terminationHandler` nor `waitUntilExit()` fires. Measured on
    /// `sh -c 'sleep 5 & printf hi'`: the direct child reaches state `Z`
    /// within 0.1s, `waitid` reports its status at 0.0002s, and Foundation's
    /// `terminationHandler` does not run until 5.018s.
    ///
    /// That is a production defect, not a slow test: on Linux any `sbx`
    /// command leaving a background process holding stdout blocked until that
    /// process exited — or until the 30s timeout turned a success into a
    /// spurious `timedOut`.
    ///
    /// `WNOWAIT` asks the kernel for the status *without* reaping, so the
    /// zombie stays waitable and Foundation's own machinery still completes
    /// normally afterwards; `markExited` is idempotent, so whichever of the
    /// two reports lands first wins and the other is a no-op.
    ///
    /// A dedicated `Thread` rather than `DispatchQueue.global().async`: this
    /// blocks for the child's whole lifetime, and parking libdispatch workers
    /// is how the pool gets starved under concurrent runs. The thread exits
    /// the moment `waitid` returns, so nothing accumulates per run.
    ///
    /// Darwin needs none of this — its `Process` is backed by a process
    /// dispatch source that fires on the direct child's exit no matter what
    /// its descendants hold — hence the `#if os(Linux)` here and at the one
    /// call site.
    nonisolated fileprivate static func startExitWatcher(pid: pid_t, session: RunSession) {
        let thread = Thread {
            var info = siginfo_t()
            while true {
                if waitid(P_PID, id_t(pid), &info, WEXITED | WNOWAIT) == 0 { break }
                // `errno` is only meaningful once `waitid` has actually failed.
                if errno == EINTR { continue }
                // ECHILD means Foundation reaped the child before we asked, so
                // its `terminationHandler` has already reported the status (or
                // is about to). Any other failure is equally unreportable —
                // leave it to that path rather than inventing an exit code.
                return
            }
            // Matches what `Process.terminationStatus` would report: the exit
            // code for a normal exit (`CLD_EXITED`), the signal number for a
            // death by signal (`CLD_KILLED`/`CLD_DUMPED`, which Foundation
            // surfaces as `terminationReason == .uncaughtSignal`).
            session.markExited(code: info._sifields._sigchld.si_status)
        }
        thread.name = "ProcessRunner.exitWatcher"
        thread.start()
    }
    #endif

    nonisolated static func asSeconds(_ duration: Duration) -> Double {
        let c = duration.components
        return Double(c.seconds) + Double(c.attoseconds) / 1e18
    }
}

/// Mutable state shared between the readability handlers, the termination
/// handler, the timeout timer and the cancellation handler — each of which
/// runs on a different queue. All access is guarded by one lock, and the
/// continuation is resumed exactly once.
nonisolated private final class RunSession: @unchecked Sendable {
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
    private var killIssued = false

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

    /// Idempotent by design: on Linux the exit is reported twice, by
    /// `ProcessRunner.startExitWatcher`'s `waitid` thread and by Foundation's
    /// `terminationHandler`, and both fire on every run. The first report wins
    /// outright and the second returns here having changed nothing.
    ///
    /// All three of the things a second report could otherwise do are ruled
    /// out by the early return, under the same lock that publishes `exited`:
    /// it cannot overwrite `exitCode`, it cannot schedule a second drain
    /// deadline (which would extend the post-exit grace by however far apart
    /// the two reports are — three whole seconds in the grandchild case), and
    /// it cannot drive another `tryFinish`. Resuming the continuation twice
    /// was already impossible one level down, where `tryFinish` latches
    /// `finished` under the lock before handing back a resumption.
    func markExited(code: Int32) {
        lock.lock()
        guard !exited else {
            lock.unlock()
            return
        }
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
    ///
    /// Recording the failure and issuing the kill are deliberately separate:
    /// a cancel that lands before `attach(process:)` (i.e. before
    /// `process.run()`) has no process to kill yet. `beginFailure` may be
    /// called again later (once `run()` has launched the child) purely to
    /// retry the kill — `pendingFailure` is already set by then, so only
    /// `attemptKill()` needs to run again; nothing else here re-executes
    /// thanks to `killIssued` / `finished` guards.
    func beginFailure(_ error: Error) {
        lock.lock()
        let isNewFailure = pendingFailure == nil
        if isNewFailure { pendingFailure = error }
        let alreadyFinished = finished
        lock.unlock()

        guard !alreadyFinished else { return }

        attemptKill()

        if isNewFailure {
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
        }

        tryFinish()
    }

    /// Sends SIGTERM (escalating to SIGKILL after `terminateGrace`) at most
    /// once, and only once the child has actually been launched. Safe to
    /// call repeatedly — a no-op once issued, and a no-op if the process
    /// hasn't started running yet (nothing to kill; the caller is expected
    /// to retry once it has).
    private func attemptKill() {
        lock.lock()
        guard !killIssued, let proc = process, proc.isRunning else {
            lock.unlock()
            return
        }
        killIssued = true
        lock.unlock()

        proc.terminate()
        let pid = proc.processIdentifier
        DispatchQueue.global().asyncAfter(deadline: .now() + ProcessRunner.asSeconds(ProcessRunner.terminateGrace)) {
            if proc.isRunning { kill(pid, SIGKILL) }
        }
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

    /// Never call `FileHandle.close()` from here — this method can run
    /// synchronously *inside* a readability handler: `tryFinish` is invoked
    /// from `markEOF`, which the handlers in `run` call before returning
    /// (see the EOF branch there). On swift-corelibs-foundation, `close()`
    /// does `queue.sync { … }` against the handle's own dispatch-source
    /// queue to serialize with any in-flight readability event. Calling that
    /// from inside the very event it would wait for means waiting on the
    /// queue we are currently running on; libdispatch's deadlock detector
    /// traps that as an illegal instruction
    /// (`__DISPATCH_WAIT_FOR_QUEUE__`). That is exactly the SIGILL this
    /// crashed Linux CI with — Darwin's Foundation happens to tolerate the
    /// same self-wait, which is why every macOS suite passed.
    ///
    /// Instead, just drop every strong reference we hold: the two handle
    /// ivars, and `process` (which — via `Process.standardOutput`/
    /// `standardError` — is the only thing keeping the owning `Pipe`, and
    /// therefore its `FileHandle`s, alive once we let go here). Once nothing
    /// references a `FileHandle` anymore, its `deinit` closes the underlying
    /// fd on its own, and deliberately *without* the synchronous queue wait
    /// `close()` uses — swift-corelibs-foundation's `FileHandle.deinit` calls
    /// `_immediatelyClose` directly for precisely this reentrancy reason.
    /// That is safe regardless of whether this particular handle has already
    /// observed EOF, so there is no need to special-case it here anymore.
    private func releaseHandles() {
        lock.lock()
        stdoutHandle = nil
        stderrHandle = nil
        process?.terminationHandler = nil
        process = nil
        lock.unlock()
    }
}
