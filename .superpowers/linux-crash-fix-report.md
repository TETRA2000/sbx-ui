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
SPM `SBXCoreTests`/`CLIE2ETests`) passed while only Linux crashed. The
downstream CI noise (`Unexpected end of file during JSON parse`, `CLI exited
4` in several CLIE2E tests) was the same bug — `sbx-ui-cli` dying mid-output —
not a separate issue.

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
`FileHandle`." Separately, `FileHandle`'s internal readability-monitoring
dispatch source operates on a `dup()`'d fd with its own independent
cancel-handler close, and captures `self` only weakly — so it does not keep
the original `FileHandle` alive and does not need to finish canceling before
dealloc/close of the original fd is safe.

This applies uniformly regardless of whether the handle already observed EOF,
so the previous EOF-conditional close (added to avoid racing a live handler
with a concurrent explicit close) is no longer needed — dropping all
references and letting ARC/deinit handle it is simpler and covers every path
(EOF'd, forced/timeout, drain-deadline).

Doc comment on `releaseHandles()` was rewritten to explain the queue
self-deadlock reason (not just "don't race a live handler") so a future
"helpful" re-add of `close()` doesn't reintroduce this.

## Regression guard: fd-leak harness (from commit `2a9b7cf`)

Built a standalone SPM executable in scratchpad
(`/private/tmp/.../scratchpad/fdharness`, path-dependency on `cli`'s
`SBXCore` product, **not committed**) that calls `ProcessRunner.run` directly
and counts `/dev/fd` entries before/after:

- **Launch-failure path**: 50 consecutive `ProcessRunner.run` calls against a
  nonexistent binary (`/nonexistent/binary/that/does/not/exist-<uuid>`),
  `timeout: .seconds(5)`.
- **Successful-run path**: 20 runs, one in five running `cat` over a 200KB
  temp file (>64KB pipe buffer, exercises the EOF-draining path), the rest
  `echo`. 500ms settle before the final fd count.

### Results

| Path | Before this fix (post-`2a9b7cf`, with explicit `close()`) | After this fix |
|---|---|---|
| 50 launch failures | delta: 0 | delta: 0 |
| 20 successful runs (incl. >64KB) | delta: 0 | delta: 0 |

Both before and after are 0 — this fix does not reintroduce the
`2a9b7cf` leak (nilling `process` still happens unconditionally, first thing,
under the lock). The "before" run here is HEAD's `releaseHandles()` (i.e.
after `2a9b7cf`, before this fix) obtained by `git stash push --keep-index --
sbx-ui/Services/ProcessRunner.swift`, rebuilding, running, then `git stash
pop` to restore this fix — verified via `git diff` afterward that the working
tree matched this fix exactly.

Note: this harness runs on macOS, where the bug we're fixing does not
manifest as a crash (Darwin tolerates the self-wait) — it only proves fd
hygiene, not the deadlock fix itself. The deadlock fix is validated by direct
inspection of swift-corelibs-foundation source (above), not by execution.

## Tests run (all macOS — see "Linux unverified" below)

**SPM (Linux-shared code, executed on macOS toolchain):**
```
$ swift build --package-path cli
Build complete! (1.97s)

$ swift test --package-path cli
Test run with 138 tests in 27 suites passed after 5.984 seconds.
```
Re-ran after the stash round-trip (to confirm the restored fix still builds
clean): 138/138 passed again.

**macOS unit tests (Xcode):**
```
$ xcodebuild -project sbx-ui.xcodeproj -scheme "sbx-ui Canary" \
    -destination 'platform=macOS' -only-testing:sbx-uiTests test
** TEST SUCCEEDED **
```
Ran twice (once immediately after the edit, once again as a final check
after the stash round-trip). Both: 329 passed, 0 failed (`grep -c "passed"` /
`grep -c "failed"` on the raw log).

Did not run `sbx-uiUITests` — 19/48 of its tests are known-failing on `main`
already, pre-existing and unrelated, per instructions.

## Explicit statement: Linux is not verified locally

**This machine has no Docker and no Linux toolchain.** All test runs above
(`swift build`/`swift test --package-path cli`, and the Xcode `sbx-uiTests`
target) executed on macOS, where the underlying bug does not crash — Darwin's
Foundation tolerates the same synchronous self-wait that traps on
swift-corelibs-foundation. **These runs cannot prove the crash is fixed on
Linux.** Confidence in the fix rests on: (1) the crash's own stack trace
pointing exactly at `FileHandle.close()` called from inside
`RunSession.tryFinish()` called from inside a readability handler, (2)
swift-corelibs-foundation's own source and comments describing this exact
scenario and prescribing exactly this fix (drop references, let `deinit`
close immediately, bypassing the `.sync` wait), and (3) the fd-leak harness
showing no regression in fd hygiene. Actual confirmation requires the `Linux
CLI Tests` CI job to pass on the next push.

## Constraints honored

- No `nonisolated`/`init`/`static` changes needed — this fix only edits the
  body of a private instance method, no actor-isolation surface changed.
- No hand-editing of `project.pbxproj`.
- Pre-existing unrelated `Package.resolved` working-tree modification left
  untouched and unstaged.
- Fix scoped to `releaseHandles()` only; no unrelated cleanup from
  `docs/process-exec-followups.md` touched.
- fd harness lives entirely under the scratchpad directory, never added to
  the repo or git.
