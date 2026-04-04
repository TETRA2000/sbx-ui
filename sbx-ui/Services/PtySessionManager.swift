import Foundation
import AppKit
@preconcurrency import SwiftTerm

@MainActor @Observable
final class PtySessionManager {
    private var sessions: [String: SessionEntry] = [:]

    struct SessionEntry {
        let process: LocalProcess?
        let emitter: MockPtyEmitter?
        let terminal: Terminal?
    }

    func attach(name: String, terminalView: LocalProcessTerminalView, isMock: Bool) {
        appLog(.info, "PTY", "Attaching session: \(name) (mode: \(isMock ? "mock" : "real"))")
        // Dispose existing session for this name
        if sessions[name] != nil {
            dispose(name: name)
        }

        appLog(.debug, "PTY", "Terminal view: \(terminalView), window: \(String(describing: terminalView.window))")

        if isMock {
            let emitter = MockPtyEmitter()
            let terminal = terminalView.getTerminal()
            emitter.onData { [weak terminal, weak terminalView] data in
                guard let terminal else { return }
                let bytes = Array(data.utf8)
                terminal.feed(byteArray: bytes)
                DispatchQueue.main.async { [weak terminalView] in
                    guard let view = terminalView else { return }
                    view.setNeedsDisplay(view.bounds)
                }
            }
            sessions[name] = SessionEntry(process: nil, emitter: emitter, terminal: terminal)
        } else {
            let shellPath = "/bin/zsh"
            let args = ["-c", "sbx run \(name)"]
            // Extend PATH so sbx is found (GUI apps miss /opt/homebrew/bin)
            var env: [String] = []
            for (key, value) in ProcessInfo.processInfo.environment {
                if key == "PATH" {
                    let extended = "/opt/homebrew/bin:/usr/local/bin:\(value)"
                    env.append("\(key)=\(extended)")
                } else {
                    env.append("\(key)=\(value)")
                }
            }
            // Use startProcess on the terminal view directly so keyboard input
            // is routed to the PTY process via LocalProcessTerminalView.send()
            terminalView.startProcess(executable: shellPath, args: args, environment: env, execName: nil)
            appLog(.debug, "PTY", "Started process via terminalView.startProcess for: \(name)")
            sessions[name] = SessionEntry(process: nil, emitter: nil, terminal: nil)
        }
    }

    func write(name: String, data: String) {
        guard let session = sessions[name] else { return }
        if let emitter = session.emitter {
            emitter.write(data)
        } else if let process = session.process {
            let bytes = ArraySlice(Array((data + "\n").utf8))
            process.send(data: bytes)
        }
    }

    func dispose(name: String) {
        guard let session = sessions[name] else { return }
        appLog(.info, "PTY", "Disposing session: \(name)")
        session.emitter?.dispose()
        sessions.removeValue(forKey: name)
    }

    func disposeAll() {
        for name in sessions.keys {
            dispose(name: name)
        }
    }

    func isAttached(name: String) -> Bool {
        sessions[name] != nil
    }
}
