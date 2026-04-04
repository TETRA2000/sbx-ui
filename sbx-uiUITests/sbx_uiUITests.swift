import XCTest

final class sbx_uiUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["SBX_MOCK"] = "1"
        app.launch()
    }

    // MARK: - App launches in mock mode

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

    // MARK: - Project creation

    @MainActor
    func testNewSandboxCard() throws {
        let newButton = app.buttons["newSandboxButton"]
        XCTAssertTrue(newButton.waitForExistence(timeout: 5))
        newButton.click()

        let deploySubmit = app.buttons["deployButton"]
        XCTAssertTrue(deploySubmit.waitForExistence(timeout: 3))
    }

    // MARK: - Policies

    @MainActor
    func testNavigateToPolicies() throws {
        let policies = app.staticTexts["POLICIES"]
        XCTAssertTrue(policies.waitForExistence(timeout: 5))
        policies.click()

        let addButton = app.buttons["addPolicyButton"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
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
    }
}
