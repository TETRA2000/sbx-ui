import SwiftUI
import UniformTypeIdentifiers

enum SidebarDestination: Hashable {
    case dashboard
    case policies
}

struct ShellView: View {
    @State private var selection: SidebarDestination? = .dashboard
    @State private var selectedSessionID: String?
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
                SidebarView(selection: $selection, onSelectSession: { sessionID in
                    selectedSessionID = sessionID
                })
            } detail: {
                Group {
                    if let sessionID = selectedSessionID,
                       let session = sessionStore.session(for: sessionID),
                       let sandbox = sandboxStore.sandboxes.first(where: { $0.name == session.sandboxName }),
                       sandbox.status == .running {
                        SessionPanelView(sessionID: sessionID, sandbox: sandbox, onBack: { selectedSessionID = nil })
                    } else {
                        switch selection {
                        case .dashboard, .none:
                            DashboardView(
                                onSelectSandbox: { sandbox in
                                    if let agentID = sessionStore.agentSessionID(for: sandbox.name) {
                                        selectedSessionID = agentID
                                    } else {
                                        let (id, _) = sessionStore.startSession(sandboxName: sandbox.name, type: .agent)
                                        selectedSessionID = id
                                    }
                                },
                                onOpenShellSession: { sessionID in
                                    selectedSessionID = sessionID
                                }
                            )
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
        .onChange(of: sessionStore.activeSessionIDs) { _, newIDs in
            if let selected = selectedSessionID, !newIDs.contains(selected) {
                selectedSessionID = nil
            }
        }
    }
}

struct DashboardView: View {
    var onSelectSandbox: (Sandbox) -> Void
    var onOpenShellSession: (String) -> Void
    @Environment(SandboxStore.self) private var sandboxStore
    @Environment(TerminalSessionStore.self) private var sessionStore
    @Environment(NavigationCoordinator.self) private var navigationCoordinator
    @State private var showCreateSheet = false
    @State private var isDropTargeted = false
    @State private var droppedWorkspacePath: String?

    var body: some View {
        VStack(spacing: 0) {
            GlobalStatsView()
            if sandboxStore.initialLoading {
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.large)
                    Text("Loading sandboxes\u{2026}")
                        .font(.ui(13))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    SandboxGridView(
                        onSelectSandbox: onSelectSandbox,
                        onCreateNew: { showCreateSheet = true },
                        onOpenShellSession: onOpenShellSession
                    )
                    .padding()
                }
                .overlay { DropZoneOverlay(isVisible: isDropTargeted) }
                .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
                    DropHandler.handleDrop(
                        providers: providers,
                        sandboxes: sandboxStore.sandboxes,
                        coordinator: navigationCoordinator,
                        showCreateSheet: &showCreateSheet,
                        droppedWorkspacePath: &droppedWorkspacePath
                    )
                }
            }
        }
        .background(Color.surface)
        .sheet(isPresented: $showCreateSheet) {
            CreateProjectSheet(prefilledPath: droppedWorkspacePath)
        }
        .task {
            while !Task.isCancelled {
                sessionStore.captureSnapshots()
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }
}
