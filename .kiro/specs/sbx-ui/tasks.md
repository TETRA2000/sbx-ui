# Implementation Plan

- [ ] 1. Scaffold Electron project with React, TypeScript, Tailwind, and design system tokens
  - Initialize an Electron 36+ project using electron-vite with React 19, TypeScript strict mode, and pnpm as package manager
  - Install and configure Tailwind CSS 4 with the Technical Monolith design token palette (surface hierarchy, accent colors, font families)
  - Configure the three-font stack: Inter for UI text, JetBrains Mono for code and metrics, Space Grotesk for labels
  - Set maximum border-radius to 0.5rem in the Tailwind theme
  - Verify `pnpm run dev` opens a blank Electron window with Tailwind styles applied
  - _Requirements: 8.3, 8.4, 8.5_

- [ ] 2. Service layer: domain types, interface, and mock implementation
- [ ] 2.1 Define all domain types and the SbxService interface contract
  - Define the Sandbox type with id, name, agent, status (running/stopped/creating/removing), workspace, ports, and createdAt
  - Define PolicyRule with id, type, decision (allow/deny), and resources
  - Define PolicyLogEntry with sandbox, type, host, proxy (forward/transparent/network), rule, lastSeen, count, and blocked
  - Define PortMapping with hostPort, sandboxPort, and protocol
  - Define RunOptions with optional name and prompt fields
  - Define PtyHandle with onData, write, and dispose methods
  - Define SbxServiceError with typed error codes (NOT_FOUND, ALREADY_EXISTS, PORT_CONFLICT, NOT_RUNNING, CLI_ERROR, DOCKER_NOT_RUNNING, INVALID_NAME)
  - Define the complete SbxService interface covering lifecycle, policy, port, and session operations
  - _Requirements: 7.2, 9.2_

- [ ] 2.2 Implement the mock service with full lifecycle, policy, and port operations
  - Implement sandbox lifecycle: list returns all sandboxes, run creates with "creating" state then transitions to "running" after ~800ms delay, stop transitions to "stopped" after ~300ms and clears ports, rm removes after ~200ms
  - Auto-generate sandbox name as "claude-&lt;dirname&gt;" when no name is provided
  - Return the existing sandbox when run is called with a workspace that already has a running sandbox
  - Validate sandbox names against the allowed pattern (lowercase alphanumeric and hyphens, no leading hyphen); reject invalid names with INVALID_NAME
  - Pre-seed Balanced network policy defaults on construction (api.anthropic.com, *.npmjs.org, github.com, *.github.com, registry.hub.docker.com, *.docker.io, *.googleapis.com, api.openai.com, *.pypi.org, files.pythonhosted.org)
  - Implement policy allow, deny, remove, and list operations on the in-memory policy map
  - Simulate policy log entries referencing existing sandboxes
  - Implement port publish with duplicate host port rejection, unpublish, and list operations
  - Clear all port mappings when a sandbox is stopped
  - _Requirements: 1.3, 1.5, 7.1, 7.2, 7.3, 7.4, 7.7_

- [ ] 2.3 Write unit tests for the mock service
  - Test lifecycle transitions: create → running, running → stopped, stopped → running, running/stopped → removed
  - Test realistic delay simulation for each transition
  - Test Balanced policy defaults are present after construction
  - Test policy CRUD: add allow rule, add deny rule, remove rule, list rules
  - Test port validation: reject duplicate host port, clear on stop, reject publish on stopped sandbox
  - Test duplicate workspace returns existing sandbox instead of creating a new one
  - Test invalid sandbox name rejection
  - _Requirements: 7.2, 7.3, 7.4, 7.7_

- [ ] 3. IPC bridge: service factory, handlers, and preload
- [ ] 3.1 Implement service factory and register all IPC handlers
  - Build the service factory that returns the mock implementation when SBX_MOCK=1 is set, otherwise the real implementation
  - Register IPC handlers for all sandbox lifecycle operations (list, run, stop, rm)
  - Register IPC handlers for all policy operations (policyList, policyAllow, policyDeny, policyRemove, policyLog)
  - Register IPC handlers for all port operations (portsList, portsPublish, portsUnpublish)
  - Register IPC handlers for session operations (attach, send, detach) and wire PTY data streaming to the sbx:session:data event channel
  - Register handler for native filesystem directory selection dialog
  - Register handlers for external terminal operations (list available, open shell)
  - Catch service errors and return structured SbxServiceError objects to the renderer
  - _Requirements: 7.1, 9.1, 9.3_

- [ ] 3.2 Implement preload bridge exposing typed API to the renderer
  - Expose all lifecycle methods (list, run, stop, rm) via contextBridge
  - Expose all policy methods (policyList, policyAllow, policyDeny, policyRemove, policyLog) via contextBridge
  - Expose all port methods (portsList, portsPublish, portsUnpublish) via contextBridge
  - Expose session methods (attachSession, sendMessage, detachSession) and the onSessionData subscription with unsubscribe support
  - Expose selectDirectory for native filesystem dialog
  - Expose openExternalTerminal and getAvailableTerminals for external shell access
  - Ensure no ipcRenderer or Node.js APIs are leaked beyond the typed bridge
  - _Requirements: 9.1, 9.2_

- [ ] 4. Build application shell with sidebar navigation and top bar
  - Create the root shell layout with a fixed sidebar on the left, a fixed top bar at the top, and a scrollable content area
  - Apply the surface hierarchy: base surface (#131313), sidebar with glassmorphism (surface-variant at 60% opacity with 20px backdrop-blur)
  - Build the sidebar with navigation links for Dashboard and Policies views, plus a "Deploy Agent" CTA button at the bottom
  - Use Space Grotesk for sidebar labels (uppercase, wide tracking) and the gradient CTA style from the design system
  - Build the top bar with the application title, search input, and user area
  - Implement view switching between dashboard and policy views using simple state-based routing
  - _Requirements: 8.1, 8.2, 8.3, 8.4, 8.5_

- [ ] 5. Sandbox dashboard and project creation
- [ ] 5.1 Implement the sandbox store with polling and mutation actions
  - Create a Zustand store holding the sandbox list, loading state, and error state
  - Implement fetchSandboxes that calls the bridge to list all sandboxes
  - Implement createSandbox, stopSandbox, and removeSandbox mutation actions that call the bridge and trigger an immediate re-fetch
  - Start a 3-second polling interval that calls fetchSandboxes on dashboard view mount
  - Stop polling when the dashboard view unmounts
  - _Requirements: 2.7, 3.1, 3.2, 3.5_

- [ ] 5.2 Build the dashboard grid with sandbox cards, status indicators, and statistics
  - Render all sandboxes as cards in a CSS grid with an asymmetric bento layout (first card spans two columns on wide screens)
  - Include a "+" placeholder card for creating new projects
  - Display on each card: sandbox name, agent type ("claude"), current status chip, workspace path, and active port mappings as compact chips (e.g., 8080→3000)
  - Build the status chip: green 4px dot with glow animation and "LIVE" label for running, static "STOPPED" chip for stopped, spinner for creating/removing
  - Apply hover transition to surface-container-high background
  - Build a global statistics bar above the grid showing running sandbox count and total sandbox count
  - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5, 2.6, 5.4_

- [ ] 5.3 Build project creation dialog with directory picker and optional name
  - When the user clicks "Deploy Agent" or the "+" card, open a modal dialog
  - Trigger the native filesystem directory picker via the bridge
  - Display the selected path in JetBrains Mono font
  - Provide an optional text input for a custom sandbox name
  - On submit, call createSandbox with the selected directory and optional name; the service auto-generates "claude-&lt;dirname&gt;" if no name is given
  - If the user cancels the picker or the dialog, close without any side effects
  - If a sandbox already exists for the selected workspace, surface the returned existing sandbox
  - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5_

- [ ] 6. Add sandbox lifecycle controls to dashboard cards
  - Add a pause/stop button to running sandbox cards that calls stopSandbox and transitions the card to "stopped" status
  - Enable clicking a stopped sandbox card to resume it by calling createSandbox with the sandbox name, transitioning back to "running"
  - Add a "Terminate Agent" action (in error color) that opens a confirmation dialog before calling removeSandbox
  - If the user cancels the confirmation dialog, take no action
  - After removal, the card disappears from the grid on the next poll/re-fetch
  - During "creating" and "removing" transient states, show a spinner and disable all action buttons on the card
  - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5, 3.6_

- [ ] 7. Network policy management
- [ ] 7.1 (P) Implement policy store and build policy panel with rule management
  - Create a Zustand store holding policy rules, loading state, and error state
  - Implement fetchPolicies, addAllow, addDeny, and removeRule actions that call the bridge and trigger re-fetch
  - Build the policy panel as a dedicated view accessible from sidebar navigation
  - Display each rule with its decision (allow/deny) and resource domains
  - When the app starts with no custom policies, display the pre-seeded Balanced defaults
  - Build an add policy dialog with a text input for domains (supports comma-separated), an allow/deny toggle, and submit/cancel buttons; use JetBrains Mono for the domain input
  - Add a remove button to each policy rule row
  - _Requirements: 4.1, 4.2, 4.3, 4.4, 4.5_

- [ ] 7.2 Build policy log viewer with filtering
  - Build a data table showing network activity: sandbox name, host, proxy type, rule, last seen timestamp, request count, and blocked/allowed status
  - Use ghost borders (outline-variant at 15% opacity) for table row separation
  - Add a sandbox name filter dropdown that filters log entries by sandbox
  - Add a blocked-only toggle that shows only blocked requests
  - Implement fetchLog in the policy store with optional sandbox name parameter
  - Store filter state (sandbox name, blocked-only) in the policy store
  - _Requirements: 4.6, 4.7_

- [ ] 8. Port forwarding management
  - Build a port panel per sandbox showing all active host-to-sandbox port mappings as rows
  - Build an add port dialog with host port and sandbox port number inputs; validate that values are positive integers in range 1-65535
  - On submit, call portsPublish via the bridge; if the host port is already in use, display an inline error
  - Add an unpublish button to each port mapping row that calls portsUnpublish via the bridge
  - Implement the usePorts hook that calls port IPC methods directly and triggers the sandbox store refresh after each mutation to update Sandbox.ports[]
  - While a sandbox is stopped, disable the add port button and display a notice that ports are cleared on stop
  - When a sandbox stops, clear its port mappings from the display
  - _Requirements: 5.1, 5.2, 5.3, 5.5, 5.6, 5.7_

- [ ] 9. PTY manager and mock terminal emitter
- [ ] 9.1 (P) Implement PTY session manager and mock terminal emitter
  - Build the PTY manager that tracks one active PTY per sandbox name
  - In mock mode, create a mock emitter instance that simulates Claude Code output
  - The mock emitter emits a startup sequence with ANSI formatting: Claude Code banner, model info, workspace path, prompt character, with realistic inter-line delays
  - On receiving input via write, the mock emitter simulates an agent response sequence: thinking → reading file → writing file → done → prompt, with delays between steps
  - In real mode, spawn a node-pty pseudo-terminal running "sbx run &lt;name&gt;"
  - Implement attach (creates PTY), write (sends data to PTY stdin), dispose (kills PTY), disposeAll, and isAttached query
  - _Requirements: 6.1, 7.5, 7.6_

- [ ] 9.2 Wire PTY data events through IPC to the renderer
  - Forward PTY data events from the PTY manager to the renderer via the sbx:session:data IPC event channel
  - Ensure the preload bridge delivers data events to the onSessionData subscription callback
  - Handle session disposal by stopping data forwarding and cleaning up listeners
  - _Requirements: 6.2, 9.3_

- [ ] 10. Session interaction UI
- [ ] 10.1 Build session panel with terminal view and chat input
  - When the user clicks a running sandbox card, open a session panel that takes the full content area
  - Split the session panel: xterm.js terminal in the upper area, chat input fixed at the bottom, agent status bar between
  - Initialize an xterm.js terminal instance with the surface-container-lowest background (#0E0E0E), the fit addon for auto-sizing, and full ANSI code support
  - Connect the terminal to the PTY data stream via the onSessionData subscription; write received data to xterm.js
  - Build the chat input with a text field (JetBrains Mono), a send button, and Enter key submission
  - When the user sends a message, call sendMessage via the bridge which writes to PTY stdin
  - Disable the chat input when not connected to a session
  - _Requirements: 6.1, 6.2, 6.3_

- [ ] 10.2 Implement session store with lifecycle management and status display
  - Create a Zustand store tracking the active sandbox name, connection status, error state, and the data subscription cleanup function
  - On attach, call the bridge attachSession, subscribe to data events, and set connected state
  - On detach (triggered by navigating away or closing the panel), call detachSession and clean up the subscription
  - When a sandbox transitions from stopped to running while the session panel is open, automatically re-attach the session
  - Only allow one active session at a time; attaching a new session detaches the previous one
  - Build the agent status bar showing model name ("claude"), sandbox name, uptime counter, and a connection indicator (green dot when connected)
  - _Requirements: 6.4, 6.5, 6.6_

- [ ] 11. External terminal integration
- [ ] 11.1 (P) Implement terminal application detection and shell launching
  - Detect which terminal applications are installed by checking known macOS bundle paths (/Applications/Terminal.app, /Applications/iTerm.app)
  - Terminal.app is always available on macOS; only include iTerm in the available list if the bundle is found
  - Launch a terminal window via osascript with AppleScript templates specific to each application
  - Execute "sbx exec -it &lt;name&gt; bash" inside the launched terminal to open an interactive bash shell
  - Validate the sandbox name against the allowed pattern before interpolation; escape the name for AppleScript string context (backslash-escape \ and ")
  - If the terminal application fails to launch, throw an error with the application name and suggest alternatives
  - _Requirements: 11.1, 11.2, 11.3, 11.6_

- [ ] 11.2 Add terminal preference setting and wire the Open Shell action
  - Create a settings store with Zustand persist middleware (localStorage) to store the user's preferred terminal application
  - Add a terminal preference selector in the settings area showing only detected terminal applications
  - Default to Terminal.app when no preference is set
  - Add an "Open Shell" button to running sandbox cards that launches a bash shell in the preferred terminal
  - Disable the "Open Shell" button when a sandbox is in stopped status
  - _Requirements: 11.4, 11.5, 11.7_

- [ ] 12. Real sbx CLI integration
- [ ] 12.1 (P) Implement CLI output parsers and command executor
  - Build the command executor that spawns sbx CLI processes using array-form child_process.spawn (never shell string interpolation) and captures stdout, stderr, and exit code
  - Build a JSON execution mode that passes --json flags and parses the output directly
  - Build a parser for "sbx ls" output: detect column headers and extract sandbox name, agent, status, ports, and workspace from each row using header position detection
  - Build a parser for "sbx policy ls" output: extract policy ID, type, decision, and resources
  - Build a parser for "sbx policy log" output: detect Blocked/Allowed sections and extract all fields; prefer --json flag when available
  - Build a parser for "sbx ports" output: extract host port and sandbox port using the digit-arrow-digit pattern
  - Handle empty output and header-only output by returning empty arrays
  - Write unit tests for each parser with realistic CLI output samples and edge cases
  - _Requirements: 9.3_

- [ ] 12.2 Implement the real service wrapping all CLI commands
  - Implement each SbxService method by calling the corresponding sbx CLI command through the executor and parsing the output
  - Map: list → "sbx ls", run → "sbx run claude &lt;workspace&gt; --name &lt;name&gt;", stop → "sbx stop &lt;name&gt;", rm → "sbx rm &lt;name&gt;"
  - Map policy methods to "sbx policy" subcommands and port methods to "sbx ports" subcommands
  - Detect missing sbx CLI (binary not found on PATH) and throw CLI_ERROR on construction
  - Detect Docker not running and throw DOCKER_NOT_RUNNING with descriptive message
  - Validate sandbox names before passing to CLI commands
  - _Requirements: 9.3, 9.4_

- [ ] 13. Error handling, toast notifications, and input validation
  - Implement a toast notification component that displays user-friendly error messages, auto-dismisses after a few seconds, and supports stacking multiple toasts
  - Surface all service errors from IPC calls as toast notifications with clear messages (e.g., "Port 8080 is already in use", "Sandbox not found")
  - Build a full-screen error state shown when sbx CLI is not installed or Docker Desktop is not running, with guidance on how to install or start the required dependency
  - Add sandbox name validation in the project creation dialog: only allow lowercase alphanumeric characters and hyphens, no leading hyphen; show inline error for invalid names
  - Validate domain inputs in the add policy dialog before submission (non-empty, no catch-all patterns)
  - Validate port numbers as positive integers within range 1-65535 in the add port dialog
  - _Requirements: 5.5, 9.4, 9.5, 11.6_

- [ ] 14. E2E test suite
- [ ] 14.1 Set up end-to-end testing with Playwright and mock mode
  - Configure Playwright with Electron support in the project
  - Set up test fixtures that force SBX_MOCK=1 so all tests run against the mock service without Docker Desktop
  - Verify the test runner can launch the Electron app, interact with the renderer, and capture UI state
  - _Requirements: 10.2_

- [ ] 14.2 (P) Write E2E tests for project creation and sandbox lifecycle
  - Test project creation: trigger the deploy action, select a directory, verify a new sandbox appears in the grid as LIVE with the correct name and workspace path
  - Test full lifecycle: create a sandbox → verify LIVE status → stop it → verify STOPPED status → remove it with confirmation → verify it is gone from the grid
  - _Requirements: 10.1, 10.3_

- [ ] 14.3 (P) Write E2E tests for policies, ports, and session messaging
  - Test policy management: add an allow rule for a test domain, verify it appears in the policy list, remove it, verify it is gone
  - Test port forwarding: publish a port mapping (e.g., 8080:3000), verify it appears on the sandbox card and in the port panel, unpublish it, verify it is gone
  - Test session messaging: click a running sandbox to open the session, verify terminal output appears, send a message in the chat input, verify simulated Claude Code response output streams into the terminal
  - _Requirements: 10.1, 10.4, 10.5, 10.6_
