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
    @Environment(TerminalSessionStore.self) private var sessionStore
    @Environment(ToastManager.self) private var toastManager

    /// Names of running sandboxes, used to detect status changes for session cleanup.
    private var runningSandboxNames: Set<String> {
        Set(sandboxStore.sandboxes.filter { $0.status == .running }.map(\.name))
    }

    var body: some View {
        VStack(spacing: 0) {
            NavigationSplitView {
                SidebarView(selection: $selection, onSelectSession: { name in
                    if let sandbox = sandboxStore.sandboxes.first(where: { $0.name == name }) {
                        selectedSandbox = sandbox
                    }
                })
            } detail: {
                Group {
                    if let selected = selectedSandbox,
                       let sandbox = sandboxStore.sandboxes.first(where: { $0.name == selected.name }),
                       sandbox.status == .running {
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
        .task {
            sandboxStore.startPolling()
        }
        .onAppear {
            let logStore = LogStore.shared
            logStore.info("App", "sbx-ui started")
            let mode = ProcessInfo.processInfo.environment["SBX_CLI_MOCK"] == "1" ? "CLI mock" : "real"
            logStore.info("App", "Service mode: \(mode)")
        }
        .onChange(of: runningSandboxNames) { _, _ in
            sessionStore.cleanupStaleSessions(sandboxes: sandboxStore.sandboxes)
        }
        .onChange(of: sessionStore.activeSessionNames) { _, newNames in
            // Auto-navigate back to dashboard when the active session's process exits
            if let selected = selectedSandbox, !newNames.contains(selected.name) {
                selectedSandbox = nil
            }
        }
    }
}

struct DashboardView: View {
    var onSelectSandbox: (Sandbox) -> Void
    @Environment(SandboxStore.self) private var sandboxStore
    @Environment(TerminalSessionStore.self) private var sessionStore
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
        .sheet(isPresented: $showCreateSheet) {
            CreateProjectSheet()
        }
        .task {
            while !Task.isCancelled {
                sessionStore.captureSnapshots()
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }
}
