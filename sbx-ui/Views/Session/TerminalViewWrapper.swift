import SwiftUI
@preconcurrency import SwiftTerm

/// LocalProcessTerminalView subclass that auto-focuses when added to a window
/// and notifies when the spawned process terminates.
class FocusableTerminalView: LocalProcessTerminalView {
    /// Called when the PTY process exits (may fire on a background thread).
    var onProcessExit: ((_ exitCode: Int32?) -> Void)?

    override func processTerminated(_ source: LocalProcess, exitCode: Int32?) {
        super.processTerminated(source, exitCode: exitCode)
        onProcessExit?(exitCode)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            window.makeFirstResponder(self)
        }
    }
}

struct TerminalViewWrapper: NSViewRepresentable {
    let sessionID: String
    @Environment(TerminalSessionStore.self) private var sessionStore

    func makeNSView(context: Context) -> NSView {
        let container = NSView(frame: .zero)
        guard let session = sessionStore.session(for: sessionID) else {
            return container
        }
        let terminalView = session.terminalView
        terminalView.removeFromSuperview()
        terminalView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(terminalView)
        NSLayoutConstraint.activate([
            terminalView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            terminalView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            terminalView.topAnchor.constraint(equalTo: container.topAnchor),
            terminalView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: ()) {
        // Remove terminal from container but do NOT destroy it —
        // TerminalSessionStore retains the reference for background sessions.
        nsView.subviews.forEach { $0.removeFromSuperview() }
    }
}
