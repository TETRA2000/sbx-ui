# sbx CLI Modernization + E2E Testing Improvement Plan

## Context

sbx-ui wraps Docker's `sbx` (Docker Sandboxes) CLI, but the app is built and documented against **sbx v0.23.0** (`docs/sbx-cli-reference.md`, "verified 2026-04-04"), while the real CLI has moved to **v0.34.0 stable** (v0.35.0-rc1 in progress). Three releases' worth of behavior changes have landed since — a deprecated `run` invocation form, a scope-default change on policy commands, a new stable `id` field on `sbx ls --json`, and a renamed `policy set-default` command — none of which this app's parsing/service layer accounts for. The bash mock (`tools/mock-sbx`) that all current tests run against faithfully reproduces the *old* behavior, so the test suite stays green while silently testing the wrong contract.

Separately, the E2E test story has two known gaps: GitHub Actions' XCUITest step has been commented out since commit `70a995e` ("Disable UI tests on CI temporarily", no rationale recorded in the commit — believed to be macOS-runner cost, since `macos-26` runners bill at a steep multiple of Linux runner minutes), and no CI job or Claude Code web session workflow ever exercises the app against a *real* `sbx` binary. Every test path today (bash mock tests, Swift unit tests, `CLIE2ETests` subprocess tests) runs against the mock by construction, so version drift like the above can never be caught automatically.

This plan closes the version-drift gap and builds durable, low-cost E2E signal on the platforms that don't require paying for macOS CI minutes: Linux GitHub Actions runners (which have Docker preinstalled) and Claude Code web sessions (already documented, currently manual, in `docs/install-sbx-claude-code-web.md`).

**Decisions locked in:**
- **Policy scope**: adopt sbx's new global-scope default for `policy allow/deny/rm` as-is. No service/protocol signature changes — `PolicyStore.swift` has no per-sandbox scoping today (only the log view filters client-side), so there's nothing to preserve. Just update docs/copy.
- **XCUITest on GitHub Actions**: stays disabled (likely cost-driven). No spike to re-enable it. Clean up the dead comment block and misleading job name, document the rationale, and put E2E investment into the Linux CLI + Claude Code Web paths instead.

This document is intended to feed `/kiro:spec-init` for one or two formal specs once scoped further — it is the pre-spec design, not an implementation-ready task list. Given the repo's 3-phase approval workflow (Requirements → Design → Tasks → Implementation), the workstreams below should go through that process — especially Workstream A, which changes production CLI-invocation behavior — before code lands.

---

## Workstream A — sbx CLI Modernization (v0.23.0 → v0.34.0)

Goes first: Workstream B's real-CLI integration job is only useful once the app actually understands v0.34.0 output — otherwise every real-CLI test fails on drift the app doesn't handle yet, which is noise, not signal.

### A1 — Docs pass
- `docs/sbx-cli-reference.md`: bump to v0.34.0. Document: `run --name` replacing the bare positional form (deprecated in v0.33.0); `ls --json`'s new `id` field; `policy ls` hiding inactive rules by default (`--include-inactive` to show all); `policy allow/deny/rm` now defaulting to **global** scope with `-g/--global` deprecated (global is simply the behavior now, no `--sandbox` flag needed in this app's usage); `policy set-default` → `policy init` rename; simplified single-line `sbx version` output (`-D/--debug` for detail); sandbox names rejecting `+` (already enforced client-side via `SbxValidation.isValidName`, `Models/DomainTypes.swift:113-115`); note v0.35.0-rc1's `policy` tooling revamp (`--wide/--source/--decision`, `policy inspect`, `policy check network`) as "future, do not build against yet." Fix the existing `factory-ai` agent-list inconsistency while in there.
- `docs/install-sbx-claude-code-web.md`: bump the `v0.24.2` example to current stable; replace `sbx policy set-default` → `sbx policy init`; replace `sbx run <name>` → `sbx run --name <name>` in Step 7 and the command table.
- Verification: manual diff against a real installed v0.34.0 binary's `--help` output (Phase B2/B3 tooling makes this repeatable later).

### A2 — `tools/mock-sbx` modernization
- `cmd_version` (`tools/mock-sbx:691-694`): single-line default + `-D` debug branch; keep the unambiguous `v0.99.0-mock` marker.
- `policy_ls/allow/deny/rm` (`tools/mock-sbx:371-451`): global-scope semantics (drop implicit per-sandbox behavior); add `--include-inactive` to `policy_ls`; wire `policy init` as the primary command (accept `set-default` as a silent alias for one transition release, then drop it).
- `sbx ls --json`: emit a stable `id` per sandbox.
- `docs/mock-sbx.md` + `tools/mock-sbx-tests.sh`: update/extend to cover all of the above (currently 101 assertions) — the fastest feedback loop in the whole workstream.
- Verification: `bash tools/mock-sbx-tests.sh` green (already wired into both `tests.yml` and `linux-cli-tests.yml`).

### A3 — Swift service/parser changes
- `RealSbxService.swift:37`: `["run", name]` → `["run", "--name", name]`.
- `RealSbxService.swift:80,88,96` (`policyAllow`/`policyDeny`/`policyRemove`): no signature change needed (global scope decision) — add a short comment noting the v0.32.0 scope-default change so a future reader isn't confused about the absent `--sandbox` flag. Pass `--include-inactive` from `policyList()` to preserve the full-visibility behavior the app had pre-v0.32.0, so the Policies view doesn't silently start hiding rows.
- `SbxServiceProtocol.swift:62-86` (`SbxSandboxJson`): add `let id: String?` (decodable-tolerant, defaults nil against old-shaped/mock JSON) — additive only, don't change `Sandbox.id` identity wiring in `RealSbxService.list()` (`RealSbxService.swift:19`) this round.
- `SbxOutputParser.swift` `parsePolicyList`/`parsePolicyLog`: no structural change required for v0.34.0 itself; add a test case confirming behavior with `--include-inactive` on/off.
- Update test doubles (`StubSbxService`/`FailingSbxService` in `sbx_uiTests.swift`) and add unit tests for: the new `--name` resume call, `id` field decode (present/absent), `--include-inactive` policy list behavior.
- Verification: `swift test --package-path cli` (103 tests) and the macOS unit suite green.

### A4 — `sbx version` compatibility awareness (new, small capability)
- Add `func version() async throws -> SbxVersionInfo` to `SbxServiceProtocol.swift`; implement in `RealSbxService` via `sbx version`; add `SbxOutputParser.parseVersion` handling both the new single-line default and `-D` detail format.
- Add a small pure `SbxCliCompatibility` helper comparing the detected version against a `verifiedVersion = "0.34.0"` constant → `.compatible`/`.olderThanVerified`/`.newerThanVerified` (informational only, never blocks an operation).
- Surface via a new `Doctor`/`Version` command in `cli/Sources/sbx-ui-cli/Commands.swift` (registered in `CLI.swift`), following the existing pattern in `HelpAndVersionTests.swift`. macOS GUI surfacing (Settings/About) is a stretch goal, not a blocker — `SettingsStore.swift` exists but isn't wired to any view yet; treat as explicitly deferred.
- Verification: unit tests for `parseVersion` against mock and real-CLI-shaped fixtures; new `CLIE2ETests` cases for the new subcommand; this becomes the tool Phase B2/B3 use to confirm real-CLI compatibility going forward.

### A5 — Fragility hardening (trails the rest, lower priority)
- `parsePolicyList`/`parsePolicyLog` have no JSON fallback (none exists for `policy ls` as of v0.34.0) and are keyed on exact header strings. Given the v0.35.0-rc1 `policy` revamp preview, add a defensive "unexpected header shape → log + return empty" fallback so a future format change fails loudly (via A4's compatibility layer) instead of silently mis-parsing.

---

## Workstream B — E2E Testing Improvements (GitHub Actions + Claude Code on the Web)

### B0 — Test coverage + doc cleanup (independent, do anytime)
- Implement `.kiro/specs/editor/tasks.md:199` task **10.3** (the one unchecked task in an otherwise complete spec): XCUITest for sandbox-stop editor-state preservation — open file, edit, stop sandbox from dashboard, confirm dashboard view with no crash, restart, re-enter session, assert tab set/active tab/dirty state restored (Requirement 14.5). Add alongside `EditorE2ETests.swift`'s existing pattern.
- Fix stale counts: `README.md:295-296` ("73 unit + UI tests" → 322 unit + 47 UI = 369; "25 unit + integration tests" → 103, since `swift test --package-path cli` runs both `SBXCoreTests` (25) and the previously-undocumented `CLIE2ETests` (78)); document `cli/Tests/CLIE2ETests/` in the Test Structure section; fix `linux-cli-tests.yml`'s trigger description (it has no path filter today, despite the doc implying one); `CLAUDE.md:118` test count.

### B1 — GitHub Actions: retire the dead XCUITest step cleanly (no spike)
- Remove the commented-out block in `.github/workflows/tests.yml:66-72` and replace it with a short comment explaining XCUITest is intentionally not run on GitHub-hosted macOS runners (cost), pointing to wherever XCUITest *does* run (locally via Xcode, and/or Xcode Cloud if that's confirmed to cover it — worth a quick check of Xcode Cloud config, since recent commits show Xcode Cloud/TestFlight packaging work).
- Rename the `tests.yml` job from "Unit & UI Tests" to "Unit Tests" so CI status accurately reflects what runs.
- Closes the "no explanation given anywhere" gap without spending macOS CI budget.

### B2 — GitHub Actions: real-CLI integration job (new workflow, Linux-only, cheap)
New `.github/workflows/real-cli-integration.yml`, `runs-on: ubuntu-latest` (Docker preinstalled). Two tiers:

**Tier 1 — no-auth contract checks (build now)**:
- Install the real `sbx` `.deb` the same way `docs/install-sbx-claude-code-web.md` does (fetch latest release metadata from `docker/sbx-releases`, `apt-get install --no-install-recommends`).
- Run `sbx version` and `--help` for every subcommand the app shells out to (`ls`, `create`, `run`, `stop`, `rm`, `policy ls|allow|deny|rm|log`, `ports ls|publish|unpublish`) — verify first that these truly don't require `sbx login` (the install doc suggests `version` works pre-auth; confirm for the others before relying on it, drop any that don't).
- Assert against the exact flags/subcommands the Swift code and `docs/sbx-cli-reference.md` assume post-A1 (e.g. `run --help` shows `--name`, `policy --help` shows `init` not `set-default`) — a lightweight contract test that would have caught this exact v0.23→v0.34 drift, continuously.
- Verification that it's a real check: temporarily revert one A3 fix locally and confirm the job fails.

**Tier 2 — live lifecycle tests (gated on a short spike into non-interactive auth)**:
- `sbx login` is an interactive device-code OAuth flow; no repo workflow currently has a non-interactive credential path (`grep -rn "secrets\."` across `.github/workflows/` returns nothing). Before building this tier, spend a short spike checking whether Docker Sandboxes offers any token/service-account-style non-interactive login suitable for a GitHub Actions secret.
- If yes: add an opt-in env switch (e.g. `SBX_UI_REAL_CLI=1`) that `CLIE2ETests/CLIE2EHelpers.swift`'s `CLIRunner.run()` (currently forces `SBX_CLI_MOCK=1` + mock PATH-prepend at lines 104-110) can check to run against the real, authenticated CLI instead. Scope to `create`/`run`/`ls --json`/`stop`/`rm` lifecycle + `policy allow/deny/ls`. Run non-blocking (scheduled + `workflow_dispatch`, not on every PR), clean up sandboxes unconditionally even on failure.
- If no viable non-interactive credential exists: drop Tier 2 entirely — don't leave it half-built. Tier 1 + Workstream B3 (where a human *can* complete `sbx login` once per web session) become the closest available substitute for live-lifecycle real-CLI coverage.

### B3 — Claude Code on the Web: automate the automatable parts of `docs/install-sbx-claude-code-web.md`
Use the `session-start-hook` skill to create `.claude/settings.json` + a `SessionStart` hook script:
- **Automate**: detect OS/arch, fetch latest `docker/sbx-releases` metadata, download + `apt-get install --no-install-recommends` the `.deb`, run `sbx version` to confirm install and log the detected version (dogfoods A4), check auth state and export an env var (e.g. `SBX_REAL_CLI_AVAILABLE`) via `$CLAUDE_ENV_FILE` for later test invocations to branch on, and `swift build --package-path cli` so `sbx-ui-cli` is ready.
- **Cannot automate**: `sbx login`'s device-code OAuth — stays a documented manual step (post-A1-fixed) in `docs/install-sbx-claude-code-web.md` for anyone who wants real-CLI-backed testing in a given web session.
- **Graceful degradation**: any test path that would exercise the real CLI checks `SBX_REAL_CLI_AVAILABLE`/auth state first and falls back to `tools/mock-sbx` with a clear log line if not authenticated — reuse the same `SBX_UI_REAL_CLI`-style switch from B2 Tier 2 so both paths share one mechanism.
- **Explicitly out of scope**: XCUITest/the macOS GUI layer cannot run here (Linux, no Xcode, no GUI session) — this workstream's E2E story is the Linux CLI + `SBXCore` layer only.
- Files: new `.claude/settings.json`, new `.claude/hooks/session-start.sh`; update `docs/install-sbx-claude-code-web.md` to point at the hook for the now-automated steps.
- Verification: run the hook script directly and confirm `sbx version` succeeds afterward; confirm a test run before `sbx login` gracefully falls back to mock.

---

## Sequencing

```
A1 (docs) → A2 (mock) → A3 (Swift service/parser) → A4 (version awareness) → A5 (hardening)
                                                         ↑ B2 Tier 1 becomes genuinely useful once A1-A3 land

B0 (test coverage + doc counts)   — independent, anytime
B1 (retire dead XCUITest step)    — independent, anytime, quick
B2 Tier 1 (no-auth contract checks) — can start immediately; re-run/expand once A1-A3 land
B2 Tier 2 (live lifecycle, gated on auth spike) — only if the spike finds a viable path
B3 (web session hook)             — install/build automation independent of Workstream A;
                                     "run real-CLI tests" portion benefits from A1-A4
```

Recommended order: **A1 → A2 → A3** (unblocks correctness) in parallel with **B0 / B1 / B2-Tier-1** (no dependency) → **A4** → re-run B2-Tier-1 against the modernized app → short auth spike → **B2-Tier-2** if viable → **B3** → **A5**.

## Verification Summary

| Phase | Primary signal |
|---|---|
| A1 | Manual diff against real `sbx --help` / `sbx policy --help` |
| A2 | `bash tools/mock-sbx-tests.sh` green (extended assertions) |
| A3 | `swift test --package-path cli` (103 tests) + macOS unit suite green |
| A4 | New version-parsing unit tests + `CLIE2ETests` case for the new subcommand |
| B0 | New XCUITest passes locally; doc counts match `grep -c` output |
| B1 | `tests.yml` diff reviewed — no functional change, just cleanup |
| B2 Tier 1 | Job fails when a deliberately-reverted A3 fix is reintroduced (proves it's a real check) |
| B2 Tier 2 | Manual `workflow_dispatch` with secret configured; sandbox cleanup confirmed |
| B3 | Direct hook script run + pre-login graceful mock fallback confirmed |

## Critical Files

- `sbx-ui/Services/RealSbxService.swift` — CLI argument construction (A3)
- `sbx-ui/Services/SbxServiceProtocol.swift` — JSON models, protocol surface (A3, A4)
- `sbx-ui/Services/SbxOutputParser.swift` — table parsing (A3, A5)
- `sbx-ui/Stores/PolicyStore.swift` — confirmed no per-sandbox scoping exists (informs A1/A3)
- `tools/mock-sbx` + `tools/mock-sbx-tests.sh` — emulator + its tests (A2)
- `docs/sbx-cli-reference.md`, `docs/install-sbx-claude-code-web.md` — docs (A1, B3)
- `.github/workflows/tests.yml`, `.github/workflows/linux-cli-tests.yml` — existing CI (B1)
- new `.github/workflows/real-cli-integration.yml` (B2)
- `cli/Tests/CLIE2ETests/CLIE2EHelpers.swift` — mock-forcing switch to make opt-out-able (B2, B3)
- `cli/Sources/sbx-ui-cli/Commands.swift`, `CLI.swift` — new version/doctor command (A4)
- `.kiro/specs/editor/tasks.md` — task 10.3 (B0)
- new `.claude/settings.json`, `.claude/hooks/session-start.sh` (B3)

## Next Step

Run `/kiro:spec-init` against this document (splitting into an "sbx-cli-modernization" spec for Workstream A and an "e2e-testing-infra" spec for Workstream B is a reasonable split, since they have different reviewers/risk profiles) to produce formal requirements, design, and tasks docs before implementation begins.
