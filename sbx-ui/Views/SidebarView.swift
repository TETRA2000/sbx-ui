import SwiftUI

struct SidebarView: View {
    @Binding var selection: SidebarDestination?
    var onSelectSession: (String) -> Void
    @Environment(TerminalSessionStore.self) private var sessionStore
    @State private var showCreateSheet = false

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
                    Text("POLICIES")
                        .font(.label(11))
                        .tracking(1.2)
                } icon: {
                    Image(systemName: "shield.lefthalf.filled")
                }
                .tag(SidebarDestination.policies)
            }

            if !sessionStore.activeSessionNames.isEmpty {
                Section {
                    Text("SESSIONS")
                        .font(.label(9))
                        .tracking(1.2)
                        .foregroundStyle(.tertiary)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 16))

                    ForEach(sessionStore.activeSessionNames, id: \.self) { name in
                        Button {
                            onSelectSession(name)
                        } label: {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(Color.secondary)
                                    .frame(width: 6, height: 6)
                                Text(name)
                                    .font(.code(11))
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("sidebarSession-\(name)")
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
                CreateProjectSheet()
            }
        }
    }
}
