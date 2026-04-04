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
- **`tools/mock-sbx`** — Bash CLI emulator (32 tests in `tools/mock-sbx-tests.sh`)

### Overview
sbx-ui is a macOS native desktop GUI (SwiftUI + Swift) that wraps the Docker Sandbox (`sbx`) CLI. It enables developers to manage sandbox lifecycles, network policies, port forwarding, and Claude Code agent sessions without terminal interaction.

### Architecture
- **Service Layer** (`sbx-ui/Services/`): `SbxServiceProtocol` with `MockSbxService` (actor) and `RealSbxService` implementations. `ServiceFactory` selects mock when `SBX_MOCK=1`.
- **Store Layer** (`sbx-ui/Stores/`): `@MainActor @Observable` classes — `SandboxStore`, `PolicyStore`, `SessionStore`, `SettingsStore`. Bridges between services and views.
- **View Layer** (`sbx-ui/Views/`): SwiftUI views organized by feature — Dashboard, Policies, Ports, Session, Error.
- **Design System** (`sbx-ui/DesignSystem/`): Color/Font/Constants extensions for "The Technical Monolith" dark theme.

### Key Build Settings
- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` — all types default to `@MainActor` unless opted out
- `ENABLE_APP_SANDBOX = NO` — required for CLI spawning
- SwiftTerm 1.13+ via SPM for terminal rendering

### Building & Running
- **Prefer Xcode MCP tools** over `xcodebuild` CLI
  - `mcp__xcode__XcodeListWindows` → get `tabIdentifier`
  - `mcp__xcode__BuildProject` → build
  - `mcp__xcode__RunAllTests` / `mcp__xcode__RunSomeTests` → run tests
- Open `sbx-ui.xcodeproj` in Xcode
- Set `SBX_MOCK=1` in scheme environment variables for development without Docker
- Build and run (Cmd+R)

## Testing Guide

### Test Structure
- **Unit tests**: `sbx-uiTests/sbx_uiTests.swift` — Swift Testing framework (`@Test`, `#expect`)
- **UI/E2E tests**: `sbx-uiUITests/sbx_uiUITests.swift` — XCTest (`XCTestCase`, `XCTAssertTrue`)
- All tests run against `MockSbxService` (no Docker required)

### Test Strategy
- **Always write and run tests after any code change** — both unit tests and UI/E2E tests
- Run the full suite to confirm no regressions before considering work done

### Running Tests
- Xcode: Product → Test (Cmd+U) runs all 76 tests
- Xcode MCP (preferred): `RunAllTests` or `RunSomeTests` with target/identifier

### Writing Unit Tests

**Pattern**: Create a test struct per component, instantiate `MockSbxService` or inject it into stores.

```swift
struct SandboxStoreTests {
    @Test func createReturnsAndRefreshes() async throws {
        let service = MockSbxService()
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
- `MockSbxService` is an `actor` — call methods with `await`
- Use `FailingSbxService` (defined in test file) to test error handling paths
- Error assertions: use `do/catch` with `SbxServiceError` pattern matching
- Mock delays: create ~800ms, stop ~300ms, remove ~200ms (real in tests, not mocked out)

### Writing E2E Tests

**Pattern**: XCUITest with `SBX_MOCK=1` injected via `app.launchEnvironment`.

```swift
final class sbx_uiUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["SBX_MOCK"] = "1"
        app.launch()
    }

    @MainActor
    func testMyWorkflow() throws {
        // Find elements by accessibility identifier or text
        let button = app.buttons["myButtonId"]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        button.click()
    }
}
```

**Key patterns**:
- `CreateProjectSheet` auto-fills workspace path to `/tmp/mock-project` when `SBX_MOCK=1`
- Use `waitForExistence(timeout:)` generously (5-8s) for async operations
- Find elements: `app.buttons["id"]`, `app.staticTexts["text"]`, `app.textFields["id"]`
- SwiftUI VStacks with `.accessibilityIdentifier` are NOT reliably found as `app.groups` or `app.otherElements` — use child text/button identifiers instead
- Buttons inside complex card views (with `.onTapGesture`, `.confirmationDialog`) may not be discoverable by XCUITest — test these via unit tests on the store layer instead
- Use `waitForNonExistence(timeout:)` to verify elements disappear after deletion
- For button enable state: use `XCTNSPredicateExpectation` with `isEnabled == true`

### Sandbox Creation Helper (E2E)
```swift
private func createSandbox(name: String) {
    app.buttons["newSandboxButton"].click()
    sleep(1) // Wait for .onAppear to set mock workspace
    let nameField = app.textFields["sandboxNameField"]
    nameField.click()
    nameField.typeText(name)
    // Wait for deploy button to be enabled
    let deployButton = app.buttons["deployButton"]
    let enabled = NSPredicate(format: "isEnabled == true")
    let exp = XCTNSPredicateExpectation(predicate: enabled, object: deployButton)
    XCTWaiter.wait(for: [exp], timeout: 3)
    deployButton.click()
}
```

### Available Accessibility Identifiers
- **Dashboard**: `newSandboxButton`, `sandboxCard-{name}`, `statusChip-{status}`, `stopButton-{name}`, `terminateButton-{name}`, `openShellButton-{name}`
- **Create Sheet**: `browseButton`, `sandboxNameField`, `deployButton`
- **Policies**: `addPolicyButton`, `removePolicy-{resources}`, `domainInput`, `decisionPicker`, `submitPolicyButton`, `logSandboxFilter`, `blockedOnlyToggle`
- **Ports**: `addPortButton`, `hostPortField`, `sbxPortField`, `publishPortButton`, `unpublishPort-{hostPort}`
- **Session**: `terminalView`, `agentStatusBar`, `backToDashboard`
