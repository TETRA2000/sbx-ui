import Foundation
import AppKit

struct ExternalTerminalLauncher: ExternalTerminalProtocol {

    func detectAvailable() async -> [TerminalApp] {
        var available: [TerminalApp] = [.terminal]
        if NSWorkspace.shared.urlForApplication(withBundleIdentifier: TerminalApp.iterm.bundleIdentifier) != nil {
            available.append(.iterm)
        }
        return available
    }

    func openShell(sandboxName: String, app: TerminalApp) async throws {
        guard SbxValidation.isValidName(sandboxName) else {
            throw SbxServiceError.invalidName(sandboxName)
        }

        let escapedName = sandboxName
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let script: String
        switch app {
        case .terminal:
            script = """
            tell application "Terminal"
                activate
                do script "sbx exec -it \(escapedName) bash"
            end tell
            """
        case .iterm:
            script = """
            tell application "iTerm"
                activate
                create window with default profile command "sbx exec -it \(escapedName) bash"
            end tell
            """
        }

        let appleScript = NSAppleScript(source: script)
        var errorDict: NSDictionary?
        appleScript?.executeAndReturnError(&errorDict)
        if let error = errorDict {
            let message = error[NSAppleScript.errorMessage] as? String ?? "Unknown error"
            throw SbxServiceError.cliError("Failed to launch \(app.displayName): \(message)")
        }
    }
}
