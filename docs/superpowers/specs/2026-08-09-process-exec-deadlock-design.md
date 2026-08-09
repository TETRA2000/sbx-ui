# Process Execution Deadlock Fix — Design

**Date:** 2026-08-09
**Status:** Approved
**Scope:** Correctness fix for subprocess pipe handling in `CliExecutor` and `DefaultEditorDocumentProvider`

## Problem

Three related defects in how the app spawns and drains subprocesses. All three are
resolved by one shared component.

### 1. `CliExecutor.exec` drains pipes after the process exits

`sbx-ui/Services/CliExecutor.swift:74-75` reads both pipes inside
`process.terminationHandler`:

```swift
process.terminationHandler = { [cmdLine] process in
    let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
    let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
    ...
}
```

A pipe holds roughly 64KB. When a child writes more than that and nobody is
reading, the child blocks in `write(2)`. A blocked child never exits, so
`terminationHandler` never fires, so nothing ever reads the pipe. The
continuation is never resumed and the calling task hangs forever.

This sits on the path of **every** `sbx` invocation the GUI makes — 18 call
sites via `RealSbxService`. Commands whose output can plausibly exceed 64KB
include `sbx policy log --json` and `sbx ls --json` on a host with many
sandboxes.

### 2. `DefaultEditorDocumentProvider.listChangedFiles` waits before draining

`sbx-ui/Services/DefaultEditorDocumentProvider.swift:73-76`:

```swift
process.waitUntilExit()

let data = stdout.fileHandleForReading.readDataToEndOfFile()
let errData = stderr.fileHandleForReading.readDataToEndOfFile()
```

Same deadlock, but guaranteed rather than probabilistic: any repository with
more than 64KB of `git status --porcelain=v1 -z` output hangs here every time.

This one carries a second defect. The method is `nonisolated public func ...
async`, so `waitUntilExit()` blocks a Swift cooperative thread pool thread —
the exact failure class `CLAUDE.md` documents under "when encountering flaky
tests, always find and fix the root cause."

### 3. No timeout anywhere

Neither site bounds how long it will wait. A genuinely hung `sbx` — not just a
full pipe — hangs the calling store indefinitely with no recovery path.

### Reference implementation already in the repo

`sbx-ui/Plugins/PluginHost.swift:229-237` drains its subprocess correctly using
`readabilityHandler`. The fix generalizes that pattern rather than inventing one.

## Approach

Extract a single internal `ProcessRunner` used by both call sites, instead of
patching two hand-rolled implementations in parallel.

Alternatives considered:

- **Blocking reads on background dispatch queues.** Simplest to reason about,
  but costs three threads per exec and reintroduces the blocking-read pattern
  `CLAUDE.md` warns against.
- **Redirect output to temp files.** No pipe buffer, therefore no possible
  deadlock, and no concurrency at all. Rejected because it adds temp-file
  lifecycle management and diverges from how the rest of the codebase spawns
  processes.

`readabilityHandler` accumulation wins on two counts: it matches existing repo
precedent, and it composes with timeout and cancellation for free. To enforce
either, terminate the child; that closes the pipes, which drives EOF, which
completes the call through the same path as a normal exit. The alternatives
each need a separate mechanism bolted on.

Placing `ProcessRunner` in `sbx-ui/Services/` also puts its tests in
`SBXCoreTests`, which runs on the **Linux CI job** — the only test suite that
gates every pull request.

## Design

### `ProcessRunner`

New file `sbx-ui/Services/ProcessRunner.swift`.

```swift
public struct ProcessOutput: Sendable {
    public let stdout: Data
    public let stderr: Data
    public let exitCode: Int32
}

public enum ProcessRunnerError: Error, Sendable {
    case launchFailed(String)
    case timedOut(Duration)
}

public enum ProcessRunner {
    nonisolated public static func run(
        executable: URL,
        arguments: [String],
        currentDirectory: URL? = nil,
        environment: [String: String]? = nil,
        standardInput: FileHandle? = FileHandle.nullDevice,
        timeout: Duration? = .seconds(30)
    ) async throws -> ProcessOutput
}
```

Internally a lock-guarded collector class wraps a
`withCheckedThrowingContinuation`:

- Both pipes get a `readabilityHandler` that appends `availableData` and marks
  EOF when a read returns empty. On EOF the handler clears itself.
- `terminationHandler` records the exit code and marks the process exited.
- The continuation resumes exactly once, guarded by a `resumed` flag held under
  the same lock as the state it checks.

### Completion condition

The naive join — stdout EOF, stderr EOF, and process exited — has a hole. If
`sbx` spawns a grandchild (for example `docker`) that inherits the pipe write
end, the child can exit while the pipe stays open. EOF never arrives and the
call hangs again, just in a new place.

The actual condition is therefore:

```
exited && (bothPipesAtEOF || drainDeadlinePassed)
```

When the process exits, a 2-second drain timer starts. If it fires before both
pipes reach EOF, the runner clears the readability handlers, closes the read
ends, and completes with whatever was collected. Data already buffered in the
pipe is read promptly by the readability handlers, so the truncation risk in
practice is negligible — and this is what makes the fix terminal instead of
relocating the hang.

### Timeout and cancellation

Both funnel into one path:

1. Send `SIGTERM` via `process.terminate()`.
2. After a 2-second grace period, escalate to `SIGKILL`.
3. Pipes close, EOF arrives, normal completion runs.
4. A flag decides whether to throw `.timedOut` / `CancellationError` rather than
   return the collected output.

Cancellation is wired through `withTaskCancellationHandler`. No path leaves a
running child process behind.

### Protocol change

Swift does not permit default values in protocol requirements, so
`CliExecutorProtocol` gains the explicit form and a protocol extension supplies
the defaulted convenience:

```swift
public protocol CliExecutorProtocol: Sendable {
    func exec(command: String, args: [String], timeout: Duration?) async throws -> CliResult
    func execJson<T: Decodable & Sendable>(command: String, args: [String], timeout: Duration?) async throws -> T
}

extension CliExecutorProtocol {
    public func exec(command: String, args: [String]) async throws -> CliResult {
        try await exec(command: command, args: args, timeout: .seconds(30))
    }
    public func execJson<T: Decodable & Sendable>(command: String, args: [String]) async throws -> T {
        try await execJson(command: command, args: args, timeout: .seconds(30))
    }
}
```

All 18 existing call sites compile unchanged. Only two types conform to this
protocol and need real updates: `CliExecutor` and `SpyCliExecutor`
(`cli/Tests/SBXCoreTests/SBXCoreTests.swift:406`).

### Timeout opt-out

`SandboxStore.resumeSandbox` (`sbx-ui/Stores/SandboxStore.swift:64-75`)
deliberately fires `sbx run --name <name>` as a never-returning call — it
attaches to the agent interactively, and polling in `fetchSandboxes()` clears
the busy flag. A blanket timeout would start killing that attach.

`RealSbxService.run()` therefore passes `timeout: nil` on the `run --name`
resume branch only. Every other call keeps the 30-second default. The single
intentional exception is explicit at the line where it applies rather than
implicit in the executor.

#### Accepted consequence: unbounded buffering on the `nil` timeout path

Today that attach benefits from accidental backpressure — it writes 64KB, the
pipe fills, and the child blocks. After this fix the child runs indefinitely and
the collector accumulates its stdout in memory for the life of the session,
which for an agent attached over hours is unbounded. The output is discarded
anyway, since `resumeSandbox` ignores the result.

`ProcessRunner` therefore caps retained output at a few megabytes, keeping the
tail and dropping the head once the cap is reached. The exact cap and whether
truncation is signalled in `ProcessOutput` are settled in the implementation
plan; the requirement here is only that no call path can grow without bound.

### Call site changes

- `CliExecutor.exec` keeps PATH resolution (`resolveCommand`) and its `appLog`
  logging, and delegates execution to `ProcessRunner`.
- `DefaultEditorDocumentProvider.listChangedFiles` drops `waitUntilExit()` and
  both `readDataToEndOfFile()` calls, calling `ProcessRunner.run` instead. This
  removes the blocking call from the cooperative thread pool.

## Testing

Tests are written before the fix.

Two notes on what "fails first" means here. `ProcessRunnerTests` cannot fail
against current code, because the component does not exist yet — red means the
suite does not compile. That is ordinary TDD, but only the macOS
`listChangedFiles` regression genuinely demonstrates the existing bug against
existing code.

More importantly, the failing state of every deadlock repro is a **hang**, not
an assertion failure, and an unbounded hang wedges CI until the outer job
timeout. Each deadlock-repro test therefore carries an explicit time limit —
the Swift Testing `.timeLimit` trait for the `SBXCoreTests` cases, and
`executionTimeAllowance` for the XCTest-based macOS regression — so the red
state is a fast and legible timeout.

### `cli/Tests/SBXCoreTests/ProcessRunnerTests.swift`

Runs on the Linux CI job, which gates every pull request.

| Test | Asserts |
|---|---|
| `largeStdoutDoesNotDeadlock` | ~1MB on stdout returns complete; hangs today |
| `largeStderrDoesNotDeadlock` | ~1MB on stderr returns complete; hangs today |
| `largeStdoutAndStderrSimultaneously` | Both at ~1MB; hangs today |
| `nonZeroExitCodePropagates` | Exit code surfaces unchanged |
| `timeoutTerminatesChildAndThrows` | `sleep 30` with 1s timeout throws `.timedOut` well inside the deadline, child no longer running |
| `nilTimeoutDoesNotTerminate` | A `nil` timeout completes normally |
| `cancellationTerminatesChild` | Cancelling the task kills the child |
| `launchFailureThrows` | Nonexistent binary throws `.launchFailed` |

### `sbx-uiTests`

`DefaultEditorDocumentProvider` is not in `Package.swift`'s `sources:` list, so
it is macOS-only and tested in the Xcode target: build a temp git repository
with enough changed files to push `git status --porcelain=v1 -z` past 64KB, then
assert every entry is returned. This test hangs against current code.

### Regression

Full suite before the work is considered done, per `CLAUDE.md`:
`swift test --package-path cli`, the Xcode unit and UI targets, and
`bash tools/mock-sbx-tests.sh`.

## Constraints

- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` in the Xcode project means every
  explicit `init` and `static` on a `Sendable` type needs `nonisolated`, or the
  macOS build breaks.
- Signal escalation needs `#if canImport(Darwin)` / `#else import Glibc` guards
  to keep the Linux build working.
- `ProcessRunner.swift` must be added to `Package.swift`'s explicit `sources:`
  array or `SBXCore` will not compile it.

## Out of scope

Deliberately excluded, recorded here so they are not silently lost:

- `RealSbxService.list()` stamps `createdAt: Date()` on every refresh,
  fabricating timestamps.
- `policyAllow` / `policyDeny` synthesize `PolicyRule`s with random UUIDs when
  the post-command lookup misses.
- `RealSbxService.run()`'s `$0.workspace == workspace` fallback can match the
  wrong sandbox when several share a workspace.
- Name validation is applied on the create path but skipped on resume.
- `KanbanPersistence.loadBoards` lets one corrupt JSON file fail the whole load.
- No SwiftLint or swift-format configuration and no lint CI job.
- `sbx_uiTests.swift` is 3442 lines; `EditorStore.swift` is 795.
- `.DS_Store` is not in `.gitignore`.
