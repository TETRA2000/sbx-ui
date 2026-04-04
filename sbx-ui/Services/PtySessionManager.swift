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
        // Dispose existing session for this name
        if sessions[name] != nil {
            dispose(name: name)
        }

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
            let process = LocalProcess(delegate: terminalView)
            let shellPath = "/bin/zsh"
            let args = ["-c", "sbx run \(name)"]
            process.startProcess(executable: shellPath, args: args, environment: nil, execName: nil)
            sessions[name] = SessionEntry(process: process, emitter: nil, terminal: nil)
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
