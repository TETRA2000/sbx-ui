import Foundation
import AppKit
@preconcurrency import SwiftTerm

@MainActor @Observable
final class PtySessionManager {
    private var sessions: Set<String> = []

    func attach(name: String, terminalView: LocalProcessTerminalView) {
        appLog(.info, "PTY", "Attaching session: \(name)")
        // Dispose existing session for this name
        if sessions.contains(name) {
            dispose(name: name)
        }

        appLog(.debug, "PTY", "Terminal view: \(terminalView), window: \(String(describing: terminalView.window))")

        let shellPath = "/bin/zsh"
        let args = ["-c", "sbx run \(name)"]
        // Build environment: extend PATH and set TERM for color support
        var env: [String] = []
        var hasTerm = false
        for (key, value) in ProcessInfo.processInfo.environment {
            if key == "PATH" {
                let extended = "/opt/homebrew/bin:/usr/local/bin:\(value)"
                env.append("\(key)=\(extended)")
            } else if key == "TERM" {
                env.append("TERM=xterm-256color")
                hasTerm = true
            } else {
                env.append("\(key)=\(value)")
            }
        }
        if !hasTerm {
            env.append("TERM=xterm-256color")
        }
        env.append("COLORTERM=truecolor")
        // Use startProcess on the terminal view directly so keyboard input
        // is routed to the PTY process via LocalProcessTerminalView.send()
        terminalView.startProcess(executable: shellPath, args: args, environment: env, execName: nil)
        appLog(.debug, "PTY", "Started process via terminalView.startProcess for: \(name)")
        sessions.insert(name)
    }

    func dispose(name: String) {
        guard sessions.contains(name) else { return }
        appLog(.info, "PTY", "Disposing session: \(name)")
        sessions.remove(name)
    }

    func disposeAll() {
        for name in sessions {
            dispose(name: name)
        }
    }

    func isAttached(name: String) -> Bool {
        sessions.contains(name)
    }
}
