import SwiftUI

struct SessionPanelView: View {
    let sandbox: Sandbox
    var onBack: () -> Void
    @Environment(SessionStore.self) private var sessionStore

    private var isMock: Bool {
        ProcessInfo.processInfo.environment["SBX_MOCK"] == "1"
    }

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
            TerminalViewWrapper(sandboxName: sandbox.name, isMock: isMock)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("terminalView")

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
