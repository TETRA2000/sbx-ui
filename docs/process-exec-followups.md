# Process Execution — Known Issues and Follow-Ups

Findings surfaced while fixing the subprocess pipe deadlock
(`docs/superpowers/specs/2026-08-09-process-exec-deadlock-design.md`) that were
reviewed, triaged as deferrable, and deliberately **not** fixed in that branch.

Each entry records why it was judged safe to defer. None is a known-broken
behavior users hit today; several are refutations of concerns that turned out
not to hold.

## ProcessRunner

**Post-exit, pre-EOF failure reporting.** A timeout or cancellation landing after
the child exited cleanly but before EOF arrives throws instead of returning the
complete output (`ProcessRunner.swift`, the `pendingFailure` branch in
`tryFinish`). The window is the microseconds between `terminationHandler` and the
EOF callbacks, and the resulting error is honest rather than corrupt.

**`appendCapped` copy cost.** Once the cap is reached, `removeFirst` memmoves up
to `maxOutputBytes` on every subsequent chunk. At a realistic agent output rate
(~10MB/hour in ~8KB chunks) this is ~1.4 MB/s of memmove. Only a large burst
costs real CPU — a 100MB emitter through a 4MB cap spends roughly 10–25s spread
across the write. Mitigable with a slack threshold if it ever matters.

**No validation on `maxOutputBytes`.** A negative value traps in `removeFirst`.
Both call sites pass compile-time constants (the 4MB default and a 64MB literal),
so this is public-API hygiene only.

**Retain cycle on an un-EOF'd handle.** `releaseHandles` deliberately leaves the
readability handler installed on a handle whose EOF was never observed, because
clearing and closing it would reintroduce the close-vs-live-handler crash that
change fixed. Measured behavior: when the grandchild eventually exits, fds return
to baseline within ~30s. Retention is permanent **only** if a grandchild
daemonizes and never closes the pipe.

> The same root cause was *not* benign on the launch-failure path, where handlers
> never fire at all. That leaked 6 fds permanently per failure and **was fixed**
> (`process = nil` in `releaseHandles`, commit `2a9b7cf`).

**`proc.isRunning` evaluated under the session lock.** Raised as a latent ABBA
against `terminationHandler` → `markExited`, then refuted in practice: the normal
path already does the strictly riskier thing, clearing
`process.terminationHandler` from inside a stack that originates within
`terminationHandler` itself. If Foundation held an internal `Process` lock across
that call, every run would deadlock — and the full suites pass. The under-lock
check is also load-bearing for the `killIssued` latch's correctness, so changing
it would cost more than it buys.

**Pid-reuse race in SIGKILL escalation.** `proc.isRunning` can be true, the child
exit, its pid be recycled, and the escalation then signal an unrelated process.
Pre-existing code relocated verbatim; requires pid wraparound inside a 2s window.

**No EPIPE/SIGPIPE for a still-writing grandchild.** Dropping the unconditional
`close()` means a grandchild that outlives its parent no longer gets a broken
pipe when the run completes. This is an improvement rather than a regression.

**Timeout timer captures `session` strongly.** Every other deferred block in the
file uses a weak capture. A session and its collected output are retained for the
remainder of the timeout after the command completes. Harmless at realistic
output sizes; the inconsistency is worth a comment or a weak capture.

**Dead write in `beginFailure`.** `pendingFailure` is written even when `finished`
is already true, where it can no longer be observed. Cosmetic.

**Shared truncation flag across streams.** `truncated` is one flag covering both
stdout and stderr, so a stderr-only overflow fails a `sandbox/exec` whose stdout
is intact. Conservative, and consistent with the documented behavior.

## CliExecutor / service layer

**Truncation ignored on non-plugin paths.** `CliExecutor` does not inspect
`outputTruncated`. GUI paths fail safely on their own — `execJson` raises a JSON
decode error, `parseSandboxList` returns `[]` when the header is gone, and a
truncated `policy log` simply shows the most recent output, which is what you
want. A one-line warning log would still be an improvement.

**`sbx create` and `sbx stop` under the blanket 30s timeout.** These are the two
commands most likely to legitimately exceed it — `create` on a cold Docker image
pull, `stop` on a long container SIGTERM grace. The design explicitly sanctioned
the blanket default. If users report "Command timed out after 30 seconds" on a
first-ever sandbox creation, this is why.

**`agent` empty and no name falls through to create.** Produces
`args = ["create", "", workspace]`. Pre-existing and untested at any layer. Worth
a `guard`, particularly since the plugin API makes the resume branch's entry
condition more reachable than originally assumed.

## Plugin API

**`sandbox/run` can reach the `timeout: nil` attach branch from a caller that
awaits.** `handleSandboxRun` awaits `service.run(...)`, and the documented method
covers resume, which takes the never-returning attach branch — so the JSON-RPC
response is never sent. The design invariant "exactly one call path may pass
`timeout: nil`" holds at the code line but not at the caller level. Impact is
contained: `PluginHost` dispatches each request in its own `Task`, so one hung
request leaks a Task and an unanswered response without wedging other calls.

This path deadlocked outright before the branch, so it is strictly improved.
The proper fix is to move the exemption out of `RealSbxService` to the caller —
an explicit attach path, or a `RunOptions` flag — so the plugin API and the Linux
CLI cannot silently inherit it.

**Error-table imprecision.** `docs/plugin-development.md` describes `-32002` as
wrapping `SbxServiceError`; the truncation error does not.

**Truncation test asserts the code, not the message.** `-32002` is shared with the
generic error path, so asserting on message text would discriminate more sharply.

## Testing

**The `listChangedFiles` truncation guard has no test.** The 64MB cap is
hardcoded inside the method, making the branch unreachable from tests. It was
verified manually by temporarily lowering the cap. Giving the provider an
internal `maxOutputBytes` with an overriding init would make it testable.

**`launchFailureThrows` lacks `.timeLimit`.** That path resumes synchronously and
cannot hang, so the omission is currently harmless.

**`largeStderrDoesNotDeadlock` omits the `outputTruncated == false` assertion**
that its stdout counterpart carries.

**The outside-git-repo test checks `error.code` but not `error.domain`.**
Collision risk is low given how distinctive the code is.

**`ProcessRunnerError.timedOut` maps to `EditorErrorCode.gitUnavailable`,**
conflating "git missing" with "git hung". The localized description carries the
accurate text, so the user-visible message is right even though the code is not.

## Unrelated: the UI test suite is red on `main`

19 of 48 `sbx-uiUITests` tests fail on `main`, verified by running the target at
merge-base in an isolated worktree and diffing the sorted failure sets against a
branch run — byte-identical. CI does not run this target (a documented cost
decision in `.github/workflows/tests.yml`), so nothing surfaces it.

Failures span create-sandbox flows, env/port sheets, background-session
badge/sidebar, session reattach and switching, and the terminal thumbnail. At
least one looks environmental rather than logical (`Not hittable: Button` on a
Kanban play button). Diagnosing them is independent of the deadlock work.

## Platform divergences worth knowing (Linux)

Two Linux behaviors cost significant debugging time and are invisible from
macOS. Neither is documented anywhere obvious, and both bite anyone touching
`ProcessRunner` next.

**corelibs `Process` learns a child's exit from a socketpair that every
descendant inherits — not from `waitpid`.** `terminationHandler` and
`waitUntilExit()` therefore do not fire until the last *descendant* holding
that inherited descriptor exits, even though the direct child is long since a
zombie. Measured on `sh -c 'sleep 5 & printf hi'`: the direct child reaches
`/proc` state `Z` within 0.1s and `waitid(P_PID, …, WEXITED | WNOWAIT)` reports
its status at 0.0002s, but `terminationHandler` does not run until 5.018s.
Redirecting the grandchild's stdio away from our pipes changes nothing; a
grandchild that holds our pipes but closes every *other* inherited fd reports
at 0.0045s, which is what isolated the socketpair. The exit *status* is
unavailable for that whole window too, so no restructuring around
`Foundation.Process` can complete the run earlier. Darwin's `Process` is backed
by a process dispatch source keyed on the direct child, so none of this shows
up there. `ProcessRunner.startExitWatcher` works around it with a Linux-only
`waitid` thread; anything else that waits on a `Process` has the same exposure.

**`FileHandle` does not reliably close its descriptor when the last reference
drops.** On Darwin, dropping every reference to a read-end `FileHandle` runs
`deinit`, which closes the fd — the assumption commit `6529526` was built on.
On Linux something still retains the handle after a run whose readability
events fired, `deinit` never runs, and two pipe descriptors leak per
*successful* run: measured as +40 pipe fds per 20 runs, sustained across every
phase, while launch failures (where no readability event ever fires) leak
nothing and macOS is 0 throughout. The fix is an explicit `close()`, but it
must be dispatched **off** the handle's own queue — a synchronous `close()`
reachable from inside a readability handler self-deadlocks and traps as SIGILL,
which is precisely what `6529526` was fixing. See the `releaseHandles()` doc
comment for the shape that satisfies both constraints at once.
