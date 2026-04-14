# Testing Guide

This guide covers testing strategies, patterns, and best practices for sbx-ui.

## Table of Contents

- [Overview](#overview)
- [Test Structure](#test-structure)
- [Running Tests](#running-tests)
- [Writing Unit Tests](#writing-unit-tests)
- [Writing UI/E2E Tests](#writing-ui-e2e-tests)
- [Writing SPM Tests](#writing-spm-tests)
- [Testing with the CLI Mock](#testing-with-the-cli-mock)
- [Test Patterns](#test-patterns)
- [Debugging Test Failures](#debugging-test-failures)
- [CI/CD Testing](#cicd-testing)

## Overview

sbx-ui has comprehensive test coverage across three test suites:

| Test Suite | Framework | Count | Platform | What it tests |
|------------|-----------|-------|----------|---------------|
| **Xcode Unit** | Swift Testing | ~48 | macOS | Stores, services, models |
| **Xcode UI/E2E** | XCTest | ~25 | macOS | Full user flows, UI interactions |
| **SPM Tests** | Swift Testing | 25 | macOS/Linux | Models, parsers, integration |
| **CLI Mock** | Bash | 32 | macOS/Linux | Mock CLI behavior |

**Total: 130+ tests**

All tests use the **CLI mock** (`tools/mock-sbx`) - **no Docker required!**

## Test Structure

### Unit Tests (`sbx-uiTests/sbx_uiTests.swift`)

**Framework**: Swift Testing (`@Test`, `#expect`)

**Purpose**: Test business logic, stores, and service layer

**Pattern**: Create test struct per component, inject stubs

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

### UI/E2E Tests (`sbx-uiUITests/sbx_uiUITests.swift`)

**Framework**: XCTest (`XCTestCase`, `XCTAssertTrue`)

**Purpose**: Test full user flows, UI interactions, accessibility

**Pattern**: Launch app with CLI mock, exercise UI elements

```swift
final class sbx_uiUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["SBX_CLI_MOCK"] = "1"
        let stateDir = NSTemporaryDirectory() + "mock-sbx-\(UUID().uuidString)"
        app.launchEnvironment["SBX_MOCK_STATE_DIR"] = stateDir
        let existingPath = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin"
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().path
        let toolsDir = URL(fileURLWithPath: projectRoot).appendingPathComponent("tools").path
        app.launchEnvironment["PATH"] = "\(toolsDir):\(existingPath)"
        app.launch()
    }

    func testCreateSandbox() {
        app.buttons["newSandboxButton"].click()
        sleep(2)  // Wait for workspace auto-fill
        let nameField = app.textFields["sandboxNameField"]
        nameField.click()
        nameField.typeText("test-sandbox")
        app.buttons["deployButton"].click()
        XCTAssertTrue(app.staticTexts["test-sandbox"].waitForExistence(timeout: 10))
    }
}
```

### SPM Tests (`Tests/SBXCoreTests/SBXCoreTests.swift`)

**Framework**: Swift Testing (`@Test`, `#expect`)

**Purpose**: Test cross-platform code (Models, Services, Parsers)

**Pattern**: Test SBXCore library functionality

```swift
struct SandboxValidationTests {
    @Test func validNamesAccepted() throws {
        #expect(try Sandbox.validateName("my-sandbox") == ())
        #expect(try Sandbox.validateName("test123") == ())
    }

    @Test func invalidNamesRejected() {
        #expect(throws: SbxServiceError.self) {
            try Sandbox.validateName("My Sandbox")
        }
    }
}
```

### CLI Mock Tests (`tools/mock-sbx-tests.sh`)

**Framework**: Bash test suite

**Purpose**: Validate CLI mock behavior matches real `sbx` CLI

**Pattern**: Run commands, verify output

```bash
test_ls_json() {
    export SBX_MOCK_STATE_DIR=$(mktemp -d)
    output=$(sbx ls --json)
    echo "$output" | jq . > /dev/null || fail "Invalid JSON"
    pass
}
```

## Running Tests

### All Tests (macOS)

**Xcode:**
```bash
# Product → Test (Cmd+U)
# Runs all 73 unit + UI tests
```

**Command line:**
```bash
# SPM tests
swift test

# CLI mock tests
bash tools/mock-sbx-tests.sh
```

### Specific Test Suites

**Unit tests only:**
```bash
# In Xcode: click diamond icon next to test struct
# Or: Cmd+U with sbx-uiTests/sbx_uiTests.swift open
```

**UI tests only:**
```bash
# In Xcode: Cmd+U with sbx-uiUITests/sbx_uiUITests.swift open
```

**SPM tests (Linux/macOS):**
```bash
swift test
```

**Filtered SPM tests:**
```bash
swift test --filter SandboxValidationTests
swift test --filter testCreateSandbox
```

### Running Tests in CI

See [CI/CD Testing](#cicd-testing) section below.

## Writing Unit Tests

### Basic Pattern

1. **Create a test struct** (not class):
   ```swift
   struct MyFeatureTests {
   }
   ```

2. **Add test methods** with `@Test` attribute:
   ```swift
   @Test func featureBehavesCorrectly() async throws {
       // Test code
   }
   ```

3. **Use `#expect` for assertions**:
   ```swift
   #expect(value == expectedValue)
   #expect(throws: ErrorType.self) {
       try somethingThatShouldThrow()
   }
   ```

### Testing Stores

**Pattern**: Inject `StubSbxService`, use `await` for MainActor properties

```swift
struct SandboxStoreTests {
    @Test func refreshLoadsActiveSandboxes() async throws {
        let service = StubSbxService()
        let store = await SandboxStore(service: service)

        try await store.refresh()

        let count = await store.sandboxes.count
        #expect(count == 2)  // StubSbxService returns 2 sandboxes
    }

    @Test func createAddsToList() async throws {
        let service = StubSbxService()
        let store = await SandboxStore(service: service)

        let sandbox = try await store.createSandbox(
            workspace: "/tmp/project",
            name: "test"
        )

        #expect(sandbox.name == "test")
        let count = await store.sandboxes.count
        #expect(count == 1)
    }
}
```

**Key patterns**:
- Stores are `@MainActor` → access properties via `await store.property`
- `StubSbxService` is an `actor` → call methods with `await`
- Use `FailingSbxService` to test error handling

### Testing Error Handling

**Pattern**: Use `do/catch` with pattern matching

```swift
@Test func createFailsWithInvalidName() async throws {
    let service = FailingSbxService()
    let store = await SandboxStore(service: service)

    do {
        _ = try await store.createSandbox(workspace: "/tmp", name: "Invalid Name")
        Issue.record("Expected error to be thrown")
    } catch let error as SbxServiceError {
        #expect(error == .invalidSandboxName("Invalid Name"))
    }
}
```

### Testing Services

**Pattern**: Test service layer with mock CLI

```swift
@Test func createSandboxSucceeds() async throws {
    // Use CLI mock via PATH injection
    let service = await ServiceFactory.createService()

    let sandbox = try await service.createSandbox(
        agent: "claude",
        workspace: "/tmp/test",
        name: "test"
    )

    #expect(sandbox.name == "test")
    #expect(sandbox.agent == "claude")
    #expect(sandbox.status == .running)
}
```

## Writing UI/E2E Tests

### Basic Pattern

1. **Set up the test class**:
   ```swift
   final class MyFeatureUITests: XCTestCase {
       var app: XCUIApplication!

       override func setUpWithError() throws {
           continueAfterFailure = false
           app = XCUIApplication()
           // Configure CLI mock (see example above)
           app.launch()
       }
   }
   ```

2. **Write test methods**:
   ```swift
   func testFeature() {
       // Interact with UI
       app.buttons["buttonId"].click()

       // Verify result
       XCTAssertTrue(app.staticTexts["Expected Text"].exists)
   }
   ```

### Accessing UI Elements

**Buttons**:
```swift
app.buttons["buttonIdentifier"].click()
app.buttons["buttonIdentifier"].waitForExistence(timeout: 10)
```

**Text fields**:
```swift
let field = app.textFields["fieldIdentifier"]
field.click()
field.typeText("text to enter")
```

**Static text**:
```swift
app.staticTexts["text content"].waitForExistence(timeout: 5)
XCTAssertTrue(app.staticTexts["text"].exists)
```

### Waiting for Elements

**Use generous timeouts** (5-10s) because the CLI mock spawns real processes:

```swift
// Wait for element to appear
let exists = app.buttons["myButton"].waitForExistence(timeout: 10)
XCTAssertTrue(exists)

// Wait for element to disappear
let disappeared = app.buttons["myButton"].waitForNonExistence(timeout: 10)
XCTAssertTrue(disappeared)
```

### Waiting for Button Enable State

```swift
let deployButton = app.buttons["deployButton"]
let enabled = NSPredicate(format: "isEnabled == true")
let expectation = XCTNSPredicateExpectation(predicate: enabled, object: deployButton)
XCTWaiter.wait(for: [expectation], timeout: 5)
deployButton.click()
```

### Common Test Patterns

**Creating a sandbox**:
```swift
private func createSandbox(name: String) {
    app.buttons["newSandboxButton"].click()
    sleep(2)  // Wait for .onAppear to set mock workspace
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

**Verifying sandbox appears**:
```swift
let cardExists = app.staticTexts["test-sandbox"].waitForExistence(timeout: 10)
XCTAssertTrue(cardExists, "Sandbox card should appear")
```

**Deleting a sandbox**:
```swift
app.buttons["terminateButton-test-sandbox"].click()
let disappeared = app.staticTexts["test-sandbox"].waitForNonExistence(timeout: 10)
XCTAssertTrue(disappeared, "Sandbox should be removed")
```

### Accessibility Identifiers

All UI elements should have accessibility identifiers for testing:

```swift
// In your view:
Button("Create") { }
    .accessibilityIdentifier("createButton")

// In your test:
app.buttons["createButton"].click()
```

**Common identifiers** (see CLAUDE.md for full list):
- `newSandboxButton`
- `sandboxCard-{name}`
- `stopButton-{name}`
- `terminateButton-{name}`
- `addPolicyButton`
- `addPortButton`

### UI Test Gotchas

1. **VStacks are not reliably found as groups** - Use child element identifiers instead
2. **CLI mock is slower** - Use generous timeouts (5-10s)
3. **Workspace auto-fill** - `CreateProjectSheet` auto-fills to `/tmp/mock-project` when `SBX_CLI_MOCK=1`

## Writing SPM Tests

### Basic Pattern

SPM tests use Swift Testing framework, same as unit tests:

```swift
struct ParserTests {
    @Test func parseSandboxList() throws {
        let json = """
        [{"name":"test","agent":"claude","status":"running"}]
        """
        let sandboxes = try SbxOutputParser.parseSandboxList(json)
        #expect(sandboxes.count == 1)
        #expect(sandboxes[0].name == "test")
    }
}
```

### Integration Tests with Mock CLI

**Pattern**: Set environment variables, use `RealSbxService`

```swift
@Test func createSandboxIntegration() async throws {
    // Ensure mock CLI is in PATH and state dir is set
    let service = await RealSbxService()

    let sandbox = try await service.createSandbox(
        agent: "claude",
        workspace: "/tmp/test",
        name: "test"
    )

    #expect(sandbox.name == "test")
}
```

**Note**: CI sets `SBX_MOCK_STATE_DIR` and PATH for integration tests.

## Testing with the CLI Mock

### Setup

**Set environment variables**:
```bash
export SBX_MOCK_STATE_DIR=$(mktemp -d)
export PATH="$(pwd)/tools:$PATH"
```

**Verify it works**:
```bash
sbx version  # Should print "0.23.0"
sbx ls       # Should list sandboxes
```

### Mock CLI Behavior

The CLI mock (`tools/mock-sbx`):
- Stores state in JSON files at `$SBX_MOCK_STATE_DIR`
- Seeds 10 default allow policies on first run
- Returns exit code 1 on errors
- Matches real `sbx` CLI output formats

### State Directory Structure

```
$SBX_MOCK_STATE_DIR/
  .initialized
  sandboxes/<name>.json
  policies/<uuid>.json
  ports/<name>.json
  policy-log/entries.json
```

### Inspecting State

```bash
# List sandboxes
cat $SBX_MOCK_STATE_DIR/sandboxes/*.json | jq .

# List policies
cat $SBX_MOCK_STATE_DIR/policies/*.json | jq .

# List ports for a sandbox
cat $SBX_MOCK_STATE_DIR/ports/test-sandbox.json | jq .
```

### Resetting State

```bash
rm -rf $SBX_MOCK_STATE_DIR
export SBX_MOCK_STATE_DIR=$(mktemp -d)
```

## Test Patterns

### Testing Async Code

```swift
@Test func asyncOperation() async throws {
    let result = try await someAsyncFunction()
    #expect(result.isValid)
}
```

### Testing Throws

```swift
@Test func operationThrows() {
    #expect(throws: MyError.self) {
        try functionThatThrows()
    }
}

@Test func specificError() {
    #expect(throws: SbxServiceError.invalidSandboxName("test")) {
        try Sandbox.validateName("Invalid Name")
    }
}
```

### Testing MainActor Properties

```swift
@Test func storeProperty() async throws {
    let store = await SandboxStore(service: StubSbxService())
    let count = await store.sandboxes.count  // Use await
    #expect(count >= 0)
}
```

### Testing with Stubs

**StubSbxService** (defined in `sbx-uiTests/sbx_uiTests.swift`):
```swift
actor StubSbxService: SbxServiceProtocol {
    func listSandboxes() async throws -> [Sandbox] {
        [
            Sandbox(name: "test-1", agent: "claude", status: .running, workspace: "/tmp/test-1"),
            Sandbox(name: "test-2", agent: "claude", status: .stopped, workspace: "/tmp/test-2")
        ]
    }
    // ... other methods
}
```

**FailingSbxService** (for error testing):
```swift
actor FailingSbxService: SbxServiceProtocol {
    func listSandboxes() async throws -> [Sandbox] {
        throw SbxServiceError.commandFailed(code: 1, output: "Error")
    }
}
```

### Test Organization

Group related tests in structs:

```swift
struct SandboxStoreTests {
    @Test func refresh() async throws { }
    @Test func create() async throws { }
    @Test func stop() async throws { }
}

struct PolicyStoreTests {
    @Test func loadPolicies() async throws { }
    @Test func addPolicy() async throws { }
}
```

## Debugging Test Failures

### Common Issues

**"Element not found"**:
- Check accessibility identifier is set
- Increase timeout: `waitForExistence(timeout: 10)`
- Use `app.debugDescription` to inspect view hierarchy

**"Test timed out"**:
- CLI mock is slow (spawns processes) - increase timeout
- Check that `PATH` includes `tools/` directory
- Verify `SBX_CLI_MOCK=1` is set

**"Sandbox not found"**:
- Check `$SBX_MOCK_STATE_DIR` is set
- Inspect state files: `ls $SBX_MOCK_STATE_DIR/sandboxes/`

**"Port already published"**:
- Check existing port mappings
- Reset state: `rm -rf $SBX_MOCK_STATE_DIR`

### Debugging Tools

**Print app hierarchy**:
```swift
print(app.debugDescription)
```

**Check element exists**:
```swift
if !app.buttons["myButton"].exists {
    print("Button not found in hierarchy:")
    print(app.debugDescription)
}
```

**Inspect CLI mock state**:
```bash
cat $SBX_MOCK_STATE_DIR/sandboxes/*.json | jq .
```

**Run tests with verbose output**:
```bash
swift test --verbose
```

### Flaky Tests

**Never delete flaky tests!** Find and fix the root cause.

Common causes in this project:
- `FileHandle.availableData` blocks thread pool → use `readabilityHandler`
- Storing `@Observable` references breaks SwiftUI → use closures
- Plugin process tests need proper pipe cleanup → close stdin, terminate, close stdout

## CI/CD Testing

### GitHub Actions Workflows

| Workflow | Trigger | Runner | Tests |
|----------|---------|--------|-------|
| **Tests** | push/PR to main | macOS | Xcode unit + UI (73 tests) |
| **Linux CLI Tests** | push/PR (SPM paths) | Ubuntu | SPM (25 tests) + CLI mock (32 tests) |

### CI Environment

**macOS (Xcode):**
- Xcode 16+ on macOS runner
- `SBX_CLI_MOCK=1` set in scheme
- PATH includes `tools/` directory
- Runs: `xcodebuild test`

**Linux (SPM):**
- Swift 6.0 on Ubuntu 22.04
- `SBX_MOCK_STATE_DIR` set to temp dir
- PATH includes `tools/` directory
- Runs: `swift test && bash tools/mock-sbx-tests.sh`

### Running Tests Locally Like CI

**macOS:**
```bash
# Same as CI
xcodebuild test -scheme sbx-ui -destination 'platform=macOS'
```

**Linux:**
```bash
export SBX_MOCK_STATE_DIR=$(mktemp -d)
export PATH="$(pwd)/tools:$PATH"
swift test
bash tools/mock-sbx-tests.sh
```

## Best Practices

1. **Write tests first** (TDD) - Catches issues early
2. **Test behavior, not implementation** - Tests should survive refactoring
3. **Use descriptive names** - `testCreateSandboxRefreshesStore()` not `test1()`
4. **One assertion per test when possible** - Easier to debug failures
5. **Generous timeouts for UI tests** - CLI mock spawns processes
6. **Always use the CLI mock** - No Docker required, faster CI
7. **Reset state between tests** - Use unique `SBX_MOCK_STATE_DIR` per test
8. **Test error paths** - Use `FailingSbxService` for error testing
9. **Fix flaky tests** - Never delete, always find root cause
10. **Keep tests fast** - Mock external dependencies

## Further Reading

- **CLAUDE.md → Testing Guide** - Detailed testing patterns and examples
- **docs/mock-sbx.md** - CLI mock documentation
- **CONTRIBUTING.md → Testing Requirements** - Test coverage requirements

---

Happy testing! 🧪
