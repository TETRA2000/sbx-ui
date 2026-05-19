# sbx-ui Roadmap: Wire Up Recent sbx CLI Capabilities

## Context

sbx-ui currently wraps `sbx` CLI v0.23.0 (last verified `2026-04-04` per `docs/sbx-cli-reference.md`). Today (`2026-05-19`) I re-fetched the official Docker Sandbox docs (https://docs.docker.com/ai/sandboxes/*) and cross-referenced them against `sbx-ui/Services/SbxServiceProtocol.swift`, `sbx-ui/Services/RealSbxService.swift`, `sbx-ui/Models/DomainTypes.swift`, the store layer, and the view layer.

**Finding:** the sbx CLI exposes roughly twelve capabilities that the UI does not surface. Most are not "brand new" features — they have existed for some time — but they have never been wired in. The gaps cluster into three themes:

1. **Security plumbing** (`sbx secret`, `sbx login`, `sbx diagnose`, `sbx reset`, per-sandbox policy scoping, `sbx policy reset`/`set-default`) — directly contradicts the "security-conscious enterprise-class" positioning in `.kiro/steering/product.md` because users have to drop to the CLI to manage credentials and recover from broken state.
2. **Workflow completeness** (`--branch` mode, resource limits/templates, multi-agent support, multi-workspace mounts, `sbx run -- AGENT_ARGS`) — the steering doc explicitly says "Exposes the full `sbx` surface area … no terminal memorization required", but several common flows still require the CLI.
3. **Operational polish** (`sbx cp`, telemetry opt-out, version probe) — small additions that round out the surface.

The intended outcome is a prioritized roadmap that the team can convert into Kiro specs one at a time, mirroring how `sbx-ui` and `editor` were sequenced (see `.kiro/specs/*/spec.json`). This file is the roadmap, not the implementation plan for any single feature.

## Prerequisite: re-verify the CLI reference

Before drafting any feature spec, refresh `docs/sbx-cli-reference.md` against a live `sbx` binary on the latest release channel. The doc is dated `2026-04-04` and several command shapes below (e.g. `sbx diagnose --output`, `sbx reset --preserve-secrets`, `sbx secret set-custom`) need flag-level verification before they are encoded into Swift. Owner of this pass should also confirm the installed CLI version (`sbx --version`) and update the `Requirements` section of `README.md` if the floor has moved past v0.23.0.

---

## Tier 1 — Security plumbing (do these first)

These three eliminate the largest "drop to terminal" gap and reinforce the security narrative in the steering doc.

### 1.1 Secrets management — `sbx secret`
**Why first.** The Docker docs explicitly recommend keychain-stored secrets over plaintext env vars; today sbx-ui forces users into the latter (`sbx-ui/Stores/EnvVarStore.swift` + `/etc/sandbox-persistent.sh`). This is the only Tier-1 item that adds a brand-new view.

**CLI surface to add:**
- `sbx secret ls [--json]`
- `sbx secret set -g <service>` and `sbx secret set <sandbox> <service>` for built-ins: `anthropic, aws, github, google, groq, mistral, nebius, openai, xai`
- `sbx secret set-custom --host <domain> --env <var> --value <secret>`
- `sbx secret rm <id-or-service>`
- Special flows: `sbx secret set -g openai --oauth`, GitHub piping `gh auth token | sbx secret set -g github`

**Critical files to touch:**
- `sbx-ui/Services/SbxServiceProtocol.swift` — add `secretList`, `secretSet`, `secretSetCustom`, `secretRemove`
- `sbx-ui/Services/RealSbxService.swift` — shell-out implementations, mirroring existing `policy*` patterns at lines 73–130
- `sbx-ui/Models/DomainTypes.swift` — new `Secret`, `SecretScope` (`.global` / `.sandbox(String)`), `BuiltInService` enum
- `sbx-ui/Stores/` — new `SecretStore.swift` (model on `PolicyStore`)
- `sbx-ui/Views/Secrets/` — new feature folder with `SecretPanelView`, `AddSecretSheet`, parallels `Views/Policies/`
- `sbx-ui/Views/SidebarView.swift` — add Secrets nav item
- `tools/mock-sbx` and `tools/mock-sbx-tests.sh` — emulate the new subcommand using on-disk state files so UI tests stay Docker-free
- `cli/Sources/sbx-ui-cli/` — mirror as `SecretCommands.swift`
- `docs/sbx-cli-reference.md` and `docs/mock-sbx.md` — extend both references

**Reuse:** policy CRUD pattern in `PolicyStore` and `Views/Policies/`; accessibility-identifier conventions in `CLAUDE.md` ("Available Accessibility Identifiers" section); `SbxOutputParser` for table parsing.

---

### 1.2 Diagnose & recovery — `sbx diagnose`, `sbx reset`
**Why second.** Today, when `RealSbxService.checkCli` (line 219) detects `dockerNotRunning`, the only recourse the UI shows is the `ErrorStateView`. The CLI offers real diagnostics that we silently ignore.

**CLI surface to add:**
- `sbx diagnose` (text) and `sbx diagnose --output json` — power a Settings → Diagnostics panel
- `sbx diagnose --output github-issue` — copyable bug report
- `sbx diagnose --upload` — generates a support bundle ID; surface the returned identifier
- `sbx reset --force` and `sbx reset --preserve-secrets` — last-resort recovery action in Settings, with a strong confirmation modal

**Critical files to touch:**
- `sbx-ui/Services/SbxServiceProtocol.swift` — add `diagnose() -> DiagnosticReport`, `reset(preserveSecrets: Bool)`
- `sbx-ui/Models/DomainTypes.swift` — `DiagnosticReport` (checks: cli binary, daemon, version, storage dirs, auth) + `DiagnosticIssue`
- `sbx-ui/Views/Settings/DiagnosticsPanelView.swift` — new
- `sbx-ui/Views/Error/ErrorStateView.swift` — link "Run diagnostics" from existing error states
- `sbx-ui/Stores/SettingsStore.swift` — diagnostics state + last-run timestamp
- `tools/mock-sbx` — return a canned `--output json` payload for tests

**Reuse:** existing `LogStore` + `DebugLogView.swift` patterns for streaming output; `ErrorStateView` already in `Views/Error/`.

---

### 1.3 Policy scoping & defaults — `-g`, `policy reset`, `policy set-default`
**Why third.** Quick win; only touches one feature area. `RealSbxService.policyAllow/Deny` (lines 79–93) currently always invokes global scope by passing no sandbox; the CLI supports per-sandbox scoping via the positional argument, and the UI claims "global allow/deny" in `product.md` despite no scope control.

**CLI surface to add:**
- `sbx policy allow|deny network [-g | SANDBOX] <resources>` — already partially implemented; expose scope toggle
- `sbx policy reset [--force]` — clear custom policies
- `sbx policy set-default <allow-all|balanced|deny-all>`

**Critical files to touch:**
- `sbx-ui/Services/SbxServiceProtocol.swift` — add `scope: PolicyScope` parameter to allow/deny, plus `policyReset()`, `policySetDefault(PolicyDefault)`
- `sbx-ui/Models/DomainTypes.swift` — `PolicyScope` enum, `PolicyDefault` enum, extend `PolicyRule` with `scope` and `origin` (the doc lists `NAME / TYPE / ORIGIN / DECISION / STATUS / RESOURCES` columns; we drop `ORIGIN` and `STATUS` today)
- `sbx-ui/Services/SbxOutputParser.swift` — parse the `ORIGIN`/`STATUS` columns
- `sbx-ui/Views/Policies/AddPolicySheet.swift` — scope picker; defaults to global to preserve current behavior
- `sbx-ui/Views/Policies/PolicyPanelView.swift` — "Reset" + "Default profile" controls; `PolicyDefault` segmented picker
- `tools/mock-sbx` — extend policy table format

**Reuse:** existing `PolicyPanelView`, `AddPolicySheet`, `policyList` parser.

---

## Tier 2 — Workflow completeness

### 2.1 Branch mode — `--branch <name>` / `--branch auto`
Touches the central create flow. Most-requested per `IDEA.md` ("Worktree support").
- Extend `RunOptions` (`Models/DomainTypes.swift:71-78`) with `branch: BranchMode?`
- Update `RealSbxService.run` (line 32) to pass `--branch`
- `CreateProjectSheet.swift` gains a branch toggle (off / auto / named)
- Surface `git worktree remove .sbx/<name>-worktrees/<branch>` recovery in the Diagnostics panel (Tier 1.2)

### 2.2 Resource limits & templates
- `RunOptions` gains `memory`, `cpus`, `template`
- `CreateProjectSheet.swift` adds an "Advanced" disclosure section
- Template list seeded from `docker/sandbox-templates:claude-code` and similar; defer template discovery (no CLI subcommand exposes the catalog) — hard-code a short allow-list and an "Other…" text field

### 2.3 Multi-agent support
- `Sandbox.agent` is already a `String` but the UI forces `"claude"`; expose an enum-backed picker for `claude, codex, copilot, docker-agent, factory-ai, gemini, kiro, opencode, shell`
- `CreateProjectSheet.swift` agent picker; `SandboxCardView.swift` already renders `agent`
- Reconsider `TerminalSessionStore` agent-specific prompt assumptions; the Kanban auto-execution path sends `claude --dangerously-skip-permissions` literal strings and must be parametrized

### 2.4 Multi-workspace mounts (with `:ro`)
- `Sandbox.workspace` is a single `String`; widen `Sandbox.workspaces: [WorkspaceMount]` with `path` + `readOnly`
- The `sbx ls --json` `workspaces` field is already an array (`SbxSandboxJson.workspaces` in `SbxServiceProtocol.swift:68`), but the service collapses it to `workspaces?.first ?? ""` (`RealSbxService.swift:25`)
- `CreateProjectSheet.swift` allows adding additional read-only mounts

### 2.5 Agent-arg forwarding — `sbx run -- AGENT_ARGS`
The Kanban store already constructs `claude --dangerously-skip-permissions "<prompt>"` strings inline via `sbx exec`. Move this to a first-class `runOptions.agentArgs: [String]` and let the Session panel offer `--continue` / `--resume` shortcuts.

---

## Tier 3 — Operational polish

### 3.1 `sbx cp` — host↔sandbox file transfer
- New `SbxServiceProtocol.copy(from: CopyTarget, to: CopyTarget)`
- Power "Upload file" in the Editor (`Views/Editor/SandboxWorkspaceView.swift`) and a "Save to host" command from the right-click menu in `FileTreeView.swift`

### 3.2 Telemetry opt-out
- Add `SBX_NO_TELEMETRY=1` toggle in `SettingsStore` and `ServiceFactory` (export the env var when spawning the CLI)

### 3.3 Login flow — `sbx login`
- Detect "You are not authenticated to Docker" in `RealSbxService.checkCli` and route to a new `LoginView`
- Most users authenticate via Docker Desktop; this is best-effort

### 3.4 Version probe + drift warning
- New `RealSbxService.version()` running `sbx --version`
- On app launch, compare against a hard-coded `MIN_SBX_VERSION = "0.23.0"`; warn via `ToastView` if older

---

## Sequencing recommendation

Convert each tier-1 item into its own Kiro spec under `.kiro/specs/`, in order. The `sbx-ui` spec used `Phase 0 → 1 → 2` per `CLAUDE.md`; reuse that cadence:

1. `/kiro:spec-init "sbx-secrets"` → ship 1.1
2. `/kiro:spec-init "sbx-diagnostics"` → ship 1.2 (depends on 1.1's confirmation patterns for the reset action)
3. `/kiro:spec-init "sbx-policy-scope"` → ship 1.3
4. `/kiro:spec-init "sbx-branch-mode"` → ship 2.1
5. Bundle 2.2–2.5 into `sbx-create-sheet-v2` since they all hit `CreateProjectSheet.swift` and `RunOptions`
6. Bundle 3.x into `sbx-polish`

Document this ordering in `.kiro/steering/product.md` so future contributors see the planned surface expansion.

---

## Verification approach for any of these specs

Each spec must follow the existing test discipline in `CLAUDE.md` ("ALWAYS write and run tests after ANY code change"):

- **Unit tests** under `sbx-uiTests/` using `StubSbxService` pattern — extend the stub with every new protocol method
- **CLI mock** extension to `tools/mock-sbx` so the new subcommand is emulated; add cases to `tools/mock-sbx-tests.sh`
- **SPM tests** in `cli/Tests/SBXCoreTests/` and `cli/Tests/CLIE2ETests/` to keep Linux parity
- **UI/E2E tests** in `sbx-uiUITests/` driving the new views with `SBX_CLI_MOCK=1` + a unique `SBX_MOCK_STATE_DIR`; new accessibility identifiers added to the catalog in `CLAUDE.md` ("Available Accessibility Identifiers")
- **Documentation** sync: `docs/sbx-cli-reference.md` (real-CLI behavior) and `docs/mock-sbx.md` (mock behavior) must be updated together so the team can diff them when sbx upstream changes

Sanity check before merging any of the above: `swift test --package-path cli`, the Xcode `RunAllTests` MCP action, and `bash tools/mock-sbx-tests.sh` — all three must be green.

---

## Out of scope for this roadmap

- Org-managed policies (paid Docker Admin Console feature) — read-only "managed by admin" badge could ship with 1.3, but full UI is deferred
- MCP server installation flows for Claude Code agents inside the sandbox — those configs live in the workspace, already covered by the Editor feature
- Plugin-system changes (`docs/plugin-development.md`) — unrelated to sbx CLI surface; track separately
- Local Docker Model Runner integration — not enough CLI surface to wrap today
