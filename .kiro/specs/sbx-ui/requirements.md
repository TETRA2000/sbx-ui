# Requirements Document

## Introduction
sbx-ui is a desktop GUI application for Docker Sandbox (`sbx`) — a secure, container-based environment for AI coding agents. Phase 1 delivers a working Electron desktop app where developers can create projects from local Git repositories, launch Claude Code inside Docker Sandboxes, interact with the agent through a chat-style UI, manage network policies and port forwarding, open bash shells inside sandboxes via external terminal applications (Terminal/iTerm), and stop or destroy sandboxes — all without using the terminal. A full in-memory mock of the `sbx` CLI enables E2E testing without Docker Desktop.

## Requirements

### Requirement 1: Project Creation
**Objective:** As a developer, I want to create a project by selecting a local Git repository root directory, so that I can associate a sandbox with my codebase.

#### Acceptance Criteria
1. When the user clicks the "Deploy Agent" or "+" button on the dashboard, the App shall open a native filesystem directory picker dialog.
2. When the user selects a valid directory and confirms, the App shall create a sandbox associated with that directory path as its workspace.
3. When the user submits project creation with an optional custom name, the App shall auto-generate a sandbox name as `claude-<dirname>` if no name is provided.
4. If the user cancels the directory picker dialog, the App shall close the dialog without creating any sandbox.
5. If a sandbox with the same workspace directory already exists and is running, the App shall return the existing sandbox instead of creating a duplicate.

### Requirement 2: Sandbox Dashboard Grid
**Objective:** As a developer, I want to see all my sandboxes in a visual grid layout, so that I can quickly monitor their status and take actions.

#### Acceptance Criteria
1. The App shall display all sandboxes as cards in a grid layout on the main dashboard view.
2. The App shall display for each sandbox card: sandbox name, agent type ("claude"), current status, and workspace path.
3. While a sandbox has status "running", the App shall display a green animated LED pulse indicator (LIVE status chip).
4. While a sandbox has status "stopped", the App shall display a STOPPED status chip without animation.
5. While a sandbox has status "creating" or "removing", the App shall display a spinner and disable action controls on that card.
6. The App shall display a global statistics bar showing the count of running sandboxes and total sandbox count.
7. The App shall poll the sandbox list every 3 seconds to refresh the grid with current status.

### Requirement 3: Sandbox Lifecycle Management
**Objective:** As a developer, I want to launch, stop, and destroy sandboxes from the UI, so that I can manage sandbox lifecycles without the terminal.

#### Acceptance Criteria
1. When the user triggers "launch" for a new project, the App shall call `sbx.run("claude", workspacePath, { name })` and display the sandbox in "creating" state transitioning to "running".
2. When the user clicks the pause/stop button on a running sandbox card, the App shall call `sbx.stop(name)` and transition the card to "stopped" status.
3. When the user clicks a stopped sandbox card to resume, the App shall call `sbx.run(name)` and transition the card back to "running" status.
4. When the user triggers "Terminate Agent" on a sandbox, the App shall display a confirmation dialog before proceeding.
5. When the user confirms termination, the App shall call `sbx.rm(name)` and remove the card from the grid.
6. If the user cancels the termination confirmation dialog, the App shall take no action on the sandbox.

### Requirement 4: Network Policy Management
**Objective:** As a developer, I want to view, add, and remove network access policies, so that I can control which domains sandboxes can reach.

#### Acceptance Criteria
1. The App shall display a policy panel listing all current network policy rules with their decision (allow/deny) and resource domains.
2. When the application starts with no custom policies, the App shall display the pre-seeded Balanced policy defaults (api.anthropic.com, *.npmjs.org, github.com, etc.).
3. When the user submits an "allow" policy for a domain or comma-separated list of domains, the App shall call `sbx.policyAllow(resources)` and refresh the policy list.
4. When the user submits a "deny" policy for a domain or comma-separated list of domains, the App shall call `sbx.policyDeny(resources)` and refresh the policy list.
5. When the user clicks the remove button on a policy rule, the App shall call `sbx.policyRemove(resource)` and remove it from the list.
6. The App shall display a network activity log table showing: sandbox name, host, proxy type, rule, last seen timestamp, request count, and blocked/allowed status.
7. Where the policy log viewer is displayed, the App shall support filtering by sandbox name and a blocked-only toggle.

### Requirement 5: Port Forwarding Management
**Objective:** As a developer, I want to publish and unpublish port mappings per sandbox, so that I can access services running inside sandboxes from my host machine.

#### Acceptance Criteria
1. The App shall display a port panel per sandbox showing all active host-to-sandbox port mappings.
2. When the user submits a new port mapping with host port and sandbox port, the App shall call `sbx.portsPublish(name, hostPort, sbxPort)` and refresh the port list.
3. When the user clicks unpublish on a port mapping, the App shall call `sbx.portsUnpublish(name, hostPort, sbxPort)` and remove it from the list.
4. The App shall display active port mappings as compact chips (e.g., `8080→3000`) on each sandbox card in the dashboard grid.
5. If the user attempts to publish a host port that is already in use, the App shall display an error message and reject the mapping.
6. While a sandbox is in "stopped" status, the App shall not allow publishing new port mappings and shall indicate that ports are cleared on stop.
7. When a sandbox is stopped, the App shall clear all its port mappings from the display (matching real `sbx` behavior where ports are not persistent across stops).

### Requirement 6: Claude Code Session Interaction
**Objective:** As a developer, I want to send messages to a running Claude Code session and see its output in a chat-style interface with an embedded terminal, so that I can interact with the AI agent visually.

#### Acceptance Criteria
1. When the user clicks on a running sandbox card, the App shall open a session panel with a split layout: terminal view on top and chat input at the bottom.
2. When a session is attached, the App shall render the PTY data stream in an xterm.js terminal embed with full ANSI code support.
3. When the user types a message in the chat input and presses send, the App shall write the message to the sandbox PTY stdin via `sbx.sendMessage(name, message)`.
4. The App shall display an agent status bar showing the model name, sandbox name, uptime, and connection status.
5. When a sandbox transitions from stopped to running, the App shall automatically re-attach the session if the session panel is open.
6. When the user navigates away from or closes the session panel, the App shall detach the PTY session via `sbx.detachSession(name)`.

### Requirement 7: Mock Layer for Development and E2E Testing
**Objective:** As a developer, I want a full in-memory mock of the sbx service, so that I can develop the UI and run E2E tests without Docker Desktop.

#### Acceptance Criteria
1. When the environment variable `SBX_MOCK=1` is set, the App shall use `MockSbxService` instead of `RealSbxService` for all operations.
2. The MockSbxService shall implement the complete `SbxService` interface identically to the real implementation's contract.
3. The MockSbxService shall simulate sandbox lifecycle transitions with realistic delays (creating→running: ~800ms, stop: ~300ms, remove: ~200ms).
4. The MockSbxService shall pre-seed the Balanced network policy defaults on construction (api.anthropic.com, *.npmjs.org, github.com, etc.).
5. The MockSbxService shall simulate terminal output via `MockPtyEmitter` that emits realistic Claude Code startup sequences and agent response streams with ANSI formatting.
6. When `sbx.sendMessage` is called on the mock, the MockPtyEmitter shall simulate a Claude Code thinking → reading → writing → done response sequence with realistic delays.
7. The MockSbxService shall enforce the same validation rules as the real service: reject duplicate host ports for port forwarding, clear port mappings on sandbox stop, and return existing sandbox for duplicate workspace runs.

### Requirement 8: Application Shell and Navigation
**Objective:** As a developer, I want a consistent application layout with sidebar navigation, so that I can easily switch between dashboard, policies, and other views.

#### Acceptance Criteria
1. The App shall display a persistent shell layout with a sidebar, top bar, and main content area.
2. The App shall provide sidebar navigation to switch between the dashboard (sandbox grid) view and the policy management view.
3. The App shall follow "The Technical Monolith" design system: dark surface hierarchy (#131313 → #1C1B1B → #2A2A2A → #353534), no 1px borders, tonal depth for boundaries.
4. The App shall use the specified font stack: Inter for UI elements, JetBrains Mono for code/metrics, and Space Grotesk for labels.
5. The App shall use a maximum border-radius of 0.5rem for all components.

### Requirement 9: IPC and Security Architecture
**Objective:** As a developer, I want secure communication between the Electron renderer and main process, so that the app follows Electron security best practices.

#### Acceptance Criteria
1. The App shall expose the `sbx` API to the renderer exclusively through Electron's `contextBridge` in the preload script.
2. The App shall define a typed `window.sbx` API covering all lifecycle, policy, port, session, and filesystem dialog operations.
3. The App shall handle all `sbx` CLI spawning and PTY management in the main process only, never in the renderer.
4. If the real `sbx` CLI is not installed or Docker is not running, the App shall display an error state with guidance rather than crashing.
5. If any sbx CLI operation fails, the App shall surface the error as a user-friendly toast notification.

### Requirement 10: E2E Test Coverage
**Objective:** As a developer, I want comprehensive E2E test coverage for all Phase 1 features, so that regressions are caught automatically.

#### Acceptance Criteria
1. The E2E test suite shall cover: project creation, sandbox lifecycle (create → running → stop → stopped → remove), network policy CRUD, port forwarding CRUD, and session messaging flows.
2. The E2E test suite shall run against `MockSbxService` (forced via `SBX_MOCK=1`) without requiring Docker Desktop.
3. When a sandbox lifecycle E2E test runs, it shall verify status transitions: create → verify LIVE → stop → verify STOPPED → remove → verify gone.
4. When a policy management E2E test runs, it shall verify adding an allow rule, seeing it in the list, and removing it.
5. When a port forwarding E2E test runs, it shall verify publishing a port mapping, seeing it displayed, and unpublishing it.
6. When a session messaging E2E test runs, it shall verify sending a message and observing simulated Claude Code response output in the terminal.

### Requirement 11: External Terminal Integration
**Objective:** As a developer, I want to open a bash shell inside a sandbox in an external terminal application (Terminal or iTerm), so that I can inspect or work inside the sandbox environment using a full-featured terminal.

#### Acceptance Criteria
1. When the user triggers "Open Shell" on a running sandbox, the App shall launch the user's preferred terminal application and open an interactive bash shell inside the sandbox.
2. The App shall support Terminal.app and iTerm as external terminal targets on macOS.
3. The App shall detect which supported terminal applications are installed and present only available options.
4. Where the user has not set a preferred terminal, the App shall default to the system's default terminal application (Terminal.app on macOS).
5. The App shall provide a setting for the user to select their preferred external terminal application.
6. If the target terminal application is not installed or fails to launch, the App shall display an error message with the application name and suggest alternatives.
7. While a sandbox is in "stopped" status, the App shall disable the "Open Shell" action.
