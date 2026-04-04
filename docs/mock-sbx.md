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

All commands match the real `sbx` CLI v0.23.0 syntax (see `docs/sbx-cli-reference.md`):

- `sbx ls [--json]` — List sandboxes
- `sbx run <agent> <workspace> [--name <name>]` — Create and attach
- `sbx run <name>` — Attach to existing sandbox
- `sbx stop <name>` — Stop sandbox, clear ports
- `sbx rm [-f] <name>` — Remove sandbox
- `sbx create [--name <name>] <agent> [<workspace>]` — Create without attaching
- `sbx policy ls` — List policies (tabular)
- `sbx policy allow network <resources>` — Add allow rule
- `sbx policy deny network <resources>` — Add deny rule
- `sbx policy rm network --resource <resource>` — Remove rule
- `sbx policy log [<sandbox>] --json` — Policy log (JSON)
- `sbx ports <name> [--json]` — List ports
- `sbx ports <name> --publish <host>:<sbx>` — Publish port
- `sbx ports <name> --unpublish <host>:<sbx>` — Unpublish port
- `sbx exec -it <name> bash` — Open shell in sandbox
- `sbx version` — Show version
- `sbx help` — Show help

## Interactive Mode

When `sbx run` is called with a TTY attached (as by `PtySessionManager`), the script enters interactive mode:
1. Prints a Claude Code startup banner with ANSI colors
2. Shows a `>` prompt
3. Reads stdin line by line
4. For each input, simulates: Thinking → Reading file → Writing file → Done

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
