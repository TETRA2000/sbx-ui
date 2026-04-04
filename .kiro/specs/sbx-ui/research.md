# Research & Design Decisions

## Summary
- **Feature**: sbx-ui
- **Discovery Scope**: New Feature (greenfield macOS native desktop application)
- **Key Findings**:
  - The `sbx` CLI is the sole programmatic interface — no REST API, SDK, or event system exists; all operations require CLI invocation and stdout parsing
  - SwiftTerm (v1.13.0, MIT, actively maintained) provides production-ready terminal emulation with PTY management for macOS, eliminating the need for xterm.js
  - App Sandbox must be disabled to spawn external CLI tools like `sbx`; Hardened Runtime is compatible and required for notarization

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
  - SbxService must spawn CLI processes via Foundation `Process` and parse column-delimited stdout
  - Policy log should prefer `--json` flag for reliable parsing
  - No event/WebSocket API exists — polling is required for state updates
  - `sbx exec -it <name> bash` is the exact command for opening a shell inside a sandbox
  - Port management is always a separate operation after sandbox creation

### SwiftTerm Terminal Emulation Library
- **Context**: Need terminal rendering with full ANSI support for Claude Code session interaction, replacing xterm.js
- **Sources Consulted**:
  - https://github.com/migueldeicaza/SwiftTerm (v1.13.0, released 2026-03-27)
  - SwiftTerm source: `Sources/SwiftTerm/Mac/MacTerminalView.swift`, `MacLocalTerminalView.swift`, `LocalProcess.swift`, `Pty.swift`
- **Findings**:
  - **Production-proven**: Used in Secure Shellfish, La Terminal, and CodeEdit. 1,451+ stars, MIT license.
  - **Platform support**: macOS, iOS, visionOS, Linux, Windows. The macOS front-end uses AppKit (NSView).
  - **Terminal capabilities**: VT100/Xterm emulation, ANSI/256/TrueColor, bold/italic/underline/strikethrough, mouse events, Sixel/iTerm2/Kitty graphics, hyperlinks, Metal rendering, search, selection.
  - **Architecture**: UI-agnostic engine (`Terminal.swift`, `Buffer.swift`, parser) with platform-specific front-ends. Engine is thread-safe and can be used headlessly.
  - **PTY management**: `LocalProcess` class handles PTY creation via two paths:
    - Modern: `openpty` + `posix_spawn` with `POSIX_SPAWN_SETSID` (preferred, avoids `fork()`)
    - Legacy: `forkpty` wrapper via `PseudoTerminalHelpers`
  - **`MacLocalTerminalView`**: Convenience NSView subclass that wires `TerminalView` to `LocalProcess` — handles PTY creation, data piping, and window resize automatically.
  - **SwiftUI integration**: Wrap `MacLocalTerminalView` or `TerminalView` using `NSViewRepresentable`.
  - **Data flow**: `LocalProcess` reads from PTY master fd via `readabilityHandler`, feeds data to `Terminal` engine, which triggers NSView redraws.
- **Implications**:
  - SwiftTerm replaces both `node-pty` and `xterm.js` from the Electron design
  - `NSViewRepresentable` wrapper needed for SwiftUI integration
  - For mock mode: use the headless `Terminal` engine fed by a `MockPtyEmitter` actor that generates simulated ANSI output
  - No WKWebView/xterm.js needed — native rendering is superior for macOS

### Foundation Process for CLI Spawning
- **Context**: Need to spawn `sbx` CLI commands from a macOS app, replacing Electron's `child_process.spawn`
- **Sources Consulted**: Apple Developer Documentation (Foundation.Process), Swift Concurrency documentation
- **Findings**:
  - `Process` (formerly NSTask) spawns external commands with full stdout/stderr/exit code capture
  - Use `Pipe` for stdout/stderr capture, `terminationStatus` for exit code
  - `AsyncStream` wraps `readabilityHandler` for non-blocking output streaming with Swift Concurrency
  - `terminationHandler` callback provides async notification of process completion
  - Array-form arguments (not shell string interpolation) prevents command injection — same safety as `child_process.spawn` with array args
  - Use `/usr/bin/env` as executable with `["sbx", ...]` as arguments to locate `sbx` on PATH
- **Implications**:
  - `CliExecutor` maps directly from the Electron design — `Process` replaces `child_process.spawn`
  - `SbxOutputParser` stays conceptually the same, implemented in Swift with `String` APIs
  - Background execution via `Task.detached` or wrapping `waitUntilExit()` in `withCheckedContinuation`

### macOS App Sandbox and Security
- **Context**: Understanding security constraints for a macOS app that spawns external CLI tools
- **Sources Consulted**: Apple Developer Documentation (App Sandbox, Hardened Runtime, Notarization)
- **Findings**:
  - **App Sandbox blocks `Process` from spawning arbitrary executables** — a sandboxed app can only launch executables within its own bundle or at a few system paths
  - No entitlement exists to selectively allow `Process` spawning from within a sandbox
  - **Hardened Runtime** (required for notarization) is fully compatible with `Process` — does not block spawning external tools
  - Developer tools (iTerm2, VS Code, Docker Desktop) distribute outside Mac App Store without App Sandbox
  - XPC Service could allow a non-sandboxed helper to spawn processes for a sandboxed host, but adds significant complexity
  - `com.apple.security.cs.allow-unsigned-executable-memory` entitlement only needed for unsigned plugins, not for `Process`
- **Implications**:
  - App Sandbox must be disabled for sbx-ui
  - Distribute outside Mac App Store via direct download (DMG)
  - Enable Hardened Runtime for notarization
  - This is the standard approach for developer tools wrapping CLI utilities

### SwiftUI macOS Architecture Patterns
- **Context**: Determine the best architecture for a macOS SwiftUI app replacing the Electron Main/Preload/Renderer layered architecture
- **Sources Consulted**: Apple WWDC 2024-2025 sessions, Swift documentation, SwiftUI API reference
- **Findings**:
  - **State management**: `@Observable` macro (Observation framework, macOS 14+) is the standard. Replaces `@ObservableObject`/`@Published` with simpler, granular property tracking. Views only re-render when accessed properties change.
  - **Navigation**: `NavigationSplitView` for sidebar + detail layout. Bind selection to `@State` or `@Observable` property. Three-column layout available via `content` closure.
  - **Design system**: Custom `Color` extensions for semantic tokens. `.preferredColorScheme(.dark)` at window level. Custom fonts via Info.plist `ATSApplicationFontsPath` + `Font.custom()`.
  - **Service layer**: Protocol-oriented with `Sendable` conformance. `protocol SbxServiceProtocol: Sendable { ... }`. Inject via `.environment()`. This directly replaces TypeScript interfaces.
  - **Concurrency**: `async/await` for all operations. `actor` for thread-safe service state. `AsyncStream`/`AsyncSequence` for polling. `.task { }` view modifier for lifecycle-bound async work.
  - **Data**: In-memory `@Observable` state for ephemeral data (sandbox list, session state). SwiftData only for persistent preferences.
- **Implications**:
  - Electron's Main/Preload/Renderer boundary collapses into a single-process Swift app with `@Observable` models
  - No IPC layer needed — views directly call service protocols
  - Zustand stores map to `@Observable` model classes
  - contextBridge/preload layer is eliminated entirely

### macOS Testing Strategy
- **Context**: Determine testing approach for a macOS SwiftUI app, replacing Electron's Vitest + Playwright
- **Sources Consulted**: Apple Developer Documentation (Swift Testing, XCUITest), swift-snapshot-testing library
- **Findings**:
  - **Swift Testing** (`import Testing`, `@Test`, `#expect`): Preferred for unit and integration tests in Xcode 16+. Better diagnostics, parameterized tests, tags. The Xcode project already uses this.
  - **XCUITest**: Still required for UI automation — Swift Testing does not support XCUIApplication. Use `XCTestCase` in the UI test target.
  - **Mock injection**: Launch arguments (`CommandLine.arguments.contains("--mock-mode")`) or environment variables (`ProcessInfo.processInfo.environment["SBX_MOCK"]`) for test-time service swapping.
  - **XCUITest for macOS**: `XCUIApplication().launch()`, query via `app.buttons["Label"]`, `app.staticTexts["Text"]`. Use `.accessibilityIdentifier()` for reliable element queries.
  - **NavigationSplitView testing**: Click sidebar items via `app.outlines` or `app.staticTexts`, assert detail content.
  - **Sheets/alerts**: `app.sheets.firstMatch`, `app.dialogs.firstMatch.buttons["OK"].click()`.
  - **Snapshot testing**: swift-snapshot-testing (Point-Free) works with `NSHostingView` wrapping SwiftUI views.
  - **NSWorkspace for app detection**: `NSWorkspace.shared.urlForApplication(withBundleIdentifier:)` is preferred over filesystem checks — location-independent.
- **Implications**:
  - Vitest → Swift Testing for unit tests
  - Playwright → XCUITest for E2E tests
  - `SBX_MOCK=1` environment variable works identically via `ProcessInfo.processInfo.environment`
  - Accessibility identifiers are critical for reliable UI test element queries

### External Terminal Launching on macOS (Updated)
- **Context**: Requirement 11 specifies opening bash shells in external terminal applications
- **Sources Consulted**: macOS NSWorkspace API, osascript/AppleScript documentation, iTerm2 AppleScript API
- **Findings**:
  - **App detection**: `NSWorkspace.shared.urlForApplication(withBundleIdentifier:)` is preferred over filesystem checks:
    - Terminal.app: `com.apple.Terminal`
    - iTerm2: `com.googlecode.iterm2`
  - **Terminal launching**: osascript remains the best approach for passing commands:
    - Terminal.app: `osascript -e 'tell app "Terminal" to do script "sbx exec -it <name> bash"'`
    - iTerm: `osascript -e 'tell app "iTerm2" to create window with default profile command "sbx exec -it <name> bash"'`
  - **Swift API**: Can also use `Process` to run `osascript` with arguments, or use `NSAppleScript` class directly
  - Both apps support AppleScript for programmatic window creation
- **Implications**:
  - `NSWorkspace` for detection replaces filesystem checks — more robust for non-standard installations
  - `NSAppleScript` or `Process` with `osascript` for launching — both work without App Sandbox
  - User preference stored via SwiftData or `UserDefaults` (simpler than localStorage)
  - Command to execute inside terminal: `sbx exec -it <name> bash`

## Architecture Pattern Evaluation

| Option | Description | Strengths | Risks / Limitations | Notes |
|--------|-------------|-----------|---------------------|-------|
| Single-process @Observable MVVM | SwiftUI views bind to @Observable model classes; services injected via environment | Natural fit for SwiftUI; no IPC overhead; granular reactivity | All code in one process — no forced isolation | Preferred for macOS native apps |
| Multi-process with XPC | Main app delegates CLI operations to an XPC helper service | Could enable sandboxed main app | Over-engineering; XPC adds significant complexity; not needed without sandbox | Would only be needed for Mac App Store |
| Hexagonal Ports and Adapters | Abstract all external I/O behind protocol interfaces | Highly testable, easy mock/real swap | Adapter layer adds indirection | SbxServiceProtocol already provides this |

**Selected**: Single-process SwiftUI app with `@Observable` models and protocol-based service injection. SbxServiceProtocol acts as the primary port/adapter boundary for testability (mock/real swap). No IPC layer needed — SwiftUI views call services directly through `@Observable` models.

## Design Decisions

### Decision: macOS Native with SwiftUI (Replacing Electron)
- **Context**: User changed technology direction from Electron to macOS native
- **Alternatives Considered**:
  1. Electron + React + TypeScript (original design)
  2. macOS native with SwiftUI + Swift
  3. macOS native with AppKit only
- **Selected Approach**: SwiftUI with AppKit interop where needed (terminal view)
- **Rationale**: SwiftUI provides modern declarative UI with native macOS look and feel. AppKit interop via `NSViewRepresentable` covers cases like terminal rendering. Eliminates Electron's web overhead and Node.js dependency.
- **Trade-offs**: SwiftUI macOS has some rough edges compared to AppKit; terminal rendering requires NSViewRepresentable bridge. Single-platform (macOS only).
- **Follow-up**: Consider Catalyst or cross-platform frameworks if iOS/iPad support is needed in Phase 2

### Decision: SwiftTerm for Terminal Emulation (Replacing xterm.js + node-pty)
- **Context**: Need terminal rendering with full ANSI support and PTY management
- **Alternatives Considered**:
  1. SwiftTerm (native macOS terminal library)
  2. WKWebView + xterm.js (web-based terminal in native shell)
  3. Custom AppKit NSView with CoreText rendering
- **Selected Approach**: SwiftTerm via `MacLocalTerminalView` wrapped in `NSViewRepresentable`
- **Rationale**: Production-proven (1,451+ stars, used in Secure Shellfish, La Terminal, CodeEdit). Handles both PTY management and terminal rendering in one library. Native rendering avoids WKWebView bridge overhead. MIT license.
- **Trade-offs**: Dependency on third-party library; requires `NSViewRepresentable` bridge for SwiftUI
- **Follow-up**: Monitor SwiftTerm releases; consider contributing upstream if gaps found

### Decision: CLI Wrapping via Foundation Process
- **Context**: The `sbx` CLI is the only programmatic interface to Docker Sandbox
- **Alternatives Considered**:
  1. Foundation `Process` with `Pipe` for stdout/stderr capture
  2. Wait for a Docker Sandbox SDK (none announced)
  3. POSIX-level `posix_spawn` directly
- **Selected Approach**: Foundation `Process` with `AsyncStream` for async output
- **Rationale**: `Process` is the idiomatic Swift API for CLI spawning. Array-form arguments prevent command injection. `AsyncStream` integrates cleanly with Swift Concurrency.
- **Trade-offs**: Parsing stdout is fragile if CLI output format changes; `--json` mitigates this where available
- **Follow-up**: Monitor Docker Sandbox releases for SDK or JSON output modes on all commands

### Decision: Polling for State Updates
- **Context**: Need near-real-time sandbox status, but `sbx` has no event/WebSocket API
- **Alternatives Considered**:
  1. Poll `sbx ls` at fixed interval (3s)
  2. Watch filesystem directory for state changes
  3. Parse Docker events from the sandbox's Docker daemon
- **Selected Approach**: Poll `sbx ls` every 3 seconds via `AsyncStream` timer
- **Rationale**: Matches `sbx` TUI behavior. Filesystem watching is unreliable and requires internal state knowledge. Docker events are inside the sandbox VM.
- **Trade-offs**: 3s polling latency; CPU overhead from repeated CLI spawning
- **Follow-up**: Monitor for event API in future `sbx` releases

### Decision: Disable App Sandbox
- **Context**: App needs to spawn external CLI tools (`sbx`, `osascript`)
- **Alternatives Considered**:
  1. Disable App Sandbox, enable Hardened Runtime, notarize for direct distribution
  2. XPC Service helper for process spawning (sandboxed main app)
  3. Embed `sbx` binary within app bundle
- **Selected Approach**: Disable App Sandbox; distribute outside Mac App Store
- **Rationale**: Standard approach for developer tools (iTerm2, VS Code, Docker Desktop). No entitlement exists for selective Process spawning. XPC adds unnecessary complexity.
- **Trade-offs**: Cannot distribute on Mac App Store; reduced sandboxing
- **Follow-up**: Consider XPC architecture if Mac App Store distribution becomes a requirement

### Decision: @Observable for State Management (Replacing Zustand)
- **Context**: Need reactive state management for UI updates
- **Alternatives Considered**:
  1. `@Observable` macro (Observation framework, macOS 14+)
  2. `@ObservableObject` / `@Published` (Combine-based)
  3. Third-party state management (TCA, etc.)
- **Selected Approach**: `@Observable` classes with `.environment()` injection
- **Rationale**: Modern SwiftUI standard. Granular property tracking — views only re-render when accessed properties change. No boilerplate publishers. Simpler than Combine-based alternatives.
- **Trade-offs**: Requires macOS 14+ (Sonoma). Less ecosystem tooling than TCA.
- **Follow-up**: None — this is the Apple-recommended approach

### Decision: External Terminal via NSAppleScript
- **Context**: Requirement 11 requires opening bash shells in external terminal applications
- **Alternatives Considered**:
  1. `NSAppleScript` for direct AppleScript execution
  2. `Process` with `osascript` command
  3. `NSWorkspace.open` (cannot pass commands)
- **Selected Approach**: `NSAppleScript` with per-application AppleScript templates, `NSWorkspace` for app detection
- **Rationale**: Direct API avoids spawning another process. `NSWorkspace.urlForApplication(withBundleIdentifier:)` is more robust than filesystem checks for app detection.
- **Trade-offs**: macOS-only; Windows support would need different approach (Phase 2)
- **Follow-up**: Add Windows support in Phase 2

### Decision: UserDefaults for User Preferences (Replacing localStorage)
- **Context**: Need to persist user's preferred terminal application
- **Alternatives Considered**:
  1. `UserDefaults` (Foundation standard)
  2. SwiftData (full persistence framework)
  3. JSON file in app support directory
- **Selected Approach**: `UserDefaults` for simple key-value preferences
- **Rationale**: Simplest approach for a single key-value preference. Built into Foundation, no additional dependency. Survives app restarts automatically.
- **Trade-offs**: Not suitable for complex data; acceptable for simple preferences
- **Follow-up**: Migrate to SwiftData if more complex settings are added in Phase 2

## Risks & Mitigations
- **CLI output format changes** — Pin tested `sbx` version in docs; prefer `--json` where available; parser unit tests catch breakage early
- **SwiftTerm compatibility** — Library is actively maintained and production-proven; pin version in Package.swift
- **App Sandbox disabled** — Required for CLI access; mitigate with Hardened Runtime and notarization; input validation prevents command injection
- **Polling CPU overhead** — 3s interval is conservative; can increase interval or add smart backoff when app is not focused
- **External terminal app detection** — `NSWorkspace` bundle ID lookup handles non-standard installations; manual configuration as fallback
- **Mock drift from real behavior** — Shared SbxServiceProtocol enforced at compile time; E2E tests catch behavioral drift
- **SwiftUI macOS rough edges** — AppKit interop via `NSViewRepresentable` covers gaps; terminal rendering uses proven AppKit NSView

## References
- [Docker Sandbox Get Started](https://docs.docker.com/ai/sandboxes/get-started/) — Installation, login, credential setup
- [Docker Sandbox Usage](https://docs.docker.com/ai/sandboxes/usage/) — CLI command reference, lifecycle, ports, TUI
- [Docker Sandbox Architecture](https://docs.docker.com/ai/sandboxes/architecture/) — microVM, proxy, workspace passthrough model
- [Docker Sandbox Security](https://docs.docker.com/ai/sandboxes/security/) — Trust boundary, data flow, isolation layers
- [Docker Sandbox Security Policy](https://docs.docker.com/ai/sandboxes/security/policy/) — Network policy CLI, precedence rules, wildcards
- [Docker Sandbox Claude Code](https://docs.docker.com/ai/sandboxes/agents/claude-code/) — Agent launch, prompt passthrough, authentication
- [Docker Sandbox Credentials](https://docs.docker.com/ai/sandboxes/security/credentials/) — Secret management, proxy injection
- [Docker Sandbox Workspace](https://docs.docker.com/ai/sandboxes/security/workspace/) — Workspace trust model, critical risk files
- [Docker Sandbox Troubleshooting](https://docs.docker.com/ai/sandboxes/troubleshooting/) — Common issues, diagnostic commands
- [Docker Sandbox FAQ](https://docs.docker.com/ai/sandboxes/faq/) — Sign-in, telemetry, custom env vars
- [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) — Native terminal emulator for Swift (macOS/iOS/Linux)
- [Apple Observation Framework](https://developer.apple.com/documentation/observation) — @Observable macro documentation
- [Apple NavigationSplitView](https://developer.apple.com/documentation/swiftui/navigationsplitview) — Sidebar+detail layout
- [Apple Foundation Process](https://developer.apple.com/documentation/foundation/process) — External process spawning
- [Apple Hardened Runtime](https://developer.apple.com/documentation/security/hardened-runtime) — Runtime protections for notarized apps
- [Swift Testing](https://developer.apple.com/documentation/testing) — Modern test framework for Swift
- [swift-snapshot-testing](https://github.com/pointfreeco/swift-snapshot-testing) — Snapshot testing for SwiftUI
