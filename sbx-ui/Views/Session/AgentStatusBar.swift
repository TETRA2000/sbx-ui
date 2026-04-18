import SwiftUI

struct AgentStatusBar: View {
    let sandbox: Sandbox
    let sessionID: String
    @Environment(TerminalSessionStore.self) private var sessionStore

    private var session: TerminalSession? {
        sessionStore.session(for: sessionID)
    }

    var body: some View {
        HStack(spacing: 16) {
            // Session type indicator
            if let sessionType = session?.sessionType {
                let (icon, label): (String, String) = {
                    switch sessionType {
                    case .agent:      return ("cpu", "agent")
                    case .shell:      return ("terminal", "shell")
                    case .kanbanTask: return ("checklist", "task")
                    }
                }()
                HStack(spacing: 4) {
                    Image(systemName: icon)
                        .font(.system(size: 10))
                    Text(label)
                        .font(.code(11))
                }
                .foregroundStyle(.secondary)
            }

            // Sandbox name
            Text(sandbox.name)
                .font(.code(11, weight: .bold))
                .foregroundStyle(.primary)

            // Uptime
            if let startTime = session?.startTime {
                TimelineView(.periodic(from: .now, by: 1.0)) { timeline in
                    let elapsed = timeline.date.timeIntervalSince(startTime)
                    Text(formatUptime(elapsed))
                        .font(.code(11))
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            // Connection indicator
            HStack(spacing: 4) {
                let isConnected = session != nil
                Circle()
                    .fill(isConnected ? Color.secondary : Color.error)
                    .frame(width: 6, height: 6)
                Text(isConnected ? "Connected" : "Disconnected")
                    .font(.label(10))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.surfaceContainer)
        .accessibilityIdentifier("agentStatusBar")
    }

    private func formatUptime(_ seconds: TimeInterval) -> String {
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        let s = Int(seconds) % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }
}
