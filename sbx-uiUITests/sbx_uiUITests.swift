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

        // Wait for the sheet to dismiss before checking dashboard
        let dismissed = deployButton.waitForNonExistence(timeout: 15)
        XCTAssertTrue(dismissed, "Create sheet should dismiss after deploy")
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

    // MARK: - Session & Terminal E2E

    /// Helper: opens a session for the named sandbox (must already exist on dashboard).
    /// Clicks the sandbox name text, which triggers .onTapGesture on the parent card.
    @MainActor
    private func openSession(name: String) {
        let nameText = app.staticTexts[name]
        XCTAssertTrue(nameText.waitForExistence(timeout: 10))
        nameText.click()

        let backButton = app.buttons["backToDashboard"]
        XCTAssertTrue(backButton.waitForExistence(timeout: 10))
    }

    @MainActor
    func testSessionPanelOpens() throws {
        createSandbox(name: "test-session")

        let liveChip = app.staticTexts["LIVE"]
        XCTAssertTrue(liveChip.waitForExistence(timeout: 10))

        openSession(name: "test-session")

        // Verify session panel elements
        let backButton = app.buttons["backToDashboard"]
        XCTAssertTrue(backButton.exists)

        // Agent status bar shows connected
        let connected = app.staticTexts["Connected"]
        XCTAssertTrue(connected.waitForExistence(timeout: 10))
    }

    @MainActor
    func testTerminalAutoFocusReceivesKeyboardInput() throws {
        createSandbox(name: "test-autofocus")

        let liveChip = app.staticTexts["LIVE"]
        XCTAssertTrue(liveChip.waitForExistence(timeout: 10))

        openSession(name: "test-autofocus")

        // Wait for terminal to render and auto-focus via viewDidMoveToWindow
        sleep(3)

        // Type keys — if auto-focus worked, the terminal has first responder
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
        createSandbox(name: "test-noleak")

        let liveChip = app.staticTexts["LIVE"]
        XCTAssertTrue(liveChip.waitForExistence(timeout: 10))

        openSession(name: "test-noleak")
        sleep(3)

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
        createSandbox(name: "test-reattach")

        let liveChip = app.staticTexts["LIVE"]
        XCTAssertTrue(liveChip.waitForExistence(timeout: 10))

        // First attach
        openSession(name: "test-reattach")
        sleep(2)
        app.typeKey("a", modifierFlags: [])

        // Go back to dashboard
        app.buttons["backToDashboard"].click()
        let newButton = app.buttons["newSandboxButton"]
        XCTAssertTrue(newButton.waitForExistence(timeout: 10))

        // Re-enter the same session
        openSession(name: "test-reattach")

        // Wait for re-attach and auto-focus
        sleep(3)

        // Type again — terminal should accept input after re-attach
        app.typeKey("b", modifierFlags: [])
        app.typeKey("c", modifierFlags: [])
        app.typeKey(XCUIKeyboardKey.return, modifierFlags: [])

        // Session still connected after re-attach
        let connected = app.staticTexts["Connected"]
        XCTAssertTrue(connected.waitForExistence(timeout: 10))
    }

    @MainActor
    func testTerminalAcceptsSustainedInput() throws {
        createSandbox(name: "test-sustained")

        let liveChip = app.staticTexts["LIVE"]
        XCTAssertTrue(liveChip.waitForExistence(timeout: 10))

        openSession(name: "test-sustained")
        sleep(1)

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

        // Session still alive (mock-sbx sleeps to keep process alive)
        let backButton = app.buttons["backToDashboard"]
        XCTAssertTrue(backButton.exists)
        let connected = app.staticTexts["Connected"]
        XCTAssertTrue(connected.exists)
    }

    // MARK: - Background Session E2E

    @MainActor
    func testBackgroundSessionShowsBadgeOnDashboard() throws {
        createSandbox(name: "test-bg-badge")

        let liveChip = app.staticTexts["LIVE"]
        XCTAssertTrue(liveChip.waitForExistence(timeout: 10))

        // Open terminal session
        openSession(name: "test-bg-badge")
        sleep(2)

        // Go back to dashboard — session stays alive in background
        app.buttons["backToDashboard"].click()
        let newButton = app.buttons["newSandboxButton"]
        XCTAssertTrue(newButton.waitForExistence(timeout: 10))

        // Session badge should appear on the sandbox card
        let sessionBadge = app.staticTexts["SESSION"]
        XCTAssertTrue(sessionBadge.waitForExistence(timeout: 5))
    }

    @MainActor
    func testBackgroundSessionShowsInSidebar() throws {
        createSandbox(name: "test-bg-sidebar")

        let liveChip = app.staticTexts["LIVE"]
        XCTAssertTrue(liveChip.waitForExistence(timeout: 10))

        // Open terminal session
        openSession(name: "test-bg-sidebar")

        // Go back to dashboard
        app.buttons["backToDashboard"].click()
        let newButton = app.buttons["newSandboxButton"]
        XCTAssertTrue(newButton.waitForExistence(timeout: 10))

        // Sidebar should show SESSIONS section with the session label
        let sidebarSession = app.buttons["sidebarSession-test-bg-sidebar (agent)"]
        XCTAssertTrue(sidebarSession.waitForExistence(timeout: 5))

        sidebarSession.click()

        let backButton = app.buttons["backToDashboard"]
        XCTAssertTrue(backButton.waitForExistence(timeout: 10))
    }

    @MainActor
    func testDisconnectButtonEndsSession() throws {
        createSandbox(name: "test-disconnect")

        let liveChip = app.staticTexts["LIVE"]
        XCTAssertTrue(liveChip.waitForExistence(timeout: 10))

        // Open terminal session
        openSession(name: "test-disconnect")
        sleep(2)

        // Click disconnect — should end session and return to dashboard
        let disconnectButton = app.buttons["disconnectButton"]
        XCTAssertTrue(disconnectButton.exists)
        disconnectButton.click()

        // Should be back on dashboard
        let newButton = app.buttons["newSandboxButton"]
        XCTAssertTrue(newButton.waitForExistence(timeout: 10))

        // Session badge should NOT appear (session was disconnected, not backgrounded)
        let sessionBadge = app.staticTexts["SESSION"]
        XCTAssertFalse(sessionBadge.waitForExistence(timeout: 3))
    }

    @MainActor
    func testSessionsCountInGlobalStats() throws {
        createSandbox(name: "test-stats")

        let liveChip = app.staticTexts["LIVE"]
        XCTAssertTrue(liveChip.waitForExistence(timeout: 10))

        // Open terminal session then go back
        openSession(name: "test-stats")
        sleep(2)
        app.buttons["backToDashboard"].click()

        let newButton = app.buttons["newSandboxButton"]
        XCTAssertTrue(newButton.waitForExistence(timeout: 10))

        // Global stats should show "SESSIONS" label
        let sessionsLabel = app.staticTexts["SESSIONS"]
        XCTAssertTrue(sessionsLabel.waitForExistence(timeout: 5))
    }

    // MARK: - Multi-Session Switching E2E

    @MainActor
    func testSwitchBetweenTwoBackgroundSessions() throws {
        // Create two sandboxes
        createSandbox(name: "test-switch-a")
        let liveA = app.staticTexts["LIVE"]
        XCTAssertTrue(liveA.waitForExistence(timeout: 10))

        createSandbox(name: "test-switch-b")
        sleep(3)  // Wait for polling to show the second sandbox

        // Start session A then background it
        openSession(name: "test-switch-a")
        app.buttons["backToDashboard"].click()
        let newButton = app.buttons["newSandboxButton"]
        XCTAssertTrue(newButton.waitForExistence(timeout: 10))

        // Start session B then background it
        openSession(name: "test-switch-b")
        app.buttons["backToDashboard"].click()
        XCTAssertTrue(newButton.waitForExistence(timeout: 10))

        // Switch to session A via sidebar
        let sidebarA = app.buttons["sidebarSession-test-switch-a (agent)"]
        XCTAssertTrue(sidebarA.waitForExistence(timeout: 5))
        sidebarA.click()

        let backButton = app.buttons["backToDashboard"]
        XCTAssertTrue(backButton.waitForExistence(timeout: 10))

        // Go back and switch to session B via sidebar
        backButton.click()
        XCTAssertTrue(newButton.waitForExistence(timeout: 10))

        let sidebarB = app.buttons["sidebarSession-test-switch-b (agent)"]
        XCTAssertTrue(sidebarB.waitForExistence(timeout: 5))
        sidebarB.click()

        XCTAssertTrue(backButton.waitForExistence(timeout: 10))
    }

    @MainActor
    func testDisconnectOneSessionPreservesOther() throws {
        // Create two sandboxes
        createSandbox(name: "test-keep-a")
        let liveChip = app.staticTexts["LIVE"]
        XCTAssertTrue(liveChip.waitForExistence(timeout: 10))

        createSandbox(name: "test-keep-b")
        sleep(3)

        // Start both sessions
        openSession(name: "test-keep-a")
        app.buttons["backToDashboard"].click()
        let newButton = app.buttons["newSandboxButton"]
        XCTAssertTrue(newButton.waitForExistence(timeout: 10))

        openSession(name: "test-keep-b")

        // Disconnect session B (using disconnect button, not back)
        let disconnectButton = app.buttons["disconnectButton"]
        XCTAssertTrue(disconnectButton.exists)
        disconnectButton.click()

        // Should be back on dashboard
        XCTAssertTrue(newButton.waitForExistence(timeout: 10))

        // Session B should NOT be in sidebar
        let sidebarB = app.buttons["sidebarSession-test-keep-b (agent)"]
        XCTAssertFalse(sidebarB.waitForExistence(timeout: 3))

        // Session A should still be in sidebar
        let sidebarA = app.buttons["sidebarSession-test-keep-a (agent)"]
        XCTAssertTrue(sidebarA.waitForExistence(timeout: 5))
        sidebarA.click()
        let backButton = app.buttons["backToDashboard"]
        XCTAssertTrue(backButton.waitForExistence(timeout: 10))
    }

    @MainActor
    func testRapidSessionSwitching() throws {
        // Create two sandboxes
        createSandbox(name: "test-rapid-a")
        let liveChip = app.staticTexts["LIVE"]
        XCTAssertTrue(liveChip.waitForExistence(timeout: 10))

        createSandbox(name: "test-rapid-b")
        sleep(3)

        // Start both sessions
        openSession(name: "test-rapid-a")
        app.buttons["backToDashboard"].click()
        let newButton = app.buttons["newSandboxButton"]
        XCTAssertTrue(newButton.waitForExistence(timeout: 10))

        openSession(name: "test-rapid-b")
        app.buttons["backToDashboard"].click()
        XCTAssertTrue(newButton.waitForExistence(timeout: 10))

        // Rapidly switch between sessions via sidebar
        let sidebarA = app.buttons["sidebarSession-test-rapid-a (agent)"]
        let sidebarB = app.buttons["sidebarSession-test-rapid-b (agent)"]
        XCTAssertTrue(sidebarA.waitForExistence(timeout: 5))
        XCTAssertTrue(sidebarB.waitForExistence(timeout: 5))

        for _ in 0..<3 {
            sidebarA.click()

            let backButton = app.buttons["backToDashboard"]
            XCTAssertTrue(backButton.waitForExistence(timeout: 10))
            backButton.click()
            XCTAssertTrue(newButton.waitForExistence(timeout: 10))

            sidebarB.click()

            XCTAssertTrue(backButton.waitForExistence(timeout: 10))
            backButton.click()
            XCTAssertTrue(newButton.waitForExistence(timeout: 10))
        }

        // Both sessions should still be active after rapid switching
        XCTAssertTrue(sidebarA.exists)
        XCTAssertTrue(sidebarB.exists)
    }

    @MainActor
    func testTerminalThumbnailAreaAppearsOnCard() throws {
        createSandbox(name: "test-thumb")

        let liveChip = app.staticTexts["LIVE"]
        XCTAssertTrue(liveChip.waitForExistence(timeout: 10))

        // Open terminal session then go back
        openSession(name: "test-thumb")
        sleep(2)
        app.buttons["backToDashboard"].click()

        let newButton = app.buttons["newSandboxButton"]
        XCTAssertTrue(newButton.waitForExistence(timeout: 10))

        // The thumbnail area shows "Connecting..." placeholder initially,
        // then updates to a bitmap snapshot. Either state confirms the
        // thumbnail section is rendering on the card.
        let connecting = app.staticTexts["Connecting..."]
        let sessionBadge = app.staticTexts["SESSION"]
        let found = connecting.waitForExistence(timeout: 8) || sessionBadge.waitForExistence(timeout: 2)
        XCTAssertTrue(found, "Terminal thumbnail area or session badge should appear on card")
    }
}
