import SwiftUI

struct SessionPanelView: View {
    let sandbox: Sandbox
    var onBack: () -> Void
    @Environment(SessionStore.self) private var sessionStore

    var body: some View {
        VStack(spacing: 0) {
            // Navigation bar
            HStack {
                Button {
                    sessionStore.detach()
                    onBack()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Dashboard")
                            .font(.ui(12))
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.surfaceContainer)

            // Terminal area
            TerminalPlaceholderView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Agent status bar
            AgentStatusBar(sandbox: sandbox)

            // Chat input
            ChatInputView()
        }
        .background(Color.surfaceLowest)
        .task {
            do {
                try await sessionStore.attach(name: sandbox.name)
            } catch {
                // Handle error
            }
        }
        .onDisappear {
            sessionStore.detach()
        }
    }
}

/// Placeholder terminal view (real SwiftTerm integration in Task 9)
struct TerminalPlaceholderView: View {
    @Environment(SessionStore.self) private var sessionStore

    var body: some View {
        ZStack {
            Color.surfaceLowest
            if sessionStore.connected {
                VStack(spacing: 4) {
                    Text("Terminal Session")
                        .font(.code(14))
                        .foregroundStyle(.secondary)
                    Text("Connected to \(sessionStore.activeSandbox ?? "")")
                        .font(.code(11))
                        .foregroundStyle(.tertiary)
                }
            } else {
                Text("Not connected")
                    .font(.code(12))
                    .foregroundStyle(.tertiary)
            }
        }
        .accessibilityIdentifier("terminalView")
    }
}
