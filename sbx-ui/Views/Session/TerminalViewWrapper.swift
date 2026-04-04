import SwiftUI
@preconcurrency import SwiftTerm

/// LocalProcessTerminalView subclass that auto-focuses when added to a window.
class FocusableTerminalView: LocalProcessTerminalView {
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
    let sandboxName: String
    @Environment(TerminalSessionStore.self) private var sessionStore

    func makeNSView(context: Context) -> NSView {
        let container = NSView(frame: .zero)
        let terminalView = sessionStore.startSession(name: sandboxName)
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
