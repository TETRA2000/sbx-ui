# sbx CLI Reference (v0.23.0)

Verified against real `sbx` CLI on 2026-04-04. This document captures the actual command syntax, output formats, and JSON schemas for all operations used by sbx-ui.

## Sandbox Lifecycle

### `sbx ls` — List sandboxes
```
sbx ls [--json] [-q]
```

**Table output:**
```
SANDBOX       AGENT    STATUS    PORTS                                                WORKSPACE
sbx-ui        claude   stopped                                                        /Users/dev/project
test-ports    claude   running   127.0.0.1:8080->3000/tcp, 127.0.0.1:9090->4000/tcp   /Users/dev/other
```

Column header: `SANDBOX` (not `NAME`).
Ports format: `<host_ip>:<host_port>-><sandbox_port>/<protocol>`, comma-separated.

**JSON output (`--json`):**
```json
{
  "sandboxes": [
    {
      "name": "test-ports",
      "agent": "claude",
      "status": "running",
      "ports": [
        { "host_ip": "127.0.0.1", "host_port": 8080, "sandbox_port": 3000, "protocol": "tcp" }
      ],
      "socket_path": "/tmp/sboxd-501-sandboxes/docker.sock",
      "workspaces": ["/Users/dev/project"]
    }
  ]
}
```

Note: `ports` field is absent (not empty array) when no ports are published. `workspaces` is an array.

### `sbx run` — Run agent in sandbox
```
sbx run [flags] SANDBOX | AGENT [PATH...] [-- AGENT_ARGS...]
```

Flags: `--name <name>`, `--branch <branch>`, `-m <memory>`, `-t <template>`, `--cpus <n>`

- Creates sandbox if it doesn't exist; attaches to existing one if it does
- Default name: `<agent>-<workdir>` (e.g., `claude-myproject`)
- Agents: claude, codex, copilot, docker-agent, factory-ai, gemini, kiro, opencode, shell

Arguments after `--` are forwarded to the agent CLI, **appended to sbx's
default launch command**. For claude this means they are appended to
`claude --dangerously-skip-permissions`. This works both when creating a
new sandbox and when attaching to an existing one:

```sh
# Resume the sandbox's previous agent session
sbx run claude -- --continue

# Attach to an existing sandbox with an initial prompt (claude treats the
# first positional as its initial prompt). sbx-ui uses this exact shape
# for autonomous Kanban task execution:
sbx run claude-markdown-jam -- "Implement feature X"
```

### `sbx create` — Create without attaching
```
sbx create [--name <name>] AGENT [PATH...]
```

Output on success:
```
✓ Created sandbox 'test-verify'
  Workspace: /path/to/project (direct mount)
  Agent: claude
```

### `sbx stop` — Stop sandbox
```
sbx stop SANDBOX [SANDBOX...]
```

Error: `Error: sandbox 'name' not found` (exit 1)

### `sbx rm` — Remove sandbox
```
sbx rm [SANDBOX...] [--force] [--all]
```

**Important:** Without `--force`, prompts for confirmation interactively. Use `-f` for programmatic removal.

Error: `Error: sandbox 'name' not found` (exit 1)

### `sbx exec` — Execute command in sandbox
```
sbx exec [flags] SANDBOX COMMAND [ARG...]
```

Flags: `-i` (interactive), `-t` (tty), `-d` (detach), `-u <user>`, `-e <env>`, `-w <workdir>`

Common usage: `sbx exec -it <sandbox> bash`

## Port Management

### `sbx ports` — Manage ports
```
sbx ports SANDBOX [--publish SPEC] [--unpublish SPEC] [--json]
```

No subcommands — uses flags on the `ports` command directly.

Port spec format: `[[HOST_IP:]HOST_PORT:]SANDBOX_PORT[/PROTOCOL]`

**List ports (no flags):**
```
sbx ports my-sandbox
```

Table output:
```
HOST IP     HOST PORT   SANDBOX PORT   PROTOCOL
127.0.0.1   8080        3000           tcp
```

JSON output:
```json
[
  { "host_ip": "127.0.0.1", "host_port": 8080, "sandbox_port": 3000, "protocol": "tcp" }
]
```

**Publish port:**
```
sbx ports my-sandbox --publish 8080:3000
```
Output: `Published 127.0.0.1:8080 -> 3000/tcp`

**Unpublish port:**
```
sbx ports my-sandbox --unpublish 8080:3000
```
Output: `Unpublished 127.0.0.1:8080 -> 3000/tcp`

**Duplicate port error:**
```
ERROR: publish port: port 127.0.0.1:8080/tcp is already published
```

## Network Policy Management

All policy commands use the `network` subcommand for the resource type.

### `sbx policy ls` — List policies
```
sbx policy ls [--type network]
```

Note: command is `ls` not `list`.

Table output:
```
NAME                                         TYPE      DECISION   RESOURCES
default-allow-all                            network   allow      **

local:e8b2eb34-972b-4b2c-9d2d-d30edd7612e6   network   allow      test.example.com

local:6b0dfb29-a64e-48cc-8a3a-6e35a40704ba   network   deny       evil.example.com
```

Note: Column header is `NAME` (not `ID`). Rules have blank line separators between them. Name format for user-added rules: `local:<uuid>`.

### `sbx policy allow network` — Add allow rule
```
sbx policy allow network RESOURCES
```

Output: `Policy added: <uuid> (<resources>)`

### `sbx policy deny network` — Add deny rule
```
sbx policy deny network RESOURCES
```

Output: `Policy added: <uuid> (<resources>)`

### `sbx policy rm network` — Remove policy
```
sbx policy rm network --resource <resource>
sbx policy rm network --id <uuid>
```

Output: `Policy removed: resources=<resource>`

### `sbx policy log` — View policy logs
```
sbx policy log [SANDBOX] [--json] [--limit N] [--type network]
```

Note: Sandbox name is a **positional argument**, not `--sandbox` flag.

**Table output:**
```
Allowed requests:
SANDBOX       TYPE      HOST                      PROXY            RULE             LAST SEEN        COUNT
test-verify   network   ports.ubuntu.com:80       forward          domain-allowed   18:55:49 4-Apr   1

Blocked requests:
SANDBOX       TYPE      HOST                PROXY     RULE          LAST SEEN        COUNT
test-verify   network   evil.example.com    forward   user-denied   18:56:01 4-Apr   3
```

Note: Output is grouped into "Allowed requests:" and "Blocked requests:" sections. No `STATUS` column — blocked/allowed is determined by section.

**JSON output (`--json`):**
```json
{
  "blocked_hosts": [
    {
      "host": "evil.example.com",
      "vm_name": "test-verify",
      "proxy_type": "forward",
      "rule": "user-denied",
      "last_seen": "2026-04-04T18:56:01.123456+09:00",
      "since": "2026-04-04T18:56:01.123456+09:00",
      "count_since": 3
    }
  ],
  "allowed_hosts": [
    {
      "host": "ports.ubuntu.com:80",
      "vm_name": "test-verify",
      "proxy_type": "forward",
      "rule": "domain-allowed",
      "last_seen": "2026-04-04T18:55:49.432561+09:00",
      "since": "2026-04-04T18:55:49.432561+09:00",
      "count_since": 1
    }
  ]
}
```

## Error Patterns

| Scenario | stderr | Exit Code |
|----------|--------|-----------|
| Sandbox not found | `Error: sandbox '<name>' not found` | 1 |
| Port already published | `ERROR: publish port: port 127.0.0.1:<port>/tcp is already published` | 1 |
| Timeout / daemon issue | `...net/http: request canceled (Client.Timeout exceeded while awaiting headers)` | 1 |
| No policy logs | `No policy log entries found` (stdout) | 0 |
| No published ports | `No published ports` (stdout) | 0 |

## Status Values

Observed: `running`, `stopped`. The `creating` and `removing` states are transient and may not appear in `sbx ls` output (they happen during `sbx run`/`sbx rm` execution).

## Available Agents

claude, codex, copilot, docker-agent, gemini, kiro, opencode, shell
