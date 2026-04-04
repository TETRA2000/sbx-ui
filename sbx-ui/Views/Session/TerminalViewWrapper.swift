import SwiftUI
import SwiftTerm

struct TerminalViewWrapper: NSViewRepresentable {
    let sandboxName: String
    let isMock: Bool
    @Environment(SessionStore.self) private var sessionStore

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        let terminalView = LocalProcessTerminalView(frame: .zero)
        terminalView.nativeBackgroundColor = NSColor(
            red: 0x0E / 255.0,
            green: 0x0E / 255.0,
            blue: 0x0E / 255.0,
            alpha: 1.0
        )
        terminalView.nativeForegroundColor = .white

        // Set JetBrains Mono font if available, fallback to Menlo
        if let font = NSFont(name: "JetBrainsMono-Regular", size: 13) {
            terminalView.font = font
        } else {
            terminalView.font = NSFont(name: "Menlo", size: 13) ?? NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        }

        context.coordinator.terminalView = terminalView
        return terminalView
    }

    func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {
        // Re-attach if needed
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator {
        var terminalView: LocalProcessTerminalView?
    }
}
