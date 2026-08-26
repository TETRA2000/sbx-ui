# sbx-ui Codebase Improvement Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **Register:** Like `docs/sbx-modernization-plan.md`, this is a **pre-spec design document**, not an implementation-ready task list for all items. The repo's 3-phase workflow (Requirements → Design → Tasks → Implementation) routes substantive workstreams through `/kiro:spec-init`. Workstreams 0–2 are specified to bite-sized-task granularity and can be executed directly; Workstreams 3–9 give concrete file:line targets, proposed fixes, and a test approach per finding but should be scoped through a spec before large changes land. Appendix A is the complete finding inventory so nothing is dropped silently.

**Goal:** Fix a build-breaking P0, eliminate a repeated subprocess-deadlock defect that violates the repo's own concurrency rule, close confirmed security/data-integrity holes, and make the test infrastructure actually enforce what it claims — turning ~110 audit findings into an ordered, verifiable work queue.

**Architecture:** No architectural rewrite. Changes stay within the existing layering (SBXCore services/models, `@MainActor @Observable` stores, SwiftUI views, Linux CLI, bash mock, plugin host + SDKs). The one cross-cutting change is centralizing subprocess I/O so the pipe-drain fix lives in one place.

**Tech Stack:** Swift 6.3 / SwiftUI (macOS, Xcode 26.6), Swift Package Manager + swift-argument-parser (Linux CLI + SBXCore), bash 3.2/5.x mock, Python + TypeScript plugin SDKs, GitHub Actions CI.

## Global Constraints

- **`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`** — every type defaults to `@MainActor`; explicit inits on `Sendable` types must be `nonisolated`. New syntax (`nonisolated protocol`) is not proven on the CI runner's Swift — see Workstream 0.
- **`ENABLE_APP_SANDBOX = NO`** (required for CLI spawning).
- **Never use `FileHandle.availableData` or `waitUntilExit()` on the Swift cooperative thread pool.** Use `readabilityHandler` and continuation-bridged process exit. This rule is in CLAUDE.md and is violated at four sites (Workstream 1).
- **Cross-store communication uses closures, never stored `@Observable` references.** (Currently followed correctly — do not regress.)
- **Write and run both unit and UI/E2E tests after any code change.** All tests run against the `tools/mock-sbx` bash mock; no Docker required.
- **Target sbx CLI floor: v0.33.0; verified against v0.34.0.** (The machine used to audit this plan runs v0.37.0 — drift is ongoing; see Workstream 9.)

---

## Current test state (measured 2026-07-31, this toolchain)

| Suite | Command | Result |
|---|---|---|
| Xcode unit (`sbx-uiTests`) | RunAllTests | **355 pass / 0 fail** (with the Workstream 0 fix applied) |
| Xcode UI (`sbx-uiUITests`) | RunAllTests | **19 fail / 28 pass / 1 not-run** — see note below |
| SPM (`SBXCore` + `CLIE2E`) | `swift test --package-path cli` | **121 pass / 0 fail** |
| mock-sbx bash | `bash tools/mock-sbx-tests.sh` | **47 pass** (but only ~26 actually enforce their assertions — Workstream 6) |

**Two facts a reader will immediately ask about, answered up front:**

1. **At `HEAD` the macOS *test target does not compile* on Xcode 26.6** (`actor` stubs cannot conform to the MainActor-inferred `SbxServiceProtocol`). CI is green only because the `macos-26` runner still ships an older Xcode. This is Workstream 0. Until it is fixed, the UI suite is not runnable at all on current toolchains.
2. **The 19 UI failures are an environment/harness issue, not a regression.** The console log from the run shows the app resolved **`/opt/homebrew/bin/sbx` (real sbx v0.37.0, installed on this machine)** instead of the `tools/` mock, and created zero sandboxes — so every sandbox-creation-dependent UI test failed. This is a live manifestation of the `CliExecutor` hardcoded-PATH finding (Workstream 6, F-6.5). On a machine without real sbx installed (and on CI), the mock wins and these tests pass.

---

## How to read this plan

- **Verification marker on every finding:** ⚙ = reproduced by executing code/commands during the audit; 📖 = derived by reading code (high-confidence but not independently reproduced — reproduce before spending a day on it).
- **Dependency ordering is a hard constraint in two places** (not a preference): the `mock-sbx-tests.sh` `run_test` fix (F-6.1) must land **before** any other mock-sbx change, or the suite that verifies those changes silently passes anything; and the plugin `ui/log → onOutput` fix (F-7.9) unblocks the plugin end-to-end round-trip test (F-7.13).
- Severity is the audit's, adjusted where two agents' evidence combined.

---

## Workstream 0 — P0: macOS test target does not compile (SEPARATE PR)

**Ship on its own one-commit branch so CI adjudicates the syntax in isolation** — the repo has already had one toolchain-isolation fight (commit `4b2f98a`), and `nonisolated protocol` is newer syntax than the `nonisolated func`/`init` that fix used. It compiles locally on Xcode 26.6; it is unproven on the CI runner's Swift.

**Files:**
- Modify: `sbx-ui/Services/SbxServiceProtocol.swift:3` and `:36`

- [ ] **Step 1 — Reproduce the break.** With Xcode 26.6, `BuildProject(buildForTesting: true)`. Expected: two errors, `Actor 'FailingSbxService' cannot conform to global-actor-isolated protocol 'SbxServiceProtocol'` and the same for `StubSbxService` (`sbx_uiTests.swift:36,57`). ⚙ (already reproduced)
- [ ] **Step 2 — Apply the fix.** Mark both protocols `nonisolated`:
  ```swift
  public nonisolated protocol SbxServiceProtocol: Sendable { … }
  public nonisolated protocol CliExecutorProtocol: Sendable { … }
  ```
- [ ] **Step 3 — Verify macOS build + unit tests.** `BuildProject(buildForTesting: true)` succeeds; `RunAllTests` unit target green. ⚙ (verified: build OK, 355 unit pass)
- [ ] **Step 4 — Verify SPM still builds.** `swift build --package-path cli` succeeds. ⚙ (verified)
- [ ] **Step 5 — Commit on `claude/fix-macos-test-target-compile`, open PR, and let CI report.** If CI's older Swift rejects `nonisolated protocol`, fall back to the proven-shape alternative: convert the two test stubs from `actor` to `final class … : @unchecked Sendable` with an internal `NSLock` guarding their mutable state (methods are already `nonisolated`), leaving the protocol untouched. That formulation compiles on both old and new Swift.

---

## Workstream 1 — Subprocess I/O: the pipe-drain deadlock (LEAD)

**This is the single strongest narrative in the audit: one root cause, four sites, and it violates a rule written in this repo's own CLAUDE.md.** Every site reads a child process's pipes only *after* the process exits (or blocks a cooperative thread with `waitUntilExit()`), so any child that emits more than the ~64 KB pipe buffer blocks on `write()`, never exits, and the awaiting Swift task hangs forever with no timeout. ⚙ Reproduced by the services and CLI agents: 32 KB returns fine, 512 KB / 1 MB hang.

**Files:**
- Create: `sbx-ui/Services/ProcessRunner.swift` (one drained, cancellation-aware, timeout-capable process runner)
- Modify: `sbx-ui/Services/CliExecutor.swift:44-101` (F-1.1)
- Modify: `sbx-ui/Services/DefaultEditorDocumentProvider.swift:73-76` (F-1.2)
- Modify: `sbx-ui/Plugins/PluginHost.swift:224` (F-1.4 — blocking-write variant)
- Modify: `cli/Tests/CLIE2ETests/CLIE2EHelpers.swift:146-150` (F-1.3 — test harness, same bug + a lying comment)

**Interfaces:**
- Produces: `func runProcess(executableURL:arguments:environment:stdin:timeout:) async throws -> CliResult` that (a) attaches `readabilityHandler` to stdout and stderr, accumulating concurrently while the child runs; (b) resumes its continuation only after `terminationHandler` fires **and** both handlers see EOF; (c) is wrapped in `withTaskCancellationHandler` to `terminate()` the child on cancellation; (d) enforces an optional deadline that terminates the child and throws `SbxServiceError.cliError`. `CliExecutor.exec` becomes a thin caller of this.

- [ ] **Step 1 — Failing test for the deadlock.** In a new SBXCore test, run a helper that writes 512 KB to stdout then exits; assert it returns within a few seconds with the full 512 KB. Against the current `CliExecutor` drain shape this times out. ⚙
- [ ] **Step 2 — Implement `ProcessRunner`** with the interface above.
- [ ] **Step 3 — Route `CliExecutor.exec` through it**, preserving the existing `resolveCommand`, `/dev/null` stdin, and `appLog` behavior. Keep the DEBUG log but **redact stdout for env-var commands** (F-6.13 — env values are secrets). Verify the Step-1 test passes.
- [ ] **Step 4 — Fix `DefaultEditorDocumentProvider`**: replace `process.waitUntilExit()` + post-hoc `readDataToEndOfFile()` with `ProcessRunner`. Add a failing test that a git repo with >64 KB of `status --porcelain` output (large untracked tree) returns promptly. ⚙-target
- [ ] **Step 5 — Fix the interactive-attach path** (`SandboxStore.resumeSandbox` → `RealSbxService.run` with `["run","--name",name]`, F-1.5): a long-lived agent session must not be drained by the batch runner. Route it through `TerminalSessionStore` (PTY) or discard output via `FileHandle.nullDevice`; also add the missing `SbxValidation.isValidName(name)` guard that the create branch has and the resume branch skips. 📖
- [ ] **Step 6 — Fix `PluginHost.writeLine`** (blocking `write(contentsOf:)` on the actor): move writes onto a dedicated serial queue with a bounded outbound buffer that errors rather than blocks when full. 📖
- [ ] **Step 7 — Fix `CLIE2EHelpers`**: make the drain actually concurrent (readabilityHandlers) and correct the comment that already claims it is. Add a test child writing 1 MB to stderr. ⚙-target
- [ ] **Step 8 — Commit** each site as its own reviewable change.

---

## Workstream 2 — Security & data integrity (confirmed exploitable / corrupting)

Highest-severity correctness. Two are ⚙-confirmed code execution / data corruption; the rest are 📖 with clear reasoning.

- [ ] **F-2.1 ⚙ Env-var shell injection.** `RealSbxService.swift:201` + `SbxOutputParser.swift:277` write env values into `/etc/sandbox-persistent.sh` **unquoted** inside an unescaped heredoc. Confirmed in bash: a value with a space truncates, a backtick executes on source (arbitrary code exec in the sandbox), and a value line equal to `SBXENVEOF` truncates the file. **Fix:** single-quote values with `'\''` escaping, teach `parseManagedEnvVars` to unquote symmetrically, and use a random heredoc delimiter (or write via base64/stdin). Test: round-trip values containing space, `$`, backtick, `;`, `'`, and the literal delimiter.
- [ ] **F-2.2 📖 Plugin permission over-grant.** `SandboxProfile.swift:69-75` — declaring *any* policy permission, including read-only `policy.list`, appends `(allow network*)` and unrestricted `(allow mach-lookup)`, discarding the scoped four-service list. Plugins need no network (requests go over stdio to the host). **Fix:** grant neither for `.policyList`; scope network for the mutating policy calls; never widen `mach-lookup`. Test: profile-generation unit test asserting `.policyList` alone yields no `network*`/broad `mach-lookup`.
- [ ] **F-2.3 📖 Plugin identity/approval is forgeable.** `PluginListView.swift:106-124` copies a plugin folder without validating its manifest and silently overwrites an existing dir; `PluginPermission.swift:135-140` keys approval purely on manifest `id` (validated only as `contains(".")`); `PluginManager.startPlugin` has no approval check. A new plugin declaring an already-approved `id` with a permission subset starts with no prompt. **Fix:** validate manifest before copy; reject an `id` already claimed by a different directory; add duplicate-`id` detection in `discoverPlugins`; bind approval to directory + content hash of the entry file, not `id` alone.
- [ ] **F-2.4 📖 Symlink scope escapes (two sites, same root cause).** `EditorPath.swift:12-27` and `PluginApiHandler.swift:260-269` both validate scope lexically (`standardizedFileURL` / `..` normalization) without `resolvingSymlinksInPath()`, so a symlink *inside* the trusted root that points outside it passes — editor and plugin `file/read`+`file/write` can reach arbitrary host paths. **Fix:** compare `resolvingSymlinksInPath()` of candidate and root at both sites. Tests: temp-dir symlink pointing outside root is rejected (currently missing, `EditorProviderTests.swift`).
- [ ] **F-2.5 ⚙ Policy-log timestamps never parse.** `RealSbxService.swift:123,131` — a default `ISO8601DateFormatter` lacks `.withFractionalSeconds`; the CLI and mock both emit fractional seconds, so every `date(from:)` returns `nil` and falls back to `Date()` — the "last seen" column is silently always "now". Confirmed by running the formatter. **Fix:** one `static let` formatter with `[.withInternetDateTime, .withFractionalSeconds]` (+ non-fractional fallback); assert a known timestamp in the `policyLog()` test that currently doesn't check it.
- [ ] **F-2.6 📖 Plugin `runtime` unvalidated + invisible at approval.** `PluginHost.swift:55-58` never validates the manifest `runtime`; any absolute path becomes the exec'd binary and gets a `process-exec` allow, while the approval dialog shows only permission display names. **Fix:** validate `runtime` as a bare command or allowlisted path; surface resolved runtime + entry in the approval dialog.

---

## Workstream 3 — Silent failures & error surfacing

A recurring theme across three agents: failures are swallowed into log lines or written to `error` properties no view reads. This is the "empty dashboard with no explanation" class of bug.

- [ ] **F-3.1 📖 Store `error` never surfaced.** `SandboxStore`, `PolicyStore`, `EnvVarStore`, `TerminalSessionStore`, `PluginStore` all publish `var error` that no view reads (only `kanbanStore.error` is read). **Fix:** route through the app-wide `ToastManager`, or delete the unread property. Pair with F-3.2.
- [ ] **F-3.2 📖 `ErrorStateView` never instantiated.** A 79-line view purpose-built for Docker-not-running / CLI-not-found guidance is dead. **Fix:** render it in Dashboard when `sandboxStore.error != nil && sandboxes.isEmpty`.
- [ ] **F-3.3 ⚙ CLI `exec` swallows output and exit code.** `Commands.swift:195-204` throws via `checkCli` before printing; `exec sb sh -c "echo out; exit 7"` exits 1 with no stdout. **Fix:** bypass `checkCli`, print stdout/stderr, `throw ExitCode(result.exitCode)`. Makes `sbx-ui exec sb npm test` usable in scripts.
- [ ] **F-3.4 ⚙ `doctor` can never fail.** `DoctorCommand.swift:37-46` never throws; the one command a CI/install script gates on always exits 0. **Fix:** `throw ExitCode(1)` for any non-`.compatible` status (or `--strict`).
- [ ] **F-3.5 📖 One bad file blanks a whole feature.** `KanbanPersistence.swift:25-28` (`try` inside `compactMap` propagates the first decode error → all boards vanish) and `KanbanStore.save():329-335` (persistence failure swallowed → edits vanish on relaunch). **Fix:** `try?` per file + log; assign `self.error` in `save`'s catch (already rendered).
- [ ] **F-3.6 📖 `checkCli` "not found" over-match (merged: services + cli).** `RealSbxService.swift:244` maps any stderr containing `"not found"` to `notFound`, rendered as `Sandbox 'X' not found`. Two confirmed symptoms: a shell `command not found` from `exec` is misclassified, and a *policy* `rm` failure is reported as a *sandbox* error (⚙ via `policy rm`). **Fix:** anchor a regex on `Error: sandbox '<name>' not found`; skip the classifier for `exec` and policy/port operations, or pass a resource-kind.

---

## Workstream 4 — Kanban correctness & crashes

- [ ] **F-4.1 📖 User-reachable index-out-of-range crash.** `KanbanStore.swift:316,254,256,371-374,270-275` — five sites reuse a `boards` array index resolved *before* an `await`; deleting or reordering a board mid-execution traps. **Fix:** a `withBoard(id:)`/`withTask(id:)` helper that re-resolves by ID after every suspension point; never capture a raw index across `await`. Test: stub `onExecuteTask` deletes a board mid-await.
- [ ] **F-4.2 📖 False completion cascade.** `syncSandboxStatus:294-311` marks a task `.completed` merely because its sandbox stopped or is absent, then fires `checkAndExecuteDependents`, auto-launching dependents off a crash/manual-stop. **Fix:** a distinct "stopped without result" terminal state that does not satisfy the dependency predicate.
- [ ] **F-4.3 📖 `cancelTask` lies on failure.** `:269-273` `try?`-stops then unconditionally marks `.cancelled`; a failed stop leaves the agent running while the board says cancelled. **Fix:** check the stop result; surface the error and keep prior state on failure.

---

## Workstream 5 — Linux CLI machine-readability & contract

- [ ] **F-5.1 ⚙ Every documented `--json` invocation fails.** Docs show `sbx-ui --json ls`; the flag is a per-subcommand `OptionGroup`, so `--json ls` → `Error: Unexpected argument 'ls'` (exit 64). **Fix:** either move `OutputOptions` to the root command and thread it down, or rewrite all doc examples to the working `sbx-ui ls --json` form.
- [ ] **F-5.2 ⚙ `create --json` emits a status line before the JSON.** `printInfo` writes to stdout (`Commands.swift:91`), breaking `| jq` and contradicting the docs. **Fix:** suppress info when `--json`, or route `printInfo` to stderr.
- [ ] **F-5.3 ⚙ Hand-rolled JSON drifts and lies about types.** All six JSON commands build `[String:Any]` dicts instead of encoding the already-`Encodable` domain types; `policy log --json` stringifies `count`/`blocked` and drops `last_seen`/`type`; `ls --json` drops ports. **Fix:** one `JSONEncoder` emit helper in SBXCore (snake_case, sorted keys); encode domain types directly; fix the E2E assertions that currently codify the string-typed bug.
- [ ] **F-5.4 ⚙ Port spec accepts garbage; two resolvers diverge.** `parsePortSpec` accepts any `Int` (`-1:99999` passes, doubled `Error:` prefix); `Run` uses its own PATH-only sbx resolver while every other command uses `CliExecutor.resolveCommand`. **Fix:** validate `1...65535`; make the SBXCore resolver `public` and have `Run` use it.
- [ ] **F-5.5 📖 No non-interactive resume; `doctor` undocumented.** GUI `resumeSandbox` has no CLI equivalent (`Run` execvps). **Fix:** add `sbx-ui start <name>` calling the resume path; document `doctor` (text + `--json` + status values) in `docs/linux-cli.md`.

---

## Workstream 6 — Test infrastructure integrity (ORDERING-CRITICAL)

**F-6.1 must land first.** Until it does, none of the other mock-sbx fixes can be verified by the suite meant to verify them.

- [ ] **F-6.1 ⚙ `run_test` discards all but the last assertion.** `mock-sbx-tests.sh:27` invokes each test as an `if` condition, suspending `errexit` for the whole body; ~21 of 47 tests silently pass anything but their final command (mutation-proven). **Fix:** capture status without the `if` (`"$@"; rc=$?`) or set a `FAILED=1` flag inside the `assert_*` helpers; also stop discarding assert stderr while keeping mock stdout chatter (`:27`). **Do this before F-6.2–F-6.4.**
- [ ] **F-6.2 ⚙ Mock concurrency races.** First-run seeding is check-then-act (6 concurrent invocations → 60 policies, 3/3 trials); `port_publish` does non-atomic read-modify-write (8 concurrent → 4 entries + corrupt leading-comma JSON). The app fires parallel sbx calls at launch, and every XCUITest makes a fresh state dir — this is a real flake source. **Fix:** `mkdir`-as-lock + wait-for-marker for seeding; lock + temp-file+`mv` for ports.
- [ ] **F-6.3 ⚙ Mock fidelity gaps.** `policy_rm` greps the resource unescaped so wildcard policies (6 of 10 seeded) can never be removed; port-spec parsing mangles the documented `HOST_IP:HOST_PORT:SANDBOX_PORT` form into invalid JSON; catch-all `-*) shift` eats valued flags (`--cpus 4` → `agent="4"`); duplicate-port grep lacks a delimiter (808 matches 8080); `stop`/`rm` ignore extra names and `rm a b` removes only `b`; `ls --json` never emits `ports`; `policy_log` ignores its sandbox filter. **Fix:** per finding in Appendix A; each gets a mock-sbx test (now that F-6.1 makes them real).
- [ ] **F-6.4 ⚙ bash 3.2 portability.** `mock-sbx` `"${agent_args[@]}"` empty-array expansion is fatal under `set -u` on stock macOS `/bin/bash` (reproduced: `line 222: agent_args[@]: unbound variable`); `scripts/build.sh` uses `declare -A` (bash 4+). **Fix:** `${agent_args[@]+"${agent_args[@]}"}` ×4; replace assoc arrays with a `case`; add a `/bin/bash tools/mock-sbx-tests.sh` CI step.
- [ ] **F-6.5 ⚙ E2E harness shadowed by real sbx.** `CliExecutor` prepends `/opt/homebrew/bin` to the search path, so on a machine with real sbx installed the app runs `/opt/homebrew/bin/sbx` (v0.37.0 here) instead of the `tools/` mock — the cause of the 19 UI failures on this machine. **Fix:** gate the homebrew-path injection behind a flag the GUI sets and tests/CLI don't; have XCUITest force mock resolution (absolute `SBX_BIN` override, or an env the resolver honors before extra paths).
- [ ] **F-6.6 📖 Coverage gaps.** No behavioral E2E for `run` execvp path, `policy log <sandbox>` positional filter, `create` without `--name`, `status` Ports section, `env ls` on nonexistent sandbox, `doctor` older/unresolvable; store-side gaps in `KanbanStore.cancelTask`/`checkAndExecuteDependents`, `SandboxStore` polling, concurrent `EnvVarStore` adds, `PluginStore` approval flow, `TerminalSessionStore.disconnect` asserting the child is gone. `SBXCoreTests` `setenv` races with concurrent suites. **Fix:** one test per gap; pass env via `Process.environment` not `setenv`.

---

## Workstream 7 — Plugin subsystem hardening & SDKs

- [ ] **F-7.1 ⚙ Python SDK deadlocks on the documented handler shape.** `rpc.py:108,81` — `_read_loop` awaits `_handle_message`, which awaits the handler coroutine; a handler that awaits an RPC blocks the only reader that would resolve its future. Every Python plugin written from the quick-start hangs on its first API call. **Fix:** dispatch handlers with `asyncio.create_task(...)`. Add a test whose handler issues a request during `initialize`.
- [ ] **F-7.2 📖 Process lifecycle.** `PluginHost` closes the stdout handle before nilling its `readabilityHandler` (`:165`, NSFileHandleOperationException risk); never retains/cleans the stderr handle (`:97`, fd + dispatch-source leak per start/stop); orphans a SIGTERM-ignoring child (`:160`, no SIGKILL escalation); has an unbounded stdout line buffer (`:240`). **Fix:** nil handlers before every close; store + clean stderr; SIGKILL after grace; cap the buffer. One test with a plugin that ignores `shutdown`+SIGTERM covers the close-ordering and SIGKILL items together.
- [ ] **F-7.3 📖→ enables E2E test. `ui/log`/`ui/notify` are silent no-ops.** `PluginApiHandler.swift:332-340` only `appLog`s; neither reaches the `onOutput` callback that feeds the detail view. **Fix:** route both through `onOutput`. **This unblocks F-7.4.**
- [ ] **F-7.4 📖 No end-to-end JSON-RPC round-trip test.** `PluginExecutionTests` asserts only `isRunning`. Once F-7.3 lands, assert `mock-plugin`'s `"mock-plugin-executed"` `ui/log` arrives via `onOutput` within a timeout — covering framing, decode, permission check, dispatch, write-back.
- [ ] **F-7.5 📖 Profile broader than the API it documents.** `file-write*` on `/tmp` bypasses the API's plugin-dir scoping; `process-exec` spans all of `/usr/bin`,`/bin`,`/usr/sbin`; `onAppLaunch` trigger is declared/documented/tested but never dispatched. **Fix:** scope or drop the `/tmp` write and the broad exec; dispatch `onAppLaunch` after discovery or remove it.
- [ ] **F-7.6 📖 SDK examples are broken.** TS example `entry: index.js` doesn't exist and calls `ui.notify` not in its perms; Python example hardcodes `/Users/takahiko/.asdf/shims/python3`. **Fix:** build step / compiled JS; add `ui.notify`; use bare `python3`.

---

## Workstream 8 — View layer

- [ ] **F-8.1 📖 Editor pane blank after session switch.** `ShellView.swift:49` + `SandboxWorkspaceView.swift:29` — switching from sandbox A's to B's session never re-runs `editorStore.open` (no `.id()`, only `.onAppear`), so B's editor is permanently empty. **Fix:** `.id(sandbox.name)` or `.onChange(of: sandbox.name)`.
- [ ] **F-8.2 📖 Invisible status labels (contrast).** `KanbanTaskCardView.swift:19` etc. pass surface tokens to `foregroundStyle` (~1.4:1); every new `.pending` task's label is invisible. **Fix:** add a `Color.textMuted` token; replace the six surface-as-text uses.
- [ ] **F-8.3 📖 Destructive uninstall, no confirm.** `PluginDetailView.swift:138` deletes the plugin dir via `try?` with no confirmation, unlike sandbox-terminate/task-delete. **Fix:** `.confirmationDialog` + toast on error + a11y id.
- [ ] **F-8.4 📖 Dead / duplicated views and unbounded toasts.** Dead: the find feature (`EditorPanelView` + `EditorFindBar`, ~110 lines), `SessionPanelView`, `TabLimitWarningDialog`, `checkExternalChange`. Toasts have no cap/dedup and cover nav buttons (two UI tests are engineered around the defect). **Fix:** delete dead code or wire Cmd+F; cap toasts at 3 with dedup + identifiers.
- [ ] **F-8.5 📖 Missing a11y identifiers block documented tests.** The Policies "Activity Log" button (only door to `logSandboxFilter`/`blockedOnlyToggle`) and the board-rename flow have no identifiers. **Fix:** add `activityLogButton`, `renameBoardButton`/`boardNameField`/`submitRenameButton`.
- [ ] **F-8.6 📖 Layout robustness.** Long sandbox names wrap and desync grid heights; the deploy sheet clips its buttons with ~8 env vars (no ScrollView); the Kanban drop index assumes a fixed card height; empty columns have no placeholder. **Fix:** `lineLimit(1)`/`truncationMode(.middle)`; ScrollView + `minHeight`; anchor-preference drop math; empty-state branch.
- [ ] **F-8.7 📖 Design-system leaks.** ~7 raw-color sites bypass tokens; `.secondary` vs `Color.secondary` (gray vs the theme's green) is a live edit trap; three copy-pasted components (chip, pulse, snapshot-poll loop). **Fix:** add `Color.warning`; rename the ambiguous token; extract `ChipView`/`.pulsing()`/`startSnapshotPolling()`.

---

## Workstream 9 — Docs, steering & CI hygiene

- [ ] **F-9.1 ⚙ Test counts wrong in four docs; "just recount" already failed once.** Actual: unit 326 (not 322), Xcode total 374, SBXCore 41 (not 39), SPM 121 declared / ~141 executed. Stale in CLAUDE.md, `docs/linux-cli.md`, `.kiro/steering/tech.md`, `docs/sbx-modernization-plan.md`. **Fix:** delete the numbers from prose, or add a CI step that recomputes and fails on mismatch.
- [ ] **F-9.2 ⚙ The Editor subsystem is absent from all steering + CLAUDE.md.** `.kiro/steering/structure.md` lists features/stores without Editor (8 views, `EditorStore`, a spec, 54 tests — ~15% of the app); "editor" appears zero times in steering. Since CLAUDE.md loads all steering as project memory, every session starts with an incomplete model. **Fix:** add Editor to structure.md and README; add `docs/plugin-development.md` + `tools/mock-plugin` + `sdk/` to CLAUDE.md's Reference list and README.
- [ ] **F-9.3 📖 Documented sbx floor is impossible.** `README`/`tech.md` say v0.23.0+, but the app sends `policy ls --include-inactive` (v0.32) and `run --name` (v0.33). **Fix:** state floor v0.33.0, verified v0.34.0, consistently.
- [ ] **F-9.4 📖 CI hygiene.** No `timeout-minutes` anywhere and `mock-plugin`'s watchdog is broken (`(sleep 10; exit 0) &` exits the subshell — a hang runs to the 6-hour default on the billed macOS runner); no dependency caching; `sdk-tests.yml` uses `npm install` not `npm ci`; Beta/Stable schemes never compiled pre-merge; no `permissions:` block. **Fix:** `kill $$` watchdog + `timeout-minutes`; `actions/cache` (SwiftPM, DerivedData, npm, pip); `npm ci`; `pull_request` build of all schemes; `permissions: contents: read`.
- [ ] **F-9.5 📖 Consolidate the release recipe.** `build.yml` duplicates and has diverged from `scripts/build.sh` (signing flags), so a local build doesn't reproduce CI. **Fix:** have the workflow call the script.

---

## Scope: what this plan does NOT do (and why)

- **No architectural rewrite.** The layering is sound; the store→closure discipline and lack of retain cycles were verified clean.
- **No TDD-per-line spec for Workstreams 3–9.** With ~110 findings that would be a 3,000-line document; instead each finding carries a file:line, a proposed fix, and a test approach, and substantive workstreams go through `/kiro:spec-init` per repo workflow.
- **Deferred low-value items** are retained in Appendix A rather than dropped: doc line-anchor drift, a date typo, `pendingSaveAll` dead state, empty `SettingsStore`, `FlowLayout` infinite-width-on-nil, unused formatters. Batch them into a single "hygiene" cleanup PR.
- **The open question the services agent flagged** (`envVarSync`'s `sbx exec -d` exit semantics) needs verification against a real v0.34.0+ binary before any change; the quoting/heredoc fix (F-2.1) stands independently.

---

## Appendix A — Full finding inventory

`⚙` reproduced by execution · `📖` verified by reading · Sev H/M/L. Findings folded into the workstreams above are marked with their F-id; the remainder are the deferred long tail.

### Services / Models (audit-services, 21)
| Sev | File:line | Finding | Ver | Where |
|---|---|---|---|---|
| H | CliExecutor.swift:73 | Pipe drain deadlock | ⚙ | F-1.1 |
| H | SandboxStore.swift:70→RealSbxService.swift:39 | Interactive attach through batch executor; skips name validation | 📖 | F-1.5 |
| H | DefaultEditorDocumentProvider.swift:73 | `waitUntilExit()` + post-hoc drain | 📖 | F-1.2 |
| M | CliExecutor.swift:44 | No timeout / not cancellation-aware | 📖 | F-1 |
| H | RealSbxService.swift:123,131 | Policy-log timestamps never parse | ⚙ | F-2.5 |
| H | RealSbxService.swift:201 + SbxOutputParser.swift:277 | Env-var shell injection | ⚙ | F-2.1 |
| M | RealSbxService.swift:57 | Post-create lookup can return wrong sandbox | 📖 | F-3/appendix |
| M | RealSbxService.swift:15 | Dead UTF-8 guard; empty stdout → DecodingError | 📖 | F-3.6-adjacent |
| M | SbxOutputParser.swift:101 | Column-offset policy parse silently drops rows | 📖 | Appendix |
| M | RealSbxService.swift:244 | `not found` over-match | ⚙ | F-3.6 |
| M | KanbanPersistence.swift:25 | One bad file aborts all boards | 📖 | F-3.5 |
| M | EditorPath.swift:12 | Lexical-only scope (symlink escape) | 📖 | F-2.4 |
| L | RealSbxService.swift:115,144 | `try?`→[] hides schema drift | 📖 | Appendix |
| L | KanbanPersistence.swift:7 | Force-unwrap app-support dir | 📖 | Appendix |
| L | SbxOutputParser.swift:4 | `nonisolated(unsafe)` shared Regex | 📖 | Appendix |
| L | SbxOutputParser.swift:10,112,175 | 3 parsers with no production callers | 📖 | Appendix |
| L | SbxServiceProtocol.swift:38 | `execJson` never called | 📖 | Appendix |
| L | RealSbxService.swift:219 | `sendMessage` empty no-op (merged w/ stores+cli) | 📖 | Appendix |
| L | DomainTypes.swift:82 / EditorDocumentProvider.swift:75 | Never-thrown error cases advertise absent guards | 📖 | Appendix |
| M | DefaultEditorDocumentProvider.swift:177 | `parsePorcelain` rename branch untested | ⚙ | F-6.6 |
| L | EditorProviderTests.swift:7 | No symlink-escape test | 📖 | F-2.4 |

### Stores (audit-stores, 17)
| Sev | File:line | Finding | Ver | Where |
|---|---|---|---|---|
| H | TerminalSessionStore.swift:238 | `disconnect` leaks PTY child + fd | 📖 | Appendix (pairs W1) |
| H | KanbanStore.swift:316… | Stale-index crash ×5 | 📖 | F-4.1 |
| H | SandboxStore.swift:63 | `resumeSandbox` can't throw; failure invisible | 📖 | F-1.5/F-3.1 |
| H | SandboxStore.swift:13 … | 5 stores' `error` never read | 📖 | F-3.1 |
| M | SandboxStore.swift:111 | `startPolling` unstructured, never stopped | 📖 | Appendix |
| M | SandboxStore.swift:25 | `fetchSandboxes` no in-flight guard → stale snapshot | 📖 | Appendix |
| M | EnvVarStore.swift:28 | Read-modify-write lost update | 📖 | F-6.6 |
| M | KanbanStore.swift:329 | `save` swallows failure | 📖 | F-3.5 |
| M | KanbanStore.swift:294 | False-completion cascade | 📖 | F-4.2 |
| M | KanbanStore.swift:269 | `cancelTask` lies on failed stop | 📖 | F-4.3 |
| M | TerminalSessionStore.swift:253 | `cleanupStaleSessions` reimplements `disconnect` | 📖 | Appendix (pairs W1) |
| M | AppDelegateAdapter.swift:11 | Synchronous SHA256 of all buffers on quit | 📖 | Appendix |
| M | SandboxStore.swift:19 | Needless `nonisolated(unsafe)` | 📖 | Appendix |
| L | TerminalSessionStore.swift:296 | `sendMessage` no caller; 30s untracked Task | 📖 | Appendix |
| L | EditorStore.swift:781 | `checkExternalChange` dead; deleted-file→`.unchanged` | 📖 | F-8.4 |
| L | PluginStore.swift:19 | `error` never cleared; `stopAll` diverges | 📖 | Appendix |
| L | SettingsStore.swift:3 | Empty class still injected | 📖 | Appendix |

### Views / DesignSystem (audit-views, 30) → F-8.x + Appendix
### Plugins / SDKs (audit-plugins, 20) → F-2.2/2.3/2.6 + F-7.x + Appendix
### Linux CLI (audit-cli, 25) → F-3.3/3.4/3.6 + F-5.x + F-6.5/6.6/6.13 + Appendix
### Tooling / CI / docs (audit-tooling, 24) → F-6.x + F-9.x + Appendix

> The per-agent full lists (every low finding with its one-line fix) are preserved verbatim in the PR description and the audit transcripts. This appendix maps them to workstreams; the deferred-hygiene items (doc anchors, date typo, `pendingSaveAll`, empty `SettingsStore`, `FlowLayout`, duplicate formatters, workflow `permissions`) are intentionally batched, not dropped.

---

## Suggested execution order

1. **Workstream 0** (separate PR, CI adjudicates syntax).
2. **F-6.1** (unblocks mock verification) — do before any other mock change.
3. **Workstream 1** (pipe-drain) — highest structural risk, one shared fix.
4. **Workstream 2** (security/data integrity).
5. **Workstream 3–4** (silent failures, Kanban crashes).
6. **Workstream 6** remainder (mock fidelity, portability, harness, coverage).
7. **Workstream 5, 7, 8** in parallel (independent surfaces).
8. **Workstream 9** (docs/CI) — landable anytime; do the CI-timeout + caching items early to make the rest cheaper.
