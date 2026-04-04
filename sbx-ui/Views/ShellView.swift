import SwiftUI

enum SidebarDestination: Hashable {
    case dashboard
    case policies
}

struct ShellView: View {
    @State private var selection: SidebarDestination? = .dashboard
    @State private var selectedSandbox: Sandbox?
    @State private var showDebugLog = false
    @Environment(SandboxStore.self) private var sandboxStore
    @Environment(SessionStore.self) private var sessionStore
    @Environment(ToastManager.self) private var toastManager
    var body: some View {
        VStack(spacing: 0) {
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

            if showDebugLog {
                Divider()
                DebugLogView()
                    .environment(LogStore.shared)
                    .frame(height: 250)
            }
        }
        .preferredColorScheme(.dark)
        .overlay(alignment: .top) {
            ToastOverlay()
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    showDebugLog.toggle()
                } label: {
                    Image(systemName: showDebugLog ? "ladybug.fill" : "ladybug")
                        .foregroundStyle(showDebugLog ? Color.accent : .secondary)
                }
                .help("Toggle Debug Log")
            }
        }
        .onAppear {
            let logStore = LogStore.shared
            logStore.info("App", "sbx-ui started")
            let mode = ProcessInfo.processInfo.environment["SBX_MOCK"] == "1" ? "in-memory mock"
                : ProcessInfo.processInfo.environment["SBX_CLI_MOCK"] == "1" ? "CLI mock"
                : "real"
            logStore.info("App", "Service mode: \(mode)")
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
