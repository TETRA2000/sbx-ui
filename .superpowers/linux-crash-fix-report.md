# Linux CI crash fix: ProcessRunner self-deadlock on `FileHandle.close()`

## Summary

`sbx-ui-cli` was crashing with SIGILL on Linux CI (`Linux CLI Tests` job). Root
cause: `RunSession.releaseHandles()` (`sbx-ui/Services/ProcessRunner.swift`)
called `FileHandle.close()` synchronously from a call chain that runs *inside*
a readability handler closure (`markEOF` → `tryFinish` → `releaseHandles`).
On swift-corelibs-foundation, `close()` does `queue.sync { … }` against the
handle's own dispatch-source queue to serialize with any in-flight
readability event — calling it from inside that very event means waiting on
the queue currently executing, which libdispatch's deadlock detector traps as
an illegal instruction (`__DISPATCH_WAIT_FOR_QUEUE__`). Darwin's Foundation
tolerates the same self-wait, which is why every macOS suite (`sbx-uiTests`,
SPM `SBXCoreTests`/`CLIE2ETests`) passed while only Linux crashed.

**This is now verified on real Linux, both locally via Docker (`swift:6.1`,
matching CI's pinned toolchain) and via the actual `Linux CLI Tests` GitHub
Actions job on the pushed commit** — see "Linux verification" below. The fix
eliminates the crash. It also surfaced two **pre-existing, unrelated**
Linux-only timing/lifecycle issues that were previously invisible because the
crash always killed the test process before they could manifest — see
"Two pre-existing issues surfaced, not caused, by this fix" below. This
revises the original premise that all downstream CI noise (`Unexpected end of
file during JSON parse`, `CLI exited 4`, byte-count mismatches) was "the same
bug" — some of it is, some of it is this second, distinct drain-timing issue.

## The fix

`sbx-ui/Services/ProcessRunner.swift`, `RunSession.releaseHandles()`: removed
the explicit `try? out?.close()` / `try? err?.close()` calls entirely (and
the now-unneeded EOF-conditional extraction of `out`/`err`). The method now
only drops strong references: nils `stdoutHandle`, `stderrHandle`, clears
`process.terminationHandler`, and nils `process`.

Why this is sufficient: `process` was the only thing (besides the two ivars
we're also nilling) keeping `Process.standardOutput`/`standardError` — the
`Pipe`s, and therefore their `FileHandle`s — alive. Once nothing references a
`FileHandle`, its `deinit` closes the underlying fd. Verified directly against
swift-corelibs-foundation's source
(`Sources/Foundation/FileHandle.swift`, fetched from
`swiftlang/swift-corelibs-foundation@main`):

```swift
deinit {
    // .close() tries to wait after operations in flight on the handle queue, if one exists, and then close. It does so by sending .sync { … } work to it.
    // if we try to do that here, we may end up in a situation where:
    // - the last reference is held by the handle queue;
    // - the last operation holding onto the handle finishes, and the block is released;
    // - the handle is released;
    // - the handle's deinit is invoked;
    // - deinit tries to .sync { … } to serialize the work on the handle queue, _which we're already on_
    // - deadlock! DispatchQueue's deadlock detection triggers and crashes us.
    // since all operations on the handle queue retain the handle during use, if the handle is being deinited, then there are no more operations on the queue, so this is serial with respect to them anyway. Just close the handle immediately.
    try? _immediatelyClose(closeFd: _closeOnDealloc)
}
```

This is *exactly* the crash scenario, described almost verbatim by upstream,
with the documented fix being precisely "let dealloc close it directly,
skipping the synchronous queue wait." `close()` itself is `performOnQueueIfExists
{ try _immediatelyClose() }` (the `.sync` call this crashed on); `deinit`
bypasses that and calls `_immediatelyClose` directly. Also confirmed
Pipe-created handles are constructed with `closeOnDealloc: true`
(`self.fileHandleForReading = FileHandle(fileDescriptor: fds.pointee,
closeOnDealloc: true)`), matching the file's pre-existing doc comment that
"the underlying fd closes on its own once nothing references the
`FileHandle`."

This applies uniformly regardless of whether the handle already observed EOF,
so the previous EOF-conditional close (added to avoid racing a live handler
with a concurrent explicit close) is no longer needed — dropping all
references and letting ARC/deinit handle it is simpler and covers every path
(EOF'd, forced/timeout, drain-deadline).

Doc comment on `releaseHandles()` was rewritten to explain the queue
self-deadlock reason (not just "don't race a live handler") so a future
"helpful" re-add of `close()` doesn't reintroduce this.

## Linux verification

Docker (`swift:6.1`, matching `.github/workflows/linux-cli-tests.yml`'s pinned
`swift-version: "6.1"`) became available mid-task. Ran both a local RED→GREEN
repro and confirmed against the real CI job on the pushed commit.

### RED: crash reproduced on unmodified `ed7f334`

Isolated worktree (`git worktree add /tmp/red-repro ed7f334`, pre-fix code,
confirmed via `grep close()`), run inside the container:

```
docker run --rm -v /tmp/red-repro:/src -w /src swift:6.1 \
  swift test --package-path cli
```

Crashed. Full backtrace (captured twice, across two separate runs — once with
a custom `--scratch-path`, once with the default path):

```
*** Program crashed: System trap at 0x0000ffff9c5e387c ***
Thread 1 crashed:
 0  __DISPATCH_WAIT_FOR_QUEUE__ + 332                                    in libdispatch.so
 1  _dispatch_sync_f_slow + 159                                          in libdispatch.so
 2  DispatchQueue.sync(execute:) + 147                                   in libswiftDispatch.so
 3  specialized FileHandle.performOnQueueIfExists(_:) + 171              in libFoundation.so
 4  FileHandle.close() + 23                                              in libFoundation.so
 5  RunSession.releaseHandles() + 987      ProcessRunner.swift:340:19
 6  RunSession.tryFinish() + 2839          ProcessRunner.swift:314:9
 7  RunSession.markEOF(isStdout:) + 283    ProcessRunner.swift:203:9
 8  closure #2 in closure #1 in closure #1 in static ProcessRunner.run(...) ProcessRunner.swift:95:33
 9  partial apply for closure #1 in FileHandle.readabilityHandler.setter    in libFoundation.so
10  closure #1 in FileHandle.monitor(forReading:resumed:handler:)          in libFoundation.so
...
14  _dispatch_lane_serial_drain                                          in libdispatch.so
16  _dispatch_worker_thread                                              in libdispatch.so
```

This is an exact match to the reported crash signature. The default-path run
(no `--scratch-path`, so `swift-testing`'s normal parallel test execution ran
undisturbed) hit **8 independent crashes** at the identical
`__DISPATCH_WAIT_FOR_QUEUE__` instruction across concurrently-running tests
before the crash-reporting machinery itself gave up with a secondary `Fatal
error: Index out of range`. The process never printed a "Test run with N
tests" completion line — it never finished. This proves the bug triggers
reliably under Linux's default concurrent test execution, not as a rare edge
case, and confirms the diagnosis unambiguously.

### GREEN: no crash with the fix, on Linux

Isolated worktree (`git worktree add /tmp/green-repro 6529526`, fix commit,
confirmed via `grep close()` — no explicit `close()` calls remain), same
container command:

```
docker run --rm -v /tmp/green-repro:/src -w /src swift:6.1 \
  swift test --package-path cli
```

No crash. Process completed normally: `Test run with 138 tests failed after
9.452 seconds with 5 issues.` (5 issues — see next section; this is a normal
test-assertion failure summary, not a crash — no backtrace, no
`__DISPATCH_WAIT_FOR_QUEUE__`, no `Program crashed`).

### GREEN, independently confirmed on real CI

The commit was pushed before Docker became available on this machine (per the
original brief's ordering), so real CI already ran against it:
`gh pr checks 29` / `gh run view 31342231609 --log` for the `Linux CLI Tests`
job on commit `6529526` (`ubuntu-latest`, real GitHub-hosted runner, not
Docker/emulation):

- **No crash.** The job ended with `Test run with 138 tests failed after
  11.313 seconds with 2 issues` + `##[error]Process completed with exit code
  1` — a normal test-failure exit, not a SIGILL/backtrace.
- **136/138 passed.** The 2 failures were `largeStdoutDoesNotDeadlock()` at
  `ProcessRunnerTests.swift:31` (983040/1000000 bytes) and
  `grandchildHoldingPipeDoesNotHang()` at `ProcessRunnerTests.swift:240`
  (elapsed 5.002s, assertion requires `< 4.5`) — both instances of the
  drain-timing issue described below, not crashes.

This is stronger evidence than the local Docker run (which showed 5/138
failures under heavier local resource contention) and is the most direct
proof available: the actual CI environment, on the actual pushed fix, no
longer crashes.

## Two pre-existing issues surfaced, not caused, by this fix

Both were invisible before this fix because the SIGILL always killed the test
process first. Neither is touched by this diff. Reporting rather than fixing,
per the brief's "keep the change minimal and focused" — both would need their
own design discussion.

### 1. Large-output drain-timing sensitivity on Linux (pre-existing)

`largeStdoutDoesNotDeadlock`, `largeStderrDoesNotDeadlock`,
`largeStdoutAndStderrSimultaneously`, and `grandchildHoldingPipeDoesNotHang`
(all in `ProcessRunnerTests.swift`, plus one in `CliExecutorTests.swift`)
failed intermittently on Linux (2/138 on real CI, up to 5/138 under local
Docker contention) with byte counts short of the expected total, and one
elapsed-time assertion running past its 4.5s upper bound.

Root cause, confirmed against swift-corelibs-foundation source
(`FileHandle.swift`, `_readDataOfLength`): on Linux, `FileHandle.availableData`
for a pipe reads **at most one 8192-byte block per call** (`readBlockSize =
1024 * 8` for non-regular files, and the read loop breaks unconditionally
after one `read(2)` when `untilEOF == false`, which is how `availableData`
calls it). Darwin's real Foundation.framework does not have this cap. All
observed shortfalls were exact multiples of 8192 (117, 118, 119, 30/34 blocks
in local runs; 120 blocks — 983040 bytes — on CI) and all were under one 64KB
pipe capacity, meaning only a handful of additional dispatch-source firings
were needed after the child exited, within `ProcessRunner`'s 2-second
`drainGrace` — and they didn't consistently happen in time under load. This
is a resource/scheduling-sensitivity problem (8KB-per-call ceiling × a fixed
2s grace window × Linux dispatch scheduling under contention), not a logic
bug in the code this diff touches.

**This is mechanically impossible to be caused by this fix.**
`RunSession.tryFinish()` (`ProcessRunner.swift:291-316`) constructs the
`ProcessOutput` — the exact byte counts asserted on — under the lock, and
only *afterward* calls `releaseHandles()`. This diff only changes the body of
`releaseHandles()`, which runs after the counts are already frozen. Nothing
in the change can affect these numbers. A pre-fix Linux baseline for these
specific tests is unobtainable by direct comparison, because the crash sits
on the same completion path and pre-fix runs die before these tests can ever
report a count — the orthogonality argument has to be (and is) mechanical,
not empirical.

Not in `docs/process-exec-followups.md` — newly discovered, not a
previously-triaged deferred item. Has several viable fixes (loop
`availableData` until a short read inside the handler, raise `drainGrace`,
read via `read(2)` directly instead of `availableData`), each with
cross-platform implications and its own test consequences (raising
`drainGrace` naively would break `grandchildHoldingPipeDoesNotHang`'s
*upper* bound of 4.5s) — a design decision, not something to guess at inside
this fix.

### 2. fd growth on the un-EOF'd-handle path, measured on Linux (pre-existing, not a regression)

Team lead's fd-leak regression harness (below) showed non-zero deltas on
Linux for both paths. Investigated and confirmed **identical before and
after this fix** — not a regression:

**Mechanical proof.** For any handle that has not observed EOF by the time
`releaseHandles()` runs (both the launch-failure path — no child ever starts,
so EOF never arrives — and the drain-deadline path in the harness's
>64KB-output runs), the pre-fix code's conditional close
(`stdoutAtEOF ? stdoutHandle : nil`) already evaluated to `nil` and skipped
calling `.close()`. For exactly this input, pre-fix and post-fix
`releaseHandles()` bodies are byte-for-byte equivalent (both just nil the
three ivars under the lock). The diff can only differ in behavior for a
handle that *did* observe EOF — which is precisely the deadlock-crash path
this fix addresses, not the fd-count path.

**Empirical confirmation**, same container, same harness, pre-fix worktree
(`ed7f334`) vs. fix worktree (`6529526`):

| Path | Pre-fix (`ed7f334`) on Linux | Post-fix (`6529526`) on Linux |
|---|---|---|
| 50 launch failures | delta: 10 | delta: 10 (exact match) |
| 20 successful runs (incl. >64KB) | delta: 58 | delta: 78 (same order of magnitude; both runs also showed 4/4 large-output reads truncated via the drain-timing issue above — the exact delta varies run to run with how many dispatch-source firings land before the 2s grace timeout, not with this diff) |

The launch-failure delta is an exact match. The successful-run delta varies
between runs on both pre-fix and post-fix code (consistent with docker/VM
timing noise interacting with the same drain-timing issue above, not with
this diff).

Likely explanation for *why* Linux behaves differently from Darwin here
(where the equivalent harness runs showed delta 0 on both paths, see below):
swift-corelibs-foundation's `FileHandle.monitor(forReading:)` creates its
dispatch source on a **`dup()`'d fd**, independent of the `FileHandle`'s own
`_fd`, with a `setCancelHandler` that only closes that duplicate — and GCD
dispatch sources are documented to require an explicit `.cancel()` before
their resources are released, independent of Swift ARC. If a handle's
`readabilityHandler` is never nilled (because EOF was never observed), the
source is never canceled, and the duplicated fd is not closed — a
pre-existing Linux-specific consequence of `docs/process-exec-followups.md`'s
already-documented "Retain cycle on an un-EOF'd handle" section, which
appears to have only been characterized/verified for the "eventual grandchild
exit" recovery scenario, not for Linux's dispatch-source cancellation
requirements or for the launch-failure case specifically. Not fixed here —
same "report, don't fix" scope reasoning as issue 1.

## Regression guard: fd-leak harness

Standalone SPM executable in scratchpad
(`/private/tmp/.../scratchpad/fdharness`, path-dependency on `cli`'s
`SBXCore` product, **not committed**) that calls `ProcessRunner.run` directly
and counts open file descriptors before/after (`/dev/fd` entries, works
identically on macOS and Linux/procfs):

- **Launch-failure path**: 50 consecutive `ProcessRunner.run` calls against a
  nonexistent binary (`/nonexistent/binary/that/does/not/exist-<uuid>`),
  `timeout: .seconds(5)`.
- **Successful-run path**: 20 runs, one in five running `cat` over a 200KB
  temp file (>64KB pipe buffer, exercises the EOF-draining path), the rest
  `echo`. 500ms settle before the final fd count.

### macOS results

| Path | Before this fix (post-`2a9b7cf`, with explicit `close()`) | After this fix |
|---|---|---|
| 50 launch failures | delta: 0 | delta: 0 |
| 20 successful runs (incl. >64KB) | delta: 0 | delta: 0 |

Obtained via `git stash push --keep-index -- sbx-ui/Services/ProcessRunner.swift`
(reverts to pre-fix code in the working tree), rebuild, run, then `git stash
pop` to restore the fix — verified via `git diff` afterward that the working
tree matched the fix exactly.

### Linux results

See "Two pre-existing issues surfaced" §2 above: delta 10/10 (launch
failures, exact match pre- vs. post-fix) and delta 58/78 (successful runs,
same order of magnitude, variance attributable to the drain-timing issue in
§1, not to this diff). Neither is a regression introduced by this fix.

## Tests run

**SPM (Linux-shared code):**

macOS:
```
$ swift build --package-path cli
Build complete! (1.97s)

$ swift test --package-path cli
Test run with 138 tests in 27 suites passed after 5.984 seconds.
```
Ran twice on macOS (once immediately after the edit, once after the
stash round-trip used for the fd-harness A/B test) — 138/138 both times.

Linux (Docker, `swift:6.1`): see "Linux verification" above — no crash;
133-136/138 pass depending on load, all remaining failures attributable to
the pre-existing drain-timing issue in §1, not this diff.

Linux (real CI, `ubuntu-latest`, commit `6529526`): 136/138 pass, no crash
(see above).

**macOS unit tests (Xcode):**
```
$ xcodebuild -project sbx-ui.xcodeproj -scheme "sbx-ui Canary" \
    -destination 'platform=macOS' -only-testing:sbx-uiTests test
** TEST SUCCEEDED **
```
Ran twice locally: 329/329 passed, 0 failed, both times.

Real CI's `Unit Tests` (macOS) job on commit `6529526` *did* fail, but on
`PluginExecutionTests.pluginHostStartsAndStopsProcess()` timing out at
60.000s — a test in a completely different file (`PluginHost`, which does
not use `ProcessRunner` at all; confirmed via
`grep -rl ProcessRunner sbx-ui/Services/` — only `ProcessRunner.swift`,
`CliExecutor.swift`, `SbxServiceProtocol.swift`, and
`DefaultEditorDocumentProvider.swift` reference it, `PluginHost.swift` is not
among them). The CI log shows an unrelated test
(`TerminalSessionStoreTests/sessionLookupReturnsNilForUnknown()`) taking
64.906 seconds immediately beforehand, versus ~0.4s for its neighbors —
consistent with a stalled GitHub Actions runner, not a deterministic bug.
This diff does not touch `PluginHost.swift`, and the local run above passed
this exact test twice.

Did not run `sbx-uiUITests` — 19/48 of its tests are known-failing on `main`
already, pre-existing and unrelated, per instructions.

## Constraints honored

- No `nonisolated`/`init`/`static` changes needed — this fix only edits the
  body of a private instance method, no actor-isolation surface changed.
- No hand-editing of `project.pbxproj`.
- Pre-existing unrelated `Package.resolved` working-tree modification left
  untouched and unstaged.
- Fix scoped to `releaseHandles()` only; no unrelated cleanup from
  `docs/process-exec-followups.md` touched, and the two newly-discovered
  issues above were investigated and reported, not fixed.
- fd harness lives entirely under the scratchpad directory, never added to
  the repo or git. Verification worktrees (`/tmp/red-repro`,
  `/tmp/green-repro`, `/tmp/red-repro2`) were removed after use
  (`git worktree remove --force`).
