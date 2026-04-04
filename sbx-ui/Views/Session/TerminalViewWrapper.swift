import SwiftUI
@preconcurrency import SwiftTerm

struct TerminalViewWrapper: NSViewRepresentable {
    let sandboxName: String
    let isMock: Bool
    let ptyManager: PtySessionManager

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        let terminalView = LocalProcessTerminalView(frame: .zero)
        terminalView.nativeBackgroundColor = NSColor(
            red: 0x0E / 255.0,
            green: 0x0E / 255.0,
            blue: 0x0E / 255.0,
            alpha: 1.0
        )
        terminalView.nativeForegroundColor = .white
        terminalView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)

        context.coordinator.terminalView = terminalView

        let name = sandboxName
        let mock = isMock
        let manager = ptyManager
        DispatchQueue.main.async {
            manager.attach(name: name, terminalView: terminalView, isMock: mock)
        }

        return terminalView
    }

    func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator {
        var terminalView: LocalProcessTerminalView?
    }
}
