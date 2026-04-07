# Plugin Development Guide

> **Experimental:** The plugin system is under active development and may have security vulnerabilities. Only install and run plugins from sources you trust. Use at your own risk.

Build custom plugins to extend sbx-ui with automation, integrations, and custom commands.

## Quick Start

### 1. Create a plugin directory

```bash
mkdir -p ~/Library/Application\ Support/sbx-ui/plugins/com.example.my-plugin
cd ~/Library/Application\ Support/sbx-ui/plugins/com.example.my-plugin
```

### 2. Write a manifest (`plugin.json`)

```json
{
  "id": "com.example.my-plugin",
  "name": "My Plugin",
  "version": "1.0.0",
  "description": "A custom plugin for sbx-ui",
  "entry": "main.py",
  "runtime": "python3",
  "permissions": ["sandbox.list", "ui.log"],
  "triggers": ["manual"]
}
```

### 3. Write the plugin (Python example)

```python
#!/usr/bin/env python3
from sbx_plugin import SbxPlugin

plugin = SbxPlugin()

@plugin.on("initialize")
async def on_init(params):
    sandboxes = await plugin.sandbox.list()
    await plugin.ui.log(f"Found {len(sandboxes)} sandboxes")

plugin.start()
```

### 4. Install and run

Open sbx-ui → Plugins → Install Plugin → select your plugin directory. Click the play button to start.

---

## Architecture

Plugins run as **separate OS processes** that communicate with sbx-ui via **JSON-RPC 2.0 over stdin/stdout**. Each line of stdin/stdout is a complete JSON-RPC message.

```
┌──────────┐  stdin (JSON-RPC)   ┌────────────┐
│  sbx-ui  │ ─────────────────→  │   Plugin   │
│  (host)  │ ←─────────────────  │  (process) │
└──────────┘  stdout (JSON-RPC)  └────────────┘
                                  stderr → log
```

This means plugins can be written in **any language** — Python, TypeScript/Node.js, Go, Rust, shell scripts, etc.

---

## Plugin Manifest Reference

`plugin.json` in the plugin directory root:

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `id` | string | Yes | Reverse-domain identifier (e.g., `com.example.my-plugin`) |
| `name` | string | Yes | Human-readable name |
| `version` | string | Yes | Semantic version |
| `description` | string | Yes | Short description |
| `entry` | string | Yes | Relative path to entry file |
| `runtime` | string | No | Runtime command (e.g., `python3`, `node`). Omit for native binaries. |
| `permissions` | string[] | Yes | Required permissions (see below) |
| `triggers` | string[] | Yes | When the plugin runs (see below) |

### Permissions

| Permission | Description |
|-----------|-------------|
| `sandbox.list` | List sandboxes |
| `sandbox.exec` | Execute commands in sandboxes |
| `sandbox.stop` | Stop sandboxes |
| `sandbox.run` | Create or resume sandboxes |
| `ports.list` | List port mappings |
| `ports.publish` | Publish ports |
| `ports.unpublish` | Unpublish ports |
| `envVar.list` | List environment variables |
| `envVar.sync` | Set environment variables |
| `policy.list` | List network policies |
| `policy.allow` | Add allow rules |
| `policy.deny` | Add deny rules |
| `policy.remove` | Remove policy rules |
| `file.read` | Read files on host filesystem |
| `file.write` | Write files on host filesystem |
| `ui.notify` | Show notifications in sbx-ui |
| `ui.log` | Write to sbx-ui app log |

### Triggers

| Trigger | Description |
|---------|-------------|
| `manual` | Run on-demand from the Plugins UI |
| `onSandboxCreated` | Run when a sandbox is created |
| `onSandboxStopped` | Run when a sandbox is stopped |
| `onSandboxRemoved` | Run when a sandbox is removed |
| `onAppLaunch` | Run when sbx-ui starts |

---

## JSON-RPC Protocol Reference

### Host → Plugin (Notifications)

#### `initialize`
Sent when the plugin process starts.
```json
{"jsonrpc":"2.0","method":"initialize","params":{"pluginId":"com.example.my-plugin","version":"1.0.0"}}
```

#### `shutdown`
Sent when the plugin should gracefully exit.
```json
{"jsonrpc":"2.0","method":"shutdown"}
```

#### `event/onSandboxCreated`
```json
{"jsonrpc":"2.0","method":"event/onSandboxCreated","params":{"name":"my-sandbox","workspace":"/path/to/project"}}
```

#### `event/onSandboxStopped`, `event/onSandboxRemoved`
```json
{"jsonrpc":"2.0","method":"event/onSandboxStopped","params":{"name":"my-sandbox"}}
```

### Plugin → Host (Requests)

All requests follow JSON-RPC 2.0: include `jsonrpc`, `id`, `method`, and optional `params`.

#### `sandbox/list`
List all sandboxes.
- **Params**: none
- **Result**: `[{name, agent, status, workspace, ports}]`

#### `sandbox/exec`
Execute a command in a sandbox.
- **Params**: `{name: string, command: string, args?: string[]}`
- **Result**: `{stdout: string, stderr: string, exitCode: number}`

#### `sandbox/stop`
Stop a sandbox.
- **Params**: `{name: string}`
- **Result**: `{ok: true}`

#### `sandbox/run`
Create or resume a sandbox.
- **Params**: `{agent: string, workspace: string, name?: string}`
- **Result**: `{name, agent, status, workspace, ports}`

#### `sandbox/ports/list`
- **Params**: `{name: string}`
- **Result**: `[{hostPort, sandboxPort, protocolType}]`

#### `sandbox/ports/publish`
- **Params**: `{name: string, hostPort: number, sbxPort: number}`
- **Result**: `{hostPort, sandboxPort, protocolType}`

#### `sandbox/ports/unpublish`
- **Params**: `{name: string, hostPort: number, sbxPort: number}`
- **Result**: `{ok: true}`

#### `sandbox/envVars/list`
- **Params**: `{name: string}`
- **Result**: `[{key, value}]`

#### `sandbox/envVars/set`
- **Params**: `{name: string, key: string, value: string}`
- **Result**: `{ok: true}`

#### `policy/list`
- **Params**: none
- **Result**: `[{id, type, decision, resources}]`

#### `policy/allow`
- **Params**: `{resources: string}`
- **Result**: `{id, type, decision, resources}`

#### `policy/deny`
- **Params**: `{resources: string}`
- **Result**: `{id, type, decision, resources}`

#### `policy/remove`
- **Params**: `{resource: string}`
- **Result**: `{ok: true}`

#### `file/read`
Read a file from the host filesystem.
- **Params**: `{path: string}`
- **Result**: `{path: string, content: string}`

#### `file/write`
Write a file on the host filesystem.
- **Params**: `{path: string, content: string}`
- **Result**: `{path: string, ok: true}`

#### `ui/notify`
Show a notification in sbx-ui.
- **Params**: `{title: string, message: string, level?: string}`
- **Result**: `{ok: true}`

#### `ui/log`
Write to the sbx-ui app log.
- **Params**: `{message: string, level?: string}`
- **Result**: `{ok: true}`

### Error Codes

| Code | Meaning |
|------|---------|
| -32700 | Parse error |
| -32600 | Invalid request |
| -32601 | Method not found |
| -32602 | Invalid params |
| -32603 | Internal error |
| -32000 | Permission denied |
| -32001 | Rate limited |
| -32002 | Sandbox error (wraps SbxServiceError) |

---

## SDK Reference

### TypeScript (Node.js)

Install: `npm install @sbx-ui/plugin-sdk`

```typescript
import { SbxPlugin } from '@sbx-ui/plugin-sdk';

const plugin = new SbxPlugin();

// Handle events
plugin.on('initialize', async () => { /* ... */ });
plugin.on('event/onSandboxCreated', async (params) => { /* ... */ });

// API
await plugin.sandbox.list();
await plugin.sandbox.exec('my-sandbox', 'ls', ['-la']);
await plugin.sandbox.stop('my-sandbox');
await plugin.ports.list('my-sandbox');
await plugin.ports.publish('my-sandbox', 8080, 3000);
await plugin.envVars.list('my-sandbox');
await plugin.envVars.set('my-sandbox', 'KEY', 'value');
await plugin.policy.list();
await plugin.policy.allow('example.com');
await plugin.file.read('/path/to/file');
await plugin.file.write('/path/to/file', 'content');
await plugin.ui.notify('Title', 'Message');
await plugin.ui.log('Log message');

plugin.start();
```

### Python

Install: `pip install sbx-plugin-sdk`

```python
from sbx_plugin import SbxPlugin

plugin = SbxPlugin()

@plugin.on("initialize")
async def on_init(params):
    sandboxes = await plugin.sandbox.list()
    result = await plugin.sandbox.exec("my-sandbox", "ls", ["-la"])
    await plugin.ui.log(f"Output: {result.stdout}")

@plugin.on("event/onSandboxCreated")
async def on_created(params):
    await plugin.ui.notify("Created", f"Sandbox: {params['name']}")

plugin.start()
```

---

## Security Model

1. **Permission-based**: Plugins declare required permissions in `plugin.json`. Users approve on first run.
2. **OS-level sandboxing**: Each plugin runs under macOS `sandbox-exec` with a dynamically generated profile based on declared permissions. Plugins without `file.write` permission cannot write to the filesystem; plugins without network policy permissions cannot access the network. This enforces restrictions at the kernel level, not just the API layer.
3. **Process isolation**: Each plugin runs in its own OS process. A crash won't affect sbx-ui.
4. **Filesystem restriction**: `file/read` and `file/write` reject path traversal (`../`).
5. **Rate limiting**: 100 requests/second per plugin. Exceeding returns error code `-32001`.
6. **Input validation**: All parameters are validated (sandbox names, port ranges, env var keys).
7. **Audit logging**: All plugin API calls are logged in the sbx-ui debug log.

---

## Testing Plugins

### Local development

1. Create your plugin in a temp directory
2. Use the Install Plugin button to copy it to the plugins directory
3. Start the plugin from the Plugins UI
4. Check output in the plugin detail view and the debug log

### With the mock CLI

Set `SBX_CLI_MOCK=1` and add `tools/` to PATH to test plugins against the mock sandbox CLI without Docker.

### Unit testing your plugin

Test your plugin's JSON-RPC handling by piping messages to stdin:

```bash
echo '{"jsonrpc":"2.0","method":"initialize","params":{"pluginId":"test","version":"1.0.0"}}' | python3 main.py
```
