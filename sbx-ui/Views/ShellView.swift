import SwiftUI

enum SidebarDestination: Hashable {
    case dashboard
    case policies
}

struct ShellView: View {
    @State private var selection: SidebarDestination? = .dashboard
    @State private var selectedSandbox: Sandbox?
    @Environment(SandboxStore.self) private var sandboxStore
    @Environment(SessionStore.self) private var sessionStore
    @Environment(ToastManager.self) private var toastManager

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selection)
        } detail: {
            Group {
                if let sandbox = selectedSandbox, sandbox.status == .running {
                    SessionPanelView(sandbox: sandbox, onBack: { selectedSandbox = nil })
                } else {
                    switch selection {
                    case .dashboard, .none:
                        DashboardView(onSelectSandbox: { sandbox in
                            selectedSandbox = sandbox
                        })
                    case .policies:
                        PolicyPanelView()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.surface)
        }
        .navigationSplitViewStyle(.balanced)
        .preferredColorScheme(.dark)
        .overlay(alignment: .top) {
            ToastOverlay()
        }
    }
}

struct DashboardView: View {
    var onSelectSandbox: (Sandbox) -> Void
    @Environment(SandboxStore.self) private var sandboxStore
    @State private var showCreateSheet = false

    var body: some View {
        VStack(spacing: 0) {
            GlobalStatsView()
            ScrollView {
                SandboxGridView(
                    onSelectSandbox: onSelectSandbox,
                    onCreateNew: { showCreateSheet = true }
                )
                .padding()
            }
        }
        .background(Color.surface)
        .task {
            sandboxStore.startPolling()
        }
        .onDisappear {
            sandboxStore.stopPolling()
        }
        .sheet(isPresented: $showCreateSheet) {
            CreateProjectSheet()
        }
    }
}
