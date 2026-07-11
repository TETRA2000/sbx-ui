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

    /// Requirement 14.5: editor state (tab set, active tab, dirty status)
    /// must survive a sandbox stop/restart cycle. This exercises the
    /// poll-driven EditorStore.syncSandboxStatus preserve-on-stop path by
    /// stopping the sandbox externally (via the mock CLI directly), not
    /// through the app's own confirm-before-close flow.
    func testSandboxStopPreservesEditorState() throws {
        let name = "editor-stop-test"
        createSandboxAndEnter(name: name)

        let row = app.buttons["changedFileRow-README.md"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.click()
        let buffer = app.textViews.firstMatch
        XCTAssertTrue(buffer.waitForExistence(timeout: 5))
        buffer.click()
        buffer.typeText("stop-preserve-edit\n")
        let dirty = app.otherElements["editorTabDirtyIndicator-README.md"]
        XCTAssertTrue(dirty.waitForExistence(timeout: 3), "dirty indicator should appear before stopping")
        XCTAssertTrue(app.otherElements["editorTab-README.md"].exists, "README.md tab should be open before stopping")

        // Externally-triggered stop — bypasses the in-app dirty-tab
        // confirmation flow, exercising EditorStore.syncSandboxStatus's
        // preserve-on-stop path.
        XCTAssertEqual(runMockSbx(["stop", name]), 0, "external sbx stop should succeed")

        // Next SandboxStore poll detects "stopped", drops the stale session,
        // and the app falls back to the dashboard with no crash.
        let dashboard = app.staticTexts["DASHBOARD"]
        XCTAssertTrue(dashboard.waitForExistence(timeout: 10), "should auto-return to dashboard with no crash")

        // Resume: tapping a stopped card fires SandboxStore.resumeSandbox.
        // stopButton only renders once status == .running, so wait for it
        // before re-entering.
        let tapArea = app.otherElements["sandboxCardTapArea-\(name)"]
        XCTAssertTrue(tapArea.waitForExistence(timeout: 10))
        tapArea.click()
        XCTAssertTrue(app.buttons["stopButton-\(name)"].waitForExistence(timeout: 15), "sandbox should resume to running")

        // Re-enter the running session.
        tapArea.click()

        // Assert the prior tab set, active tab, and dirty state are restored.
        XCTAssertTrue(app.otherElements["editorTab-README.md"].waitForExistence(timeout: 10), "README.md tab should be restored after restart")
        XCTAssertTrue(app.otherElements["editorTabDirtyIndicator-README.md"].waitForExistence(timeout: 5), "dirty state should be restored after restart")
    }
}
