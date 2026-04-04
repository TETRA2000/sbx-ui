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
    let ptyManager: PtySessionManager

    func makeNSView(context: Context) -> FocusableTerminalView {
        let terminalView = FocusableTerminalView(frame: .zero)
        terminalView.nativeBackgroundColor = NSColor(
            red: 0x0E / 255.0,
            green: 0x0E / 255.0,
            blue: 0x0E / 255.0,
            alpha: 1.0
        )
        terminalView.nativeForegroundColor = .white
        terminalView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)

        let name = sandboxName
        let manager = ptyManager
        DispatchQueue.main.async {
            manager.attach(name: name, terminalView: terminalView)
        }

        return terminalView
    }

    func updateNSView(_ nsView: FocusableTerminalView, context: Context) {
    }
}
