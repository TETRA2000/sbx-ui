# Linux data loss in `ProcessRunner` — investigation report

Branch `fix/process-exec-deadlock`, starting at `6529526`. Container: `swift:6.1`
(Ubuntu 24.04, aarch64), matching CI's pinned toolchain.

## Summary

Two independent Linux-only defects were reported. Both are now diagnosed with
positive controls. **Neither had the cause proposed in the brief.**

| # | Symptom | Root cause | Status |
|---|---------|-----------|--------|
| A | Silent data loss (~25–50k of 1,000,000 bytes) | Edge-triggered epoll + 8KB-capped `availableData` | **FIXED** |
| B | Drain deadline doesn't complete the run (5.007s) | corelibs `Process` exit detection gated on a socketpair inherited by grandchildren | **DIAGNOSED, NOT FIXED** — owner decision |
| C | *(new)* 2 fd leaked per successful run on Linux | Pre-existing, from `6529526` | **REPORTED** — pre-existing, not from this work |

## Reproduction (baseline, at `6529526`)

```
largeStdoutAndStderrSimultaneously  stdout 999424, stderr 974848  != 1_000_000  FAIL after 2.056s
largeStderrDoesNotDeadlock          stderr 974848                 != 1_000_000  FAIL after 2.056s
largeStdoutDoesNotDeadlock          stdout 950272                 != 1_000_000  FAIL after 2.057s
grandchildHoldingPipeDoesNotHang    elapsed 5.042659              < 4.5         FAIL after 5.044s
```

The **2.056s** figure was the first real clue and it refuted hypothesis 1 before
any instrumentation: 2s is exactly `drainGrace`. The runs were completing via
`drainDeadlinePassed`, which means `stdoutAtEOF` was never set — so no empty
`availableData` was ever delivered. A spurious empty read would have completed
the run *immediately* on `exited`, not 2s later.

---

## A. Silent data loss — FIXED

### Hypothesis 1 (from the brief): REFUTED

> "`availableData` returning empty does not reliably mean EOF on
> swift-corelibs-foundation."

Refuted twice over. The timing argument above, and directly: instrumenting every
readability callback shows **no empty read ever arrives**. The handler simply
stops being called.

### Evidence

A probe logging every callback plus `ioctl(FIONREAD)` on the read fd:

```
ev#0   t=0.0018 bytes=8192 cum=8192
...
ev#116 t=0.0050 bytes=8192 cum=958464     <- last event, ever
terminationHandler status=0 total=958464 events=117
poll#0  t=0.2524 total=958464 events=117 FIONREAD=41536
poll#7  t=2.0230 total=958464 events=117 FIONREAD=41536
poll#23 t=6.1004 total=958464 events=117 FIONREAD=41536
```

Three facts:

1. **Every callback reads exactly 8192 bytes.** swift-corelibs-foundation's
   `FileHandle.availableData` caps a pipe read at 8KB, so one `availableData`
   per event can never drain a pipe that has more buffered.
2. **41,536 bytes sit in the pipe forever.** `FIONREAD` is constant for 6+
   seconds. The data is not lost in flight — it is readable and never read.
3. **No further event, and no EOF.** Events freeze at 117 even though the writer
   has exited and closed its end.

### Root cause

libdispatch's Linux (epoll) read source is **edge-triggered**: it fires on the
*transition* to readable, not while data merely remains buffered. Because
`availableData` returns at most 8KB, each callback leaves bytes behind. While the
child keeps writing, each new write is a fresh edge, so the loop limps along and
keeps up — badly. The moment the child stops writing and exits, there is no
further edge: the handler is never called again, the residual bytes are stranded,
and **the EOF transition is never observed either**.

The run therefore can only finish via the post-exit drain deadline, 2s later,
with short data and no error. Darwin's kqueue `EVFILT_READ` source is
level-triggered, which is why every macOS suite passed.

This was a genuine production bug, not a test artifact: on Linux, any `sbx`
command emitting more than a pipe buffer's worth of output was silently
truncated, and every such call paid a 2s latency tax.

### Fix

`sbx-ui/Services/ProcessRunner.swift` — `drainingHandler(for:session:isStdout:)`.
Set `O_NONBLOCK` on the pipe read end and, on every readability event, drain with
raw `read(2)` until `EAGAIN`. Both handlers changed identically.

Why this is correct:

- Draining to `EAGAIN` is the standard edge-triggered contract: once the fd is
  drained, the next write is guaranteed to produce a fresh edge. Nothing can be
  stranded.
- `read(2)` returning `0` is **unambiguous** EOF. `availableData` on a
  non-blocking fd reports `EAGAIN` as empty `Data`, indistinguishable from EOF —
  so raw `read` also removes the ambiguity hypothesis 1 was worried about,
  rather than merely working around it.
- It is one portable mechanism, not a platform fork. Darwin's level-triggered
  source is unaffected by draining more per event (it just gets fewer events).
- No `close()` on any path, so the `6529526` SIGILL cannot return.
  `releaseHandles()` is untouched.

Proven in isolation before being adopted: a probe using this exact strategy
recovered **1,000,000/1,000,000 bytes** with a clean EOF and `FIONREAD=0`, in 17
events / 16 chunks instead of 122+ starved 8KB reads.

---

## B. Grandchild drain deadline — DIAGNOSED, NOT FIXED

### Hypothesis 2 (from the brief): CONFIRMED, with a mechanism

> "`Process.terminationHandler` fires later on Linux than on Darwin."

Confirmed, and the mechanism is more specific and more awkward than "later".

### Evidence

The direct child really does exit immediately — `time sh -c 'sleep 5 & printf hi'`
is `real 0m0.001s`, and `/proc/<pid>/stat` shows state `Z` within 0.1s. But:

```
[0.0013] launched pid=59
[0.0018] stdout bytes=2
[0.1067] /proc/59 state=Z (zombie: child really exited)
[5.0071] waitUntilExit returned
[5.0073] terminationHandler status=0
```

Redirecting the grandchild's stdio away from our pipes entirely
(`sleep 5 >/dev/null 2>/dev/null </dev/null &`) changes nothing — still 5.0094s.
So it is not our pipes. Listing the grandchild's descriptors:

```
sleep pid=40
  0 -> /dev/null
  1 -> pipe:[369]
  2 -> pipe:[370]
 18 -> socket:[372]      <- parent holds socket:[371], the other half
```

**Positive control** — a purpose-built grandchild that holds our stdout/stderr
but closes every other inherited fd:

```
S6 grandchild holds our pipes but NOT the socketpair:
  [0.0009] launched
  [0.0013] stdout bytes=2
  [0.0045] terminationHandler status=0     <- prompt
S7 baseline, grandchild holds everything:
  [0.0040] stdout bytes=2
  [5.0144] terminationHandler status=0     <- 5s
```

### Root cause

swift-corelibs-foundation's `Process` detects child exit by watching a
**socketpair the child inherits** for EOF, not by `waitpid`. Any grandchild
inherits that descriptor too, so `terminationHandler` — and `waitUntilExit()` —
do not fire until *every descendant holding it* has exited.

Consequently `markExited` is not called until 5s; the 2s drain timer starts at
5s; by then both pipes have long since hit real EOF, so the run completes at
~5.03s via the EOF path. The drain deadline is not broken — it never gets to
start.

**Critically, the exit *status* is unavailable until that same moment.** No
restructuring of `RunSession` can produce a successful `ProcessOutput` at 2s
while `Foundation.Process` is the source of the exit code. This is why the fix
is an architecture decision and not a code tweak.

Like A, this is a production defect and not just a failing test: on Linux any
`sbx` command that leaves a background process holding stdout blocks until that
process exits, or until the 30s timeout converts a success into a `timedOut`
error.

### Options for the owner (NOT implemented — flagged per the brief)

1. **`waitid(P_PID, pid, WEXITED | WNOWAIT)` on a background thread.** Probed and
   working: returned the status at **0.0016s** in the grandchild scenario, and at
   the correct `si_status=7` for `sh -c 'exit 7'`. `WNOWAIT` leaves the zombie
   waitable, so Foundation's socketpair machinery still fires normally afterwards
   (verified: `terminationHandler status=7` still arrived). Roughly 15 lines,
   Linux-only, plus an `ECHILD` fallback for when Foundation reaps first.
   Cost: one blocked thread per run on Linux.
2. **Replace `Foundation.Process` with `posix_spawn` + `waitpid`.** Full control
   and prompt exit detection on both platforms, but a substantially larger change
   (file actions, env marshalling, cwd, signal handling) and correspondingly
   riskier.

Recommendation: option 1. It is contained, additive, and independently verified.

---

## C. Pre-existing fd leak on Linux (new finding, NOT introduced here)

The required fd harness **fails on Linux**, and fails identically without this
change, so it is not a regression from this work:

```
                        with my fix          at HEAD 6529526
50 launch failures      delta=0              delta=0
20 small runs           delta=40             delta=45
20 big runs (200KB)     delta=40             delta=3 *
```

\* `3` only because HEAD aborts that phase early on the first short read
(`SHORT READ 155648`) — the data-loss bug again.

macOS is clean (`delta=0` for both phases). The leaked descriptors are ~2 pipe
fds per **successful** run — launch failures leak nothing, because nothing is
spawned. A control using raw `Foundation.Process` + `Pipe` + `waitUntilExit()`
leaks nothing, so this is `ProcessRunner`'s teardown, not Foundation itself.

This is the ARC half of commit `6529526`: dropping `FileHandle.close()` in favour
of "ARC will close it" holds on Darwin but **not** on Linux, where the read-end
handles are evidently still retained when `releaseHandles()` drops our
references, so `deinit` never runs.

Not fixed here, deliberately: the fix has to touch `releaseHandles()` — the exact
code the brief fenced off — and the safe shape (closing off the handler's own
queue, e.g. `DispatchQueue.global().async { try? h.close() }`, which is *not*
reachable-from-inside-the-handler and so cannot resurrect the SIGILL) deserves
its own commit and its own verification. Flagged for the owner.

---

## Verification

### Linux (`swift:6.1` container) — 10 consecutive runs, `--filter "ProcessRunnerTests|CliExecutorTests"`

All three data-loss tests pass in every run, in **0.017–0.056s** (was 2.05s with
short data):

```
run 1: largeStdoutDoesNotDeadlock 0.025s  largeStderrDoesNotDeadlock 0.026s  largeStdoutAndStderrSimultaneously 0.026s
run 6: 0.017s / 0.020s / 0.019s
run 9: 0.021s / 0.023s / 0.024s
...
every run: ✘ grandchildHoldingPipeDoesNotHang (elapsed ~5.03s) — the only failure
```

`Test run with 15 tests failed ... with 1 issue` — the single issue is symptom B
in every run. All `CliExecutorTests` pass.

Serialized (`--no-parallel`, x3) — large tests 0.003–0.019s, no drain-deadline
fallbacks:

```
no-parallel run 1: largeStdoutDoesNotDeadlock 0.010s largeStderrDoesNotDeadlock 0.010s largeStdoutAndStderr 0.008s
```

### Stress on the real `ProcessRunner` (Linux, 300 runs)

```
A cat-1MB:            runs=150 shortReads=0 drainDeadlineFallbacks=0 maxElapsed=0.025
B sh-pipeline-300k:   runs=150 shortReads=0 drainDeadlineFallbacks=0 maxElapsed=0.022
```

One parallel run showed a `largeStdoutDoesNotDeadlock` passing in 2.049s (correct
bytes, drain-deadline completion). Explained and benign: Swift Testing runs the
suite in one process, so when `grandchildHoldingPipeDoesNotHang` forks
`sleep 5 &`, that grandchild inherits the pipe write end of whichever test is
running concurrently, delaying its EOF. `--no-parallel` shows zero such
fallbacks, and the 300-run sequential stress shows zero. Data is never lost —
`drainGrace` covers it, which is exactly what it is for.

### macOS

```
swift test --package-path cli            -> Test run with 138 tests in 27 suites passed after 5.831 seconds
xcodebuild ... -only-testing:sbx-uiTests -> ** TEST SUCCEEDED **  (328 test cases passed, 0 failed)
fd harness                               -> baseline 4, after 50 launch failures delta=0,
                                            after 20 successful runs (2,000,000 bytes) delta=0
                                            FD HARNESS PASS
```

### fd harness (both platforms)

macOS: PASS, deltas 0. Linux: FAILS, ~2 fds per successful run — pre-existing,
see section C, reproduced identically at `6529526`.
