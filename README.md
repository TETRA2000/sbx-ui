# sbx-ui

A native macOS desktop GUI built with SwiftUI and Swift that wraps the Docker Sandbox (`sbx`) CLI. sbx-ui enables developers to manage sandbox lifecycles, network policies, port forwarding, environment variables, and Claude Code agent sessions without terminal interaction.

A **Linux CLI** (`sbx-ui-cli`) built with Swift Package Manager is also available, providing the same sandbox management operations from the command line.

## Features

- Sandbox Dashboard with live status grid and global statistics
- Sandbox Lifecycle management (create, resume, stop, terminate)
- Kanban Board for orchestrating multiple agent tasks with drag-and-drop, dependency chaining, and auto-execution
- Network Policies with global allow/deny rules and activity log
- Port Forwarding with per-sandbox host-to-sandbox mappings
- Environment Variables with per-sandbox persistent vars (via `/etc/sandbox-persistent.sh`, with managed section markers to preserve user edits)
- Embedded Terminal Sessions with agent and shell support (powered by SwiftTerm)
- Multi-Session support with sidebar switching and dashboard thumbnails
- Dark theme design system ("The Technical Monolith")
- Debug log panel for CLI interaction tracing
- **Linux CLI** with colored table output, JSON mode, and all sandbox management operations

## Requirements

### macOS GUI

- macOS 14.0+
- Docker Desktop with `sbx` CLI (v0.23.0+)
- Xcode 16+ (for building from source)

### Linux CLI

- Linux (Ubuntu 22.04+)
- Swift 6.0+
- Docker with `sbx` CLI (v0.23.0+)

## Getting Started

### macOS GUI — Build from source

```bash
git clone https://github.com/TETRA2000/sbx-ui.git
cd sbx-ui
open sbx-ui.xcodeproj
```

Build and run with Cmd+R in Xcode. The app requires Docker Desktop to be running when using real sandboxes.

### macOS GUI — Development mode (mock CLI)

For development and testing without Docker Desktop, use the bundled CLI mock:

1. Open the scheme editor in Xcode (Product -> Scheme -> Edit Scheme)
2. Under Run -> Arguments -> Environment Variables, add:
   - `SBX_CLI_MOCK` = `1`
   - `PATH` = `<project-root>/tools:$PATH`
3. Build and run

The mock CLI (`tools/mock-sbx`) emulates all `sbx` commands using file-based state, exercising the full code path: `RealSbxService` -> `CliExecutor` -> `mock-sbx`.

### Linux CLI — Build and install

```bash
git clone https://github.com/TETRA2000/sbx-ui.git
cd sbx-ui
swift build --package-path cli -c release
# Binary is at cli/.build/release/sbx-ui-cli
# Optionally copy to PATH:
cp cli/.build/release/sbx-ui-cli /usr/local/bin/sbx-ui
```

### Linux CLI — Quick start

```bash
# List sandboxes
sbx-ui ls

# Create a sandbox
sbx-ui create /path/to/workspace --name my-sandbox --agent claude

# Show detailed status
sbx-ui status my-sandbox

# Manage ports
sbx-ui ports publish my-sandbox 8080:3000
sbx-ui ports ls my-sandbox

# Manage env vars
sbx-ui env set my-sandbox API_KEY secret123
sbx-ui env ls my-sandbox

# Network policies
sbx-ui policy ls
sbx-ui policy allow example.com
sbx-ui policy log --blocked

# JSON output for scripting
sbx-ui ls --json
```

See `docs/linux-cli.md` for the full CLI reference.

## Architecture

```
SwiftUI Views (macOS)          CLI Commands (Linux)
     |                              |
  Stores (@MainActor @Observable)   |
     |                              |
     +--------- SBXCore -----------+
                   |
            SbxServiceProtocol
                   |
            RealSbxService -> CliExecutor -> sbx CLI (or mock-sbx)
```

The **SBXCore** library (Models + Services) is shared between the macOS GUI and the Linux CLI. It is built as a Swift Package Manager target from the same source files (`sbx-ui/Models/` and `sbx-ui/Services/`).

### Service Layer (`sbx-ui/Services/`)

`SbxServiceProtocol` defines the contract for all sandbox operations. `RealSbxService` implements it by invoking the `sbx` CLI through `CliExecutor`. `ServiceFactory` selects the service based on environment configuration.

### Store Layer (`sbx-ui/Stores/`) — macOS only

`@MainActor @Observable` classes that bridge services and views:

- `SandboxStore` -- sandbox lifecycle and polling
- `PolicyStore` -- network policy rules and activity log
- `EnvVarStore` -- per-sandbox environment variables
- `TerminalSessionStore` -- agent and shell terminal sessions
- `KanbanStore` -- kanban board, task CRUD, dependency engine, execution
- `SettingsStore` -- user preferences

### View Layer (`sbx-ui/Views/`) — macOS only

SwiftUI views organized by feature:

- **Dashboard** -- sandbox grid, creation sheet, status chips, global stats
- **Kanban** -- task board, columns, task cards, drag-and-drop, dependency management
- **Policies** -- policy list, add policy sheet, policy log
- **Ports** -- port mappings, add port sheet
- **EnvVars** -- environment variable management, add variable sheet
- **Session** -- terminal panel, agent status bar
- **Error** -- toast notifications, error states, debug log

### CLI Layer (`cli/Sources/sbx-ui-cli/`) — Linux

Swift ArgumentParser commands that call `SBXCore` directly:

- `CLI.swift` -- `@main` entry point and subcommand registration
- `Commands.swift` -- `ls`, `create`, `stop`, `rm`, `run`, `exec`, `status`
- `PolicyCommands.swift` -- `policy {ls,allow,deny,rm,log}`
- `PortsCommands.swift` -- `ports {ls,publish,unpublish}`
- `EnvCommands.swift` -- `env {ls,set,rm}`
- `Formatting.swift` -- ANSI colored table output

### Design System (`sbx-ui/DesignSystem/`) — macOS only

"The Technical Monolith" dark theme with surface hierarchy, custom fonts, and accent/secondary/error color tokens.

## Project Structure

```
sbx-ui/
  cli/
    Package.swift                  # SPM manifest (SBXCore + sbx-ui-cli), placed here so Xcode doesn't auto-discover it
    SBXCore/                       # Symlinks to ../../sbx-ui/{Models,Services}
    Sources/sbx-ui-cli/            # Linux CLI sources
    Tests/                         # SBXCoreTests + CLIE2ETests
  sbx-ui/
    sbx_uiApp.swift                # macOS app entry point
    Models/
      DomainTypes.swift            # Sandbox, PolicyRule, PortMapping, EnvVar, etc.
      KanbanTypes.swift            # KanbanTask, KanbanColumn, KanbanBoard
    Services/
      SbxServiceProtocol.swift     # Service protocol + JSON response types
      RealSbxService.swift         # CLI-backed implementation
      CliExecutor.swift            # Process spawning and output capture
      SbxOutputParser.swift        # CLI output parsing
      ServiceFactory.swift         # Service creation based on environment
      KanbanPersistence.swift      # Kanban JSON file persistence
      LinuxShims.swift             # Linux-only stubs (appLog, etc.)
    Stores/                        # macOS-only reactive state
    Views/                         # macOS-only SwiftUI views
    DesignSystem/                  # macOS-only theme
    Plugins/                       # Plugin system
  Sources/
    sbx-ui-cli/                    # Linux CLI executable
      CLI.swift                    # @main entry point
      Commands.swift               # Sandbox lifecycle commands
      PolicyCommands.swift         # Network policy commands
      PortsCommands.swift          # Port forwarding commands
      EnvCommands.swift            # Environment variable commands
      Formatting.swift             # ANSI table output
  Tests/
    SBXCoreTests/
      SBXCoreTests.swift           # SPM tests (25 tests, Swift Testing)
  sbx-uiTests/
    sbx_uiTests.swift             # Xcode unit tests (Swift Testing)
  sbx-uiUITests/
    sbx_uiUITests.swift           # Xcode UI/E2E tests (XCTest)
  tools/
    mock-sbx                       # CLI mock (bash)
    mock-sbx-tests.sh             # CLI mock test suite (32 tests)
  docs/
    sbx-cli-reference.md          # sbx CLI v0.23.0 reference
    mock-sbx.md                   # CLI mock documentation
    kanban-design.md              # Kanban feature design document
    linux-cli.md                  # Linux CLI reference
```

## Usage

### macOS GUI

#### Creating a Sandbox

1. Click "Deploy Agent" in the sidebar or the "+" card in the dashboard grid.
2. Select a workspace directory (auto-filled to `/tmp/mock-project` in mock mode).
3. Enter a sandbox name (lowercase alphanumeric with hyphens).
4. Optionally add initial environment variables in the creation sheet.
5. Click "Deploy" to create and start the sandbox.

#### Managing Environment Variables

Each sandbox card shows an "ENV" chip when environment variables are configured.

1. Click the "ENV" chip on a sandbox card or navigate to the sandbox's environment variable panel.
2. Add variables with key-value pairs (keys must match `[A-Za-z_][A-Za-z0-9_]*`).
3. Remove variables individually.

Variables are persisted inside the sandbox via `/etc/sandbox-persistent.sh`. The service uses managed section markers (`# --- sbx-ui managed ---` / `# --- end sbx-ui managed ---`) so user edits outside the managed section are preserved across syncs.

#### Kanban Board

1. Select "KANBAN" in the sidebar.
2. Click "Create Board" to create your first board (with default Backlog, In Progress, Done columns).
3. Click the "+" button on any column header to add a task.
4. Select a running sandbox, enter the task title and agent prompt.
5. Optionally select dependency tasks that must complete before this task can start.
6. Drag task cards between columns to reorganize. Cards can be reordered within columns.
7. Click "Start" on a task card to launch a terminal session and send the prompt.
8. Running tasks show live terminal thumbnails — click to view the full session.
9. Tasks with dependencies are marked "BLOCKED" until all upstream tasks complete, then auto-execute.

Each task Start spawns a dedicated `SessionType.kanbanTask` terminal that
runs `sbx run <sandbox> -- "<prompt>"`. `sbx run` appends the args after
`--` to its default `claude --dangerously-skip-permissions` invocation, and
Claude Code's CLI treats the first positional as the
[initial prompt for an interactive session](https://code.claude.com/docs/en/cli-reference),
so the task opens a ready-to-go conversation — no manual Enter press
required. Multiple kanban tasks coexist with any manually-attached agent
session on the same sandbox. See `docs/kanban-design.md` for the full design
document.

#### Network Policies

1. Select "POLICIES" in the sidebar to open the policy panel.
2. View existing global allow/deny rules.
3. Click "Add Policy" to create a new allow or deny rule for a domain.
4. View the activity log to see allowed and blocked requests, filterable by sandbox and blocked-only.

#### Port Forwarding

1. Select a running sandbox to view its port panel.
2. Click "Add Port" to map a host port to a sandbox port.
3. Remove existing mappings with the unpublish button.

#### Terminal Sessions

1. Click a sandbox card to open an agent session (Claude Code).
2. Use the "Open Shell" button on a sandbox card to start a shell session (`sbx exec -it <name> bash`).
3. Active sessions appear in the sidebar under "SESSIONS" -- click to switch between them.
4. Dashboard thumbnails show live previews of active sessions.

### Linux CLI

See `docs/linux-cli.md` for the full reference. Quick examples:

```bash
sbx-ui ls                                    # List all sandboxes
sbx-ui create /path/to/project -n my-sb      # Create a sandbox
sbx-ui status my-sb                          # Detailed status
sbx-ui policy log --blocked                  # View blocked requests
sbx-ui env set my-sb NODE_ENV production     # Set env var
sbx-ui --json ls                             # JSON output
```

## Testing

All tests use the CLI mock (`tools/mock-sbx`). No Docker Desktop is required to run the test suite.

### Running Tests

| Platform | Command | Tests |
|----------|---------|-------|
| macOS (Xcode) | Product -> Test (Cmd+U) | 73 unit + UI tests |
| Linux (SPM) | `swift test --package-path cli` | 25 unit + integration tests |
| CLI mock | `bash tools/mock-sbx-tests.sh` | 32 bash tests |

### Test Structure

- **Xcode unit tests** (`sbx-uiTests/sbx_uiTests.swift`) -- Swift Testing framework (`@Test`, `#expect`). Tests stores and service logic using `StubSbxService` and `FailingSbxService`.
- **Xcode UI/E2E tests** (`sbx-uiUITests/sbx_uiUITests.swift`) -- XCTest framework (`XCTestCase`). Launches the app with `SBX_CLI_MOCK=1` and exercises full user flows via XCUITest.
- **SPM tests** (`cli/Tests/SBXCoreTests/SBXCoreTests.swift`) -- Swift Testing framework. Tests models, parsers, and service layer with mock-sbx integration on Linux.
- **CLI mock tests** (`tools/mock-sbx-tests.sh`) -- Bash test suite validating the mock CLI behavior against expected `sbx` CLI output formats.

### Key Testing Patterns

- Stores are `@MainActor`, so test code accesses properties via `await store.property`.
- UI tests inject the mock CLI via `app.launchEnvironment["SBX_CLI_MOCK"] = "1"` and PATH injection.
- SPM integration tests inject mock-sbx via `SBX_MOCK_STATE_DIR` + PATH environment variables.
- Use `waitForExistence(timeout:)` generously in UI tests (5-10s) since the mock CLI spawns real processes.

## CI

| Workflow | Trigger | Runner | What it does |
|----------|---------|--------|-------------|
| **Tests** | push/PR to main | macOS | Xcode unit + UI tests |
| **Linux CLI Tests** | push/PR to main (cli/** and shared Model/Service paths) | Ubuntu | `swift build --package-path cli` + `swift test --package-path cli` + release build |
| **SDK Tests** | push/PR to main (sdk/ paths) | Ubuntu | TypeScript + Python SDK tests |
| **Build** | push to main | macOS | Release archives for canary/beta/stable |

## CLI Mock

The `tools/mock-sbx` bash script emulates the Docker Sandbox CLI for development and testing without Docker Desktop. It supports all commands used by sbx-ui (`ls`, `run`, `stop`, `rm`, `create`, `exec`, `policy`, `ports`) with file-based state stored in `$SBX_MOCK_STATE_DIR`.

Run the mock CLI test suite:

```bash
bash tools/mock-sbx-tests.sh
```

See `docs/mock-sbx.md` for full documentation.

## License

See LICENSE file for details.
