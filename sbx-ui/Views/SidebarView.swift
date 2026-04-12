import SwiftUI

struct SidebarView: View {
    @Binding var selection: SidebarDestination?
    var onSelectSession: (String) -> Void
    var onCreatedSandbox: ((Sandbox) -> Void)?
    @Environment(TerminalSessionStore.self) private var sessionStore
    @State private var showCreateSheet = false

    private var sortedSessions: [TerminalSession] {
        sessionStore.activeSessions.values.sorted { $0.startTime < $1.startTime }
    }

    var body: some View {
        List(selection: $selection) {
            Section {
                Label {
                    Text("DASHBOARD")
                        .font(.label(11))
                        .tracking(1.2)
                } icon: {
                    Image(systemName: "square.grid.2x2")
                }
                .tag(SidebarDestination.dashboard)

                Label {
                    Text("KANBAN")
                        .font(.label(11))
                        .tracking(1.2)
                } icon: {
                    Image(systemName: "rectangle.split.3x1")
                }
                .tag(SidebarDestination.kanban)

                Label {
                    Text("POLICIES")
                        .font(.label(11))
                        .tracking(1.2)
                } icon: {
                    Image(systemName: "shield.lefthalf.filled")
                }
                .tag(SidebarDestination.policies)

                Label {
                    Text("PLUGINS")
                        .font(.label(11))
                        .tracking(1.2)
                } icon: {
                    Image(systemName: "puzzlepiece.extension")
                }
                .tag(SidebarDestination.plugins)
            }

            if !sessionStore.activeSessions.isEmpty {
                Section {
                    Text("SESSIONS")
                        .font(.label(9))
                        .tracking(1.2)
                        .foregroundStyle(.tertiary)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 16))

                    ForEach(sortedSessions, id: \.id) { session in
                        Button {
                            onSelectSession(session.id)
                        } label: {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(session.sessionType == .agent ? Color.accent : Color.secondary)
                                    .frame(width: 6, height: 6)
                                Text(session.label)
                                    .font(.code(11))
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("sidebarSession-\(session.label)")
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        .background(Color.surfaceContainer)
        .safeAreaInset(edge: .bottom) {
            Button {
                showCreateSheet = true
            } label: {
                Label {
                    Text("Deploy Agent")
                        .font(.label(12, weight: .semibold))
                } icon: {
                    Image(systemName: "plus.circle.fill")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.accent)
            .padding()
            .sheet(isPresented: $showCreateSheet) {
                CreateProjectSheet(onCreated: onCreatedSandbox)
            }
        }
    }
}
