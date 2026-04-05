import SwiftUI

struct SessionPanelView: View {
    let sessionID: String
    let sandbox: Sandbox
    var onBack: () -> Void
    @Environment(TerminalSessionStore.self) private var sessionStore

    private var session: TerminalSession? {
        sessionStore.session(for: sessionID)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Navigation bar
            HStack {
                Button {
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
                .accessibilityIdentifier("backToDashboard")

                if let label = session?.label {
                    Text(label)
                        .font(.code(11))
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 8)
                }

                Spacer()

                Button {
                    sessionStore.disconnect(sessionID: sessionID)
                    onBack()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "xmark.circle")
                        Text("Disconnect")
                            .font(.ui(11))
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.error)
                .accessibilityIdentifier("disconnectButton")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.surfaceContainer)

            // Terminal area
            TerminalViewWrapper(sessionID: sessionID)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("terminalView")

            // Status bar
            AgentStatusBar(sandbox: sandbox, sessionID: sessionID)
        }
        .background(Color.surfaceLowest)
    }
}
