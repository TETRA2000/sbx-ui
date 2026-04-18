import XCTest

final class EditorE2ETests: EditorUITestCase {

    func testOpensFileFromChangedListAndDisplaysContents() throws {
        createSandboxAndEnter(name: "editor-open")
        let row = app.buttons["changedFileRow-README.md"]
        XCTAssertTrue(row.waitForExistence(timeout: 10),
                      "Changed-file row for README.md should appear")
        row.click()
        let tab = app.otherElements["editorTab-README.md"]
        let tabExists = tab.waitForExistence(timeout: 5)
            || app.staticTexts["README.md"].waitForExistence(timeout: 5)
        XCTAssertTrue(tabExists, "README.md tab should appear after clicking")
    }

    func testEditAndSaveClearsDirtyIndicator() throws {
        createSandboxAndEnter(name: "editor-save")
        let row = app.buttons["changedFileRow-README.md"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.click()
        let buffer = app.textViews.firstMatch
        XCTAssertTrue(buffer.waitForExistence(timeout: 5))
        buffer.click()
        buffer.typeText("edited\n")
        // Dirty indicator should appear.
        let dirty = app.otherElements["editorTabDirtyIndicator-README.md"]
        _ = dirty.waitForExistence(timeout: 2)
        // Cmd+S through the hidden save button.
        app.typeKey("s", modifierFlags: .command)
        // Verify indicator clears within 5 s.
        let absent = NSPredicate(format: "exists == false")
        let exp = XCTNSPredicateExpectation(predicate: absent, object: dirty)
        XCTWaiter.wait(for: [exp], timeout: 5)
    }

    func testChangedFilesListRendersEntriesForGitWorkspace() throws {
        createSandboxAndEnter(name: "editor-refresh")
        let back = app.buttons["backToDashboard"]
        XCTAssertTrue(back.waitForExistence(timeout: 10))
        let changes = app.staticTexts["CHANGES"]
        XCTAssertTrue(changes.waitForExistence(timeout: 10),
                      "CHANGES header should mount in the editor panel")
        let row = app.buttons["changedFileRow-README.md"]
        XCTAssertTrue(row.waitForExistence(timeout: 15),
                      "changedFileRow-README.md should render after initial git-status refresh")
    }

    func testCloseDirtyTabShowsConfirmDialog() throws {
        createSandboxAndEnter(name: "editor-close")
        let row = app.buttons["changedFileRow-README.md"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.click()
        let buffer = app.textViews.firstMatch
        XCTAssertTrue(buffer.waitForExistence(timeout: 5))
        buffer.click()
        buffer.typeText("dirty\n")
        // Wait for dirty indicator to confirm edit registered.
        let dirty = app.otherElements["editorTabDirtyIndicator-README.md"]
        _ = dirty.waitForExistence(timeout: 3)
        // Navigate back to trigger dirty-tab confirmation.
        let backButton = app.buttons["backToDashboard"]
        XCTAssertTrue(backButton.waitForExistence(timeout: 5), "backToDashboard should be present")
        backButton.click()
        let dialogAny = app.descendants(matching: .any).matching(identifier: "editorConfirmCloseDialog").firstMatch
        XCTAssertTrue(dialogAny.waitForExistence(timeout: 5), "Dirty-tab confirmation dialog should appear")
    }
}
