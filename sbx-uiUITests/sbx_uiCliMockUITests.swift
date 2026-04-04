import XCTest

/// E2E tests using the mock-sbx bash CLI emulator instead of the in-memory MockSbxService.
/// These tests exercise the real RealSbxService → CliExecutor → mock-sbx pipeline.
final class sbx_uiCliMockUITests: XCTestCase {
    var app: XCUIApplication!

    /// Derive the project root from this source file's compile-time path.
    /// This file is at: <project_root>/sbx-uiUITests/sbx_uiCliMockUITests.swift
    /// Tools are at: <project_root>/tools/
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

        // Use CLI mock mode (NOT SBX_MOCK=1 — we want RealSbxService)
        app.launchEnvironment["SBX_CLI_MOCK"] = "1"

        // Unique state directory for this test run
        let stateDir = NSTemporaryDirectory() + "mock-sbx-\(UUID().uuidString)"
        app.launchEnvironment["SBX_MOCK_STATE_DIR"] = stateDir

        // Put tools/ directory on PATH so /usr/bin/env sbx finds mock-sbx
        let existingPath = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        app.launchEnvironment["PATH"] = "\(Self.toolsDir):\(existingPath)"

        app.launch()
    }

    // MARK: - Sandbox Lifecycle via CLI Mock

    @MainActor
    func testAppLaunchesWithCliMock() throws {
        XCTAssertTrue(app.windows.firstMatch.exists)
    }

    @MainActor
    func testSidebarExists() throws {
        let dashboard = app.staticTexts["DASHBOARD"]
        XCTAssertTrue(dashboard.waitForExistence(timeout: 5))
    }

    @MainActor
    private func createSandbox(name: String) {
        let newButton = app.buttons["newSandboxButton"]
        XCTAssertTrue(newButton.waitForExistence(timeout: 5))
        newButton.click()

        let nameField = app.textFields["sandboxNameField"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 3))
        sleep(1)

        nameField.click()
        nameField.typeText(name)

        let deployButton = app.buttons["deployButton"]
        XCTAssertTrue(deployButton.waitForExistence(timeout: 3))
        let enabled = NSPredicate(format: "isEnabled == true")
        let exp = XCTNSPredicateExpectation(predicate: enabled, object: deployButton)
        let result = XCTWaiter.wait(for: [exp], timeout: 3)
        XCTAssertEqual(result, .completed)
        deployButton.click()
    }

    @MainActor
    func testCreateSandboxViaCliMock() throws {
        createSandbox(name: "cli-test")

        let liveChip = app.staticTexts["LIVE"]
        XCTAssertTrue(liveChip.waitForExistence(timeout: 10))

        let nameText = app.staticTexts["cli-test"]
        XCTAssertTrue(nameText.waitForExistence(timeout: 3))
    }

    // MARK: - Policy via CLI Mock

    @MainActor
    func testPolicyDefaultsViaCliMock() throws {
        let policies = app.staticTexts["POLICIES"]
        XCTAssertTrue(policies.waitForExistence(timeout: 5))
        policies.click()

        let addButton = app.buttons["addPolicyButton"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 8))

        let defaultRule = app.buttons["removePolicy-api.anthropic.com"]
        XCTAssertTrue(defaultRule.waitForExistence(timeout: 8))
    }

    @MainActor
    func testPolicyCRUDViaCliMock() throws {
        let policies = app.staticTexts["POLICIES"]
        XCTAssertTrue(policies.waitForExistence(timeout: 5))
        policies.click()

        let addButton = app.buttons["addPolicyButton"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 8))
        addButton.click()

        let domainInput = app.textFields["domainInput"]
        XCTAssertTrue(domainInput.waitForExistence(timeout: 3))
        domainInput.click()
        domainInput.typeText("cli-mock-test.example.com")

        let submitButton = app.buttons["submitPolicyButton"]
        submitButton.click()

        let removeButton = app.buttons["removePolicy-cli-mock-test.example.com"]
        XCTAssertTrue(removeButton.waitForExistence(timeout: 8))

        removeButton.click()
        let disappeared = removeButton.waitForNonExistence(timeout: 8)
        XCTAssertTrue(disappeared)
    }
}
