# sbx-ui Improvement Plan

_Based on sbx CLI releases v0.31.0 – v0.33.0 (June 2026)_

---

## 1. Executive Summary

sbx has shipped significant new capabilities over the last several releases: a reworked sandbox identity model, clone-mode workspace isolation, a full secrets management layer, templates and kits for customisation, governance/audit features for enterprise, and multi-agent expansion beyond Claude. sbx-ui currently wraps sbx v0.23.0 and only covers Claude Code. This document maps the new sbx surface area to concrete improvements for sbx-ui.

---

## 2. New sbx Features Reference

### v0.31.0
- **Clone mode (`--clone`)** replaces `--branch`. The repository is mounted read-only; the agent works on an in-container shallow clone. A `sandbox-<name>` Git remote is added to the host and sandbox refs are mirrored to `refs/sandboxes/<name>/*`.
- **`sbx create` auto-starts daemon** when it is not already running.
- **`sbx logout` stops daemon and running sandboxes.**
- **Registry credentials** – `sbx secret set --registry <host>` stores OCI registry credentials for private template/kit pulls.
- **Policy and rule names** shown in `sbx policy ls` output.
- **Kits** (experimental) – declarative YAML artifacts applied at sandbox creation time.
- **Templates** – reusable sandbox images; `sbx template ls`, `sbx template save`, `sbx run --template`.

### v0.32.0
- **Audit logging** – structured JSONL records for every policy decision. Written to a per-OS log directory. Requires Docker AI Governance subscription.
- **Sign-in enforcement** – administrators can require Docker org membership verification via MDM/registry/policy file.
- **OpenRouter built-in secret provider** – `sbx secret set <sandbox> openrouter`.
- **`sbx secret set-custom`** unhidden – wildcard host patterns, repeatable `--host` flag.
- **On-disk encrypted fallback secrets store** for headless Linux hosts.
- **Governance policy visibility** – inactive governed rules hidden by default in `sbx policy ls`; `--include-inactive` reveals them.
- **`sbx version`** simplified to one line; `-D/--debug` gates details.
- **Global-default policy scope** – `-g/--global` removed; global is now default. `--sandbox <name>` scopes to a specific sandbox.

### v0.33.0-rc1 / rc2
- **`sbx run --name` identity overhaul** – `--name` identifies a sandbox independent of working directory. Multiple same-agent sandboxes per workspace with unique names. `sbx run <name>` (positional) deprecated in favour of `sbx run --name <name>`.
- **Stable per-sandbox `id`** – `sbx ls --json` now returns an `id` field.
- **DNS-based policy enforcement** – sandboxed DNS lookups are now gated on the network policy (closes DNS-exfiltration channel).
- **CIDR subnet allow rules** – `sbx policy allow network 10.10.14.0/24`.
- **`sbx cp -L`** – follow symlinks for container-to-host copies.
- **`sbx exec`** uses same working directory as `sbx run`.
- **Daemon inspect output** included in diagnostics bundle.

---

## 3. Current sbx-ui Capability Inventory

| Area | Status |
|------|--------|
| Sandbox lifecycle (create/stop/rm) | ✅ Implemented |
| Agent sessions (Claude Code) | ✅ Implemented |
| Shell sessions | ✅ Implemented |
| Kanban task orchestration | ✅ Implemented |
| Network policy (global allow/deny/log) | ✅ Implemented |
| Port forwarding | ✅ Implemented |
| Environment variables per sandbox | ✅ Implemented |
| Linux CLI (sbx-ui-cli) | ✅ Implemented |
| Multi-agent support | ❌ Claude only |
| Clone mode (`--clone`) | ❌ Not supported |
| Stable sandbox IDs | ❌ Not tracked |
| `sbx run --name` identity model | ❌ Uses old model |
| Secrets management UI | ❌ Not implemented |
| Templates UI | ❌ Not implemented |
| Kits UI | ❌ Not implemented |
| Per-sandbox policy scoping | ❌ Global only |
| Governance / audit log viewer | ❌ Not implemented |
| CIDR-format policy rules | ❌ Not validated |
| File copy (`sbx cp`) | ❌ Not implemented |
| Daemon management | ❌ Not implemented |
| sbx CLI reference up to date | ❌ Pinned to v0.23.0 |

---

## 4. Improvement Areas

### 4.1 Multi-Agent Support (High Priority)

sbx supports eight agent types: `claude`, `codex`, `gemini`, `kiro`, `opencode`, `copilot`, `docker-agent`, `shell`. sbx-ui only creates Claude sandboxes.

**Changes needed:**
- Add an "Agent" picker to the Create Sandbox sheet (dropdown of all supported agents).
- Store the agent type in `Sandbox.agent` (already in the model) and display it on the sandbox card.
- Update session launch logic so `sbx run <agent> --name <name>` uses the correct agent binary.
- Add agent-specific icons/badges in the UI (Claude, Codex, Gemini, Kiro, etc.).
- Update the mock (`tools/mock-sbx`) to accept and record the agent argument.
- Surface per-agent credential requirements (e.g. prompt to run `sbx secret set` for the selected agent if not yet configured).

### 4.2 Sandbox Identity Overhaul — `--name` and Stable IDs (High Priority)

The sbx CLI now treats `--name` as the primary sandbox identifier, independent of working directory.  `sbx ls --json` returns a stable `id`.

**Changes needed:**
- Update `Sandbox` model to store the stable `id` returned by `sbx ls --json` (already partially there, but the mock still generates its own IDs).
- Change `run(agent:workspace:opts:)` to use `sbx run <agent> --name <name>` form.
- Remove any working-directory coupling from sandbox identity.
- Allow re-attaching to a sandbox from a different workspace via its name.
- Update `SbxOutputParser` to decode the new `id` field from `sbx ls --json`.
- Update `tools/mock-sbx` to produce `id` in JSON output.
- Update `docs/sbx-cli-reference.md` to document the new `--name` behaviour and deprecation of positional sandbox name.

### 4.3 Clone Mode Support (High Priority)

`--clone` provides stronger workspace isolation and is the recommended approach for agent work going forward.

**Changes needed:**
- Add a "Clone mode" toggle to the Create Sandbox sheet (off by default, matching sbx default).
- Pass `--clone` to `sbx create`/`sbx run` when selected.
- Show clone mode status on the sandbox card (e.g. a "Clone" badge).
- In clone mode, show the `sandbox-<name>` Git remote URL and a "Sync to host" action (using `git fetch sandbox-<name>`).
- Update `RunOptions` model to carry a `cloneMode: Bool` field.
- Update the mock to handle `--clone` flag and produce appropriate output.

### 4.4 Secrets Management UI (High Priority)

sbx now has a rich secrets layer: built-in service providers (Anthropic, OpenAI, GitHub, OpenRouter, etc.), custom secrets with wildcard host patterns, and registry credentials. There is no UI for any of this.

**Changes needed:**
- Add a **Secrets** panel (new top-level section alongside Policies and Ports).
- List stored secrets with `sbx secret ls` (service name, scope: global vs sandbox).
- Allow adding secrets for built-in providers via a guided form (service picker + credential input).
- Allow removing secrets with `sbx secret rm`.
- **Custom secrets** form: host pattern(s), env var name, optional placeholder, secret value.
- **Registry credentials** form: registry host, username, token, optional sandbox scope.
- Show a "Secrets not configured" warning on the Create Sandbox sheet when the selected agent has no stored credential.
- Extend `SbxServiceProtocol` with `secretList`, `secretSet`, `secretRemove` methods.
- Extend the mock to support `sbx secret ls/set/rm` commands.

### 4.5 Templates and Kits UI (Medium Priority)

Templates are reusable sandbox images; kits are YAML artifacts that layer config/credentials/tools at runtime.

**Changes needed:**
- Add a **Templates** sub-section under Settings or the Create sheet.
  - List available templates with `sbx template ls`.
  - Allow selecting a template in the Create Sandbox sheet (`--template <name>`).
  - Allow saving a running sandbox as a template (`sbx template save <sandbox> <name>`).
- Add a **Kits** sub-section (experimental badge).
  - List available kits and apply a kit when creating a sandbox (`--kit <name>`).
  - Show kit status on sandbox cards.
- Extend `SbxServiceProtocol` with `templateList`, `templateSave`, and `kitList` methods.

### 4.6 Per-Sandbox Policy Scoping (Medium Priority)

As of v0.32.0, `sbx policy allow|deny` is global by default and uses `--sandbox <name>` to scope to a specific sandbox. The current UI uses the old `-g` flag and only manages global rules.

**Changes needed:**
- Update all `sbx policy allow/deny/rm` invocations to drop the `-g` flag (now the default).
- Add a "Scope" picker on the Add Policy sheet: "All sandboxes" (global default) vs "This sandbox only" (adds `--sandbox <name>`).
- Display per-sandbox rules separately from global rules on the Policies panel.
- Update `SbxOutputParser` to parse policy names (now shown in `sbx policy ls`).
- Support `--sandbox` argument in the mock.

### 4.7 Governance & Audit Log Viewer (Medium Priority)

Enterprise users need visibility into audit records and governance policy status.

**Changes needed:**
- Add a **Governance** section to the Policies panel.
  - Show "Managed by `<org>`" header when a governance policy is active (parse from `sbx policy ls` output).
  - Show inactive governed rules in a collapsed section with a "Show inactive" toggle (maps to `--include-inactive`).
- Add an **Audit Logs** viewer panel.
  - Tail-read JSONL files from the platform-appropriate audit directory (`~/Library/Logs/com.docker.sandboxes/sandboxes/auditkit/` on macOS).
  - Show records in a timeline view: timestamp, sandbox, resource, decision (allow/deny), rule, username.
  - Allow filtering by sandbox name, decision, and time range.
  - Add an "Export" action to copy records to clipboard or save to file.

### 4.8 CIDR Subnet Policy Rules (Medium Priority)

`sbx policy allow network 10.10.14.0/24` is now supported. The current policy input only accepts domain names.

**Changes needed:**
- Update the resource input validation in the Add Policy sheet to accept CIDR notation (`x.x.x.x/nn`) as well as domain names.
- Show CIDR rules with a different icon/badge vs domain rules in the policy list.

### 4.9 File Copy UI — `sbx cp` (Low Priority)

`sbx cp` copies files between the host and sandbox.  `sbx cp -L` follows symlinks for container-to-host copies.

**Changes needed:**
- Add a "Files" action button on the sandbox card or in the session view.
- Simple file browser panel showing sandbox `/workspace` contents.
- Drag-and-drop (or file picker) to copy files in both directions.
- Expose `sbx cp [--follow-symlinks]` through a new `fileCopy` service method.

### 4.10 Daemon Management Panel (Low Priority)

The daemon lifecycle is now more visible (auto-start on `sbx create`, stop on `sbx logout`).

**Changes needed:**
- Show daemon status (running/stopped) in the sidebar or toolbar.
- Add explicit "Start Daemon" / "Stop Daemon" actions.
- Show a "Daemon not running" banner on the dashboard when `sbx ls` fails with a daemon-not-running error.
- Add a "Collect Diagnostics" action that triggers `sbx diagnostics` and reveals the output folder.

### 4.11 CLI Reference Update (Low Priority)

`docs/sbx-cli-reference.md` is pinned to v0.23.0 and many commands have changed.

**Changes needed:**
- Update the reference document to v0.33.0, covering:
  - `sbx run --name` syntax and deprecation of positional sandbox name.
  - `sbx ls --json` new `id` field.
  - `sbx policy allow|deny|rm` global-default scope, `--sandbox` flag, removal of `-g`.
  - `sbx secret set/set-custom/ls/rm` full command surface.
  - `sbx template ls/save`, `sbx run --template`.
  - `sbx cp [-L]`.
  - `sbx version` simplified output.
  - Clone mode (`--clone`) replacing `--branch`.
- Update the mock (`tools/mock-sbx`) to match the new CLI surface.

---

## 5. Phased Delivery

### Phase 1 — CLI Compatibility & Multi-Agent (Weeks 1–3)
_Unblocks all future work by keeping sbx-ui compatible with sbx v0.33+._

1. Update `docs/sbx-cli-reference.md` to v0.33.0.
2. Update `tools/mock-sbx` to match v0.33.0 output (new `id` field, `--name` identity, dropped `-g`).
3. Implement stable sandbox `id` in the model and parser.
4. Switch `sbx policy allow|deny|rm` invocations to global-default (drop `-g`).
5. Add agent picker to the Create Sandbox sheet and update `sbx run` invocation.
6. Update tests to cover new mock behaviour.

### Phase 2 — Secrets Management (Weeks 4–5)
_High developer value; unblocks multi-agent credential setup._

1. Extend `SbxServiceProtocol` with secrets methods.
2. Implement `SecretStore` (list, add, remove, built-in + custom + registry).
3. Build Secrets panel UI with service picker and credential forms.
4. Add sandbox-create-time credential warnings per selected agent.

### Phase 3 — Clone Mode & Identity (Weeks 6–7)

1. Add clone mode toggle to Create sheet; update `RunOptions`.
2. Display clone status on sandbox cards.
3. Add "Sync to host" Git remote action for cloned sandboxes.
4. Implement per-sandbox policy scoping in the Policies panel.
5. Update CIDR subnet validation in policy add form.

### Phase 4 — Templates, Kits & Governance (Weeks 8–10)

1. Templates UI (list, select at create-time, save from running sandbox).
2. Kits UI (list, apply at create-time, experimental badge).
3. Governance status display in Policies panel.
4. Audit log viewer (JSONL file reader, timeline view, export).

### Phase 5 — Quality of Life (Weeks 11–12)

1. Daemon management panel (status, start/stop, diagnostics).
2. File copy UI (`sbx cp`).
3. Daemon-not-running banner on dashboard.

---

## 6. Cross-Cutting Concerns

### Test Coverage
- Every new service method must have a corresponding `StubSbxService` stub and unit test.
- Every new UI surface must have at least one `XCUITest` E2E scenario using the mock.
- The mock must be extended in lockstep with new CLI surface so no feature can ship without test coverage.

### CLI Reference Discipline
- `docs/sbx-cli-reference.md` must be kept current. Any service or parser change that touches a CLI command must update the reference document in the same PR.

### Linux CLI Parity
- Features added to `SBXCore` (new service methods, model fields) should be exposed in `sbx-ui-cli` commands at the same time.

### Security
- Secrets (API keys, tokens) must never appear in sbx-ui logs, accessibility labels, or persisted state.
- The Secrets panel must mask credential values by default (show/hide toggle).
- Audit log files are read-only; sbx-ui must never write to or delete them.
