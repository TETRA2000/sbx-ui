import SwiftUI

struct SessionPanelView: View {
    let sandbox: Sandbox
    var onBack: () -> Void
    @Environment(TerminalSessionStore.self) private var sessionStore

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

                Spacer()

                Button {
                    sessionStore.disconnect(name: sandbox.name)
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
            TerminalViewWrapper(sandboxName: sandbox.name)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("terminalView")

            // Agent status bar
            AgentStatusBar(sandbox: sandbox)
        }
        .background(Color.surfaceLowest)
    }
}
