import Foundation
import AppKit
@preconcurrency import SwiftTerm

// MARK: - Process Launcher Abstraction

protocol TerminalProcessLauncher {
    func launch(on terminalView: FocusableTerminalView, sandboxName: String, sessionType: SessionType, initialPrompt: String?)
}

/// Single-quote a string for safe inclusion in a /bin/zsh -c command line.
/// Wraps the value in single quotes and escapes any embedded single quotes
/// using the standard `'\''` shell idiom.
func shellSingleQuote(_ value: String) -> String {
    "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
}

struct RealTerminalProcessLauncher: TerminalProcessLauncher {
    func launch(on terminalView: FocusableTerminalView, sandboxName: String, sessionType: SessionType, initialPrompt: String?) {
        let shellPath = "/bin/zsh"
        // In mock mode, `exec cat` keeps the PTY alive so UI tests can assert on session state.
        // In real mode, the process exits when sbx finishes, triggering onProcessExit → disconnect.
        let mockMode = ProcessInfo.processInfo.environment["SBX_CLI_MOCK"] == "1"
        let keepAlive = mockMode ? "; exec cat" : ""
        let quotedName = shellSingleQuote(sandboxName)
        let args: [String]
        switch sessionType {
        case .agent:
            args = ["-c", "sbx run \(quotedName)\(keepAlive)"]
        case .shell:
            args = ["-c", "sbx exec -it \(quotedName) bash\(keepAlive)"]
        case .kanbanTask:
            // Kanban tasks run through `sbx run <sandbox> -- '<prompt>'`.
            // sbx forwards args after `--` to its default
            // `claude --dangerously-skip-permissions` launch, so this becomes
            // `claude --dangerously-skip-permissions '<prompt>'` — claude
            // consumes the prompt from argv at startup, which avoids the Ink
            // TUI "bare \r not recognized as submit" problem. Each task
            // spawns its own fresh session.
            let trimmedPrompt = initialPrompt?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let promptSegment = trimmedPrompt.isEmpty ? "" : " -- \(shellSingleQuote(trimmedPrompt))"
            args = ["-c", "sbx run \(quotedName)\(promptSegment)\(keepAlive)"]
        }
        var env: [String] = []
        var hasTerm = false
        var resolvedPath = ""
        for (key, value) in ProcessInfo.processInfo.environment {
            if key == "PATH" {
                let extended = "/opt/homebrew/bin:/usr/local/bin:\(value)"
                env.append("\(key)=\(extended)")
                resolvedPath = extended
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

        // Verbose launch logging — the spawned shell is invisible until its
        // first byte of output reaches the terminal view, so when "nothing
        // happens" we want to see exactly what we tried to run, with what
        // env, and where `sbx` was discovered (or not).
        let scriptForLog = args.dropFirst().joined(separator: " ")
        appLog(.debug, "PTY", "Launching: \(shellPath) -c \(scriptForLog)")
        appLog(.debug, "PTY", "  type=\(sessionType.rawValue) sandbox=\(sandboxName) mock=\(mockMode)")
        appLog(.debug, "PTY", "  PATH=\(resolvedPath)")
        if let sbxPath = locateExecutable("sbx", searchPath: resolvedPath) {
            appLog(.debug, "PTY", "  resolved sbx → \(sbxPath)")
        } else {
            appLog(.warn, "PTY", "  `sbx` NOT FOUND on PATH — terminal will exit immediately")
        }

        terminalView.startProcess(executable: shellPath, args: args, environment: env, execName: nil)

        // After startProcess, the LocalProcess holds the spawned shell's PID.
        // Reading it confirms the fork/exec actually happened.
        let pid = terminalView.process.shellPid
        if pid > 0 {
            appLog(.debug, "PTY", "  spawned shell PID=\(pid)")
        } else {
            appLog(.warn, "PTY", "  startProcess returned without a PID — spawn may have failed")
        }
    }

    /// Resolve the absolute path of `name` against the given PATH string. Used
    /// only for diagnostic logging — returns nil if the binary is not on PATH
    /// or is not executable.
    private func locateExecutable(_ name: String, searchPath: String) -> String? {
        for dir in searchPath.split(separator: ":") {
            let candidate = "\(dir)/\(name)"
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }
}

// MARK: - Terminal Session

struct TerminalSession {
    let id: String
    let sandboxName: String
    let sessionType: SessionType
    let label: String
    let terminalView: FocusableTerminalView
    let startTime: Date
    var connected: Bool
}

@MainActor @Observable
final class TerminalSessionStore {
    private(set) var activeSessions: [String: TerminalSession] = [:]  // keyed by session ID
    private(set) var thumbnails: [String: NSImage] = [:]              // keyed by session ID
    var error: String?

    private let service: any SbxServiceProtocol
    private let processLauncher: any TerminalProcessLauncher
    private var shellCounters: [String: Int] = [:]

    init(service: any SbxServiceProtocol, processLauncher: any TerminalProcessLauncher = RealTerminalProcessLauncher()) {
        self.service = service
        self.processLauncher = processLauncher
    }

    var activeSessionIDs: [String] {
        activeSessions.values.sorted { $0.startTime < $1.startTime }.map(\.id)
    }

    var activeSessionCount: Int {
        activeSessions.count
    }

    func session(for sessionID: String) -> TerminalSession? {
        activeSessions[sessionID]
    }

    /// Check if any session exists for the given sandbox.
    func hasAnySession(sandboxName: String) -> Bool {
        activeSessions.values.contains { $0.sandboxName == sandboxName }
    }

    /// Find the agent session ID for a given sandbox, if one exists.
    func agentSessionID(for sandboxName: String) -> String? {
        activeSessions.values.first { $0.sandboxName == sandboxName && $0.sessionType == .agent }?.id
    }

    /// All sessions for a given sandbox.
    func sessions(for sandboxName: String) -> [TerminalSession] {
        activeSessions.values
            .filter { $0.sandboxName == sandboxName }
            .sorted { $0.startTime < $1.startTime }
    }

    /// Start a new session or reattach to an existing agent session.
    /// Agent sessions are idempotent (returns existing). Shell and kanban-task
    /// sessions always create new. `initialPrompt` is required for
    /// `.kanbanTask` (forwarded to the spawned `claude` as a positional
    /// argument) and is ignored for other session types.
    @discardableResult
    func startSession(sandboxName: String, type: SessionType, initialPrompt: String? = nil) -> (id: String, view: FocusableTerminalView) {
        // Agent sessions are idempotent — reattach if one already exists
        if type == .agent,
           let existing = activeSessions.values.first(where: { $0.sandboxName == sandboxName && $0.sessionType == .agent }) {
            appLog(.info, "PTY", "Reattaching existing agent session: \(sandboxName)")
            return (existing.id, existing.terminalView)
        }

        let sessionID = UUID().uuidString
        let label: String
        switch type {
        case .agent:
            label = "\(sandboxName) (agent)"
        case .shell:
            shellCounters[sandboxName, default: 0] += 1
            label = "\(sandboxName) (shell \(shellCounters[sandboxName]!))"
        case .kanbanTask:
            label = "\(sandboxName) (task)"
        }

        appLog(.info, "PTY", "Starting new \(type.rawValue) session: \(label)")
        let terminalView = FocusableTerminalView(frame: .zero)
        terminalView.nativeBackgroundColor = NSColor(
            red: 0x0E / 255.0,
            green: 0x0E / 255.0,
            blue: 0x0E / 255.0,
            alpha: 1.0
        )
        terminalView.nativeForegroundColor = .white
        terminalView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        terminalView.linkHighlightMode = .hover
        terminalView.notifyUpdateChanges = true  // enables rangeChanged for output quiescence detection
        terminalView.installLinkDelegate()

        terminalView.onProcessExit = { [weak self] exitCode in
            DispatchQueue.main.async {
                guard let self else { return }
                appLog(.info, "PTY", "Process exited for session: \(label) (code: \(exitCode.map(String.init) ?? "nil"))")
                self.disconnect(sessionID: sessionID)
            }
        }

        let promptForLaunch = (type == .kanbanTask) ? initialPrompt : nil
        processLauncher.launch(on: terminalView, sandboxName: sandboxName, sessionType: type, initialPrompt: promptForLaunch)
        if let promptForLaunch, !promptForLaunch.isEmpty {
            appLog(.debug, "PTY", "Launched process for: \(label) (with initial prompt, \(promptForLaunch.count) chars)")
        } else {
            appLog(.debug, "PTY", "Launched process for: \(label)")
        }

        let session = TerminalSession(
            id: sessionID,
            sandboxName: sandboxName,
            sessionType: type,
            label: label,
            terminalView: terminalView,
            startTime: Date(),
            connected: true
        )
        activeSessions[sessionID] = session
        return (sessionID, terminalView)
    }

    func disconnect(sessionID: String) {
        guard let session = activeSessions[sessionID] else { return }
        appLog(.info, "PTY", "Disconnecting session: \(session.label)")
        activeSessions.removeValue(forKey: sessionID)
        thumbnails.removeValue(forKey: sessionID)
    }

    func disconnectAll() {
        let ids = Array(activeSessions.keys)
        for id in ids {
            disconnect(sessionID: id)
        }
    }

    /// Remove sessions whose sandbox is no longer running.
    func cleanupStaleSessions(sandboxes: [Sandbox]) {
        let runningNames = Set(sandboxes.filter { $0.status == .running }.map(\.name))
        let staleIDs = activeSessions.filter { !runningNames.contains($0.value.sandboxName) }.map(\.key)
        for id in staleIDs {
            appLog(.info, "PTY", "Cleaning up stale session: \(activeSessions[id]?.label ?? id)")
            activeSessions.removeValue(forKey: id)
            thumbnails.removeValue(forKey: id)
        }
        // Clean up shell counters for sandboxes that no longer have sessions
        let activeSandboxNames = Set(activeSessions.values.map(\.sandboxName))
        shellCounters = shellCounters.filter { activeSandboxNames.contains($0.key) }
    }

    /// Capture bitmap snapshots of all active terminal views.
    func captureSnapshots() {
        for (id, session) in activeSessions {
            let view = session.terminalView
            var captureRect = view.bounds
            let needsTempFrame = captureRect.width == 0 || captureRect.height == 0

            if needsTempFrame {
                view.frame = NSRect(origin: .zero, size: NSSize(width: 800, height: 600))
                view.layoutSubtreeIfNeeded()
                captureRect = view.bounds
            }

            guard captureRect.width > 0, captureRect.height > 0,
                  let bitmapRep = view.bitmapImageRepForCachingDisplay(in: captureRect) else {
                if needsTempFrame { view.frame = .zero }
                continue
            }

            view.cacheDisplay(in: captureRect, to: bitmapRep)
            if needsTempFrame { view.frame = .zero }

            let image = NSImage(size: captureRect.size)
            image.addRepresentation(bitmapRep)
            thumbnails[id] = image
        }
    }

    /// Sends a message to the agent session's terminal, waiting for the terminal to quiesce
    /// (no output for `quietInterval` seconds) before typing. Caps total wait at `maxWait` seconds.
    func sendMessage(_ message: String, to sandboxName: String,
                     quietInterval: TimeInterval = 1.0, maxWait: TimeInterval = 30.0) {
        guard let sessionID = agentSessionID(for: sandboxName),
              let session = activeSessions[sessionID],
              session.connected else { return }
        let terminalView = session.terminalView
        Task { @MainActor in
            let deadline = Date().addingTimeInterval(maxWait)
            while Date() < deadline {
                let idle = Date().timeIntervalSince(terminalView.lastOutputAt)
                if idle >= quietInterval { break }
                try? await Task.sleep(for: .milliseconds(200))
            }
            terminalView.send(txt: message)
            appLog(.info, "PTY", "Sent text to \(sandboxName): \(message.prefix(80))")
            try? await Task.sleep(for: .milliseconds(300))
            terminalView.send(txt: "\r")
            appLog(.info, "PTY", "Sent Enter to \(sandboxName)")
        }
    }
}
