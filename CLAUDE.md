# AI-DLC and Spec-Driven Development

Kiro-style Spec Driven Development implementation on AI-DLC (AI Development Life Cycle)

## Project Context

### Paths
- Steering: `.kiro/steering/`
- Specs: `.kiro/specs/`

### Steering vs Specification

**Steering** (`.kiro/steering/`) - Guide AI with project-wide rules and context
**Specs** (`.kiro/specs/`) - Formalize development process for individual features

### Active Specifications
- Check `.kiro/specs/` for active specifications
- Use `/kiro:spec-status [feature-name]` to check progress

## Development Guidelines
- Think in English, generate responses in English. All Markdown content written to project files (e.g., requirements.md, design.md, tasks.md, research.md, validation reports) MUST be written in the target language configured for this specification (see spec.json.language).

## Minimal Workflow
- Phase 0 (optional): `/kiro:steering`, `/kiro:steering-custom`
- Phase 1 (Specification):
  - `/kiro:spec-init "description"`
  - `/kiro:spec-requirements {feature}`
  - `/kiro:validate-gap {feature}` (optional: for existing codebase)
  - `/kiro:spec-design {feature} [-y]`
  - `/kiro:validate-design {feature}` (optional: design review)
  - `/kiro:spec-tasks {feature} [-y]`
- Phase 2 (Implementation): `/kiro:spec-impl {feature} [tasks]`
  - `/kiro:validate-impl {feature}` (optional: after implementation)
- Progress check: `/kiro:spec-status {feature}` (use anytime)

## Development Rules
- **ALWAYS write and run tests after ANY code change** — this is non-negotiable. Write both unit tests and UI/E2E tests as appropriate, then run the full test suite to confirm no regressions before considering work done.
- **When encountering flaky tests, always find and fix the root cause** — never delete or skip flaky tests without understanding why they fail. Common root causes in this project:
  - `FileHandle.availableData` blocks the Swift cooperative thread pool and cannot be reliably unblocked by closing the handle from another thread. Use `readabilityHandler` instead.
  - Storing `@Observable` class references (even `weak var`) inside other `@Observable` classes can break SwiftUI rendering. Use closures for cross-store communication.
  - Plugin process tests require proper pipe cleanup: close stdin first (signals EOF to plugin), then terminate, then close stdout.
- 3-phase approval workflow: Requirements → Design → Tasks → Implementation
- Human review required each phase; use `-y` only for intentional fast-track
- Keep steering current and verify alignment with `/kiro:spec-status`
- Follow the user's instructions precisely, and within that scope act autonomously: gather the necessary context and complete the requested work end-to-end in this run, asking questions only when essential information is missing or the instructions are critically ambiguous.

## Steering Configuration
- Load entire `.kiro/steering/` as project memory
- Default files: `product.md`, `tech.md`, `structure.md`
- Custom files are supported (managed via `/kiro:steering-custom`)

## Project Details

### Reference
- **`docs/sbx-cli-reference.md`** — Verified sbx CLI v0.23.0 command syntax, output formats, JSON schemas, and error patterns
- **`docs/mock-sbx.md`** — Documentation for the bash CLI emulator used in integration testing
- **`docs/linux-cli.md`** — Linux CLI (`sbx-ui-cli`) full command reference
- **`tools/mock-sbx`** — Bash CLI emulator (32 tests in `tools/mock-sbx-tests.sh`)

### Overview
sbx-ui is a macOS native desktop GUI (SwiftUI + Swift) that wraps the Docker Sandbox (`sbx`) CLI. It enables developers to manage sandbox lifecycles, network policies, port forwarding, and Claude Code agent sessions without terminal interaction.

A **Linux CLI** (`sbx-ui-cli`) built with Swift Package Manager provides the same sandbox management operations from the command line, sharing the core service layer with the macOS GUI.

### Architecture
- **SBXCore** (`sbx-ui/Models/` + `sbx-ui/Services/`): Shared library built via SPM. Contains domain types, service protocol, CLI executor, and output parser. Used by both macOS GUI and Linux CLI.
- **Service Layer** (`sbx-ui/Services/`): `SbxServiceProtocol` with `RealSbxService` implementation. `ServiceFactory` creates the service. For testing, the CLI mock (`tools/mock-sbx`) is used via PATH injection.
- **Store Layer** (`sbx-ui/Stores/`): `@MainActor @Observable` classes — `SandboxStore`, `PolicyStore`, `SessionStore`, `SettingsStore`. Bridges between services and views. macOS only.
- **View Layer** (`sbx-ui/Views/`): SwiftUI views organized by feature — Dashboard, Policies, Ports, Session, Error. macOS only.
- **CLI Layer** (`Sources/sbx-ui-cli/`): Swift ArgumentParser commands that call SBXCore directly. Linux/cross-platform.
- **Design System** (`sbx-ui/DesignSystem/`): Color/Font/Constants extensions for "The Technical Monolith" dark theme. macOS only.

### Key Build Settings (Xcode / macOS)
- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` — all types default to `@MainActor` unless opted out
- `ENABLE_APP_SANDBOX = NO` — required for CLI spawning
- SwiftTerm 1.13+ via SPM for terminal rendering

### SPM / Linux Build
- `Package.swift` at project root defines `SBXCore` library + `sbx-ui-cli` executable
- `SBXCore` includes only `Models/` and `Services/` from `sbx-ui/` (no Views, Stores, Plugins, DesignSystem)
- `SBX_SPM` compilation flag enables `LinuxShims.swift` (provides `appLog` stub for Linux)
- `#if canImport(os)` guards `os.Logger` usage in `CliExecutor.swift` for Linux
- All explicit inits on `Sendable` types must be `nonisolated` — the Xcode project uses `MainActor` default isolation, so omitting `nonisolated` breaks macOS builds
- Dependencies: `swift-argument-parser` 1.5+

### Building & Running

#### macOS (Xcode)
- **Prefer Xcode MCP tools** over `xcodebuild` CLI
  - `mcp__xcode__XcodeListWindows` → get `tabIdentifier`
  - `mcp__xcode__BuildProject` → build
  - `mcp__xcode__RunAllTests` / `mcp__xcode__RunSomeTests` → run tests
- Open `sbx-ui.xcodeproj` in Xcode
- Set `SBX_CLI_MOCK=1` and add `tools/` to PATH in scheme environment variables for development without Docker
- Build and run (Cmd+R)

#### Linux (SPM)
- `swift build` — build SBXCore library + sbx-ui-cli executable
- `swift build -c release` — optimized release build
- `swift run sbx-ui-cli ls` — run CLI directly
- `swift run sbx-ui-cli --help` — see all commands

## Testing Guide

### Test Structure
- **Unit tests**: `sbx-uiTests/sbx_uiTests.swift` — Swift Testing framework (`@Test`, `#expect`)
- **UI/E2E tests**: `sbx-uiUITests/sbx_uiUITests.swift` — XCTest (`XCTestCase`, `XCTAssertTrue`)
- **SPM tests**: `Tests/SBXCoreTests/SBXCoreTests.swift` — Swift Testing (25 tests: models, parsers, integration)
- **CLI mock tests**: `tools/mock-sbx-tests.sh` — Bash test suite (32 tests)
- All tests use the CLI mock (`tools/mock-sbx`) — no Docker required

### Test Strategy
- **Always write and run tests after any code change** — both unit tests and UI/E2E tests
- Run the full suite to confirm no regressions before considering work done

### Running Tests
- Xcode: Product → Test (Cmd+U) runs all 73 tests
- Xcode MCP (preferred): `RunAllTests` or `RunSomeTests` with target/identifier
- Linux/SPM: `swift test` runs all 25 SBXCore tests
- CLI mock: `bash tools/mock-sbx-tests.sh` runs 32 bash tests

### Writing Unit Tests

**Pattern**: Create a test struct per component, inject `StubSbxService` into stores.

```swift
struct SandboxStoreTests {
    @Test func createReturnsAndRefreshes() async throws {
        let service = StubSbxService()
        let store = await SandboxStore(service: service)
        let sandbox = try await store.createSandbox(workspace: "/tmp/project", name: "test")
        #expect(sandbox.status == .running)
        let count = await store.sandboxes.count
        #expect(count == 1)
    }
}
```

**Key patterns**:
- Stores are `@MainActor` — access properties via `await store.property` from test context
- `StubSbxService` is an `actor` — call methods with `await`
- Use `FailingSbxService` (defined in test file) to test error handling paths
- Error assertions: use `do/catch` with `SbxServiceError` pattern matching

### Writing E2E Tests

**Pattern**: XCUITest with CLI mock (`SBX_CLI_MOCK=1`) injected via `app.launchEnvironment`.

```swift
final class sbx_uiUITests: XCTestCase {
    var app: XCUIApplication!

    private static let projectRoot: String = {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().path
    }()
    private static var toolsDir: String {
        URL(fileURLWithPath: projectRoot).appendingPathComponent("tools").path
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["SBX_CLI_MOCK"] = "1"
        let stateDir = NSTemporaryDirectory() + "mock-sbx-\(UUID().uuidString)"
        app.launchEnvironment["SBX_MOCK_STATE_DIR"] = stateDir
        let existingPath = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin"
        app.launchEnvironment["PATH"] = "\(Self.toolsDir):\(existingPath)"
        app.launch()
    }
}
```

**Key patterns**:
- `CreateProjectSheet` auto-fills workspace path to `/tmp/mock-project` when `SBX_CLI_MOCK=1`
- Use `waitForExistence(timeout:)` generously (5-10s) — CLI mock spawns processes, so it's slower than in-memory mocks
- Find elements: `app.buttons["id"]`, `app.staticTexts["text"]`, `app.textFields["id"]`
- SwiftUI VStacks with `.accessibilityIdentifier` are NOT reliably found as `app.groups` or `app.otherElements` — use child text/button identifiers instead
- Card views use `.accessibilityElement(children: .contain)` to expose child buttons to XCUITest. The tappable content area (header, workspace, thumbnail) has `.onTapGesture`; action buttons and ENV chip sit outside it so they are independently clickable.
- Use `waitForNonExistence(timeout:)` to verify elements disappear after deletion
- For button enable state: use `XCTNSPredicateExpectation` with `isEnabled == true`

### Sandbox Creation Helper (E2E)
```swift
private func createSandbox(name: String) {
    app.buttons["newSandboxButton"].click()
    sleep(2) // Wait for .onAppear to set mock workspace
    let nameField = app.textFields["sandboxNameField"]
    nameField.click()
    nameField.typeText(name)
    // Wait for deploy button to be enabled
    let deployButton = app.buttons["deployButton"]
    let enabled = NSPredicate(format: "isEnabled == true")
    let exp = XCTNSPredicateExpectation(predicate: enabled, object: deployButton)
    XCTWaiter.wait(for: [exp], timeout: 5)
    deployButton.click()
}
```

### Available Accessibility Identifiers
- **Dashboard**: `newSandboxButton`, `sandboxCard-{name}`, `statusChip-{status}`, `stopButton-{name}`, `terminateButton-{name}`, `openShellButton-{name}`, `copyCommandButton-{name}`, `sessionBadge-{name}`, `sessionThumbnail-{name}`
- **Create Sheet**: `browseButton`, `sandboxNameField`, `deployButton`, `envVarSectionToggle`, `createEnvKeyField`, `createEnvValueField`, `createAddEnvVarButton`
- **Policies**: `addPolicyButton`, `removePolicy-{resources}`, `domainInput`, `decisionPicker`, `submitPolicyButton`, `logSandboxFilter`, `blockedOnlyToggle`
- **Ports**: `addPortButton`, `hostPortField`, `sbxPortField`, `publishPortButton`, `unpublishPort-{hostPort}`
- **EnvVars**: `addEnvVarButton`, `envVarKeyField`, `envVarValueField`, `submitEnvVarButton`, `removeEnvVar-{key}`, `envVarButton-{name}`
- **Session**: `terminalView`, `agentStatusBar`, `backToDashboard`, `disconnectButton`
- **Sidebar**: `sidebarSession-{label}` (label format: `"{name} (agent)"` or `"{name} (shell N)"`)
