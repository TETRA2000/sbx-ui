import SwiftUI

struct SessionPanelView: View {
    let sandbox: Sandbox
    var onBack: () -> Void
    @Environment(SessionStore.self) private var sessionStore
    @State private var ptyManager = PtySessionManager()

    var body: some View {
        VStack(spacing: 0) {
            // Navigation bar
            HStack {
                Button {
                    sessionStore.detach(ptyManager: ptyManager)
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
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.surfaceContainer)

            // Terminal area
            TerminalViewWrapper(sandboxName: sandbox.name, isMock: sessionStore.isMock, ptyManager: ptyManager)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("terminalView")

            // Agent status bar
            AgentStatusBar(sandbox: sandbox)
        }
        .background(Color.surfaceLowest)
        .task {
            do {
                try await sessionStore.attach(name: sandbox.name, ptyManager: ptyManager)
            } catch {
                // Handle error
            }
        }
        .onDisappear {
            sessionStore.detach(ptyManager: ptyManager)
        }
    }
}
