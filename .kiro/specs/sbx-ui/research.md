# Research & Design Decisions

## Summary
- **Feature**: sbx-ui
- **Discovery Scope**: New Feature (greenfield Electron desktop application)
- **Key Findings**:
  - The `sbx` CLI is the sole programmatic interface — no REST API, SDK, or event system exists; all operations require CLI invocation and stdout parsing
  - `sbx policy log --json` provides machine-readable output for policy monitoring; other commands require column-based text parsing
  - Port mappings are ephemeral (cleared on sandbox stop) and can only be managed post-creation via `sbx ports`

## Research Log

### Docker Sandbox CLI Interface
- **Context**: Needed to understand the complete CLI surface area for wrapping in SbxService
- **Sources Consulted**:
  - https://docs.docker.com/ai/sandboxes/usage/
  - https://docs.docker.com/ai/sandboxes/architecture/
  - https://docs.docker.com/ai/sandboxes/security/policy/
  - https://docs.docker.com/ai/sandboxes/agents/claude-code/
  - https://docs.docker.com/ai/sandboxes/security/credentials/
- **Findings**:
  - Lifecycle: `sbx run claude <workspace>`, `sbx ls`, `sbx stop <name>`, `sbx rm <name>`, `sbx create --name <n> claude .`
  - Policies: `sbx policy allow/deny network <domains>`, `sbx policy ls`, `sbx policy rm network --resource <domain>`, `sbx policy log [--json]`
  - Ports: `sbx ports <name> --publish <host>:<sbx>`, `sbx ports <name> --unpublish <host>:<sbx>`, `sbx ports <name>`
  - Session: `sbx run <name>` attaches PTY; prompt passthrough via `-- "message"`
  - Shell access: `sbx exec -it <name> bash` for interactive bash shell inside sandbox
  - `sbx ls` output is column-delimited (SANDBOX, AGENT, STATUS, PORTS, WORKSPACE)
  - `sbx policy ls` output is column-delimited (ID, TYPE, DECISION, RESOURCES)
  - `sbx policy log` has structured sections (Blocked/Allowed) with columns (SANDBOX, TYPE, HOST, PROXY, RULE, LAST SEEN, COUNT)
  - `sbx policy log --json` provides machine-readable JSON output
  - Port forwarding is post-creation only — cannot use `--publish` on `sbx run` or `sbx create`
  - Port mappings are NOT persistent across stop/restart
  - Services inside sandbox must bind to `0.0.0.0` (not 127.0.0.1) for port forwarding to work
  - Three default network policies: allow-all, balanced (deny-by-default with dev allowlist), deny-all
  - Wildcard syntax for policies: `*.example.com` for subdomains; catch-all patterns (`*`, `**`, `*.com`) are blocked
  - Deny beats allow when domain matches both rules
  - Credential injection via host-side proxy — credentials never enter the VM as environment variables
  - Workspace is a filesystem passthrough (not sync) — changes are instant in both directions
  - Each sandbox has its own isolated Docker daemon, image cache, and package installations
  - `sbx reset` stops all VMs and deletes all sandbox data including secrets
- **Implications**:
  - RealSbxService must spawn CLI processes and parse column-delimited stdout
  - Policy log should prefer `--json` flag for reliable parsing
  - No event/WebSocket API exists — polling is required for state updates
  - `sbx exec -it <name> bash` is the exact command for opening a shell inside a sandbox
  - Port management is always a separate operation after sandbox creation

### Electron PTY and Terminal Integration
- **Context**: Session interaction requires PTY management for Claude Code's terminal-based interface
- **Sources Consulted**: node-pty documentation, xterm.js API, Electron IPC patterns
- **Findings**:
  - `node-pty` spawns pseudo-terminals in the main process; data flows as Buffer/string events
  - `xterm.js` renders ANSI-encoded terminal output in the renderer; requires addon packages (fit, weblinks)
  - PTY data cannot cross Electron IPC directly as streams — requires IPC event channels
  - `ipcRenderer.on("channel", callback)` for streaming data from main to renderer is the established pattern
  - For real mode: `node-pty` spawns `sbx run <name>` and streams I/O
  - For mock mode: `MockPtyEmitter` (EventEmitter) generates simulated ANSI output sequences
  - Claude Code runs with `--dangerously-skip-permissions` flag inside sandbox (YOLO mode)
  - Claude Code uses base image `docker/sandbox-templates:claude-code`
- **Implications**:
  - PtyManager owns one PTY instance per active session (not per sandbox — only attached sandboxes have PTY)
  - Session data streams via IPC event channel `sbx:session:data`
  - `sendMessage` writes to PTY stdin, simulating terminal input
  - Main process must manage PTY lifecycle (create on attach, destroy on detach/sandbox stop)

### External Terminal Launching on macOS
- **Context**: Requirement 11 specifies opening bash shells in external terminal applications (Terminal.app, iTerm)
- **Sources Consulted**: macOS `open` command, osascript/AppleScript documentation, iTerm2 AppleScript API
- **Findings**:
  - Terminal.app: `osascript -e 'tell app "Terminal" to do script "sbx exec -it <name> bash"'`
  - iTerm: `osascript -e 'tell app "iTerm2" to create window with default profile command "sbx exec -it <name> bash"'`
  - Detection: Check if app bundle exists at `/Applications/iTerm.app` (Terminal.app is always present on macOS)
  - Default terminal: macOS uses Terminal.app as default; no reliable API to detect user's preferred terminal
  - Both apps support AppleScript for programmatic window creation
- **Implications**:
  - ExternalTerminalLauncher component needs AppleScript templates per terminal application
  - App detection uses filesystem checks for known bundle paths
  - User preference stored in renderer localStorage (simple key-value, no full settings system needed for Phase 1)
  - Command to execute inside terminal: `sbx exec -it <name> bash`

### CLI Output Parsing Strategy
- **Context**: Need to reliably parse `sbx` CLI stdout for all operations
- **Sources Consulted**: Phase 1 implementation plan, Docker Sandbox documentation
- **Findings**:
  - `sbx ls`: column-delimited with headers (SANDBOX, AGENT, STATUS, PORTS, WORKSPACE); split by 2+ whitespace
  - `sbx policy ls`: column-delimited (ID, TYPE, DECISION, RESOURCES)
  - `sbx policy log`: sections prefixed by "Blocked requests:" / "Allowed requests:"; column-delimited within
  - `sbx policy log --json`: machine-readable JSON — preferred for policy log
  - `sbx ports <name>`: shows HOST and SANDBOX columns; regex `(\d+)->(\d+)` extracts mappings
  - Lifecycle commands (`run`, `stop`, `rm`) return success/failure; `run` may output sandbox details
- **Implications**:
  - SbxOutputParser needs dedicated parsers per command type
  - Column-based parsing uses header positions for field extraction (not simple split — fields like workspace paths may contain spaces)
  - Policy log should use `--json` when available for robustness
  - Error detection: non-zero exit codes and stderr content

### Docker Sandbox Security Model
- **Context**: Understanding the security model is critical for correct GUI behavior and user guidance
- **Sources Consulted**:
  - https://docs.docker.com/ai/sandboxes/security/
  - https://docs.docker.com/ai/sandboxes/security/isolation/
  - https://docs.docker.com/ai/sandboxes/security/defaults/
  - https://docs.docker.com/ai/sandboxes/security/workspace/
- **Findings**:
  - Trust boundary is the microVM — agents have full sudo inside but cannot escape
  - Four isolation layers: Hypervisor, Network, Docker Engine, Credentials
  - Workspace changes affect host directly — Git hooks, CI config, Makefiles can be modified by agents
  - No sandbox-to-sandbox communication
  - All HTTP/HTTPS through host proxy; raw TCP/UDP/ICMP blocked entirely
  - Permanently blocked (not configurable): host filesystem outside workspace, host Docker daemon, host network/localhost, sandbox-to-sandbox
  - Organization-level policies (Docker Admin Console) override local `sbx policy` rules
  - Telemetry can be disabled via `SBX_NO_TELEMETRY=1`
  - Data directory: macOS `~/Library/Application Support/com.docker.sandboxes/`
- **Implications**:
  - GUI should surface workspace safety warnings (agents can modify Git hooks, CI configs)
  - Network policy UI should indicate that organization rules may override local rules
  - Error handling should detect and surface Docker/sbx installation issues clearly

## Architecture Pattern Evaluation

| Option | Description | Strengths | Risks / Limitations | Notes |
|--------|-------------|-----------|---------------------|-------|
| Layered Main/Preload/Renderer | Follows Electron native process boundaries with service interface at boundary | Natural fit for Electron, clear security boundary, enforced by process model | Tightly coupled to Electron framework | Aligns with steering tech.md and implementation plan |
| Hexagonal Ports and Adapters | Abstract all external I/O behind port interfaces | Highly testable, easy to swap implementations | Over-engineering for Phase 1 MVP; adapter layer adds indirection | SbxService interface already provides the key port |
| Event-driven pub/sub | All state changes flow through events | Good for reactive UIs, decoupled components | sbx CLI has no event API; polling required anyway; adds complexity | Could be layered in later for inter-store communication |

**Selected**: Layered architecture following Electron's Main/Preload/Renderer boundary split, with SbxService interface acting as the primary port/adapter boundary. This provides testability (mock/real swap) without over-engineering.

## Design Decisions

### Decision: CLI Wrapping via child_process.spawn
- **Context**: The `sbx` CLI is the only programmatic interface to Docker Sandbox
- **Alternatives Considered**:
  1. Wrap CLI commands via `child_process.spawn` with stdout parsing
  2. Wait for a Docker Sandbox SDK/API (none announced)
- **Selected Approach**: Wrap CLI via spawn with dedicated output parsers
- **Rationale**: No SDK exists or is planned. The CLI is stable and documented. This matches the steering decision.
- **Trade-offs**: Parsing stdout is fragile if CLI output format changes; `--json` mitigates this where available
- **Follow-up**: Monitor Docker Sandbox releases for SDK or JSON output modes on all commands

### Decision: Polling for State Updates
- **Context**: Need near-real-time sandbox status, but `sbx` has no event/WebSocket API
- **Alternatives Considered**:
  1. Poll `sbx ls` at fixed interval (3s)
  2. Watch `.sbx/` filesystem directory for state changes
  3. Parse Docker events from the sandbox's Docker daemon
- **Selected Approach**: Poll `sbx ls` every 3 seconds
- **Rationale**: Matches `sbx` TUI behavior. Filesystem watching is unreliable across platforms and requires knowledge of internal state directory structure. Docker events are inside the sandbox VM, not accessible from host.
- **Trade-offs**: 3s polling latency for status changes; CPU overhead from repeated CLI spawning
- **Follow-up**: Monitor for event API in future `sbx` releases; consider filesystem watchers as optimization

### Decision: PTY Data Streaming via IPC Events
- **Context**: Terminal output from Claude Code sessions must reach the renderer for xterm.js rendering
- **Alternatives Considered**:
  1. IPC event channel (`ipcMain` send → `ipcRenderer.on`)
  2. Electron MessagePort for direct streaming
  3. SharedArrayBuffer for zero-copy transfer
- **Selected Approach**: IPC event channel with `sbx:session:data` event
- **Rationale**: Simplest approach; proven pattern in Electron terminal apps. MessagePort adds complexity; SharedArrayBuffer requires cross-origin isolation.
- **Trade-offs**: IPC serialization overhead for high-frequency terminal data; acceptable for text-based PTY output
- **Follow-up**: Profile IPC overhead under sustained output; consider MessagePort if latency becomes an issue

### Decision: External Terminal via osascript
- **Context**: Requirement 11 requires opening bash shells in external terminal applications
- **Alternatives Considered**:
  1. osascript/AppleScript to create terminal windows
  2. `open -a Terminal.app` with a temporary shell script
  3. Embedded terminal within the app (already provided by session panel)
- **Selected Approach**: osascript with per-application AppleScript templates
- **Rationale**: Provides the most control over terminal window creation and command execution. `open -a` cannot reliably pass commands to run.
- **Trade-offs**: macOS-only; Windows support would need different approach (Phase 2)
- **Follow-up**: Add Windows support (PowerShell, Windows Terminal) in Phase 2

### Decision: User Terminal Preference Storage
- **Context**: Requirement 11.5 requires a setting for preferred external terminal
- **Alternatives Considered**:
  1. Electron-store (dedicated persistence library)
  2. Renderer localStorage
  3. JSON file in app data directory
- **Selected Approach**: Renderer localStorage via a simple Zustand persist middleware
- **Rationale**: Simplest approach for a single key-value preference. No additional dependency needed. Zustand's persist middleware integrates naturally.
- **Trade-offs**: Lost if user clears browser data; acceptable for a non-critical preference
- **Follow-up**: Consolidate into a proper settings system if more preferences are added in Phase 2

## Risks & Mitigations
- **CLI output format changes** — Pin tested `sbx` version in docs; prefer `--json` where available; parser unit tests catch breakage early
- **PTY IPC overhead** — Profile during implementation; switch to MessagePort if needed
- **Polling CPU overhead** — 3s interval is conservative; can increase interval or add smart backoff when app is not focused
- **External terminal app detection** — Filesystem checks may miss non-standard installations; manual configuration serves as fallback
- **Electron security** — contextBridge is the only safe IPC pattern; never expose `ipcRenderer` directly; enforce CSP headers
- **Mock drift from real behavior** — Shared SbxService interface enforced at compile time; E2E tests catch behavioral drift; acceptance criteria specify validation rules mock must enforce

## References
- [Docker Sandbox Get Started](https://docs.docker.com/ai/sandboxes/get-started/) — Installation, login, credential setup
- [Docker Sandbox Usage](https://docs.docker.com/ai/sandboxes/usage/) — CLI command reference, lifecycle, ports, TUI
- [Docker Sandbox Architecture](https://docs.docker.com/ai/sandboxes/architecture/) — microVM, proxy, workspace passthrough model
- [Docker Sandbox Security](https://docs.docker.com/ai/sandboxes/security/) — Trust boundary, data flow, isolation layers
- [Docker Sandbox Security Policy](https://docs.docker.com/ai/sandboxes/security/policy/) — Network policy CLI, precedence rules, wildcards
- [Docker Sandbox Claude Code](https://docs.docker.com/ai/sandboxes/agents/claude-code/) — Agent launch, prompt passthrough, authentication
- [Docker Sandbox Credentials](https://docs.docker.com/ai/sandboxes/security/credentials/) — Secret management, proxy injection, supported services
- [Docker Sandbox Workspace](https://docs.docker.com/ai/sandboxes/security/workspace/) — Workspace trust model, critical risk files
- [Docker Sandbox Troubleshooting](https://docs.docker.com/ai/sandboxes/troubleshooting/) — Common issues, diagnostic commands, reset procedures
- [Docker Sandbox FAQ](https://docs.docker.com/ai/sandboxes/faq/) — Sign-in, telemetry, custom env vars, sandbox detection
- [node-pty](https://github.com/microsoft/node-pty) — PTY spawning in Node.js
- [xterm.js](https://xtermjs.org/) — Terminal rendering for web/Electron
- [Electron contextBridge](https://www.electronjs.org/docs/latest/api/context-bridge) — Secure IPC pattern
