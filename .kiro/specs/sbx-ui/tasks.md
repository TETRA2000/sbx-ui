# Implementation Plan

- [ ] 1. Configure Xcode project with SwiftTerm dependency, design system tokens, and custom fonts
  - Add SwiftTerm as a Swift Package Manager dependency (version 1.13+)
  - Bundle custom fonts (Inter, JetBrains Mono, Space Grotesk) in the app and register them via Info.plist ATSApplicationFontsPath
  - Create SwiftUI Color extensions for the Technical Monolith surface hierarchy: surfaceLowest (#0E0E0E), surface (#131313), surfaceContainer (#1C1B1B), surfaceContainerHigh (#2A2A2A), surfaceContainerHighest (#353534), accent (#ADC6FF), secondary (#4EDEA3), error (#F2B8B5)
  - Create SwiftUI Font extensions for the three-font stack: Inter for UI text, JetBrains Mono for code and metrics, Space Grotesk for labels
  - Set maximum corner radius to 8 points (0.5rem equivalent) as a shared constant
  - Apply forced dark mode via .preferredColorScheme(.dark) at the WindowGroup level
  - Disable App Sandbox entitlement; enable Hardened Runtime for notarization compatibility
  - Verify the app builds and launches with the design system tokens applied
  - _Requirements: 8.3, 8.4, 8.5_

- [ ] 2. Service layer: domain types, protocol, and mock implementation
- [ ] 2.1 Define all domain types and the SbxServiceProtocol contract
  - Define SandboxStatus enum (running, stopped, creating, removing) conforming to Sendable and Codable
  - Define Sandbox struct with id, name, agent, status, workspace, ports, and createdAt conforming to Identifiable and Sendable
  - Define PolicyRule with id, type, decision (allow/deny enum), and resources conforming to Identifiable and Sendable
  - Define PolicyLogEntry with sandbox, type, host, proxy, rule, lastSeen, count, and blocked conforming to Sendable
  - Define PortMapping with hostPort, sandboxPort, and protocolType conforming to Sendable
  - Define RunOptions with optional name and prompt fields conforming to Sendable
  - Define PtyHandle protocol with onData, write, and dispose methods conforming to Sendable
  - Define SbxServiceError enum with typed error cases (notFound, alreadyExists, portConflict, notRunning, cliError, dockerNotRunning, invalidName) conforming to Error and Sendable
  - Define SbxServiceProtocol with all lifecycle, policy, port, and sendMessage operations; all methods async throws; protocol conforms to Sendable
  - _Requirements: 7.2, 9.2_

- [ ] 2.2 Implement the mock service actor with full lifecycle, policy, and port operations
  - Implement MockSbxService as a Swift actor conforming to SbxServiceProtocol
  - Implement sandbox lifecycle: list returns all sandboxes, run creates with "creating" state then transitions to "running" after ~800ms delay via Task.sleep, stop transitions to "stopped" after ~300ms and clears ports, rm removes after ~200ms
  - Auto-generate sandbox name as "claude-<dirname>" when no name is provided
  - Return the existing sandbox when run is called with a workspace that already has a running sandbox
  - Validate sandbox names against the allowed pattern (lowercase alphanumeric and hyphens, no leading hyphen); reject invalid names with .invalidName
  - Pre-seed Balanced network policy defaults on construction (api.anthropic.com, *.npmjs.org, github.com, *.github.com, registry.hub.docker.com, *.docker.io, *.googleapis.com, api.openai.com, *.pypi.org, files.pythonhosted.org)
  - Implement policy allow, deny, remove, and list operations on in-memory dictionaries
  - Simulate policy log entries referencing existing sandboxes
  - Implement port publish with duplicate host port rejection, unpublish, and list operations
  - Clear all port mappings when a sandbox is stopped
  - _Requirements: 1.3, 1.5, 7.1, 7.2, 7.3, 7.4, 7.7_

- [ ] 2.3 (P) Implement MockPtyEmitter for simulated terminal output
  - Build MockPtyEmitter conforming to the PtyHandle protocol
  - Simulate a startup sequence with ANSI formatting: Claude Code banner, model info, workspace path, prompt character, with realistic inter-line delays via Task.sleep
  - On receiving input via write, simulate an agent response sequence: thinking → reading file → writing file → done → prompt, with delays between steps
  - Emit data to the registered onData callback in order
  - _Requirements: 7.5, 7.6_

- [ ] 2.4 Write unit tests for the mock service and mock emitter
  - Test lifecycle transitions: create → running, running → stopped, stopped → running, running/stopped → removed
  - Test realistic delay simulation for each transition
  - Test Balanced policy defaults are present after construction
  - Test policy CRUD: add allow rule, add deny rule, remove rule, list rules
  - Test port validation: reject duplicate host port, clear on stop, reject publish on stopped sandbox
  - Test duplicate workspace returns existing sandbox instead of creating a new one
  - Test invalid sandbox name rejection
  - Test MockPtyEmitter emits startup sequence and responds to write input
  - _Requirements: 7.2, 7.3, 7.4, 7.5, 7.6, 7.7_

- [ ] 3. Service factory and app-level dependency injection
  - Build ServiceFactory that returns MockSbxService when ProcessInfo.processInfo.environment["SBX_MOCK"] == "1", otherwise RealSbxService
  - Create the service instance at app startup and inject it into the SwiftUI environment
  - Create all @MainActor @Observable store instances (SandboxStore, PolicyStore, SessionStore, SettingsStore) with the service injected
  - Inject stores into the SwiftUI view hierarchy via .environment() at the WindowGroup level
  - _Requirements: 7.1, 9.1_

- [ ] 4. Build application shell with NavigationSplitView and sidebar
  - Create ShellView as the root layout using NavigationSplitView with a fixed sidebar and scrollable detail area
  - Apply the surface hierarchy: base surface (#131313) background, sidebar with surfaceContainer (#1C1B1B)
  - Build SidebarView with navigation list items for Dashboard and Policies views, plus a "Deploy Agent" button at the bottom
  - Use Space Grotesk for sidebar labels (uppercase styling)
  - Implement view switching between dashboard and policy detail views via sidebar selection binding
  - _Requirements: 8.1, 8.2, 8.3, 8.4, 8.5_

- [ ] 5. Sandbox dashboard and project creation
- [ ] 5.1 Implement SandboxStore with polling and mutation actions
  - Build SandboxStore as @MainActor @Observable class holding the sandbox list, loading state, and error state
  - Inject SbxServiceProtocol (as any SbxServiceProtocol) via initializer
  - Implement fetchSandboxes that calls the service to list all sandboxes
  - Implement createSandbox, stopSandbox, and removeSandbox mutation actions that call the service and trigger an immediate re-fetch
  - Implement startPolling using a Task with Task.sleep(for: .seconds(3)) loop that calls fetchSandboxes
  - Implement stopPolling that cancels the polling Task
  - Start polling on dashboard view appear via .task modifier; cancel on disappear
  - _Requirements: 2.7, 3.1, 3.2, 3.5_

- [ ] 5.2 Build the dashboard grid with sandbox cards, status indicators, and statistics
  - Build SandboxGridView using LazyVGrid with adaptive columns rendering SandboxCardView per sandbox plus a "+" placeholder card
  - Display on each card: sandbox name, agent type ("claude"), current status chip, workspace path, and active port mappings as compact chips (e.g., 8080→3000)
  - Build StatusChipView: green 4px circle with pulse animation (.animation(.easeInOut.repeatForever())) and "LIVE" label for running, static "STOPPED" chip for stopped, ProgressView spinner for creating/removing
  - Apply hover effect via .onHover modifier transitioning to surfaceContainerHigh background
  - Build GlobalStatsView bar above the grid showing running sandbox count and total count with JetBrains Mono for numbers
  - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5, 2.6, 5.4_

- [ ] 5.3 Build project creation sheet with directory picker and optional name
  - When the user clicks "Deploy Agent" or the "+" card, present a .sheet modal
  - Use .fileImporter with UTType.folder for native directory picker (NSOpenPanel)
  - Display the selected path in JetBrains Mono font
  - Provide an optional TextField for a custom sandbox name
  - On submit, call SandboxStore.createSandbox with the selected directory and optional name; the service auto-generates "claude-<dirname>" if no name is given
  - If the user cancels the picker or the sheet, dismiss without any side effects
  - If a sandbox already exists for the selected workspace, surface the returned existing sandbox
  - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5_

- [ ] 6. Add sandbox lifecycle controls to dashboard cards
  - Add a pause/stop button to running sandbox cards that calls SandboxStore.stopSandbox and transitions the card to "stopped" status
  - Enable clicking a stopped sandbox card to resume it by calling createSandbox with the sandbox name, transitioning back to "running"
  - Add a "Terminate Agent" action (in error color) that opens a .confirmationDialog before calling removeSandbox
  - If the user cancels the confirmation dialog, take no action
  - After removal, the card disappears from the grid on the next poll/re-fetch
  - During "creating" and "removing" transient states, show a spinner and disable all action buttons on the card
  - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5, 3.6_

- [ ] 7. Network policy management
- [ ] 7.1 (P) Implement PolicyStore and build policy panel with rule management
  - Build PolicyStore as @MainActor @Observable class holding policy rules, loading state, and error state
  - Implement fetchPolicies, addAllow, addDeny, and removeRule actions that call the service and trigger re-fetch
  - Build PolicyPanelView as a dedicated view accessible from sidebar navigation
  - Display each rule with its decision (allow/deny) and resource domains
  - When the app starts with no custom policies, display the pre-seeded Balanced defaults
  - Build AddPolicySheet with a TextField for domains (supports comma-separated), a Picker for allow/deny toggle, and submit/cancel buttons; use JetBrains Mono for the domain input
  - Add a remove button to each policy rule row
  - Fetch rules via .task modifier on view appear
  - _Requirements: 4.1, 4.2, 4.3, 4.4, 4.5_

- [ ] 7.2 Build policy log viewer with filtering
  - Build PolicyLogView as a Table view showing network activity: sandbox name, host, proxy type, rule, last seen timestamp, request count, and blocked/allowed status
  - Use subtle dividers with surfaceContainerHigh at 15% opacity for row separation
  - Add a sandbox name filter Picker that filters log entries by sandbox
  - Add a blocked-only Toggle that shows only blocked requests
  - Implement fetchLog in PolicyStore with optional sandbox name parameter
  - Store filter state (sandbox name, blocked-only) in PolicyStore as a LogFilter struct
  - _Requirements: 4.6, 4.7_

- [ ] 8. (P) Port forwarding management
  - Build PortPanelView per sandbox showing all active host-to-sandbox port mappings as rows
  - Build AddPortSheet with host port and sandbox port TextField inputs; validate that values are positive integers in range 1-65535
  - On submit, call portsPublish via the service through SandboxStore; if the host port is already in use, display an inline error
  - Add an unpublish button to each PortMappingRow that calls portsUnpublish and triggers sandbox re-fetch
  - Port state lives in Sandbox.ports[] within SandboxStore; trigger fetchSandboxes() after each port mutation
  - While a sandbox is stopped, disable the add port button and display a notice that ports are cleared on stop
  - When a sandbox stops, clear its port mappings from the display
  - _Requirements: 5.1, 5.2, 5.3, 5.5, 5.6, 5.7_

- [ ] 9. PTY session manager and terminal view wrapper
- [ ] 9.1 (P) Implement PtySessionManager actor
  - Build PtySessionManager as a Swift actor that tracks one active PTY per sandbox name
  - Implement attach that accepts a sandbox name, terminal view reference, and isMock flag
  - In real mode, configure the terminal view as a MacLocalTerminalView with LocalProcess running "sbx run <name>"; SwiftTerm handles the PTY-to-rendering pipeline internally via delegates
  - In mock mode, create a MockPtyEmitter instance and wire it to a headless Terminal engine feeding the terminal view
  - Implement write that sends data to the active PTY stdin for a given sandbox
  - Implement dispose that terminates the process and removes from tracking, and disposeAll for cleanup
  - Implement isAttached query
  - _Requirements: 6.1, 7.5, 7.6_

- [ ] 9.2 Build TerminalViewWrapper as NSViewRepresentable
  - Create TerminalViewWrapper wrapping SwiftTerm's TerminalView via NSViewRepresentable
  - Set the terminal background to surfaceLowest (#0E0E0E)
  - Expose the underlying TerminalView reference to PtySessionManager via the NSViewRepresentable Coordinator
  - Handle view lifecycle: auto-resize via SwiftTerm's built-in resize handling
  - Support both real mode (MacLocalTerminalView with internal LocalProcess) and mock mode (TerminalView fed by MockPtyEmitter)
  - _Requirements: 6.2_

- [ ] 10. Session interaction UI
- [ ] 10.1 Build session panel with terminal view and chat input
  - When the user clicks a running sandbox card, navigate to SessionPanelView in the detail area
  - Layout SessionPanelView with TerminalViewWrapper occupying the upper area, AgentStatusBar in the middle, and ChatInputView fixed at the bottom
  - Build ChatInputView with a TextField (JetBrains Mono), a send Button, and Enter key submission via .onSubmit
  - When the user sends a message, call SessionStore.sendMessage which delegates to the service and PtySessionManager
  - Disable the chat input when not connected to a session
  - _Requirements: 6.1, 6.2, 6.3_

- [ ] 10.2 Implement SessionStore with lifecycle management and status display
  - Build SessionStore as @MainActor @Observable class tracking active sandbox name, connection status, and error state
  - Inject PtySessionManager and SbxServiceProtocol via initializer
  - On attach, call PtySessionManager.attach with the terminal view reference and set connected state
  - On detach (triggered by navigating away), call PtySessionManager.dispose and reset state
  - When a sandbox transitions from stopped to running while the session panel is open, automatically re-attach the session
  - Only allow one active session at a time; attaching a new session disposes the previous one
  - Build AgentStatusBar showing model name ("claude"), sandbox name, uptime counter (via TimelineView), and a connection indicator (green circle when connected)
  - _Requirements: 6.4, 6.5, 6.6_

- [ ] 11. External terminal integration
- [ ] 11.1 (P) Implement terminal application detection and shell launching
  - Build ExternalTerminalLauncher conforming to ExternalTerminalProtocol
  - Detect which terminal applications are installed using NSWorkspace.shared.urlForApplication(withBundleIdentifier:) for com.apple.Terminal and com.googlecode.iterm2
  - Terminal.app is always available on macOS; only include iTerm in the available list if the bundle is found
  - Launch a terminal window via NSAppleScript with AppleScript templates specific to each application
  - Execute "sbx exec -it <name> bash" inside the launched terminal to open an interactive bash shell
  - Validate the sandbox name against the allowed pattern before interpolation; escape the name for AppleScript string context (backslash-escape \ and ")
  - If the terminal application fails to launch, throw an error with the application name and suggest alternatives
  - _Requirements: 11.1, 11.2, 11.3, 11.6_

- [ ] 11.2 Add terminal preference setting and wire the Open Shell action
  - Build SettingsStore as @MainActor @Observable class persisting preferred terminal to UserDefaults
  - Load the saved preference on init; default to Terminal.app when no preference is set
  - Add a terminal preference Picker in the settings area showing only detected terminal applications
  - Add an "Open Shell" button to running sandbox cards that launches a bash shell in the preferred terminal via ExternalTerminalLauncher
  - Disable the "Open Shell" button when a sandbox is in stopped status
  - _Requirements: 11.4, 11.5, 11.7_

- [ ] 12. Real sbx CLI integration
- [ ] 12.1 (P) Implement CLI executor and output parsers
  - Build CliExecutor conforming to CliExecutorProtocol using Foundation Process with /usr/bin/env as executable and array-form arguments to prevent command injection
  - Wrap Process.waitUntilExit() in withCheckedContinuation for async/await integration
  - Capture stdout and stderr via Pipe; return CliResult with stdout, stderr, and exitCode
  - Build execJson generic method using JSONDecoder for structured output
  - Build SbxOutputParser with static methods:
    - parseSandboxList: detect column headers and extract sandbox name, agent, status, ports, workspace using header position detection via String.Index offsets
    - parsePolicyList: extract policy ID, type, decision, and resources
    - parsePolicyLog: detect Blocked/Allowed sections and extract all fields; prefer --json flag when available
    - parsePortsList: extract host port and sandbox port using the digit-arrow-digit pattern
  - Handle empty output and header-only output by returning empty arrays
  - Log warnings for unparseable lines via os.Logger
  - Write unit tests for each parser with realistic CLI output samples and edge cases
  - _Requirements: 9.3_

- [ ] 12.2 Implement RealSbxService wrapping all CLI commands
  - Build RealSbxService as a Swift actor conforming to SbxServiceProtocol
  - Inject CliExecutor and SbxOutputParser; implement each method by calling the corresponding sbx CLI command and parsing output
  - Map: list → "sbx ls", run → "sbx run claude <workspace> --name <name>", stop → "sbx stop <name>", rm → "sbx rm <name>"
  - Map policy methods to "sbx policy" subcommands and port methods to "sbx ports" subcommands
  - Implement sendMessage by delegating to PtySessionManager.write
  - Detect missing sbx CLI (binary not found on PATH) and throw .cliError on initialization
  - Detect Docker not running from stderr patterns and throw .dockerNotRunning with descriptive message
  - Validate sandbox names before passing to CLI commands
  - _Requirements: 9.3, 9.4_

- [ ] 13. Error handling, alert notifications, and input validation
  - Implement a toast-style overlay view that displays user-friendly error messages, auto-dismisses after a few seconds, and supports stacking
  - Surface all service errors from store actions as toast notifications with clear messages (e.g., "Port 8080 is already in use", "Sandbox not found")
  - Build a full-screen error state shown when sbx CLI is not installed or Docker Desktop is not running, with guidance on how to install or start the required dependency
  - Add sandbox name validation in CreateProjectSheet: only allow lowercase alphanumeric characters and hyphens, no leading hyphen; show inline error for invalid names
  - Validate domain inputs in AddPolicySheet before submission (non-empty, no catch-all patterns)
  - Validate port numbers as positive integers within range 1-65535 in AddPortSheet
  - _Requirements: 5.5, 9.4, 9.5, 11.6_

- [ ] 14. E2E test suite
- [ ] 14.1 Set up XCUITest with mock mode injection
  - Configure the XCUITest target (sbx-uiUITests) for end-to-end testing
  - Set up test fixtures that inject SBX_MOCK=1 via app.launchEnvironment so all tests run against MockSbxService without Docker Desktop
  - Add accessibility identifiers to all interactive views (buttons, text fields, cards, status chips, navigation items)
  - Verify the test runner can launch the app, interact with views, and assert on element existence
  - _Requirements: 10.2_

- [ ] 14.2 (P) Write E2E tests for project creation and sandbox lifecycle
  - Test project creation: trigger the deploy action, select a directory, verify a new sandbox appears in the grid as LIVE with the correct name and workspace path
  - Test full lifecycle: create a sandbox → verify LIVE status → stop it → verify STOPPED status → remove it with confirmation → verify it is gone from the grid
  - Use waitForExistence for async state transitions
  - _Requirements: 10.1, 10.3_

- [ ] 14.3 (P) Write E2E tests for policies, ports, and session messaging
  - Test policy management: add an allow rule for a test domain, verify it appears in the policy list, remove it, verify it is gone
  - Test port forwarding: publish a port mapping (e.g., 8080:3000), verify it appears on the sandbox card and in the port panel, unpublish it, verify it is gone
  - Test session messaging: click a running sandbox to open the session, verify terminal output appears, send a message in the chat input, verify simulated Claude Code response output streams into the terminal
  - _Requirements: 10.1, 10.4, 10.5, 10.6_
