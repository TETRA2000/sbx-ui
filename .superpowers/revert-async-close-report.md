# Revert async `close()` in `releaseHandles()` — SIGSEGV fix

## Summary

Commit `b954743` ("Close EOF'd pipe handles explicitly — ARC doesn't on
Linux") fixed a real but benign Linux pipe-fd leak by having
`RunSession.releaseHandles()` close EOF'd handles asynchronously on
`DispatchQueue.global()`. That introduced a worse bug: Linux CI crashed with
`Bad pointer dereference` inside `_dispatch_event_loop_drain`, reached from
the async close block.

Root cause: `readabilityHandler = nil` only *requests* cancellation of the
handle's underlying dispatch source — libdispatch tears it down
asynchronously, on its own schedule. Closing the fd from another thread while
that teardown is still in flight is a use-after-free. This is the second
failed shape for closing here; the first (`6529526`, closing synchronously)
self-deadlocked with SIGILL for a different reason (`queue.sync` against the
handle's own in-flight readability event).

This change reverts `releaseHandles()` to close nothing at all — the shape
`6529526` left it in — and records both failure modes in the doc comment and
in `docs/process-exec-followups.md` so a third attempt doesn't repeat either
mistake.

## What changed

`sbx-ui/Services/ProcessRunner.swift`:
- `releaseHandles()` no longer collects `closable` handles or dispatches an
  async `close()`. It only drops the four strong references (`stdoutHandle`,
  `stderrHandle`, `process.terminationHandler`, `process`), exactly as
  `6529526` left it.
- `stdoutAtEOF`/`stderrAtEOF` are untouched — still used by `tryFinish` to
  decide when a run is done. They're just no longer read inside
  `releaseHandles()`.
- The doc comment now states both failure modes (SIGILL from synchronous
  close, SIGSEGV from asynchronous close) with their symptoms, and explains
  that the fd is deliberately left to ARC — closed immediately on Darwin,
  leaked (~2 fds/successful run) on Linux, which is accepted.
- **Not touched**: `startExitWatcher`'s Linux `waitid` thread (`c5787d8`),
  the EAGAIN drain loop (`f6660e7`), `markExited`'s idempotency guard, the
  launch-failure `process = nil` fix (`2a9b7cf`).

`docs/process-exec-followups.md`:
- The entry `b954743` added claimed the leak was fixed. Corrected to record
  it as an open, accepted Linux issue: both failed close attempts with their
  crash signatures, why the practical impact is low (short-lived
  `sbx-ui-cli` process, so the leak can't accumulate within one invocation),
  and the actual fix for whoever takes it on — own an explicit
  `DispatchSource.makeReadSource(fileDescriptor:)` per pipe instead of
  `FileHandle.readabilityHandler`, so the fd can be closed race-free from the
  source's `setCancelHandler`.

## Verification

### Linux (Docker `swift:6.1`, matching CI toolchain)

Full, untargeted suite (`swift test --package-path cli --scratch-path
/scratch`, no `--filter`) run **twice**: once with the temp fd harness
present, once after removing it. `ProcessRunnerTests`/`CliExecutorTests` were
additionally run **twice more** in isolation
(`--filter "ProcessRunnerTests|CliExecutorTests"`) — 4 green passes of those
two suites total, across 3 separate `swift test` invocations logged to disk.

- **Crash-signature grep** (`Program crashed|Illegal instruction|System
  trap|Bad pointer dereference|SIGILL|SIGSEGV`) across all **3 captured log
  files** (both full runs + the filtered-repeat run): **0 occurrences**.
- `ProcessRunnerTests` + `CliExecutorTests`: **green in all 4 passes**, no
  flakes.
- `SBXCoreTests` (unit + integration, non-CLIE2E): all green, both full runs.
- `CLIE2ETests`: ~100 issues per full run, same as the pre-existing baseline
  — see "Container environment gap" below. Confirmed as environmental, not a
  regression from this change. **Caveat**: as that section shows, every
  CLIE2E test failed at `Exec format error` before ever exec'ing the ELF
  `sbx-ui-cli` binary, so these local runs never exercised the code path
  where the original SIGSEGV actually manifested (inside the spawned
  `sbx-ui-cli` process). The 0-crash-signature result here is still real
  evidence — `ProcessRunnerTests`/`CliExecutorTests`/`SBXCoreTests` exercise
  the identical `ProcessRunner` code in-process, many times over — but CI's
  `Linux CLI Tests` job (which does successfully spawn the compiled binary)
  is the authoritative confirmation for the original crash context. Pushing
  so CI can do that.

fd harness (temporary, not committed — see below): isolated
`--filter ZZFDHarnessTests` run, using `fstat()` + `S_IFIFO` to count pipe
fds via `/proc/self/fd`:

```
baseline                  pipes=17
phase1 launchFailures=50  pipes=17  delta=0     <- 2a9b7cf fix intact
phase2 smallRuns=20       pipes=57  delta=40    <- 2 fds/run, accepted leak
phase3 bigRuns=20         pipes=97  delta=80    <- another 40 (2/run)
phase4 smallRuns=20       pipes=137 delta=120   <- another 40 (2/run)
```

Exactly the accepted ~2 pipe fds leaked per successful run, consistently
across phases — matches `b954743`'s own RED baseline exactly (same 17-pipe
starting point, same 40-per-20-runs rate), confirming the revert restored
the exact pre-`b954743` behavior.

### macOS

- `swift build --package-path cli` / `swift test --package-path cli`:
  **138/138 tests passed**, 27 suites.
- `xcodebuild test -project sbx-ui.xcodeproj -scheme "sbx-ui Canary"
  -destination 'platform=macOS' -only-testing:sbx-uiTests`:
  **329/329 tests passed**, `** TEST SUCCEEDED **`.
- fd harness (same file, `/dev/fd` + `fstat`/`S_IFIFO` on Darwin, with a
  settle-poll to avoid catching Process/Pipe autorelease teardown mid-flight):

```
baseline                  pipes=3
phase1 launchFailures=50  pipes=3  delta=0
phase2 smallRuns=20       pipes=3  delta=0
phase3 bigRuns=20         pipes=3  delta=0
phase4 smallRuns=20       pipes=3  delta=0
```

Flat at baseline in every phase — Darwin's `deinit` still closes the fd
immediately once references drop, so there's no leak there and the
launch-failure fix (`2a9b7cf`) is unaffected.

One measurement note: a first pass without the settle-poll showed a
transient +300 pipes right after the 50-launch-failure loop on macOS, which
fully cleared by the next phase measurement (back to baseline, no
accumulation across phases 2–4). That's Darwin's `Process`/`Pipe`
autorelease teardown not being synchronous with the `await` returning under
a tight unyielded loop — a measurement artifact, not a leak. Added a
poll-until-stable helper (20× 50ms) to the harness and reconfirmed flat
zeros; not a code change to `ProcessRunner` itself.

The fd-harness test file (`ZZFDHarness.swift`) was temporary, used only for
this verification, and has been deleted — not committed, per the "don't
commit harnesses" constraint.

## Container environment gap (brief investigation, as requested)

Why `CLIE2ETests` fail locally in this Docker container but pass on CI:
`CLIE2EHelpers.resolveBinary()` hardcodes
`<projectRoot>/cli/.build/debug/sbx-ui-cli` (falling back to `release`) — it
does not know about `--scratch-path`. The Docker command used for this
verification (as given) passes `--scratch-path /scratch` so the container's
own Linux build artifacts land under `/scratch`, not
`<root>/cli/.build/debug/`. But this repo checkout had already been built
natively on macOS earlier in the same session
(`swift build --package-path cli`), which left a real Mach-O arm64 binary at
`cli/.build/debug/sbx-ui-cli` on the host — confirmed via `file`:

```
cli/.build/debug/sbx-ui-cli: Mach-O 64-bit executable arm64
```

That path is bind-mounted straight into the container at
`/src/cli/.build/debug/sbx-ui-cli`. `resolveBinary()` finds it (it *is*
executable-file-true) and picks it over the correctly-built Linux ELF binary
sitting under `/scratch`, so every `CLIE2ETests` spawn fails immediately with
`Exec format error` (`ENOEXEC`) — before ever reaching the code this branch
touches. CI doesn't hit this because a CI Linux runner never has a prior
native macOS build sitting at that same repo path. This is a local
dev-loop-only gap (mixing a native macOS SPM build with a `--scratch-path`
Docker Linux build against the same checkout), not a bug introduced by this
branch, and not fixed here per the "don't sink significant time into it"
guidance — noted for whoever wants a real local CLIE2E loop later (fix would
be either not redirecting `--scratch-path` for a dedicated Linux checkout, or
teaching `resolveBinary()` to check the binary's ELF/Mach-O magic bytes
rather than just executability).

## Concerns / follow-ups

- The Linux pipe leak (~2 fds/successful run) is now openly accepted and
  documented rather than silently reintroduced — no further action needed
  unless someone wants to build the `DispatchSource`-based owner described in
  `docs/process-exec-followups.md`.
- Left untouched per constraints: the strong `session` capture in the
  timeout closure, and unvalidated `maxOutputBytes` — both previously
  deferred Copilot findings.
