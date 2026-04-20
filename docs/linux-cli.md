# Linux CLI Reference (`sbx-ui-cli`)

A Swift command-line tool for managing Docker Sandboxes on Linux. Built on the same `SBXCore` service layer as the macOS GUI, it wraps the `sbx` CLI and provides colored table output with optional JSON mode.

## Installation

### Build from source

Requires Swift 6.0+ on Linux (Ubuntu 22.04+).

```bash
cd sbx-ui
swift build --package-path cli -c release
cp cli/.build/release/sbx-ui-cli /usr/local/bin/sbx-ui
```

### Development mode

```bash
swift run --package-path cli sbx-ui-cli ls
```

### Using the mock CLI

For development without Docker, point PATH at the mock:

```bash
export SBX_MOCK_STATE_DIR=$(mktemp -d)
export PATH="$(pwd)/tools:$PATH"
sbx-ui ls
```

## Global Options

| Option | Description |
|--------|-------------|
| `--json` | Output in JSON format (available on `ls`, `status`, `policy ls`, `policy log`, `ports ls`, `env ls`) |
| `--version` | Show version |
| `-h, --help` | Show help |

## Commands

### `sbx-ui ls`

List all sandboxes.

```bash
sbx-ui ls
sbx-ui --json ls
```

Output columns: `SANDBOX`, `AGENT`, `STATUS`, `PORTS`, `WORKSPACE`

### `sbx-ui create`

Create a new sandbox.

```bash
sbx-ui create <workspace> [--name <name>] [--agent <agent>]
```

| Argument/Option | Description | Default |
|-----------------|-------------|---------|
| `workspace` | Workspace path to mount (required) | |
| `-n, --name` | Sandbox name | `<agent>-<dirname>` |
| `-a, --agent` | Agent to use | `claude` |

```bash
sbx-ui create /home/user/my-project --name my-sb
sbx-ui create /home/user/project --agent claude --name demo
```

### `sbx-ui stop`

Stop a running sandbox.

```bash
sbx-ui stop <name>
```

### `sbx-ui rm`

Remove a sandbox (force, no confirmation prompt).

```bash
sbx-ui rm <name>
```

### `sbx-ui run`

Attach to a sandbox interactively. Replaces the current process with `sbx run`.

```bash
sbx-ui run <name>
```

### `sbx-ui exec`

Execute a command inside a sandbox.

```bash
sbx-ui exec <name> <command> [args...]
```

```bash
sbx-ui exec my-sb ls -la /workspace
sbx-ui exec my-sb cat /etc/os-release
```

### `sbx-ui status`

Show detailed status of a single sandbox, including ports and environment variables.

```bash
sbx-ui status <name>
sbx-ui --json status <name>
```

Example output:

```
Sandbox: my-sb
────────────────
  Agent:     claude
  Status:    running
  Workspace: /home/user/project

  Ports:
    8080 → 3000/tcp

  Environment Variables:
    API_KEY=secret123
    NODE_ENV=production
```

## Policy Commands

### `sbx-ui policy ls`

List all network policies.

```bash
sbx-ui policy ls
sbx-ui --json policy ls
```

Output columns: `NAME`, `TYPE`, `DECISION`, `RESOURCES`

### `sbx-ui policy allow`

Add a network allow rule.

```bash
sbx-ui policy allow <resources>
```

```bash
sbx-ui policy allow "*.example.com"
sbx-ui policy allow api.openai.com
```

### `sbx-ui policy deny`

Add a network deny rule.

```bash
sbx-ui policy deny <resources>
```

### `sbx-ui policy rm`

Remove a network policy by resource pattern.

```bash
sbx-ui policy rm <resources>
```

### `sbx-ui policy log`

View the policy activity log.

```bash
sbx-ui policy log [sandbox] [--blocked]
```

| Argument/Option | Description |
|-----------------|-------------|
| `sandbox` | Filter by sandbox name (optional) |
| `--blocked` | Show only blocked requests |

```bash
sbx-ui policy log                          # All entries
sbx-ui policy log my-sb                    # Filter by sandbox
sbx-ui policy log --blocked                # Only blocked
sbx-ui --json policy log                   # JSON output
```

Output is grouped into "Allowed requests" and "Blocked requests" sections with columns: `SANDBOX`, `HOST`, `PROXY`, `RULE`, `COUNT`.

## Port Commands

### `sbx-ui ports ls`

List published ports for a sandbox.

```bash
sbx-ui ports ls <name>
sbx-ui --json ports ls <name>
```

Output columns: `HOST IP`, `HOST PORT`, `SANDBOX PORT`, `PROTOCOL`

### `sbx-ui ports publish`

Publish a port mapping.

```bash
sbx-ui ports publish <name> <host_port>:<sandbox_port>
```

```bash
sbx-ui ports publish my-sb 8080:3000
sbx-ui ports publish my-sb 9090:4000
```

### `sbx-ui ports unpublish`

Remove a port mapping.

```bash
sbx-ui ports unpublish <name> <host_port>:<sandbox_port>
```

## Environment Variable Commands

Environment variables are persisted inside the sandbox via `/etc/sandbox-persistent.sh` using managed section markers, preserving any user edits outside the managed section.

### `sbx-ui env ls`

List managed environment variables for a sandbox.

```bash
sbx-ui env ls <name>
sbx-ui --json env ls <name>
```

### `sbx-ui env set`

Set (or update) an environment variable. Keys must match `[A-Za-z_][A-Za-z0-9_]*`.

```bash
sbx-ui env set <name> <key> <value>
```

```bash
sbx-ui env set my-sb API_KEY sk-abc123
sbx-ui env set my-sb NODE_ENV production
```

### `sbx-ui env rm`

Remove an environment variable.

```bash
sbx-ui env rm <name> <key>
```

## Output Formatting

- **Colored output** uses ANSI escape codes when connected to a TTY
- Set `NO_COLOR=1` to disable colors
- Set `FORCE_COLOR=1` to force colors (e.g., in CI pipelines)
- Status values are color-coded: running (green), stopped (dim), creating/removing (yellow)
- Policy decisions are color-coded: allow (green), deny (red)

## JSON Output

Pass `--json` before the subcommand for machine-readable JSON output:

```bash
sbx-ui --json ls
sbx-ui --json status my-sb
sbx-ui --json policy log
```

JSON is printed to stdout; status messages and errors go to stderr.

## Architecture

The CLI is a thin layer over the shared `SBXCore` library:

```
sbx-ui-cli (ArgumentParser commands)
     |
  SBXCore (SPM library)
     |
  RealSbxService (actor)
     |
  CliExecutor (subprocess)
     |
  sbx CLI binary
```

`SBXCore` contains the same Models and Services used by the macOS GUI. The CLI calls the service layer directly without the Store or View layers.

## Testing

Tests run on Linux via Swift Testing (`@Test`, `#expect`):

```bash
swift test --package-path cli
```

Two test targets cover the stack:

**`SBXCoreTests` (25 tests)** — library-level tests:
- **Validation** -- sandbox name and env key validation
- **Models** -- type construction, IDs, error descriptions
- **Parsers** -- policy list, policy log JSON, ports JSON, env var parsing, persistent.sh rebuild
- **Integration** -- full service operations against `mock-sbx` (create, stop, rm, policies, ports, env vars)

**`CLIE2ETests` (78 tests)** — end-to-end tests against the compiled binary:
- Spawn `sbx-ui-cli` as a subprocess with an isolated `SBX_MOCK_STATE_DIR` and
  `tools/` injected into PATH, then assert on captured stdout / stderr / exit code.
- Suites: help & version, ls, create, stop & rm, exec, status, policy ls,
  policy allow/deny/rm, policy log, ports ls, ports publish/unpublish,
  env ls, env set, env rm, formatting & color (NO_COLOR / FORCE_COLOR),
  argument-parser errors, runtime errors, scenarios (full lifecycle, policy
  round-trip, env var mutations, sandbox isolation), and runner isolation.
- Run just the E2E target with `swift test --package-path cli --filter CLIE2ETests`.
