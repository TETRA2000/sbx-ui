import Foundation

final class MockPtyEmitter: PtyHandle, @unchecked Sendable {
    private var dataCallback: (@Sendable (String) -> Void)?
    private var disposed = false

    func onData(_ callback: @escaping @Sendable (String) -> Void) {
        dataCallback = callback
        Task { [weak self] in
            await self?.emitStartupSequence()
        }
    }

    func write(_ data: String) {
        guard !disposed else { return }
        Task { [weak self] in
            await self?.emitResponse(to: data)
        }
    }

    func dispose() {
        disposed = true
        dataCallback = nil
    }

    // MARK: - Private

    private func emit(_ text: String) {
        guard !disposed else { return }
        dataCallback?(text)
    }

    private func emitStartupSequence() async {
        let lines: [(String, UInt64)] = [
            ("\u{1B}[1;36m╭─────────────────────────────────────╮\u{1B}[0m\r\n", 100),
            ("\u{1B}[1;36m│\u{1B}[0m  \u{1B}[1;37mClaude Code\u{1B}[0m \u{1B}[0;90mv1.0.0\u{1B}[0m               \u{1B}[1;36m│\u{1B}[0m\r\n", 50),
            ("\u{1B}[1;36m╰─────────────────────────────────────╯\u{1B}[0m\r\n", 100),
            ("\r\n", 50),
            ("\u{1B}[0;90mModel: claude-sonnet-4-20250514\u{1B}[0m\r\n", 80),
            ("\u{1B}[0;90mWorkspace: /Users/dev/project\u{1B}[0m\r\n", 80),
            ("\r\n", 100),
            ("\u{1B}[1;32m>\u{1B}[0m ", 200),
        ]

        for (line, delayMs) in lines {
            guard !disposed else { return }
            try? await Task.sleep(for: .milliseconds(delayMs))
            emit(line)
        }
    }

    private func emitResponse(to input: String) async {
        let steps: [(String, UInt64)] = [
            ("\r\n", 50),
            ("\u{1B}[0;33m⠋ Thinking...\u{1B}[0m\r\n", 600),
            ("\u{1B}[0;36m⠿ Reading file: src/main.swift\u{1B}[0m\r\n", 400),
            ("\u{1B}[0;36m⠿ Writing file: src/main.swift\u{1B}[0m\r\n", 300),
            ("\u{1B}[1;32m✓ Done\u{1B}[0m\r\n", 200),
            ("\r\n", 100),
            ("\u{1B}[1;32m>\u{1B}[0m ", 100),
        ]

        for (line, delayMs) in steps {
            guard !disposed else { return }
            try? await Task.sleep(for: .milliseconds(delayMs))
            emit(line)
        }
    }
}
