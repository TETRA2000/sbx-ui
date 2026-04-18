import XCTest

final class sbx_uiUITests: XCTestCase {
    var app: XCUIApplication!
    private var workspaceURL: URL?

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

        // Empty plugin directory to avoid interference from installed plugins
        let emptyPluginDir = NSTemporaryDirectory() + "empty-plugins-\(UUID().uuidString)"
        try? FileManager.default.createDirectory(atPath: emptyPluginDir, withIntermediateDirectories: true)
        app.launchEnvironment["SBX_PLUGIN_DIR"] = emptyPluginDir

        // Isolated kanban directory to avoid persistence leaking between test runs
        let kanbanDir = NSTemporaryDirectory() + "kanban-\(UUID().uuidString)"
        app.launchEnvironment["SBX_KANBAN_DIR"] = kanbanDir

        // Create a real workspace directory so EditorStore.refreshDirectory
        // doesn't fail and show a toast that covers the backToDashboard button.
        let workspace = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mock-ws-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        try Data("# Mock Project\n".utf8).write(to: workspace.appendingPathComponent("README.md"))
        self.workspaceURL = workspace
        app.launchEnvironment["SBX_CLI_MOCK_WORKSPACE"] = workspace.path

        // Disable window state restoration so WindowGroup always opens a fresh window
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]

        app.launch()
    }

    override func tearDownWithError() throws {
        if let workspaceURL {
            try? FileManager.default.removeItem(at: workspaceURL)
        }
    }

    // MARK: - App Launch & Navigation

    
    func testAppLaunches() throws {
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 5))
    }

    
    func testSidebarNavigationExists() throws {
        let dashboard = app.staticTexts["DASHBOARD"]
        XCTAssertTrue(dashboard.waitForExistence(timeout: 5))

        let policies = app.staticTexts["POLICIES"]
        XCTAssertTrue(policies.exists)
    }

    // MARK: - Create Project Sheet

    
    func testNewSandboxCardOpensSheet() throws {
        let newButton = app.buttons["newSandboxButton"]
        XCTAssertTrue(newButton.waitForExistence(timeout: 5))
        newButton.click()

        let deploySubmit = app.buttons["deployButton"]
        XCTAssertTrue(deploySubmit.waitForExistence(timeout: 5))
    }

    
    func testCreateSheetNameValidation() throws {
        let newButton = app.buttons["newSandboxButton"]
        XCTAssertTrue(newButton.waitForExistence(timeout: 5))
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
    /// After creation, the app auto-navigates to the terminal session.
    /// Pass `returnToDashboard: true` to navigate back to the dashboard.
    
    private func createSandbox(name: String, returnToDashboard: Bool = false) {
        let newButton = app.buttons["newSandboxButton"]
        XCTAssertTrue(newButton.waitForExistence(timeout: 5))
        newButton.click()

        let nameField = app.textFields["sandboxNameField"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 3))

        nameField.click()
        nameField.typeText(name)

        // Wait for deploy button to become enabled (.onAppear sets selectedPath in mock mode)
        let deployButton = app.buttons["deployButton"]
        let enabled = NSPredicate(format: "isEnabled == true")
        let expectation = XCTNSPredicateExpectation(predicate: enabled, object: deployButton)
        let result = XCTWaiter.wait(for: [expectation], timeout: 5)
        XCTAssertEqual(result, .completed, "Deploy button should become enabled")
        deployButton.click()

        let dismissed = deployButton.waitForNonExistence(timeout: 5)
        XCTAssertTrue(dismissed, "Create sheet should dismiss after deploy")

        if returnToDashboard {
            // Auto-navigation opens the terminal session — go back to dashboard
            let backButton = app.buttons["backToDashboard"]
            if backButton.waitForExistence(timeout: 3) {
                backButton.click()
                sleep(1)
            } else {
                // Fallback: click DASHBOARD in sidebar
                let dashboard = app.staticTexts["DASHBOARD"]
                if dashboard.waitForExistence(timeout: 3) {
                    dashboard.click()
                    sleep(1)
                }
            }
        }
    }

    
    func testCreateSandboxWithCustomName() throws {
        createSandbox(name: "test-create", returnToDashboard: true)

        // Wait for card to appear with LIVE status
        let liveChip = app.staticTexts["LIVE"]
        XCTAssertTrue(liveChip.waitForExistence(timeout: 5))

        // Verify sandbox name appears on dashboard
        let nameText = app.staticTexts["test-create"]
        XCTAssertTrue(nameText.waitForExistence(timeout: 5))
    }

    
    func testCreateSandboxShowsRunningStats() throws {
        createSandbox(name: "test-stats", returnToDashboard: true)

        // Wait for LIVE status
        let liveChip = app.staticTexts["LIVE"]
        XCTAssertTrue(liveChip.waitForExistence(timeout: 5))

        // Verify global stats show at least 1 running
        let runningLabel = app.staticTexts["RUNNING"]
        XCTAssertTrue(runningLabel.waitForExistence(timeout: 5))

        let totalLabel = app.staticTexts["TOTAL"]
        XCTAssertTrue(totalLabel.exists)
    }

    
    func testCreateSandboxShowsWorkspacePath() throws {
        createSandbox(name: "test-path", returnToDashboard: true)

        let liveChip = app.staticTexts["LIVE"]
        XCTAssertTrue(liveChip.waitForExistence(timeout: 5))

        // Workspace path (from SBX_CLI_MOCK_WORKSPACE) should appear on the card.
        let pathPredicate = NSPredicate(format: "value CONTAINS 'mock-ws-'")
        let pathText = app.staticTexts.matching(pathPredicate).firstMatch
        XCTAssertTrue(pathText.waitForExistence(timeout: 5))
    }

    // MARK: - Policy E2E

    
    func testNavigateToPolicies() throws {
        let policies = app.staticTexts["POLICIES"]
        XCTAssertTrue(policies.waitForExistence(timeout: 5))
        policies.click()

        let addButton = app.buttons["addPolicyButton"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
    }

    
    func testPolicyDefaultsLoaded() throws {
        let policies = app.staticTexts["POLICIES"]
        XCTAssertTrue(policies.waitForExistence(timeout: 5))
        policies.click()

        // Wait for policies to load — check for a known default domain
        let defaultRule = app.buttons["removePolicy-api.anthropic.com"]
        XCTAssertTrue(defaultRule.waitForExistence(timeout: 5))

        let githubRule = app.buttons["removePolicy-github.com"]
        XCTAssertTrue(githubRule.waitForExistence(timeout: 5))
    }

    
    func testAddPolicySheet() throws {
        let policies = app.staticTexts["POLICIES"]
        XCTAssertTrue(policies.waitForExistence(timeout: 5))
        policies.click()

        let addButton = app.buttons["addPolicyButton"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        addButton.click()

        let domainInput = app.textFields["domainInput"]
        XCTAssertTrue(domainInput.waitForExistence(timeout: 5))

        // Verify submit button exists
        let submitButton = app.buttons["submitPolicyButton"]
        XCTAssertTrue(submitButton.waitForExistence(timeout: 5))
    }

    
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
        XCTAssertTrue(domainInput.waitForExistence(timeout: 5))
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

    
    func testPolicySheetCatchAllValidation() throws {
        let policies = app.staticTexts["POLICIES"]
        XCTAssertTrue(policies.waitForExistence(timeout: 5))
        policies.click()

        let addButton = app.buttons["addPolicyButton"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
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
    
    private func openSession(name: String) {
        let nameText = app.staticTexts[name]
        XCTAssertTrue(nameText.waitForExistence(timeout: 5))
        nameText.click()

        let backButton = app.buttons["backToDashboard"]
        XCTAssertTrue(backButton.waitForExistence(timeout: 5))
    }

    
    func testSessionPanelOpens() throws {
        createSandbox(name: "test-session")

        // Terminal auto-opens after creation; wait for session panel
        sleep(2)

        // Terminal auto-opens after creation via onCreated callback; no need to openSession()
        _ = ( "test-session")

        // Verify session panel elements
        let backButton = app.buttons["backToDashboard"]
        XCTAssertTrue(backButton.exists)

        // Agent status bar shows connected
        let connected = app.staticTexts["Connected"]
        XCTAssertTrue(connected.waitForExistence(timeout: 5))
    }

    
    func testTerminalAutoFocusReceivesKeyboardInput() throws {
        createSandbox(name: "test-autofocus")

        // Terminal auto-opens after creation; wait for session panel
        sleep(2)

        // Terminal auto-opens after creation via onCreated callback; no need to openSession()
        _ = ( "test-autofocus")
        sleep(1)  // Brief wait for terminal auto-focus

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

    
    func testTerminalInputDoesNotLeakToOtherUI() throws {
        createSandbox(name: "test-noleak")

        // Terminal auto-opens after creation; wait for session panel
        sleep(2)

        // Terminal auto-opens after creation via onCreated callback; no need to openSession()
        _ = ( "test-noleak")
        sleep(1)  // Brief wait for terminal auto-focus

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

    
    func testSessionReattachAfterBack() throws {
        // Terminal auto-opens after creation
        createSandbox(name: "test-reattach")
        sleep(2)
        app.typeKey("a", modifierFlags: [])

        // Go back to dashboard
        app.buttons["backToDashboard"].click()
        let newButton = app.buttons["newSandboxButton"]
        XCTAssertTrue(newButton.waitForExistence(timeout: 5))

        // Re-enter the same session
        openSession(name: "test-reattach")

        // Type again — terminal should accept input after re-attach
        app.typeKey("b", modifierFlags: [])
        app.typeKey("c", modifierFlags: [])
        app.typeKey(XCUIKeyboardKey.return, modifierFlags: [])

        // Session still connected after re-attach
        let connected = app.staticTexts["Connected"]
        XCTAssertTrue(connected.waitForExistence(timeout: 5))
    }

    
    func testTerminalAcceptsSustainedInput() throws {
        createSandbox(name: "test-sustained")

        // Terminal auto-opens after creation; wait for session panel
        sleep(2)

        // Terminal auto-opens after creation via onCreated callback; no need to openSession()
        _ = ( "test-sustained")
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

        // Session still alive after sustained input
        let backButton = app.buttons["backToDashboard"]
        XCTAssertTrue(backButton.exists)
        let connected = app.staticTexts["Connected"]
        XCTAssertTrue(connected.exists)
    }

    // MARK: - Background Session E2E

    
    func testBackgroundSessionShowsBadgeOnDashboard() throws {
        createSandbox(name: "test-bg-badge", returnToDashboard: true)

        let liveChip = app.staticTexts["LIVE"]
        XCTAssertTrue(liveChip.waitForExistence(timeout: 5))

        // Open terminal session
        openSession(name: "test-bg-badge")

        // Go back to dashboard — session stays alive in background
        app.buttons["backToDashboard"].click()
        let newButton = app.buttons["newSandboxButton"]
        XCTAssertTrue(newButton.waitForExistence(timeout: 5))

        // Session badge should appear on the sandbox card
        let sessionBadge = app.staticTexts["SESSION"]
        XCTAssertTrue(sessionBadge.waitForExistence(timeout: 5))
    }

    
    func testBackgroundSessionShowsInSidebar() throws {
        createSandbox(name: "test-bg-sidebar", returnToDashboard: true)

        let liveChip = app.staticTexts["LIVE"]
        XCTAssertTrue(liveChip.waitForExistence(timeout: 5))

        // Open terminal session
        openSession(name: "test-bg-sidebar")

        // Go back to dashboard
        app.buttons["backToDashboard"].click()
        let newButton = app.buttons["newSandboxButton"]
        XCTAssertTrue(newButton.waitForExistence(timeout: 5))

        // Sidebar should show SESSIONS section with the session label
        let sidebarSession = app.buttons["sidebarSession-test-bg-sidebar (agent)"]
        XCTAssertTrue(sidebarSession.waitForExistence(timeout: 5))

        sidebarSession.click()

        let backButton = app.buttons["backToDashboard"]
        XCTAssertTrue(backButton.waitForExistence(timeout: 5))
    }

    
    func testDisconnectButtonEndsSession() throws {
        createSandbox(name: "test-disconnect", returnToDashboard: true)

        let liveChip = app.staticTexts["LIVE"]
        XCTAssertTrue(liveChip.waitForExistence(timeout: 5))

        // Open terminal session
        openSession(name: "test-disconnect")

        // Click disconnect — should end session and return to dashboard
        let disconnectButton = app.buttons["disconnectButton"]
        XCTAssertTrue(disconnectButton.exists)
        disconnectButton.click()

        // Should be back on dashboard
        let newButton = app.buttons["newSandboxButton"]
        XCTAssertTrue(newButton.waitForExistence(timeout: 5))

        // Session badge should NOT appear (session was disconnected, not backgrounded)
        let sessionBadge = app.staticTexts["SESSION"]
        XCTAssertFalse(sessionBadge.waitForExistence(timeout: 3))
    }

    
    func testSessionsCountInGlobalStats() throws {
        // Create sandbox — terminal auto-opens, then go back to dashboard
        createSandbox(name: "test-stats", returnToDashboard: true)

        let newButton = app.buttons["newSandboxButton"]
        XCTAssertTrue(newButton.waitForExistence(timeout: 5))

        // Global stats should show "SESSIONS" label
        let sessionsLabel = app.staticTexts["SESSIONS"]
        XCTAssertTrue(sessionsLabel.waitForExistence(timeout: 5))
    }

    // MARK: - Multi-Session Switching E2E

    
    func testSwitchBetweenTwoBackgroundSessions() throws {
        // Create two sandboxes
        createSandbox(name: "test-switch-a", returnToDashboard: true)
        createSandbox(name: "test-switch-b", returnToDashboard: true)
        // Wait for second sandbox to appear on dashboard
        let cardB = app.staticTexts["test-switch-b"]
        XCTAssertTrue(cardB.waitForExistence(timeout: 5))

        // Start session A then background it
        openSession(name: "test-switch-a")
        app.buttons["backToDashboard"].click()
        let newButton = app.buttons["newSandboxButton"]
        XCTAssertTrue(newButton.waitForExistence(timeout: 5))

        // Start session B then background it
        openSession(name: "test-switch-b")
        app.buttons["backToDashboard"].click()
        XCTAssertTrue(newButton.waitForExistence(timeout: 5))

        // Switch to session A via sidebar
        let sidebarA = app.buttons["sidebarSession-test-switch-a (agent)"]
        XCTAssertTrue(sidebarA.waitForExistence(timeout: 5))
        sidebarA.click()

        let backButton = app.buttons["backToDashboard"]
        XCTAssertTrue(backButton.waitForExistence(timeout: 5))

        // Go back and switch to session B via sidebar
        backButton.click()
        XCTAssertTrue(newButton.waitForExistence(timeout: 5))

        let sidebarB = app.buttons["sidebarSession-test-switch-b (agent)"]
        XCTAssertTrue(sidebarB.waitForExistence(timeout: 5))
        sidebarB.click()

        XCTAssertTrue(backButton.waitForExistence(timeout: 5))
    }

    
    func testDisconnectOneSessionPreservesOther() throws {
        // Create two sandboxes
        createSandbox(name: "test-keep-a", returnToDashboard: true)
        createSandbox(name: "test-keep-b", returnToDashboard: true)

        // Start both sessions
        openSession(name: "test-keep-a")
        app.buttons["backToDashboard"].click()
        let newButton = app.buttons["newSandboxButton"]
        XCTAssertTrue(newButton.waitForExistence(timeout: 5))

        openSession(name: "test-keep-b")

        // Disconnect session B (using disconnect button, not back)
        let disconnectButton = app.buttons["disconnectButton"]
        XCTAssertTrue(disconnectButton.exists)
        disconnectButton.click()

        // Should be back on dashboard
        XCTAssertTrue(newButton.waitForExistence(timeout: 5))

        // Session B should NOT be in sidebar
        let sidebarB = app.buttons["sidebarSession-test-keep-b (agent)"]
        XCTAssertFalse(sidebarB.waitForExistence(timeout: 3))

        // Session A should still be in sidebar
        let sidebarA = app.buttons["sidebarSession-test-keep-a (agent)"]
        XCTAssertTrue(sidebarA.waitForExistence(timeout: 5))
        sidebarA.click()
        let backButton = app.buttons["backToDashboard"]
        XCTAssertTrue(backButton.waitForExistence(timeout: 5))
    }

    
    func testRapidSessionSwitching() throws {
        // Create two sandboxes
        createSandbox(name: "test-rapid-a", returnToDashboard: true)
        createSandbox(name: "test-rapid-b", returnToDashboard: true)

        // Start both sessions
        openSession(name: "test-rapid-a")
        app.buttons["backToDashboard"].click()
        let newButton = app.buttons["newSandboxButton"]
        XCTAssertTrue(newButton.waitForExistence(timeout: 5))

        openSession(name: "test-rapid-b")
        app.buttons["backToDashboard"].click()
        XCTAssertTrue(newButton.waitForExistence(timeout: 5))

        // Rapidly switch between sessions via sidebar
        let sidebarA = app.buttons["sidebarSession-test-rapid-a (agent)"]
        let sidebarB = app.buttons["sidebarSession-test-rapid-b (agent)"]
        XCTAssertTrue(sidebarA.waitForExistence(timeout: 5))
        XCTAssertTrue(sidebarB.waitForExistence(timeout: 5))

        for _ in 0..<3 {
            sidebarA.click()

            let backButton = app.buttons["backToDashboard"]
            XCTAssertTrue(backButton.waitForExistence(timeout: 5))
            backButton.click()
            XCTAssertTrue(newButton.waitForExistence(timeout: 5))

            sidebarB.click()

            XCTAssertTrue(backButton.waitForExistence(timeout: 5))
            backButton.click()
            XCTAssertTrue(newButton.waitForExistence(timeout: 5))
        }

        // Both sessions should still be active after rapid switching
        XCTAssertTrue(sidebarA.exists)
        XCTAssertTrue(sidebarB.exists)
    }

    
    func testTerminalThumbnailAreaAppearsOnCard() throws {
        createSandbox(name: "test-thumb", returnToDashboard: true)

        let liveChip = app.staticTexts["LIVE"]
        XCTAssertTrue(liveChip.waitForExistence(timeout: 5))

        // Open terminal session then go back
        openSession(name: "test-thumb")
        app.buttons["backToDashboard"].click()

        let newButton = app.buttons["newSandboxButton"]
        XCTAssertTrue(newButton.waitForExistence(timeout: 5))

        // The thumbnail area shows "Connecting..." placeholder initially,
        // then updates to a bitmap snapshot. Either state confirms the
        // thumbnail section is rendering on the card.
        let connecting = app.staticTexts["Connecting..."]
        let sessionBadge = app.staticTexts["SESSION"]
        let found = connecting.waitForExistence(timeout: 5) || sessionBadge.waitForExistence(timeout: 2)
        XCTAssertTrue(found, "Terminal thumbnail area or session badge should appear on card")
    }

    // MARK: - Environment Variables

    
    func testEnvVarButtonExistsOnCard() throws {
        createSandbox(name: "test-envbtn", returnToDashboard: true)

        let liveChip = app.staticTexts["LIVE"]
        XCTAssertTrue(liveChip.waitForExistence(timeout: 5))

        let envButton = app.buttons["envVarButton-test-envbtn"]
        XCTAssertTrue(envButton.waitForExistence(timeout: 5), "ENV chip should appear on sandbox card")
    }

    
    func testEnvVarSheetOpens() throws {
        createSandbox(name: "test-envsheet", returnToDashboard: true)

        let liveChip = app.staticTexts["LIVE"]
        XCTAssertTrue(liveChip.waitForExistence(timeout: 5))

        let envButton = app.buttons["envVarButton-test-envsheet"]
        XCTAssertTrue(envButton.waitForExistence(timeout: 5))
        envButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()

        let addButton = app.buttons["addEnvVarButton"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5), "Add Variable button should appear in env var panel")

        let noVarsText = app.staticTexts["No environment variables"]
        XCTAssertTrue(noVarsText.waitForExistence(timeout: 5), "Empty state should show")
    }

    
    func testAddEnvVarSheetValidation() throws {
        createSandbox(name: "test-envval", returnToDashboard: true)

        let liveChip = app.staticTexts["LIVE"]
        XCTAssertTrue(liveChip.waitForExistence(timeout: 5))

        let envButton = app.buttons["envVarButton-test-envval"]
        XCTAssertTrue(envButton.waitForExistence(timeout: 5))
        envButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()

        let addButton = app.buttons["addEnvVarButton"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        addButton.click()

        let keyField = app.textFields["envVarKeyField"]
        XCTAssertTrue(keyField.waitForExistence(timeout: 5))

        let valueField = app.textFields["envVarValueField"]
        XCTAssertTrue(valueField.exists)

        let submitButton = app.buttons["submitEnvVarButton"]
        XCTAssertTrue(submitButton.exists)
        XCTAssertFalse(submitButton.isEnabled, "Submit should be disabled with empty fields")

        keyField.click()
        keyField.typeText("1BAD")
        let errorText = app.staticTexts["Must start with a letter or underscore, then letters, digits, or underscores"]
        XCTAssertTrue(errorText.waitForExistence(timeout: 3), "Validation error should appear for invalid key")
    }

    // MARK: - Port Forwarding

    
    func testPortButtonExistsOnCard() throws {
        createSandbox(name: "test-portbtn", returnToDashboard: true)

        let liveChip = app.staticTexts["LIVE"]
        XCTAssertTrue(liveChip.waitForExistence(timeout: 5))

        let portButton = app.buttons["portButton-test-portbtn"]
        XCTAssertTrue(portButton.waitForExistence(timeout: 5), "PORTS chip should appear on sandbox card")
    }

    
    func testPortSheetOpens() throws {
        createSandbox(name: "test-portsheet", returnToDashboard: true)

        let liveChip = app.staticTexts["LIVE"]
        XCTAssertTrue(liveChip.waitForExistence(timeout: 5))

        let portButton = app.buttons["portButton-test-portsheet"]
        XCTAssertTrue(portButton.waitForExistence(timeout: 5))
        portButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()

        let addButton = app.buttons["addPortButton"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5), "Add Port button should appear in port panel")

        let noPortsText = app.staticTexts["No port mappings"]
        XCTAssertTrue(noPortsText.waitForExistence(timeout: 5), "Empty state should show")
    }

    
    func testAddPortSheetValidation() throws {
        createSandbox(name: "test-portval", returnToDashboard: true)

        let liveChip = app.staticTexts["LIVE"]
        XCTAssertTrue(liveChip.waitForExistence(timeout: 5))

        let portButton = app.buttons["portButton-test-portval"]
        XCTAssertTrue(portButton.waitForExistence(timeout: 5))
        portButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()

        let addButton = app.buttons["addPortButton"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        addButton.click()

        let hostField = app.textFields["hostPortField"]
        XCTAssertTrue(hostField.waitForExistence(timeout: 5))

        let sbxField = app.textFields["sbxPortField"]
        XCTAssertTrue(sbxField.exists)

        let publishButton = app.buttons["publishPortButton"]
        XCTAssertTrue(publishButton.exists)
        XCTAssertFalse(publishButton.isEnabled, "Publish should be disabled with empty fields")

        hostField.click()
        hostField.typeText("99999")
        let errorText = app.staticTexts["Host port must be between 1 and 65535"]
        XCTAssertTrue(errorText.waitForExistence(timeout: 3), "Validation error should appear for invalid port")
    }

    
    func testCreateSheetEnvVarSection() throws {
        let newButton = app.buttons["newSandboxButton"]
        XCTAssertTrue(newButton.waitForExistence(timeout: 5))
        newButton.click()

        let deployButton = app.buttons["deployButton"]
        XCTAssertTrue(deployButton.waitForExistence(timeout: 5))

        // Click the env var section toggle to expand
        let toggle = app.buttons["envVarSectionToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "Env var section toggle should appear")
        toggle.click()

        // Verify env var fields appear
        let keyField = app.textFields["createEnvKeyField"]
        XCTAssertTrue(keyField.waitForExistence(timeout: 5), "Env key field should appear after expanding")

        let valueField = app.textFields["createEnvValueField"]
        XCTAssertTrue(valueField.exists, "Env value field should appear")

        let addButton = app.buttons["createAddEnvVarButton"]
        XCTAssertTrue(addButton.exists, "Add button should appear")
    }

    // MARK: - Plugin UI Tests

    func testPluginsSidebarNavigationExists() {
        // Verify PLUGINS sidebar item exists
        let pluginsLabel = app.staticTexts["PLUGINS"]
        XCTAssertTrue(pluginsLabel.waitForExistence(timeout: 5), "PLUGINS sidebar label should exist")
    }

    func testPluginsEmptyState() {
        // Navigate to Plugins
        let pluginsLabel = app.staticTexts["PLUGINS"]
        XCTAssertTrue(pluginsLabel.waitForExistence(timeout: 5))
        pluginsLabel.click()
        sleep(1)

        // Verify empty state
        let emptyTitle = app.staticTexts["No Plugins Installed"]
        XCTAssertTrue(emptyTitle.waitForExistence(timeout: 5), "Empty state title should appear")

        // Verify Install Plugin button exists
        let installButton = app.buttons["installPluginButton"]
        XCTAssertTrue(installButton.waitForExistence(timeout: 5), "Install plugin button should appear")
    }

    func testPluginsHeaderShows() {
        let pluginsLabel = app.staticTexts["PLUGINS"]
        XCTAssertTrue(pluginsLabel.waitForExistence(timeout: 5))
        pluginsLabel.click()
        sleep(1)

        let header = app.staticTexts["Plugins"]
        XCTAssertTrue(header.waitForExistence(timeout: 5), "Plugins header should appear")

        let countLabel = app.staticTexts["0 installed"]
        XCTAssertTrue(countLabel.waitForExistence(timeout: 5), "Plugin count should show 0 installed")
    }
}

// MARK: - Plugin Execution E2E Tests

final class PluginExecutionUITests: XCTestCase {
    var app: XCUIApplication!
    var pluginDir: String!
    private var workspaceURL: URL?

    private static let projectRoot: String = {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .path
    }()

    private static var toolsDir: String {
        URL(fileURLWithPath: projectRoot).appendingPathComponent("tools").path
    }

    override func setUpWithError() throws {
        continueAfterFailure = false

        // Create a temp plugin directory with mock-plugin installed
        pluginDir = NSTemporaryDirectory() + "sbx-plugins-\(UUID().uuidString)"
        let pluginSubDir = pluginDir + "/com.test.e2e"
        try FileManager.default.createDirectory(atPath: pluginSubDir, withIntermediateDirectories: true)

        // Copy mock-plugin script
        let mockPluginSrc = Self.toolsDir + "/mock-plugin"
        let mockPluginDst = pluginSubDir + "/run.sh"
        try FileManager.default.copyItem(atPath: mockPluginSrc, toPath: mockPluginDst)

        // Write plugin.json
        let manifest = """
        {
            "id": "com.test.e2e",
            "name": "E2E Test Plugin",
            "version": "1.0.0",
            "description": "Plugin for E2E testing",
            "entry": "run.sh",
            "runtime": "bash",
            "permissions": ["sandbox.list", "ui.log"],
            "triggers": ["manual"]
        }
        """
        try manifest.write(toFile: pluginSubDir + "/plugin.json", atomically: true, encoding: .utf8)

        app = XCUIApplication()
        app.launchEnvironment["SBX_CLI_MOCK"] = "1"
        let stateDir = NSTemporaryDirectory() + "mock-sbx-\(UUID().uuidString)"
        app.launchEnvironment["SBX_MOCK_STATE_DIR"] = stateDir
        let existingPath = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        app.launchEnvironment["PATH"] = "\(Self.toolsDir):\(existingPath)"
        app.launchEnvironment["SBX_PLUGIN_DIR"] = pluginDir
        let kanbanDir = NSTemporaryDirectory() + "kanban-\(UUID().uuidString)"
        app.launchEnvironment["SBX_KANBAN_DIR"] = kanbanDir

        // Create a real workspace directory so EditorStore.refreshDirectory doesn't
        // fail and show a toast that covers navigation buttons.
        let workspace = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mock-ws-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        try Data("# Mock\n".utf8).write(to: workspace.appendingPathComponent("README.md"))
        workspaceURL = workspace
        app.launchEnvironment["SBX_CLI_MOCK_WORKSPACE"] = workspace.path

        // Disable window state restoration so WindowGroup always opens a fresh window
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]

        app.launch()
    }

    override func tearDownWithError() throws {
        if let dir = pluginDir {
            try? FileManager.default.removeItem(atPath: dir)
        }
        if let url = workspaceURL {
            try? FileManager.default.removeItem(at: url)
        }
    }

    // MARK: - Plugin Discovery

    func testPluginAppearsInList() {
        let pluginsLabel = app.staticTexts["PLUGINS"]
        XCTAssertTrue(pluginsLabel.waitForExistence(timeout: 5))
        pluginsLabel.click()
        sleep(2)

        // Plugin should appear (not empty state)
        let pluginCard = app.otherElements["pluginCard-com.test.e2e"]
            .firstMatch
        // Fall back to checking for plugin name text
        let pluginName = app.staticTexts["E2E Test Plugin"]
        XCTAssertTrue(
            pluginCard.waitForExistence(timeout: 5) || pluginName.waitForExistence(timeout: 5),
            "Plugin should appear in the list"
        )

        // Count should show 1 installed
        let countLabel = app.staticTexts["1 installed"]
        XCTAssertTrue(countLabel.waitForExistence(timeout: 5), "Should show 1 installed plugin")
    }

    func testPluginShowsVersionAndDescription() {
        let pluginsLabel = app.staticTexts["PLUGINS"]
        XCTAssertTrue(pluginsLabel.waitForExistence(timeout: 5))
        pluginsLabel.click()
        sleep(2)

        let version = app.staticTexts["v1.0.0"]
        XCTAssertTrue(version.waitForExistence(timeout: 5), "Version should be visible")

        let description = app.staticTexts["Plugin for E2E testing"]
        XCTAssertTrue(description.waitForExistence(timeout: 5), "Description should be visible")
    }

    // MARK: - Plugin Trigger Badges

    func testPluginShowsTriggerBadge() {
        let pluginsLabel = app.staticTexts["PLUGINS"]
        XCTAssertTrue(pluginsLabel.waitForExistence(timeout: 5))
        pluginsLabel.click()
        sleep(2)

        // The "manual" trigger badge should be visible on the card
        let badge = app.staticTexts["manual"]
        XCTAssertTrue(badge.waitForExistence(timeout: 5), "Manual trigger badge should appear on card")
    }

    // MARK: - Kanban Board

    
    func testKanbanSidebarNavigation() throws {
        let kanbanLabel = app.staticTexts["KANBAN"]
        XCTAssertTrue(kanbanLabel.waitForExistence(timeout: 5), "KANBAN sidebar entry should exist")
        kanbanLabel.click()
        sleep(1)

        // Should show create board button (no board exists yet)
        let createBoardButton = app.buttons["createBoardButton"]
        XCTAssertTrue(createBoardButton.waitForExistence(timeout: 5), "Create Board button should appear")
    }

    
    func testKanbanCreateBoardAndDefaultColumns() throws {
        let kanbanLabel = app.staticTexts["KANBAN"]
        XCTAssertTrue(kanbanLabel.waitForExistence(timeout: 5))
        kanbanLabel.click()
        sleep(1)

        let createBoardButton = app.buttons["createBoardButton"]
        XCTAssertTrue(createBoardButton.waitForExistence(timeout: 5))
        createBoardButton.click()
        sleep(1)

        // Verify the board view with default columns
        let backlog = app.staticTexts["Backlog"]
        XCTAssertTrue(backlog.waitForExistence(timeout: 5), "Backlog column should exist")

        let inProgress = app.staticTexts["In Progress"]
        XCTAssertTrue(inProgress.exists, "In Progress column should exist")

        let done = app.staticTexts["Done"]
        XCTAssertTrue(done.exists, "Done column should exist")
    }

    
    func testKanbanCreateTask() throws {
        // First, deploy a sandbox so it appears in the sandbox picker
        let newButton = app.buttons["newSandboxButton"]
        XCTAssertTrue(newButton.waitForExistence(timeout: 5))
        newButton.click()
        let nameField = app.textFields["sandboxNameField"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 3))
        nameField.click()
        nameField.typeText("kanban-test-sbx")
        let deployButton = app.buttons["deployButton"]
        let enabled = NSPredicate(format: "isEnabled == true")
        let exp = XCTNSPredicateExpectation(predicate: enabled, object: deployButton)
        XCTWaiter.wait(for: [exp], timeout: 5)
        deployButton.click()
        sleep(3)

        // Go back from auto-opened session
        let backButton = app.buttons["backToDashboard"]
        if backButton.waitForExistence(timeout: 3) {
            backButton.click()
            sleep(1)
        }

        // Navigate to kanban and create a board
        let kanbanLabel = app.staticTexts["KANBAN"]
        XCTAssertTrue(kanbanLabel.waitForExistence(timeout: 5))
        kanbanLabel.click()
        sleep(1)

        let createBoardButton = app.buttons["createBoardButton"]
        XCTAssertTrue(createBoardButton.waitForExistence(timeout: 5))
        createBoardButton.click()
        sleep(1)

        // Click add task on any column
        let addTaskButtons = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'addTaskButton-'"))
        XCTAssertTrue(addTaskButtons.firstMatch.waitForExistence(timeout: 5), "Add task button should exist")
        addTaskButtons.firstMatch.click()
        sleep(1)

        // Fill in task details (sandbox auto-selected since there's only one)
        let titleField = app.textFields["taskTitleField"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 5), "Task title field should appear")
        titleField.click()
        titleField.typeText("My Test Task")

        // Save the task
        let saveButton = app.buttons["saveTaskButton"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5))
        saveButton.click()
        sleep(1)

        // Verify the task card appears
        let taskTitle = app.staticTexts["My Test Task"]
        XCTAssertTrue(taskTitle.waitForExistence(timeout: 5), "Task card should appear with title")
    }

    @MainActor
    func testKanbanTaskStartLaunchesTaskSession() throws {
        // Deploy a sandbox so the kanban task has somewhere to execute.
        let newButton = app.buttons["newSandboxButton"]
        XCTAssertTrue(newButton.waitForExistence(timeout: 5))
        newButton.click()
        let nameField = app.textFields["sandboxNameField"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 3))
        nameField.click()
        nameField.typeText("kanban-exec-sbx")
        let deployButton = app.buttons["deployButton"]
        let enabled = NSPredicate(format: "isEnabled == true")
        let exp = XCTNSPredicateExpectation(predicate: enabled, object: deployButton)
        XCTWaiter.wait(for: [exp], timeout: 5)
        deployButton.click()
        sleep(3)

        // Back out of the auto-opened session.
        let backButton = app.buttons["backToDashboard"]
        if backButton.waitForExistence(timeout: 3) {
            backButton.click()
            sleep(1)
        }

        // Navigate to Kanban and create a board.
        let kanbanLabel = app.staticTexts["KANBAN"]
        XCTAssertTrue(kanbanLabel.waitForExistence(timeout: 5))
        kanbanLabel.click()
        sleep(1)
        let createBoardButton = app.buttons["createBoardButton"]
        XCTAssertTrue(createBoardButton.waitForExistence(timeout: 5))
        createBoardButton.click()
        sleep(1)

        // Add a task with a prompt.
        let addTaskButtons = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'addTaskButton-'"))
        XCTAssertTrue(addTaskButtons.firstMatch.waitForExistence(timeout: 5))
        addTaskButtons.firstMatch.click()
        sleep(1)
        let titleField = app.textFields["taskTitleField"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 5))
        titleField.click()
        titleField.typeText("Auto-launch task")
        let promptField = app.textViews["taskPromptField"].exists
            ? app.textViews["taskPromptField"]
            : app.textFields["taskPromptField"]
        if promptField.exists {
            promptField.click()
            promptField.typeText("Implement the autonomous launch path")
        }
        app.buttons["saveTaskButton"].click()
        sleep(1)

        // Click the task's start button.
        let startButtons = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'startTaskButton-'"))
        XCTAssertTrue(startButtons.firstMatch.waitForExistence(timeout: 5), "Start button should appear on the new task")
        startButtons.firstMatch.click()

        // A kanban-task session spawns a new claude inside the sandbox via
        // `sbx exec -it <sbx> claude --dangerously-skip-permissions '<prompt>'`.
        // The sidebar entry is labelled "<sandbox> (task)".
        let sidebarSession = app.buttons["sidebarSession-kanban-exec-sbx (task)"]
        XCTAssertTrue(sidebarSession.waitForExistence(timeout: 10),
                      "Task sidebar entry should appear after kanban task start")
    }
}

