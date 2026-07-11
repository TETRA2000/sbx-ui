# mock-sbx — CLI Emulator for Testing

A bash script that emulates the Docker Sandbox (`sbx`) CLI for integration testing without Docker Desktop.

## Purpose

The sbx-ui app has two test modes:

| Mode | Env Var | Service | Speed | Coverage |
|------|---------|---------|-------|----------|
| **In-memory mock** | `SBX_MOCK=1` | `MockSbxService` (Swift actor) | Fast | UI logic, stores |
| **CLI mock** | `SBX_CLI_MOCK=1` | `RealSbxService` → `mock-sbx` | Slower | Full CLI integration, parsing, process spawning |

The CLI mock exercises the real code path: `RealSbxService` → `CliExecutor` → `/usr/bin/env sbx` (finds `mock-sbx` via PATH) → file-based state.

## Usage

### Standalone

```bash
export SBX_MOCK_STATE_DIR="/tmp/my-test-state"
export PATH="$(pwd)/tools:$PATH"

sbx version
sbx run claude /path/to/project --name my-sandbox
sbx ls --json
sbx policy ls
sbx ports my-sandbox --publish 8080:3000
sbx stop my-sandbox
sbx rm -f my-sandbox
```

### Running the test suite

```bash
bash tools/mock-sbx-tests.sh
```

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `SBX_MOCK_STATE_DIR` | Directory for persistent state | `/tmp/mock-sbx-state` |

## State Directory Structure

```
$SBX_MOCK_STATE_DIR/
  .initialized              # Marker to prevent re-seeding
  sandboxes/<name>.json     # Sandbox state (SbxSandboxJson format)
  policies/<uuid>.json      # Policy rules
  ports/<name>.json         # Port mappings array
  policy-log/entries.json   # Policy log entries (SbxPolicyLogResponse format)
```

## Implemented Commands

All commands match the real `sbx` CLI v0.34.0 syntax (see `docs/sbx-cli-reference.md`):

- `sbx ls [--json]` — List sandboxes (JSON includes a stable per-sandbox `id`, persisted across calls)
- `sbx run <agent> <workspace> [--name <name>] [-- <agent_args>...]` — Create and attach
- `sbx run <name> [-- <agent_args>...]` — Attach to existing sandbox (deprecated bare-positional form, still accepted)
- `sbx run --name <name> [-- <agent_args>...]` — Attach to existing sandbox (current form)
- `sbx stop <name>` — Stop sandbox, clear ports
- `sbx rm [-f] <name>` — Remove sandbox
- `sbx create [--name <name>] <agent> [<workspace>]` — Create without attaching
- `sbx policy ls [--include-inactive]` — List policies (tabular). The mock has no active/inactive rule concept, so `--include-inactive` is accepted but is a deliberate no-op — this is a simplification, not a bug.
- `sbx policy allow network <resources>` — Add allow rule (global scope, no `--sandbox`/`-g` flag)
- `sbx policy deny network <resources>` — Add deny rule (global scope)
- `sbx policy rm network --resource <resource>` — Remove rule (global scope)
- `sbx policy init <preset>` — Set default network policy preset (`allow-all`/`balanced`/`deny-all`); `sbx policy set-default <preset>` accepted as a silent alias
- `sbx policy log [<sandbox>] --json` — Policy log (JSON)
- `sbx ports <name> [--json]` — List ports
- `sbx ports <name> --publish <host>:<sbx>` — Publish port
- `sbx ports <name> --unpublish <host>:<sbx>` — Unpublish port
- `sbx exec -it <name> bash` — Open shell in sandbox
- `sbx version [-D|--debug]` — Show version (single line by default, two-line client/server detail with `-D`)
- `sbx help` — Show help

## Interactive Mode

When `sbx run` is called with a TTY attached (as by `PtySessionManager`), the script enters interactive mode:
1. Prints a Claude Code startup banner with ANSI colors
2. If positional args were forwarded after `--`, treats the first as the
   initial prompt and emits `[received] <prompt>` followed by a fake
   processing trace — mirrors the real `claude "<prompt>"` behavior used by
   the kanban autonomous-execution path.
3. Shows a `>` prompt
4. Reads stdin line by line
5. For each input, simulates: Thinking → Reading file → Writing file → Done

## Default Policies

On first use, seeds 10 allow rules matching `MockSbxService` defaults:
`api.anthropic.com`, `*.npmjs.org`, `github.com`, `*.github.com`, `registry.hub.docker.com`, `*.docker.io`, `*.googleapis.com`, `api.openai.com`, `*.pypi.org`, `files.pythonhosted.org`

## Error Patterns

Errors are written to stderr with exit code 1. Patterns match what `RealSbxService.checkCli()` expects:

- `Error: sandbox '<name>' not found`
- `ERROR: publish port: port 127.0.0.1:<port>/tcp is already published`

## Debugging

Inspect state files directly:
```bash
cat $SBX_MOCK_STATE_DIR/sandboxes/my-sandbox.json
cat $SBX_MOCK_STATE_DIR/ports/my-sandbox.json
cat $SBX_MOCK_STATE_DIR/policies/*.json
```

Reset state:
```bash
rm -rf $SBX_MOCK_STATE_DIR
```
