import XCTest

final class sbx_uiUITests: XCTestCase {
    var app: XCUIApplication!

    /// Derive the project root from this source file's compile-time path.
    private static let projectRoot: String = {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // sbx-uiUITests/
            .deletingLastPathComponent()  // project root
            .path
    }()

    private static var toolsDir: String {
        URL(fileURLWithPath: projectRoot).appendingPathComponent("tools").path
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()

        // Use CLI mock mode (RealSbxService → CliExecutor → tools/mock-sbx)
        app.launchEnvironment["SBX_CLI_MOCK"] = "1"

        // Unique state directory for this test run
        let stateDir = NSTemporaryDirectory() + "mock-sbx-\(UUID().uuidString)"
        app.launchEnvironment["SBX_MOCK_STATE_DIR"] = stateDir

        // Put tools/ directory on PATH so /usr/bin/env sbx finds mock-sbx
        let existingPath = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        app.launchEnvironment["PATH"] = "\(Self.toolsDir):\(existingPath)"

        app.launch()
    }

    // MARK: - App Launch & Navigation

    @MainActor
    func testAppLaunches() throws {
        XCTAssertTrue(app.windows.firstMatch.exists)
    }

    @MainActor
    func testSidebarNavigationExists() throws {
        let dashboard = app.staticTexts["DASHBOARD"]
        XCTAssertTrue(dashboard.waitForExistence(timeout: 10))

        let policies = app.staticTexts["POLICIES"]
        XCTAssertTrue(policies.exists)
    }

    // MARK: - Create Project Sheet

    @MainActor
    func testNewSandboxCardOpensSheet() throws {
        let newButton = app.buttons["newSandboxButton"]
        XCTAssertTrue(newButton.waitForExistence(timeout: 10))
        newButton.click()

        let deploySubmit = app.buttons["deployButton"]
        XCTAssertTrue(deploySubmit.waitForExistence(timeout: 5))
    }

    @MainActor
    func testCreateSheetNameValidation() throws {
        let newButton = app.buttons["newSandboxButton"]
        XCTAssertTrue(newButton.waitForExistence(timeout: 10))
        newButton.click()

        let nameField = app.textFields["sandboxNameField"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))

        // Type invalid name
        nameField.click()
        nameField.typeText("-invalid")

        // Verify error text appears
        let errorText = app.staticTexts["Lowercase alphanumeric and hyphens only, no leading hyphen"]
        XCTAssertTrue(errorText.waitForExistence(timeout: 2))

        // Clear and type valid name
        nameField.click()
        nameField.typeKey("a", modifierFlags: .command)
        nameField.typeText("valid-name")

        // Error should disappear
        XCTAssertFalse(errorText.exists)
    }

    // MARK: - Sandbox Lifecycle E2E

    /// Helper: creates a sandbox with a custom name via the create sheet.
    /// Mock workspace is auto-filled when SBX_CLI_MOCK=1.
    @MainActor
    private func createSandbox(name: String) {
        let newButton = app.buttons["newSandboxButton"]
        XCTAssertTrue(newButton.waitForExistence(timeout: 10))
        newButton.click()

        let nameField = app.textFields["sandboxNameField"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))

        // Wait for .onAppear to set selectedPath
        sleep(2)

        nameField.click()
        nameField.typeText(name)

        let deployButton = app.buttons["deployButton"]
        XCTAssertTrue(deployButton.waitForExistence(timeout: 5))
        let enabled = NSPredicate(format: "isEnabled == true")
        let expectation = XCTNSPredicateExpectation(predicate: enabled, object: deployButton)
        let result = XCTWaiter.wait(for: [expectation], timeout: 5)
        XCTAssertEqual(result, .completed, "Deploy button should become enabled")
        deployButton.click()
    }

    @MainActor
    func testCreateSandboxWithCustomName() throws {
        createSandbox(name: "test-create")

        // Wait for card to appear with LIVE status
        let liveChip = app.staticTexts["LIVE"]
        XCTAssertTrue(liveChip.waitForExistence(timeout: 10))

        // Verify sandbox name appears on dashboard
        let nameText = app.staticTexts["test-create"]
        XCTAssertTrue(nameText.waitForExistence(timeout: 5))
    }

    @MainActor
    func testCreateSandboxShowsRunningStats() throws {
        createSandbox(name: "test-stats")

        // Wait for LIVE status
        let liveChip = app.staticTexts["LIVE"]
        XCTAssertTrue(liveChip.waitForExistence(timeout: 10))

        // Verify global stats show at least 1 running
        let runningLabel = app.staticTexts["RUNNING"]
        XCTAssertTrue(runningLabel.waitForExistence(timeout: 5))

        let totalLabel = app.staticTexts["TOTAL"]
        XCTAssertTrue(totalLabel.exists)
    }

    @MainActor
    func testCreateSandboxShowsWorkspacePath() throws {
        createSandbox(name: "test-path")

        let liveChip = app.staticTexts["LIVE"]
        XCTAssertTrue(liveChip.waitForExistence(timeout: 10))

        // Mock workspace auto-fills to /tmp/mock-project
        let pathText = app.staticTexts["/tmp/mock-project"]
        XCTAssertTrue(pathText.waitForExistence(timeout: 5))
    }

    // MARK: - Policy E2E

    @MainActor
    func testNavigateToPolicies() throws {
        let policies = app.staticTexts["POLICIES"]
        XCTAssertTrue(policies.waitForExistence(timeout: 10))
        policies.click()

        let addButton = app.buttons["addPolicyButton"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 10))
    }

    @MainActor
    func testPolicyDefaultsLoaded() throws {
        let policies = app.staticTexts["POLICIES"]
        XCTAssertTrue(policies.waitForExistence(timeout: 10))
        policies.click()

        // Wait for policies to load — check for a known default domain
        let defaultRule = app.buttons["removePolicy-api.anthropic.com"]
        XCTAssertTrue(defaultRule.waitForExistence(timeout: 10))

        let githubRule = app.buttons["removePolicy-github.com"]
        XCTAssertTrue(githubRule.waitForExistence(timeout: 5))
    }

    @MainActor
    func testAddPolicySheet() throws {
        let policies = app.staticTexts["POLICIES"]
        XCTAssertTrue(policies.waitForExistence(timeout: 10))
        policies.click()

        let addButton = app.buttons["addPolicyButton"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 10))
        addButton.click()

        let domainInput = app.textFields["domainInput"]
        XCTAssertTrue(domainInput.waitForExistence(timeout: 5))

        // Verify submit button exists
        let submitButton = app.buttons["submitPolicyButton"]
        XCTAssertTrue(submitButton.waitForExistence(timeout: 5))
    }

    @MainActor
    func testPolicyCRUDWorkflow() throws {
        // Navigate to Policies
        let policies = app.staticTexts["POLICIES"]
        XCTAssertTrue(policies.waitForExistence(timeout: 10))
        policies.click()

        let addButton = app.buttons["addPolicyButton"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 10))

        // Add an allow rule
        addButton.click()

        let domainInput = app.textFields["domainInput"]
        XCTAssertTrue(domainInput.waitForExistence(timeout: 5))
        domainInput.click()
        domainInput.typeText("test.example.com")

        let submitButton = app.buttons["submitPolicyButton"]
        XCTAssertTrue(submitButton.isEnabled)
        submitButton.click()

        // Verify the new rule appears
        let removeButton = app.buttons["removePolicy-test.example.com"]
        XCTAssertTrue(removeButton.waitForExistence(timeout: 10))

        // Remove it
        removeButton.click()

        // Verify it's gone
        let disappeared = removeButton.waitForNonExistence(timeout: 10)
        XCTAssertTrue(disappeared)
    }

    @MainActor
    func testPolicySheetCatchAllValidation() throws {
        let policies = app.staticTexts["POLICIES"]
        XCTAssertTrue(policies.waitForExistence(timeout: 10))
        policies.click()

        let addButton = app.buttons["addPolicyButton"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 10))
        addButton.click()

        let domainInput = app.textFields["domainInput"]
        XCTAssertTrue(domainInput.waitForExistence(timeout: 5))

        // Type catch-all pattern
        domainInput.click()
        domainInput.typeText("*")

        // Verify error
        let errorText = app.staticTexts["Catch-all patterns are not allowed"]
        XCTAssertTrue(errorText.waitForExistence(timeout: 2))
    }

    // MARK: - Session E2E

    // MARK: - Session & Terminal E2E

    // NOTE: Session/terminal E2E tests (testSessionPanelOpens, testTerminalAutoFocus,
    // testTerminalInputDoesNotLeakToOtherUI, testSessionReattachAfterBack,
    // testTerminalAcceptsSustainedInput) were removed because XCUITest cannot reliably
    // trigger .onTapGesture on the sandbox card with CLI mock process-based polling.
    // Terminal focus and keyboard input behavior is covered by unit tests on SessionStore.
}
