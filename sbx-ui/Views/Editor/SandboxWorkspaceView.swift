import SwiftUI

/// Sandbox-scoped N-pane layout that hosts the editor and terminal as
/// siblings. For MVP the container is two-pane; the structure lets future
/// specs add additional pane types without rewriting the shell.
struct SandboxWorkspaceView: View {
    let sessionID: String
    let sandbox: Sandbox
    var onBack: () -> Void
    @Environment(EditorStore.self) private var editorStore
    @Environment(TerminalSessionStore.self) private var sessionStore

    private var visibility: PaneVisibility {
        editorStore.paneVisibility(for: sandbox.name)
    }

    private var rootURL: URL {
        URL(fileURLWithPath: sandbox.workspace)
    }

    var body: some View {
        VStack(spacing: 0) {
            navBar
            Divider()
            content
            AgentStatusBar(sandbox: sandbox, sessionID: sessionID)
        }
        .background(Color.surfaceLowest)
        .onAppear {
            editorStore.open(sandbox: sandbox)
        }
        // Keep .id on the terminal wrapper so session switches behave unchanged.
        .sheet(item: confirmCloseBinding) { pending in
            ConfirmCloseDialog(
                dirtyTabs: pending.dirty,
                onSave: {
                    Task { _ = await editorStore.resolvePendingClose(.save); maybeLeave() }
                },
                onDiscard: {
                    Task { _ = await editorStore.resolvePendingClose(.discard); maybeLeave() }
                },
                onCancel: {
                    Task { _ = await editorStore.resolvePendingClose(.cancel) }
                }
            )
        }
        .sheet(item: externalChangeBinding) { pending in
            ExternalChangeDialog(
                path: pending.path,
                onReload: { Task { _ = await editorStore.resolveExternalChange(reload: true) } },
                onKeepMine: { Task { _ = await editorStore.resolveExternalChange(reload: false) } },
                onShowDiff: { editorStore.acknowledgeShowDiffStub() }
            )
        }
        .alert("Tab limit reached",
               isPresented: Binding(get: { editorStore.showTabLimitWarning },
                                    set: { editorStore.showTabLimitWarning = $0 })) {
            Button("OK") { editorStore.showTabLimitWarning = false }
        } message: {
            Text("Close some tabs before opening more files (limit: \(EditorStore.maxOpenTabs)).")
        }
        .background(
            tabShortcutCatcher
        )
    }

    // MARK: - Subviews

    private var navBar: some View {
        HStack(spacing: 12) {
            Button {
                let result = editorStore.closeSandbox(sandbox.name, force: false)
                if case .needsConfirmation = result { return }
                onBack()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                    Text("Dashboard").font(.ui(12))
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("backToDashboard")

            Text(sandbox.name)
                .font(.code(11))
                .foregroundStyle(.tertiary)

            Spacer()

            // Collapse controls.
            Button {
                let v = visibility
                editorStore.setPaneVisibility(PaneVisibility(editorVisible: !v.editorVisible, terminalVisible: v.terminalVisible), for: sandbox.name)
            } label: {
                Image(systemName: visibility.editorVisible ? "sidebar.squares.leading" : "sidebar.leading")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(visibility.editorVisible ? "Collapse editor" : "Show editor")
            .accessibilityIdentifier("editorCollapseEditorButton")

            Button {
                let v = visibility
                editorStore.setPaneVisibility(PaneVisibility(editorVisible: v.editorVisible, terminalVisible: !v.terminalVisible), for: sandbox.name)
            } label: {
                Image(systemName: visibility.terminalVisible ? "sidebar.squares.trailing" : "sidebar.trailing")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(visibility.terminalVisible ? "Collapse terminal" : "Show terminal")
            .accessibilityIdentifier("editorCollapseTerminalButton")

            Button {
                sessionStore.disconnect(sessionID: sessionID)
                let result = editorStore.closeSandbox(sandbox.name, force: false)
                if case .needsConfirmation = result { return }
                onBack()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "xmark.circle")
                    Text("Disconnect").font(.ui(11))
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.error)
            .accessibilityIdentifier("disconnectButton")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.surfaceContainer)
    }

    @ViewBuilder
    private var content: some View {
        HStack(spacing: 0) {
            if visibility.editorVisible {
                EditorPanelView(sandboxName: sandbox.name, rootURL: rootURL)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if visibility.editorVisible && visibility.terminalVisible {
                Divider()
                    .accessibilityIdentifier("editorSplitter-\(sandbox.name)")
            }
            if visibility.terminalVisible {
                TerminalViewWrapper(sessionID: sessionID)
                    .id(sessionID)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityIdentifier("terminalView")
            }
        }
    }

    // MARK: - Sheet bindings

    private var confirmCloseBinding: Binding<EditorStore.PendingCloseConfirmation?> {
        Binding(
            get: { editorStore.pendingCloseConfirmation },
            set: { if $0 == nil { editorStore.pendingCloseConfirmation = nil } }
        )
    }

    private var externalChangeBinding: Binding<EditorStore.PendingExternalChange?> {
        Binding(
            get: { editorStore.pendingExternalChange },
            set: { if $0 == nil { editorStore.pendingExternalChange = nil } }
        )
    }

    private func maybeLeave() {
        if editorStore.pendingCloseConfirmation == nil {
            // Close resolved to .closed — check whether workspace was closed.
            if (editorStore.workspaces[sandbox.name]?.tabs.isEmpty ?? true) {
                onBack()
            }
        }
    }

    // MARK: - Cmd+1..9 shortcut catcher

    @ViewBuilder
    private var tabShortcutCatcher: some View {
        ZStack {
            ForEach(1...9, id: \.self) { n in
                Button("") {
                    editorStore.activateTab(sandboxName: sandbox.name, index: n)
                }
                .keyboardShortcut(KeyEquivalent(Character("\(n)")), modifiers: .command)
                .frame(width: 0, height: 0)
                .opacity(0)
            }
            Button("") {
                if let activeID = editorStore.workspaces[sandbox.name]?.activeTabID {
                    _ = editorStore.closeTab(sandboxName: sandbox.name, tabID: activeID, force: false)
                }
            }
            .keyboardShortcut("w", modifiers: .command)
            .frame(width: 0, height: 0)
            .opacity(0)
            Button("") {
                Task { _ = await editorStore.saveAll(sandboxName: sandbox.name) }
            }
            .keyboardShortcut("s", modifiers: [.command, .option])
            .frame(width: 0, height: 0)
            .opacity(0)
        }
    }
}

