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

    @MainActor
    func testSessionPanelOpens() throws {
        createSandbox(name: "test-session")

        let liveChip = app.staticTexts["LIVE"]
        XCTAssertTrue(liveChip.waitForExistence(timeout: 5))

        // Click sandbox name to enter session
        let nameText = app.staticTexts["test-session"]
        XCTAssertTrue(nameText.waitForExistence(timeout: 3))
        nameText.click()

        // Verify chat input appears (session panel opened)
        let chatInput = app.textFields["chatInput"]
        XCTAssertTrue(chatInput.waitForExistence(timeout: 5))
    }

    @MainActor
    func testChatInputSendClearsField() throws {
        createSandbox(name: "test-chat")

        let liveChip = app.staticTexts["LIVE"]
        XCTAssertTrue(liveChip.waitForExistence(timeout: 5))

        let nameText = app.staticTexts["test-chat"]
        XCTAssertTrue(nameText.waitForExistence(timeout: 3))
        nameText.click()

        let chatInput = app.textFields["chatInput"]
        XCTAssertTrue(chatInput.waitForExistence(timeout: 5))

        // Type message and send
        chatInput.click()
        chatInput.typeText("Hello Claude")

        let sendButton = app.buttons["sendButton"]
        XCTAssertTrue(sendButton.waitForExistence(timeout: 3))
        sendButton.click()

        // Verify input is cleared
        sleep(1)
        let inputValue = chatInput.value as? String ?? ""
        XCTAssertTrue(inputValue.isEmpty, "Chat input should be cleared after send")
    }
}
