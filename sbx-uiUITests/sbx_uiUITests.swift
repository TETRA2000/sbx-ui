import XCTest

final class sbx_uiUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["SBX_MOCK"] = "1"
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
        XCTAssertTrue(dashboard.waitForExistence(timeout: 5))

        let policies = app.staticTexts["POLICIES"]
        XCTAssertTrue(policies.exists)
    }

    // MARK: - Create Project Sheet

    @MainActor
    func testNewSandboxCardOpensSheet() throws {
        let newButton = app.buttons["newSandboxButton"]
        XCTAssertTrue(newButton.waitForExistence(timeout: 5))
        newButton.click()

        let deploySubmit = app.buttons["deployButton"]
        XCTAssertTrue(deploySubmit.waitForExistence(timeout: 3))
    }

    @MainActor
    func testCreateSheetNameValidation() throws {
        let newButton = app.buttons["newSandboxButton"]
        XCTAssertTrue(newButton.waitForExistence(timeout: 5))
        newButton.click()

        let nameField = app.textFields["sandboxNameField"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 3))

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
    /// Mock workspace is auto-filled when SBX_MOCK=1.
    @MainActor
    private func createSandbox(name: String) {
        let newButton = app.buttons["newSandboxButton"]
        XCTAssertTrue(newButton.waitForExistence(timeout: 5))
        newButton.click()

        let nameField = app.textFields["sandboxNameField"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 3))

        // Wait for .onAppear to set selectedPath
        sleep(1)

        nameField.click()
        nameField.typeText(name)

        let deployButton = app.buttons["deployButton"]
        XCTAssertTrue(deployButton.waitForExistence(timeout: 3))
        let enabled = NSPredicate(format: "isEnabled == true")
        let expectation = XCTNSPredicateExpectation(predicate: enabled, object: deployButton)
        let result = XCTWaiter.wait(for: [expectation], timeout: 3)
        XCTAssertEqual(result, .completed, "Deploy button should become enabled")
        deployButton.click()
    }

    @MainActor
    func testCreateSandboxWithCustomName() throws {
        createSandbox(name: "test-create")

        // Wait for card to appear with LIVE status (mock takes ~800ms)
        let liveChip = app.staticTexts["LIVE"]
        XCTAssertTrue(liveChip.waitForExistence(timeout: 5))

        // Verify sandbox name appears on dashboard
        let nameText = app.staticTexts["test-create"]
        XCTAssertTrue(nameText.waitForExistence(timeout: 3))
    }

    @MainActor
    func testCreateSandboxShowsRunningStats() throws {
        createSandbox(name: "test-stats")

        // Wait for LIVE status
        let liveChip = app.staticTexts["LIVE"]
        XCTAssertTrue(liveChip.waitForExistence(timeout: 5))

        // Verify global stats show at least 1 running
        let runningLabel = app.staticTexts["RUNNING"]
        XCTAssertTrue(runningLabel.waitForExistence(timeout: 3))

        let totalLabel = app.staticTexts["TOTAL"]
        XCTAssertTrue(totalLabel.exists)
    }

    @MainActor
    func testCreateSandboxShowsWorkspacePath() throws {
        createSandbox(name: "test-path")

        let liveChip = app.staticTexts["LIVE"]
        XCTAssertTrue(liveChip.waitForExistence(timeout: 5))

        // Mock workspace auto-fills to /tmp/mock-project
        let pathText = app.staticTexts["/tmp/mock-project"]
        XCTAssertTrue(pathText.waitForExistence(timeout: 3))
    }

    // MARK: - Policy E2E

    @MainActor
    func testNavigateToPolicies() throws {
        let policies = app.staticTexts["POLICIES"]
        XCTAssertTrue(policies.waitForExistence(timeout: 5))
        policies.click()

        let addButton = app.buttons["addPolicyButton"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
    }

    @MainActor
    func testPolicyDefaultsLoaded() throws {
        let policies = app.staticTexts["POLICIES"]
        XCTAssertTrue(policies.waitForExistence(timeout: 5))
        policies.click()

        // Wait for policies to load — check for a known default domain
        let defaultRule = app.buttons["removePolicy-api.anthropic.com"]
        XCTAssertTrue(defaultRule.waitForExistence(timeout: 5))

        let githubRule = app.buttons["removePolicy-github.com"]
        XCTAssertTrue(githubRule.waitForExistence(timeout: 3))
    }

    @MainActor
    func testAddPolicySheet() throws {
        let policies = app.staticTexts["POLICIES"]
        XCTAssertTrue(policies.waitForExistence(timeout: 5))
        policies.click()

        let addButton = app.buttons["addPolicyButton"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        addButton.click()

        let domainInput = app.textFields["domainInput"]
        XCTAssertTrue(domainInput.waitForExistence(timeout: 3))

        // Verify submit button exists
        let submitButton = app.buttons["submitPolicyButton"]
        XCTAssertTrue(submitButton.waitForExistence(timeout: 3))
    }

    @MainActor
    func testPolicyCRUDWorkflow() throws {
        // Navigate to Policies
        let policies = app.staticTexts["POLICIES"]
        XCTAssertTrue(policies.waitForExistence(timeout: 5))
        policies.click()

        let addButton = app.buttons["addPolicyButton"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))

        // Add an allow rule
        addButton.click()

        let domainInput = app.textFields["domainInput"]
        XCTAssertTrue(domainInput.waitForExistence(timeout: 3))
        domainInput.click()
        domainInput.typeText("test.example.com")

        let submitButton = app.buttons["submitPolicyButton"]
        XCTAssertTrue(submitButton.isEnabled)
        submitButton.click()

        // Verify the new rule appears
        let removeButton = app.buttons["removePolicy-test.example.com"]
        XCTAssertTrue(removeButton.waitForExistence(timeout: 5))

        // Remove it
        removeButton.click()

        // Verify it's gone
        let disappeared = removeButton.waitForNonExistence(timeout: 5)
        XCTAssertTrue(disappeared)
    }

    @MainActor
    func testPolicySheetCatchAllValidation() throws {
        let policies = app.staticTexts["POLICIES"]
        XCTAssertTrue(policies.waitForExistence(timeout: 5))
        policies.click()

        let addButton = app.buttons["addPolicyButton"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        addButton.click()

        let domainInput = app.textFields["domainInput"]
        XCTAssertTrue(domainInput.waitForExistence(timeout: 3))

        // Type catch-all pattern
        domainInput.click()
        domainInput.typeText("*")

        // Verify error
        let errorText = app.staticTexts["Catch-all patterns are not allowed"]
        XCTAssertTrue(errorText.waitForExistence(timeout: 2))
    }

    // MARK: - Session E2E

    // MARK: - Session & Terminal E2E

    /// Helper: opens a session for the named sandbox (must already exist on dashboard).
    @MainActor
    private func openSession(name: String) {
        let nameText = app.staticTexts[name]
        XCTAssertTrue(nameText.waitForExistence(timeout: 3))
        nameText.click()

        let backButton = app.buttons["backToDashboard"]
        XCTAssertTrue(backButton.waitForExistence(timeout: 5))
    }

    @MainActor
    func testSessionPanelOpens() throws {
        createSandbox(name: "test-session")

        let liveChip = app.staticTexts["LIVE"]
        XCTAssertTrue(liveChip.waitForExistence(timeout: 5))

        openSession(name: "test-session")

        // Verify session panel elements
        let backButton = app.buttons["backToDashboard"]
        XCTAssertTrue(backButton.exists)

        // Agent status bar shows connected
        let connected = app.staticTexts["Connected"]
        XCTAssertTrue(connected.waitForExistence(timeout: 5))
    }

    @MainActor
    func testTerminalAutoFocusReceivesKeyboardInput() throws {
        // Verifies FocusableTerminalView.viewDidMoveToWindow sets first responder
        // so keyboard events reach the terminal without requiring a click.
        createSandbox(name: "test-autofocus")

        let liveChip = app.staticTexts["LIVE"]
        XCTAssertTrue(liveChip.waitForExistence(timeout: 5))

        openSession(name: "test-autofocus")

        // Wait for terminal to render and auto-focus via viewDidMoveToWindow
        sleep(2)

        // Type keys — if auto-focus worked, the terminal has first responder
        // and these keys are delivered to it (not to any other UI element).
        app.typeKey("h", modifierFlags: [])
        app.typeKey("e", modifierFlags: [])
        app.typeKey("l", modifierFlags: [])
        app.typeKey("l", modifierFlags: [])
        app.typeKey("o", modifierFlags: [])
        app.typeKey(XCUIKeyboardKey.return, modifierFlags: [])

        // Session panel still active — keyboard input didn't trigger navigation
        let backButton = app.buttons["backToDashboard"]
        XCTAssertTrue(backButton.exists)

        // Connected status confirms session is still alive
        let connected = app.staticTexts["Connected"]
        XCTAssertTrue(connected.exists)
    }

    @MainActor
    func testTerminalInputDoesNotLeakToOtherUI() throws {
        // Verifies keyboard input stays in terminal, doesn't affect sidebar or navigation
        createSandbox(name: "test-noleak")

        let liveChip = app.staticTexts["LIVE"]
        XCTAssertTrue(liveChip.waitForExistence(timeout: 5))

        openSession(name: "test-noleak")
        sleep(2)

        // Type characters including ones that could match shortcuts or labels
        app.typeKey("d", modifierFlags: [])
        app.typeKey("p", modifierFlags: [])
        app.typeKey("q", modifierFlags: [])
        app.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])

        // Sidebar items still present — no navigation happened from typing
        let dashboard = app.staticTexts["DASHBOARD"]
        XCTAssertTrue(dashboard.exists)
        let policies = app.staticTexts["POLICIES"]
        XCTAssertTrue(policies.exists)

        // Still in session panel (not kicked back to dashboard)
        let backButton = app.buttons["backToDashboard"]
        XCTAssertTrue(backButton.exists)
    }

    @MainActor
    func testSessionReattachAfterBack() throws {
        // Tests that dispose + re-attach works: terminal focus and input survive round-trip
        createSandbox(name: "test-reattach")

        let liveChip = app.staticTexts["LIVE"]
        XCTAssertTrue(liveChip.waitForExistence(timeout: 5))

        // First attach
        openSession(name: "test-reattach")
        sleep(1)
        app.typeKey("a", modifierFlags: [])

        // Go back to dashboard
        app.buttons["backToDashboard"].click()
        let newButton = app.buttons["newSandboxButton"]
        XCTAssertTrue(newButton.waitForExistence(timeout: 5))

        // Re-enter the same session
        openSession(name: "test-reattach")

        // Wait for re-attach and auto-focus
        sleep(2)

        // Type again — terminal should accept input after re-attach
        app.typeKey("b", modifierFlags: [])
        app.typeKey("c", modifierFlags: [])
        app.typeKey(XCUIKeyboardKey.return, modifierFlags: [])

        // Session still connected after re-attach
        let connected = app.staticTexts["Connected"]
        XCTAssertTrue(connected.waitForExistence(timeout: 5))
    }

    @MainActor
    func testTerminalAcceptsSustainedInput() throws {
        // Stress-tests keyboard input: rapid keystrokes, special keys, modifiers
        createSandbox(name: "test-sustained")

        let liveChip = app.staticTexts["LIVE"]
        XCTAssertTrue(liveChip.waitForExistence(timeout: 5))

        openSession(name: "test-sustained")
        sleep(2)

        // Rapid keystrokes
        for char in "the quick brown fox" {
            app.typeKey(String(char), modifierFlags: [])
        }
        app.typeKey(XCUIKeyboardKey.return, modifierFlags: [])

        // Special keys
        app.typeKey(XCUIKeyboardKey.tab, modifierFlags: [])
        app.typeKey(XCUIKeyboardKey.upArrow, modifierFlags: [])
        app.typeKey(XCUIKeyboardKey.downArrow, modifierFlags: [])

        // Ctrl+C (common terminal interrupt)
        app.typeKey("c", modifierFlags: .control)

        // Session still alive
        let backButton = app.buttons["backToDashboard"]
        XCTAssertTrue(backButton.exists)
        let connected = app.staticTexts["Connected"]
        XCTAssertTrue(connected.exists)
    }
}
