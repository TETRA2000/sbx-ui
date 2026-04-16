import XCTest

/// Base class for editor UI tests. Builds a per-test temporary workspace
/// with a few fixture files, points `SBX_CLI_MOCK_WORKSPACE` at it so the
/// create-sandbox sheet auto-fills that path, then tears everything down in
/// `tearDownWithError`.
class EditorUITestCase: XCTestCase {
    var app: XCUIApplication!
    var workspaceURL: URL!

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
        app = XCUIApplication()

        app.launchEnvironment["SBX_CLI_MOCK"] = "1"

        let stateDir = NSTemporaryDirectory() + "mock-sbx-\(UUID().uuidString)"
        app.launchEnvironment["SBX_MOCK_STATE_DIR"] = stateDir

        let existingPath = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        app.launchEnvironment["PATH"] = "\(Self.toolsDir):\(existingPath)"

        let emptyPluginDir = NSTemporaryDirectory() + "empty-plugins-\(UUID().uuidString)"
        try? FileManager.default.createDirectory(atPath: emptyPluginDir, withIntermediateDirectories: true)
        app.launchEnvironment["SBX_PLUGIN_DIR"] = emptyPluginDir

        let kanbanDir = NSTemporaryDirectory() + "kanban-\(UUID().uuidString)"
        app.launchEnvironment["SBX_KANBAN_DIR"] = kanbanDir

        // Seed a per-test temporary workspace and point the sheet at it.
        let workspace = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("editor-ws-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        try Data("# README\n\nHello, editor!\n".utf8).write(to: workspace.appendingPathComponent("README.md"))
        try Data("let x = 42\n".utf8).write(to: workspace.appendingPathComponent("app.swift"))
        let gitDir = workspace.appendingPathComponent(".git", isDirectory: true)
        try FileManager.default.createDirectory(at: gitDir, withIntermediateDirectories: true)
        try Data("ignored\n".utf8).write(to: gitDir.appendingPathComponent("HEAD"))
        self.workspaceURL = workspace
        app.launchEnvironment["SBX_CLI_MOCK_WORKSPACE"] = workspace.path

        app.launch()
    }

    override func tearDownWithError() throws {
        if let workspaceURL {
            try? FileManager.default.removeItem(at: workspaceURL)
        }
    }

    // MARK: - Flow helpers

    @MainActor
    func createSandboxAndEnter(name: String) {
        app.buttons["newSandboxButton"].click()
        sleep(2) // wait for onAppear to set mock workspace
        let nameField = app.textFields["sandboxNameField"]
        nameField.click()
        nameField.typeText(name)
        let deployButton = app.buttons["deployButton"]
        let enabled = NSPredicate(format: "isEnabled == true")
        let exp = XCTNSPredicateExpectation(predicate: enabled, object: deployButton)
        XCTWaiter.wait(for: [exp], timeout: 5)
        deployButton.click()
    }
}
