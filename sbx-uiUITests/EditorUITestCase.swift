import XCTest

/// Base class for editor UI tests. Builds a per-test temporary workspace
/// with a few fixture files, runs a real `git init` + `git add` + `git commit`
/// so `git status` reports meaningful changed-file entries, points
/// `SBX_CLI_MOCK_WORKSPACE` at it, then tears everything down in
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

        // Disable window state restoration so WindowGroup always opens a fresh window
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]

        // Seed a per-test temporary workspace, initialize a real git repo,
        // and commit the fixture files; then modify README so git status
        // reports at least one entry.
        let workspace = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("editor-ws-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        try Data("# README\n\nHello, editor!\n".utf8).write(to: workspace.appendingPathComponent("README.md"))
        try Data("let x = 42\n".utf8).write(to: workspace.appendingPathComponent("app.swift"))
        XCTAssertEqual(Self.runGit(in: workspace, ["init", "-q"]), 0, "git init failed")
        XCTAssertEqual(Self.runGit(in: workspace, ["config", "user.email", "test@example.com"]), 0)
        XCTAssertEqual(Self.runGit(in: workspace, ["config", "user.name", "Test"]), 0)
        XCTAssertEqual(Self.runGit(in: workspace, ["add", "README.md", "app.swift"]), 0, "git add failed")
        XCTAssertEqual(Self.runGit(in: workspace, ["commit", "-q", "-m", "init"]), 0, "git commit failed")
        // Produce one modified entry so the changed-files list is non-empty.
        try Data("# README\n\nHello, editor! (modified)\n".utf8)
            .write(to: workspace.appendingPathComponent("README.md"))
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

    func createSandboxAndEnter(name: String) {
        let newButton = app.buttons["newSandboxButton"]
        XCTAssertTrue(newButton.waitForExistence(timeout: 5), "newSandboxButton did not appear")
        newButton.click()
        sleep(2) // wait for onAppear to set mock workspace
        let nameField = app.textFields["sandboxNameField"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5), "sandboxNameField did not appear")
        nameField.click()
        nameField.typeText(name)
        let deployButton = app.buttons["deployButton"]
        let enabled = NSPredicate(format: "isEnabled == true")
        let exp = XCTNSPredicateExpectation(predicate: enabled, object: deployButton)
        XCTWaiter.wait(for: [exp], timeout: 5)
        deployButton.click()
    }

    /// Path to a real git binary. `/usr/bin/git` is an xcrun shim which fails
    /// inside the XCUITest runner's app sandbox, so we resolve to Homebrew's
    /// git if available.
    private static let gitBinary: URL = {
        let candidates = [
            "/opt/homebrew/bin/git",
            "/usr/local/bin/git",
            "/usr/bin/git"
        ]
        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        return URL(fileURLWithPath: "/usr/bin/git")
    }()

    @discardableResult
    private static func runGit(in dir: URL, _ args: [String]) -> Int32 {
        let process = Process()
        process.currentDirectoryURL = dir
        process.executableURL = gitBinary
        process.arguments = args
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        do {
            try process.run()
        } catch {
            NSLog("EditorUITestCase.runGit launch failed for \(args): \(error)")
            return -1
        }
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            let errString = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            NSLog("EditorUITestCase.runGit \(args) exited \(process.terminationStatus): \(errString)")
        }
        return process.terminationStatus
    }
}
