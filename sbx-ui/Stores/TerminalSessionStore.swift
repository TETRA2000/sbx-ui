import Foundation
import AppKit
@preconcurrency import SwiftTerm

struct TerminalSession {
    let sandboxName: String
    let terminalView: FocusableTerminalView
    let startTime: Date
    var connected: Bool
}

@MainActor @Observable
final class TerminalSessionStore {
    private(set) var activeSessions: [String: TerminalSession] = [:]
    var error: String?

    private let service: any SbxServiceProtocol

    init(service: any SbxServiceProtocol) {
        self.service = service
    }

    var activeSessionNames: [String] {
        activeSessions.keys.sorted()
    }

    var activeSessionCount: Int {
        activeSessions.count
    }

    func session(for name: String) -> TerminalSession? {
        activeSessions[name]
    }

    func isActive(name: String) -> Bool {
        activeSessions[name] != nil
    }

    /// Returns existing terminal view if session exists, or creates a new one.
    func startSession(name: String) -> FocusableTerminalView {
        if let existing = activeSessions[name] {
            appLog(.info, "PTY", "Reattaching existing session: \(name)")
            return existing.terminalView
        }

        appLog(.info, "PTY", "Starting new session: \(name)")
        let terminalView = FocusableTerminalView(frame: .zero)
        terminalView.nativeBackgroundColor = NSColor(
            red: 0x0E / 255.0,
            green: 0x0E / 255.0,
            blue: 0x0E / 255.0,
            alpha: 1.0
        )
        terminalView.nativeForegroundColor = .white
        terminalView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)

        let shellPath = "/bin/zsh"
        let args = ["-c", "sbx run \(name)"]
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

        terminalView.startProcess(executable: shellPath, args: args, environment: env, execName: nil)
        appLog(.debug, "PTY", "Started process via terminalView.startProcess for: \(name)")

        let session = TerminalSession(
            sandboxName: name,
            terminalView: terminalView,
            startTime: Date(),
            connected: true
        )
        activeSessions[name] = session
        return terminalView
    }

    func disconnect(name: String) {
        guard activeSessions[name] != nil else { return }
        appLog(.info, "PTY", "Disconnecting session: \(name)")
        activeSessions.removeValue(forKey: name)
    }

    func disconnectAll() {
        for name in activeSessions.keys {
            disconnect(name: name)
        }
    }

    /// Remove sessions whose sandbox is no longer running.
    func cleanupStaleSessions(sandboxes: [Sandbox]) {
        let runningNames = Set(sandboxes.filter { $0.status == .running }.map(\.name))
        for name in activeSessions.keys {
            if !runningNames.contains(name) {
                appLog(.info, "PTY", "Cleaning up stale session: \(name)")
                activeSessions.removeValue(forKey: name)
            }
        }
    }

    func sendMessage(_ message: String, to name: String) async throws {
        guard activeSessions[name] != nil else { return }
        try await service.sendMessage(name: name, message: message)
    }
}
