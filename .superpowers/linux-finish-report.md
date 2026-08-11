# Linux `ProcessRunner` — finishing B (exit status) and C (fd leak)

Branch `fix/process-exec-deadlock`, starting at `f6660e7`. Container `swift:6.1`
(Ubuntu 24.04, aarch64), matching CI's pinned toolchain. Follows
`.superpowers/linux-dataloss-report.md`, which diagnosed A (fixed in `f6660e7`),
B and C.

Both fixes landed. Both are verified RED→GREEN with numbers, on Linux and macOS.
No test was weakened, skipped, or retimed.

## Summary

| # | Defect | Fix | RED | GREEN |
|---|--------|-----|-----|-------|
| B | Exit status withheld until every descendant releases corelibs' socketpair | Linux-only `waitid(P_PID, …, WEXITED \| WNOWAIT)` watcher thread | `grandchildHoldingPipeDoesNotHang` 5.002s (fails `< 4.5`) | 2.026–2.055s, 5/5 runs |
| C | 2 pipe fds leaked per successful run on Linux | Async `close()` of EOF'd handles from a global queue | +40 pipe fds per 20 runs, every phase | pipe delta **0**, every phase |

---

## B — exit status blocked by lingering descendants

### What was implemented

`ProcessRunner.startExitWatcher(pid:session:)`, guarded `#if os(Linux)` at both
the definition and its single call site (immediately after a successful
`process.run()`). It starts a dedicated `Thread` that blocks in
`waitid(P_PID, id_t(pid), &info, WEXITED | WNOWAIT)` and reports the status via
`session.markExited(code:)`.

`WNOWAIT` retrieves the status **without reaping**, so the zombie stays waitable
and Foundation's own socketpair machinery still completes normally afterwards.

Design points, each verified rather than assumed:

- **Dedicated `Thread`, not `DispatchQueue.global().async`.** The call blocks for
  the child's entire lifetime; parking libdispatch workers is how the pool gets
  starved under concurrent runs. The thread returns the moment `waitid` does.
- **`EINTR` retries; `ECHILD` (and any other failure) returns silently**, leaving
  the report to Foundation's `terminationHandler`. Probed directly: reaping via
  `waitUntilExit()` first makes a later `waitid` return `-1` with `errno == 10`
  (`ECHILD`).
- **`errno` is read only when `waitid` failed.** A probe showed `errno == 9` left
  over from earlier work after a *successful* `waitid`; branching on it
  unconditionally would have been a bug.
- **Status decode matches Foundation exactly.** `info._sifields._sigchld.si_status`
  is used for both `CLD_EXITED` and `CLD_KILLED`/`CLD_DUMPED`. Probed side by
  side: `sh -c 'exit 7'` → `si_code=1`, `si_status=7`, Foundation
  `terminationStatus=7`; SIGTERM'd child → `si_code=2`, `si_status=15`,
  Foundation `terminationStatus=15, terminationReason=1`. No `+128` convention
  was invented — corelibs reports the bare signal number and so do we.
  (`si_status` is not spellable as `info.si_status` in Swift on Linux; glibc
  defines that as a macro the Clang importer does not carry across. The union
  path above is the working spelling.)

### `markExited` idempotency — verified, not assumed

`markExited` now returns early, under the same lock that publishes `exited`, if
an exit has already been recorded. That single guard rules out all three hazards
at once: no `exitCode` overwrite, no second drain-deadline schedule, no extra
`tryFinish`. Double-resuming the continuation was already impossible one level
down, where `tryFinish` latches `finished` under the lock before handing back a
resumption.

The reschedule was the hazard that actually mattered: without the guard the
later report would restart the 2s post-exit grace from its own arrival time —
three whole seconds later in the grandchild case.

Direct evidence, from temporary instrumentation printing every `markExited` call
(since `RunSession` is `private` and cannot be unit-tested directly), over 5
runs of `ProcessRunnerTests|CliExecutorTests`:

```
22 duplicate reports observed, 0 with a disagreeing code:
  14x dup code=0  firstCode=0  finished=true
   3x dup code=0  firstCode=0  finished=false
   2x dup code=42 firstCode=42 finished=false
   2x dup code=1  firstCode=1  finished=true
   1x dup code=3  firstCode=3  finished=false
all 5 runs: Test run with 15 tests passed
```

Two things this establishes. Both paths really do fire — this is not a
theoretical race. And in **every** duplicate the second reporter's code equals
the first's, so the `waitid` decode never disagreed with Foundation's
`terminationStatus`, including for the SIGTERM'd children (`code=15` appeared as
a first report in the timeout/cancellation tests). Six duplicates arrived with
`finished=false`, i.e. inside the pre-completion window where an unguarded
reschedule would have changed the outcome.

macOS is byte-for-byte unchanged: the watcher is compiled out entirely by
`#if os(Linux)`, and with only `terminationHandler` reporting, the early return
in `markExited` is unreachable there.

### Behavior change worth stating

On Linux the post-exit `drainGrace` now starts at the child's *actual* exit
rather than whenever the last descendant released the socketpair. Output written
by a grandchild more than 2s after the direct child exits is therefore cut at
the deadline instead of collected indefinitely. That is exactly what `drainGrace`
is for, and exactly what macOS has always done — this aligns the platforms
rather than changing the contract.

### RED / GREEN

```
RED  (watcher disabled via #if os(Linux) && false):
  ✘ grandchildHoldingPipeDoesNotHang — (elapsed → 5.002166748046875) < 4.5

GREEN (5 consecutive runs, --filter "ProcessRunnerTests|CliExecutorTests"):
  run 1  grandchild 2.038s   15 tests passed
  run 2  grandchild 2.037s   15 tests passed
  run 3  grandchild 2.038s   15 tests passed
  run 4  grandchild 2.033s   15 tests passed
  run 5  grandchild 2.031s   15 tests passed
```

The test asserts `elapsed >= 1.5 && < 4.5`; 2.03s is the drain deadline finally
starting at the real exit, comfortably inside the window at both ends.
Timeout and cancellation tests continue to kill their children and return
promptly (`timeoutTerminatesChildAndThrows` ~1.03s, `cancellationTerminatesChild`
~0.31s, `cancelBeforeLaunchStillKillsChild` ~0.04s).

---

## C — fd leak on Linux

### What was implemented

`releaseHandles()` now collects the read handles whose EOF has already been
observed, drops every strong reference under the lock as before (including
`process = nil`, the `2a9b7cf` launch-failure fix, untouched), and then closes
the collected handles **asynchronously on a global queue**:

```swift
guard !closable.isEmpty else { return }
DispatchQueue.global().async {
    for handle in closable { try? handle.close() }
}
```

A global queue is by construction never the handle's own dispatch-source queue,
so this cannot reproduce the `__DISPATCH_WAIT_FOR_QUEUE__` self-wait that
`6529526` removed. Only EOF'd handles are closed: that handler set
`readabilityHandler = nil` before calling `markEOF` and cannot still be running.

### Judgment call 1 — portable, not Linux-only

Applied on both platforms, no `#if`. macOS did not need it (0 delta before and
after), but releasing the descriptor at a defined point beats releasing it
whenever the last reference happens to drop, and one path is one thing to reason
about rather than two that can diverge. The empirical condition for this choice
was that macOS shows no anomaly: it doesn't — full macOS SPM suite, full Xcode
unit target, and the macOS fd harness are all unchanged (numbers below). Had
anything moved, the fallback was to wrap it in `#if os(Linux)`.

### Judgment call 2 — the un-EOF'd handle is still left alone

Unchanged, deliberately. On the forced/drain-deadline path a grandchild still
holds the write end and that handler may be mid-callback; closing it would be
racing a live handler for one descriptor. This remains the accepted deferral
already recorded in `docs/process-exec-followups.md` ("Retain cycle on an
un-EOF'd handle" — fds return to baseline within ~30s once the grandchild
exits). Nothing here makes it worse.

### Measurement method

The harness counts `/proc/self/fd` on Linux and `/dev/fd` on macOS, and on Linux
resolves each entry so **pipes are counted separately**. That separation is what
made the result legible: total-fd deltas are contaminated by libdispatch's
worker pool lazily allocating `timerfd`/`eventfd`/`eventpoll` descriptors as it
grows. Those plateau (phase 3 and 4 both show total delta 0 after the pool has
grown) and are not a leak; pipes are what `ProcessRunner` owns.

The macOS counting method was itself checked against a deliberate leak: holding
10 `Pipe`s takes the count 4 → 24, so a flat 4 is a real zero and not a blind
metric.

### RED / GREEN (Linux)

```
RED (async close removed, everything else identical):
  baseline                  pipes=17  pipeDelta=0
  phase1 launchFailures=50  pipes=17  pipeDelta=0
  phase2 smallRuns=20       pipes=57  pipeDelta=40
  phase3 bigRuns=20         pipes=97  pipeDelta=40
  phase4 smallRuns=20       pipes=137 pipeDelta=40

GREEN:
  baseline                  pipes=11  pipeDelta=0  fdDelta=0   threads=15
  phase1 launchFailures=50  pipes=11  pipeDelta=0  fdDelta=0   threads=44
  phase2 smallRuns=20       pipes=11  pipeDelta=0  fdDelta=15  threads=44
  phase3 bigRuns=20         pipes=11  pipeDelta=0  fdDelta=3   threads=44
  phase4 smallRuns=20       pipes=11  pipeDelta=0  fdDelta=0   threads=44
```

Exactly 2 pipe fds per successful run before, 0 after, in every phase. The RED
baseline is itself higher (17 vs 11) because the harness's three warmup runs
leaked six pipes before the baseline was even taken. Residual GREEN `fdDelta` is
entirely `timerfd`/`eventfd`/`eventpoll` from pool growth, confirmed by the
per-phase breakdown and by phase 4 (another 20 identical runs) showing 0.

---

## Thread accounting (B's acceptance criterion)

```
THREADHARNESS baseline=44
THREADHARNESS after50=44   delta=0
THREADHARNESS after100=44  delta=0  growthFrom50=0
```

Flat across 100 Linux runs — the watcher thread exits when `waitid` returns, so
nothing accumulates. (44 rather than 15 because the fd harness ran first in the
same process and grew the dispatch pool; the point is that it does not grow with
run count.)

---

## Full verification

### Linux (`swift:6.1`)

- `--filter "ProcessRunnerTests|CliExecutorTests"` — **15/15 passed, 5 runs out
  of 5**, no failures in any run.
- `--filter "SBXCoreTests"` — **58/58 passed.**
- fd harness — pipe delta **0** in all four phases.
- thread harness — **0 growth** over 100 runs.

Per the brief, the ~81 `CLIE2E` failures inside the container are an environment
artifact reproducing identically at merge-base and were excluded by filtering.

### macOS

- `swift test --package-path cli` — **138 tests in 27 suites passed.**
- `xcodebuild … -only-testing:sbx-uiTests` — **TEST SUCCEEDED, 0 failed.**
- fd harness — total fds flat at 4 across all phases, delta **0**.

One note on the macOS test count, since it looks like a discrepancy. Runs
reported 329, 328, 328 and 329 passing test-case lines, always with 0 failures
and `** TEST SUCCEEDED **`; the final run against the committed tree is
**329 passed, 0 failed**. Diffing the test-case lists shows a *different* single
test missing from each short log (`PluginApiHandlerTests/sandboxExec_truncated…`
in one, `TerminalSessionStoreTests/cleanupRemovesOnlyStaleFromMultiple` in
another); each passes when run in isolation. A run of the **unmodified** branch
reports 328 as well. It is an xcodebuild log-line reporting artifact under
parallel Swift Testing, present with and without this change, not a skipped or
failing test.

### Final confirmation, against the committed tree

```
Linux   ProcessRunnerTests|CliExecutorTests   15/15 passed  x3 runs  (grandchild 2.021 / 2.039 / 2.029s)
Linux   SBXCoreTests                          58/58 passed
macOS   swift test --package-path cli         138 tests in 27 suites passed
macOS   xcodebuild -only-testing:sbx-uiTests  329 passed, 0 failed, TEST SUCCEEDED
```

---

## Constraints observed

- No test weakened, skipped, retimed, or loosened.
- No synchronous `close()` reachable from inside a readability handler.
- `process = nil` in `releaseHandles` (the `2a9b7cf` launch-failure fix) intact;
  launch-failure phase still leaks 0.
- `nonisolated` on the new `static func`, so the `MainActor`-default Xcode
  project still builds — confirmed by the passing Xcode target, not just SPM.
- Platform API behind `#if os(Linux)`.
- `Package.resolved` left dirty and unstaged. Harness and probes deleted, not
  committed.
- The two known Copilot deferrals (strong `session` capture in the timeout
  closure; unvalidated `maxOutputBytes`) left alone, as instructed.

## Concerns for the owner

**`process.terminationHandler = nil` in `releaseHandles` races with Foundation
invoking it.** Pre-existing — the drain-deadline and timeout paths could already
clear it from another thread while Foundation was about to call it. The `waitid`
watcher does not create the race but does make it reachable on the normal
success path more often, since `releaseHandles` can now run before Foundation's
handler has fired at all. It is a plain stored property on corelibs `Process`
with no synchronization. Not observed to misbehave in ~700 Linux runs across
this session, but it is the kind of thing that shows up once under CI load. Left
alone as out of scope; worth its own look.

**`attemptKill` sees a stale `proc.isRunning`.** After the watcher reports, the
child is a zombie but Foundation still believes it is running until its
socketpair closes, so a timeout landing in that window sends SIGTERM (and
possibly SIGKILL) to a zombie. Harmless in itself, and it is the same window the
already-documented pid-reuse deferral covers, but the window is now wider on
Linux than it was.
