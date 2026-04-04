# Phase 1 — Implementation Plan

## 1. Scope

Phase 1 delivers a working desktop app where a developer can create a project from a local Git repo, launch Claude Code inside a Docker Sandbox, interact with the agent through a chat-style UI, manage network policies and port forwarding, and stop or destroy the sandbox — all without touching the terminal. A mock layer for `sbx` and terminal I/O enables E2E testing without Docker Desktop.

### What ships

- Project creation (select repo root from filesystem)
- Sandbox launch, stop, destroy with live status grid
- Network policy management (allow, deny, list, remove)
- Port forwarding management (publish, unpublish, list)
- Chat-style message input to a running Claude Code session
- Full `sbx` mock for E2E tests

### What does not ship (Phase 2+)

- Branch mode / worktree UI
- Multi-agent support (Codex, Gemini, etc.)
- Template customization UI
- iTerm / VSCode / IDE integration
- Notification center
- File embedding in chat
- Shared workspaces across agents
- Org-level governance UI


## 2. Tech stack

| Layer        | Choice                       | Rationale                                                    |
|--------------|------------------------------|--------------------------------------------------------------|
| Shell        | **Electron 36+**             | Native filesystem dialogs, child process spawning, PTY, tray |
| Frontend     | **React 19 + TypeScript**    | Component model, ecosystem, matches mockup approach          |
| Styling      | **Tailwind CSS 4**           | Matches mockup design system (Monolith Console)              |
| State        | **Zustand**                  | Lightweight, no boilerplate, good for cross-component sync   |
| Terminal     | **xterm.js 5 + node-pty**    | Battle-tested PTY in Electron; renders Claude Code output    |
| IPC          | **Electron contextBridge**   | Secure main↔renderer communication                          |
| Testing      | **Vitest + Playwright**      | Unit tests + E2E with Electron support                       |
| Build        | **electron-vite**            | Fast HMR, ESM-native, single config                         |
| Package      | **electron-builder**         | macOS DMG + Windows NSIS                                     |


## 3. Architecture

```
┌─────────────────────────────────────────────────────────┐
│  Renderer (React)                                       │
│  ┌────────────┐ ┌────────────┐ ┌──────────────────────┐ │
│  │ Dashboard   │ │ Policy Mgr │ │ Session Panel        │ │
│  │ (grid view) │ │ (allow/deny│ │ (chat + mini-term)   │ │
│  │             │ │  list/rm)  │ │                      │ │
│  └──────┬──────┘ └─────┬──────┘ └──────────┬───────────┘ │
│         │              │                   │             │
│  ───────┴──────────────┴───────────────────┴──────────── │
│                   preload.ts (contextBridge)             │
└────────────────────────┬────────────────────────────────┘
                         │ IPC
┌────────────────────────┴────────────────────────────────┐
│  Main Process (Node.js)                                 │
│  ┌──────────────────────────────────────────────────┐   │
│  │ SbxService (interface)                            │   │
│  │  .list() .run() .stop() .rm()                     │   │
│  │  .policyList() .policyAllow() .policyDeny() ...   │   │
│  │  .portsPublish() .portsUnpublish() .portsList()   │   │
│  │  .exec() .attach()                                │   │
│  └───────────┬──────────────────┬────────────────────┘   │
│              │                  │                        │
│  ┌───────────▼──────┐ ┌────────▼─────────────┐          │
│  │ RealSbxService   │ │ MockSbxService        │          │
│  │ (spawns sbx CLI) │ │ (in-memory state,     │          │
│  │                  │ │  simulated output)    │          │
│  └──────────────────┘ └──────────────────────┘          │
│                                                         │
│  ┌──────────────────────────────────────────────────┐   │
│  │ PtyManager                                        │   │
│  │  Manages node-pty sessions per sandbox            │   │
│  │  Real: spawns `sbx run <name>` in PTY             │   │
│  │  Mock: emits simulated Claude Code output stream  │   │
│  └──────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────┘
```


## 4. SbxService interface

This is the central abstraction. Both `RealSbxService` and `MockSbxService` implement it.

```typescript
interface Sandbox {
  id: string;
  name: string;
  agent: "claude";
  status: "running" | "stopped" | "creating" | "removing";
  workspace: string;
  ports: PortMapping[];
  createdAt: string;
}

interface PolicyRule {
  id: string;
  type: "network";
  decision: "allow" | "deny";
  resources: string;     // e.g. "api.anthropic.com, *.npmjs.org"
}

interface PolicyLogEntry {
  sandbox: string;
  type: "network";
  host: string;
  proxy: "forward" | "transparent" | "network";
  rule: string;
  lastSeen: string;
  count: number;
  blocked: boolean;
}

interface PortMapping {
  hostPort: number;
  sandboxPort: number;
  protocol: "tcp";
}

interface SbxService {
  // Lifecycle
  list(): Promise<Sandbox[]>;
  run(agent: "claude", workspace: string, opts?: {
    name?: string;
    prompt?: string;         // passed after "--"
  }): Promise<Sandbox>;
  stop(name: string): Promise<void>;
  rm(name: string): Promise<void>;

  // Network policies
  policyList(): Promise<PolicyRule[]>;
  policyAllow(resources: string): Promise<PolicyRule>;
  policyDeny(resources: string): Promise<PolicyRule>;
  policyRemove(resource: string): Promise<void>;
  policyLog(sandboxName?: string): Promise<PolicyLogEntry[]>;

  // Port forwarding
  portsList(name: string): Promise<PortMapping[]>;
  portsPublish(name: string, hostPort: number, sbxPort: number): Promise<PortMapping>;
  portsUnpublish(name: string, hostPort: number, sbxPort: number): Promise<void>;

  // Session
  attach(name: string): PtyHandle;  // returns a PTY stream
  sendMessage(name: string, message: string): Promise<void>;
}
```


## 5. Mock design

The mock is not a bash script pretending to be `sbx`. It is a TypeScript class implementing `SbxService` with in-memory state and simulated output streams. This lets E2E tests run in CI without Docker Desktop.

### 5.1 MockSbxService state

```typescript
class MockSbxService implements SbxService {
  private sandboxes: Map<string, Sandbox> = new Map();
  private policies: Map<string, PolicyRule> = new Map();
  private policyLogs: PolicyLogEntry[] = [];
  private portMappings: Map<string, PortMapping[]> = new Map();
  private nextId = 1;

  // Pre-seeded with Balanced policy defaults
  constructor() {
    this.seedDefaultPolicies();
  }
}
```

### 5.2 Lifecycle simulation

| Command | Mock behavior |
|---------|---------------|
| `list()` | Returns all sandboxes from the map |
| `run("claude", path, opts)` | Creates sandbox entry with status "creating", transitions to "running" after 800ms delay (simulates VM boot). If sandbox with same workspace exists, returns it (idempotent, matching real `sbx run` behavior). Auto-generates name as `claude-<dirname>` if not specified. |
| `stop(name)` | Sets status to "stopped" after 300ms. Clears port mappings (matching real behavior: ports are not persistent). |
| `rm(name)` | Removes sandbox, its ports, and its policy log entries after 200ms. |

### 5.3 Policy simulation

The mock seeds the Balanced policy defaults on construction:

```typescript
private seedDefaultPolicies() {
  const balanced = [
    "api.anthropic.com",
    "api.openai.com",
    "*.npmjs.org",
    "*.pypi.org",
    "files.pythonhosted.org",
    "github.com",
    "*.github.com",
    "registry.hub.docker.com",
    "*.docker.io",
    "*.googleapis.com",
  ];
  for (const domain of balanced) {
    this.policies.set(crypto.randomUUID(), {
      id: crypto.randomUUID(),
      type: "network",
      decision: "allow",
      resources: domain,
    });
  }
}
```

`policyAllow` / `policyDeny` add entries. `policyRemove` deletes by resource match. `policyLog` returns simulated entries that reference existing sandboxes and policies.

### 5.4 Port forwarding simulation

`portsPublish` adds a mapping and validates: rejects if host port is already bound. `portsUnpublish` requires both host and sandbox port (matching real `sbx` behavior). `portsList` returns current mappings. Mappings are cleared when the sandbox stops.

### 5.5 Terminal / session simulation

This is the most complex mock. The real flow is:

1. `sbx run <name>` attaches to a PTY showing Claude Code's interactive UI
2. The user types messages; Claude Code processes them and streams output

The mock simulates this with a `MockPtyEmitter` that:

```typescript
class MockPtyEmitter extends EventEmitter {
  private lines: string[] = [
    "\x1b[1;36m╭─────────────────────────────────────╮\x1b[0m",
    "\x1b[1;36m│  Claude Code         (sandbox mode) │\x1b[0m",
    "\x1b[1;36m╰─────────────────────────────────────╯\x1b[0m",
    "",
    "\x1b[90mModel: claude-sonnet-4-20250514\x1b[0m",
    "\x1b[90mWorkspace: /Users/dev/my-project\x1b[0m",
    "",
  ];

  start() {
    // Emit startup lines with realistic delays
    this.emitSequence(this.lines, 50);
    // Then show the prompt
    setTimeout(() => this.emit("data", "\x1b[1;35m❯\x1b[0m "), 500);
  }

  write(input: string) {
    // Simulate Claude Code processing a message
    this.emit("data", input);       // echo
    this.emit("data", "\r\n");
    this.simulateAgentResponse(input);
  }

  private simulateAgentResponse(prompt: string) {
    const responses = [
      { delay: 200, text: "\x1b[33m⟡ Thinking...\x1b[0m\r\n" },
      { delay: 600, text: "\x1b[90m  Reading project files...\x1b[0m\r\n" },
      { delay: 400, text: `\x1b[36m📂 Read\x1b[0m src/index.ts\r\n` },
      { delay: 800, text: `\x1b[36m✏️  Write\x1b[0m src/index.ts (+12 lines)\r\n` },
      { delay: 300, text: "\x1b[32m✓ Done\x1b[0m\r\n\r\n" },
      { delay: 100, text: "\x1b[1;35m❯\x1b[0m " },
    ];
    let cumulative = 0;
    for (const r of responses) {
      cumulative += r.delay;
      setTimeout(() => this.emit("data", r.text), cumulative);
    }
  }
}
```

This gives E2E tests a realistic terminal stream to assert against, and lets developers see the UI in action without Docker.


## 6. Directory structure

```
sandbox-control/
├── electron.vite.config.ts
├── package.json
├── tsconfig.json
│
├── src/
│   ├── main/                          # Electron main process
│   │   ├── index.ts                   # App entry, window management
│   │   ├── ipc-handlers.ts            # IPC bridge registration
│   │   ├── services/
│   │   │   ├── sbx-service.ts         # SbxService interface
│   │   │   ├── real-sbx-service.ts    # CLI-wrapping implementation
│   │   │   ├── mock-sbx-service.ts    # In-memory mock
│   │   │   └── service-factory.ts     # Returns real or mock based on env
│   │   ├── pty/
│   │   │   ├── pty-manager.ts         # Manages node-pty sessions
│   │   │   └── mock-pty-emitter.ts    # Simulated Claude Code output
│   │   └── utils/
│   │       ├── cli-executor.ts        # Spawn + parse sbx CLI output
│   │       └── sbx-output-parser.ts   # Parse `sbx ls`, `sbx policy ls`
│   │
│   ├── preload/
│   │   └── index.ts                   # contextBridge API exposure
│   │
│   └── renderer/                      # React app
│       ├── index.html
│       ├── main.tsx
│       ├── App.tsx
│       ├── stores/
│       │   ├── sandbox-store.ts       # Zustand: sandbox list + status
│       │   ├── policy-store.ts        # Zustand: network policy rules
│       │   └── session-store.ts       # Zustand: active session state
│       ├── components/
│       │   ├── layout/
│       │   │   ├── Sidebar.tsx
│       │   │   ├── TopBar.tsx
│       │   │   └── Shell.tsx
│       │   ├── dashboard/
│       │   │   ├── SandboxGrid.tsx        # Card grid (main view)
│       │   │   ├── SandboxCard.tsx         # Individual sandbox card
│       │   │   ├── StatusChip.tsx          # LIVE / STOPPED / ALERT
│       │   │   ├── CreateProjectDialog.tsx # Repo root picker
│       │   │   └── GlobalStats.tsx         # Active count, etc.
│       │   ├── policies/
│       │   │   ├── PolicyPanel.tsx         # Allow/deny rule list
│       │   │   ├── PolicyRuleRow.tsx
│       │   │   ├── AddPolicyDialog.tsx
│       │   │   └── PolicyLogViewer.tsx     # Network activity log
│       │   ├── ports/
│       │   │   ├── PortPanel.tsx           # Port mapping list
│       │   │   ├── PortMappingRow.tsx
│       │   │   └── AddPortDialog.tsx
│       │   └── session/
│       │       ├── SessionPanel.tsx        # Chat + terminal view
│       │       ├── ChatInput.tsx           # Message composer
│       │       ├── MiniTerminal.tsx        # xterm.js embed
│       │       └── AgentStatusBar.tsx      # Model, uptime, status
│       ├── hooks/
│       │   ├── useSandboxes.ts
│       │   ├── usePolicies.ts
│       │   ├── usePorts.ts
│       │   └── useSession.ts
│       └── styles/
│           └── tailwind.css
│
├── tests/
│   ├── unit/
│   │   ├── mock-sbx-service.test.ts
│   │   ├── sbx-output-parser.test.ts
│   │   └── sandbox-store.test.ts
│   └── e2e/
│       ├── setup.ts                   # Forces mock mode
│       ├── project-creation.spec.ts
│       ├── sandbox-lifecycle.spec.ts
│       ├── policy-management.spec.ts
│       ├── port-forwarding.spec.ts
│       └── session-messaging.spec.ts
│
└── resources/
    └── icon.icns
```


## 7. Implementation milestones

### M1 — Foundation (days 1–4)

**Goal:** Electron shell boots, service abstraction compiles, mock returns data.

| Task | Deliverable |
|------|-------------|
| Scaffold Electron + React + Tailwind with electron-vite | `npm run dev` opens a window |
| Define `SbxService` interface and all types | `src/main/services/sbx-service.ts` |
| Implement `MockSbxService` with lifecycle + policies + ports | Full in-memory mock with seeded Balanced policy |
| Implement `service-factory.ts` | Reads `SBX_MOCK=1` env to select mock vs real |
| Register IPC handlers for all service methods | `preload/index.ts` exposes typed `window.sbx` API |
| Write unit tests for MockSbxService | All lifecycle, policy, and port operations covered |

**Exit criteria:** `window.sbx.list()` returns mock sandboxes from renderer.

### M2 — Dashboard grid + project creation (days 5–8)

**Goal:** User sees sandbox cards and can create a project.

| Task | Deliverable |
|------|-------------|
| Build Shell layout (sidebar + topbar + content area) | Matches Monolith Console mockup structure |
| Build SandboxGrid + SandboxCard | Cards show name, status, agent, workspace path |
| Build StatusChip (LIVE pulse / STOPPED) | Green LED animation for running sandboxes |
| Build CreateProjectDialog | Native filesystem dialog to pick repo root, name input |
| Build GlobalStats bar | Running count, total count |
| Wire "Deploy Agent" and "+" card to CreateProjectDialog | `sbx.run("claude", selectedPath, { name })` on submit |
| Zustand sandbox store with polling | Calls `sbx.list()` every 3s to refresh grid |

**Exit criteria:** User picks a directory, sandbox appears in grid as LIVE.

### M3 — Lifecycle controls (days 9–11)

**Goal:** User can stop, resume, and destroy sandboxes.

| Task | Deliverable |
|------|-------------|
| Add pause button (⏸) to SandboxCard | Calls `sbx.stop(name)`, card transitions to STOPPED |
| Add resume action | Click stopped card → `sbx.run(name)`, returns to LIVE |
| Add "Terminate Agent" action with confirm dialog | Calls `sbx.rm(name)`, card disappears from grid |
| Handle creating/removing intermediate states | Spinner + disabled controls during transitions |
| Write E2E test: full lifecycle flow | Create → verify LIVE → stop → verify STOPPED → remove → verify gone |

**Exit criteria:** E2E lifecycle test passes against mock.

### M4 — Network policy management (days 12–16)

**Goal:** User can view, add, and remove network policies.

| Task | Deliverable |
|------|-------------|
| Build PolicyPanel (sidebar drawer or dedicated view) | Toggleable via Settings nav or sandbox detail |
| Build PolicyRuleRow | Shows decision (allow/deny), resource domain, remove button |
| Build AddPolicyDialog | Domain input + allow/deny toggle, supports comma-separated |
| Build PolicyLogViewer | Table: sandbox, host, proxy type, blocked/allowed, count |
| Wire to `sbx.policyList()`, `policyAllow()`, `policyDeny()`, `policyRemove()` | Refresh on mutation |
| Add policy log filtering | By sandbox name, blocked-only toggle |
| Write E2E test: add allow rule, verify in list, remove | Policy CRUD flow |

**Exit criteria:** User adds `*.example.com` allow rule, sees it in list, removes it.

### M5 — Port forwarding management (days 17–20)

**Goal:** User can publish and unpublish ports per sandbox.

| Task | Deliverable |
|------|-------------|
| Build PortPanel (per-sandbox drawer) | Shows active mappings for selected sandbox |
| Build PortMappingRow | `host:sbx` display with unpublish button |
| Build AddPortDialog | Host port + sandbox port inputs with validation |
| Wire to `sbx.portsPublish()`, `portsUnpublish()`, `portsList()` | Refresh on mutation |
| Show port mappings in SandboxCard | Compact `8080→3000` chips on card |
| Validate: reject duplicate host ports, require running sandbox | Error toasts |
| Write E2E test: publish, verify, unpublish | Port forwarding CRUD |

**Exit criteria:** User publishes 8080:3000, sees it on card and in panel, unpublishes.

### M6 — Claude Code session integration (days 21–28)

**Goal:** User can send messages to a running Claude Code session and see output.

| Task | Deliverable |
|------|-------------|
| Implement PtyManager (real: spawns `sbx run <name>`) | Manages one PTY per sandbox attachment |
| Implement MockPtyEmitter | Simulates Claude Code startup + response sequences |
| Build SessionPanel (split: chat input bottom, terminal top) | Takes full content area when sandbox is selected |
| Build MiniTerminal with xterm.js | Renders PTY data stream, handles ANSI codes |
| Build ChatInput | Text input + send button, sends to PTY as stdin |
| Build AgentStatusBar | Shows model name, sandbox name, uptime, connection status |
| Wire "Open Terminal" on SandboxCard to SessionPanel | Click card → opens session |
| Handle session disconnect/reconnect | Auto-reconnect on sandbox resume |
| Write E2E test: send message, verify terminal output | Message appears, mock response streams |

**Exit criteria:** User clicks sandbox card, types "Add tests", sees simulated Claude Code response stream.

### M7 — Real sbx integration + polish (days 29–34)

**Goal:** App works with real Docker Sandbox when `SBX_MOCK` is not set.

| Task | Deliverable |
|------|-------------|
| Implement `RealSbxService` | Spawns `sbx` CLI, parses stdout |
| Implement `sbx-output-parser.ts` | Parse `sbx ls` columns, `sbx policy ls` table, `sbx ports` output |
| Implement real PtyManager | `node-pty` spawns `sbx run <name>` |
| Handle `sbx` not installed / Docker not running | Error state UI with install instructions |
| Handle clock drift (detect stale sandbox) | Suggest restart in UI |
| Polling tuning | 3s for sandbox list, 10s for policy log |
| Error handling + toast notifications | All CLI failures surface as user-friendly messages |
| Manual QA with real Docker Desktop 4.58+ | Test all Phase 1 flows |

**Exit criteria:** All Phase 1 features work against both mock and real `sbx`.

### M8 — E2E test suite + release (days 35–38)

**Goal:** Comprehensive E2E suite, packaged app.

| Task | Deliverable |
|------|-------------|
| Complete E2E test suite (5 specs) | project-creation, sandbox-lifecycle, policy-management, port-forwarding, session-messaging |
| CI pipeline (GitHub Actions) | Runs E2E against mock on every push |
| electron-builder config for macOS DMG | Signed, notarized (if certs available) |
| README with setup instructions | Dev setup, mock mode, running tests |


## 8. IPC contract

The preload bridge exposes a typed API to the renderer:

```typescript
// preload/index.ts
contextBridge.exposeInMainWorld("sbx", {
  // Lifecycle
  list:       ()                              => ipcRenderer.invoke("sbx:list"),
  run:        (agent, workspace, opts?)       => ipcRenderer.invoke("sbx:run", agent, workspace, opts),
  stop:       (name)                          => ipcRenderer.invoke("sbx:stop", name),
  rm:         (name)                          => ipcRenderer.invoke("sbx:rm", name),

  // Policies
  policyList:   ()                            => ipcRenderer.invoke("sbx:policy:list"),
  policyAllow:  (resources)                   => ipcRenderer.invoke("sbx:policy:allow", resources),
  policyDeny:   (resources)                   => ipcRenderer.invoke("sbx:policy:deny", resources),
  policyRemove: (resource)                    => ipcRenderer.invoke("sbx:policy:remove", resource),
  policyLog:    (sandboxName?)                => ipcRenderer.invoke("sbx:policy:log", sandboxName),

  // Ports
  portsList:      (name)                      => ipcRenderer.invoke("sbx:ports:list", name),
  portsPublish:   (name, hostPort, sbxPort)   => ipcRenderer.invoke("sbx:ports:publish", name, hostPort, sbxPort),
  portsUnpublish: (name, hostPort, sbxPort)   => ipcRenderer.invoke("sbx:ports:unpublish", name, hostPort, sbxPort),

  // Session (PTY streams via message ports)
  attachSession:  (name)                      => ipcRenderer.invoke("sbx:session:attach", name),
  sendMessage:    (name, message)             => ipcRenderer.invoke("sbx:session:send", name, message),
  detachSession:  (name)                      => ipcRenderer.invoke("sbx:session:detach", name),

  // PTY data stream (renderer subscribes)
  onSessionData: (callback) => {
    ipcRenderer.on("sbx:session:data", (_, data) => callback(data));
    return () => ipcRenderer.removeAllListeners("sbx:session:data");
  },

  // Filesystem
  selectDirectory: () => ipcRenderer.invoke("dialog:selectDirectory"),
});
```


## 9. CLI output parsing reference

Based on the docs, here is what the real `sbx` CLI outputs and how to parse it:

### `sbx ls`
```
SANDBOX         AGENT   STATUS   PORTS                    WORKSPACE
my-sandbox      claude  running  127.0.0.1:8080->3000/tcp /Users/dev/proj
api-server      claude  stopped                           /Users/dev/api
```
Parse: split by 2+ spaces, map columns positionally.

### `sbx policy ls`
```
ID                                     TYPE      DECISION   RESOURCES
a1b2c3d4-e5f6-7890-abcd-ef1234567890   network   allow      api.anthropic.com, *.npmjs.org
f9e8d7c6-b5a4-3210-fedc-ba0987654321   network   deny       ads.example.com
```
Parse: split by 2+ spaces, 4 columns.

### `sbx policy log`
```
Blocked requests:
SANDBOX      TYPE     HOST                   PROXY        RULE       LAST SEEN        COUNT
my-sandbox   network  blocked.example.com    transparent  policykit  10:15:25 29-Jan  1

Allowed requests:
SANDBOX      TYPE     HOST                   PROXY        RULE       LAST SEEN        COUNT
my-sandbox   network  api.anthropic.com      forward      policykit  10:15:23 29-Jan  42
```
Parse: detect "Blocked"/"Allowed" sections, then column-based parsing.

### `sbx ports <name>`
```
HOST                     SANDBOX
127.0.0.1:8080->3000/tcp
```
Parse: regex `(\d+)->(\d+)`.


## 10. Key design decisions

**Why Electron over Tauri?** xterm.js + node-pty is the proven stack for terminal emulation in desktop apps. Tauri would require bridging to a native PTY library, adding complexity for Phase 1. We can evaluate migration for Phase 2 if bundle size becomes a concern.

**Why a service interface over direct CLI calls?** The mock must be indistinguishable from the real implementation at the call site. A shared interface enforced at compile time guarantees this. It also makes the transition to an `sbx` SDK (if Docker ships one) trivial.

**Why polling `sbx ls` instead of a WebSocket/event model?** The `sbx` CLI has no event API. Polling at 3s intervals is acceptable for Phase 1 and matches how the `sbx` TUI itself works. We can add filesystem watchers on `.sbx/` state directories as an optimization later.

**Why chat input writes to PTY stdin?** Claude Code is a terminal application. Sending a message means writing text to its stdin and pressing enter. There is no separate message API. The chat UI is a nicer wrapper around terminal input — the xterm.js view shows what Claude Code actually does in response, including file operations and command output. This matches how the mockup's "Mini-Terminal" section works alongside the "Active Task" description.
