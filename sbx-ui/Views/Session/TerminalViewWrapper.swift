import SwiftUI
import AppKit
@preconcurrency import SwiftTerm

// MARK: - Delegate Proxy

/// Proxy that intercepts `requestOpenLink` to strip whitespace from multi-line URLs.
/// All other delegate methods forward to the terminal view via class dispatch.
/// This is necessary because `LocalProcessTerminalView` declares `TerminalViewDelegate`
/// conformance and relies on the protocol extension default for `requestOpenLink`.
/// Subclass overrides aren't reachable through protocol witness dispatch.
class TerminalDelegateProxy: TerminalViewDelegate {
    weak var terminal: FocusableTerminalView?

    func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
        var fullLink = link

        // For implicit links (no OSC 8 params), reconstruct multi-line URLs from the buffer.
        // SwiftTerm's implicit detection may only capture one line when lines aren't soft-wrapped.
        if params.isEmpty, let tv = terminal {
            fullLink = Self.reconstructURL(from: link, in: tv.getTerminal())
        }

        let cleaned = fullLink.components(separatedBy: .whitespacesAndNewlines).joined()
        if let url = URL(string: cleaned) {
            appLog(.info, "Terminal", "Opening URL: \(cleaned)")
            NSWorkspace.shared.open(url)
        } else {
            appLog(.warn, "Terminal", "Invalid URL after cleanup", detail: "raw: \(link)")
        }
    }

    /// Extend a partial URL by reading subsequent lines from the terminal buffer.
    /// A line is considered URL continuation if it contains URL-specific characters
    /// like `%`, `=`, `&`, `?`, `#`, `+`, `:`, or `/`.
    static func reconstructURL(from partialURL: String, in terminal: Terminal) -> String {
        let data = terminal.getBufferAsData()
        guard let buffer = String(data: data, encoding: .utf8) else { return partialURL }
        return reconstructURL(from: partialURL, inBuffer: buffer)
    }

    static func reconstructURL(from partialURL: String, inBuffer buffer: String) -> String {
        let lines = buffer.components(separatedBy: "\n")
        let partial = partialURL.trimmingCharacters(in: .whitespaces)
        let prefix = String(partial.prefix(min(40, partial.count)))

        // Find the line containing our partial URL
        guard let startIdx = lines.firstIndex(where: {
            $0.trimmingCharacters(in: .whitespaces).contains(prefix)
        }) else { return partialURL }

        // Extract URL from the start line (find the scheme to skip any leading text)
        let startLine = lines[startIdx].trimmingCharacters(in: .whitespaces)
        var urlStart = startLine
        if let schemeRange = startLine.range(of: "https://") ?? startLine.range(of: "http://") {
            urlStart = String(startLine[schemeRange.lowerBound...])
        }
        var parts: [String] = [urlStart]

        // Extend to subsequent lines that contain URL-specific characters
        let urlSpecificChars = CharacterSet(charactersIn: "%=&?#+:/")
        for i in (startIdx + 1)..<lines.count {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { break }
            if trimmed.unicodeScalars.contains(where: { urlSpecificChars.contains($0) }) {
                parts.append(trimmed)
            } else {
                break
            }
        }

        return parts.joined()
    }

    func send(source: TerminalView, data: ArraySlice<UInt8>) {
        terminal?.send(source: source, data: data)
    }

    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
        terminal?.sizeChanged(source: source, newCols: newCols, newRows: newRows)
    }

    func setTerminalTitle(source: TerminalView, title: String) {
        terminal?.setTerminalTitle(source: source, title: title)
    }

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        terminal?.hostCurrentDirectoryUpdate(source: source, directory: directory)
    }

    func scrolled(source: TerminalView, position: Double) {
        terminal?.scrolled(source: source, position: position)
    }

    func clipboardCopy(source: TerminalView, content: Data) {
        terminal?.clipboardCopy(source: source, content: content)
    }

    func rangeChanged(source: TerminalView, startY: Int, endY: Int) {
        terminal?.rangeChanged(source: source, startY: startY, endY: endY)
    }

    func bell(source: TerminalView) { NSSound.beep() }

    func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {}
}

// MARK: - FocusableTerminalView

/// LocalProcessTerminalView subclass that auto-focuses when added to a window
/// and notifies when the spawned process terminates.
class FocusableTerminalView: LocalProcessTerminalView {
    /// Called when the PTY process exits (may fire on a background thread).
    var onProcessExit: ((_ exitCode: Int32?) -> Void)?

    /// Strong reference keeps the proxy alive (terminalDelegate is weak).
    private var delegateProxy: TerminalDelegateProxy?

    /// Replace the default terminalDelegate with our proxy that cleans URLs.
    /// Must be called after init (which sets terminalDelegate = self internally).
    func installLinkDelegate() {
        let proxy = TerminalDelegateProxy()
        proxy.terminal = self
        delegateProxy = proxy
        terminalDelegate = proxy
    }

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

    // MARK: - Keyboard Shortcuts

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags == .command, event.charactersIgnoringModifiers == "k" {
            clearTerminalBuffer()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    /// Clear visible screen and scrollback history (Cmd+K, like iTerm2).
    func clearTerminalBuffer() {
        // ESC[H = cursor home, ESC[2J = clear screen, ESC[3J = clear scrollback
        feed(text: "\u{1b}[H\u{1b}[2J\u{1b}[3J")
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
