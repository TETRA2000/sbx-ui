import SwiftUI

@main
struct sbx_uiApp: App {
    @NSApplicationDelegateAdaptor(AppDelegateAdapter.self) private var appDelegate
    @State private var sandboxStore: SandboxStore
    @State private var policyStore: PolicyStore
    @State private var sessionStore: TerminalSessionStore
    @State private var envVarStore: EnvVarStore
    @State private var pluginStore: PluginStore
    @State private var kanbanStore: KanbanStore
    @State private var editorStore: EditorStore
    @State private var settingsStore = SettingsStore()
    @State private var toastManager = ToastManager()
    @State private var logStore = LogStore.shared

    init() {
        let service = ServiceFactory.create()
        let pluginManager = PluginManager(service: service)
        let pluginSt = PluginStore(manager: pluginManager)
        let sandbox = SandboxStore(service: service)
        let policy = PolicyStore(service: service)
        let session = TerminalSessionStore(service: service)
        let envVar = EnvVarStore(service: service)
        sandbox.onPluginEvent = { event in
            await pluginSt.dispatchEvent(event)
        }
        let kanbanDir: URL? = ProcessInfo.processInfo.environment["SBX_KANBAN_DIR"]
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
        let kanban = KanbanStore(service: service, persistenceDirectory: kanbanDir)
        kanban.onExecuteTask = { sandboxName, prompt in
            // Each kanban task Start spawns its own independent session via
            // `sbx run <sandbox> -- '<prompt>'`. sbx appends the args after
            // `--` to its default `claude --dangerously-skip-permissions`
            // invocation, and claude treats the first positional as the
            // initial prompt — so there's no need to type into any
            // already-attached TUI.
            _ = session.startSession(sandboxName: sandboxName, type: .kanbanTask, initialPrompt: prompt)
        }
        let toast = ToastManager()
        let editor = EditorStore(provider: DefaultEditorDocumentProvider(), toastManager: toast)
        EditorStore.configureShared(editor)
        _sandboxStore = State(initialValue: sandbox)
        _policyStore = State(initialValue: policy)
        _sessionStore = State(initialValue: session)
        _envVarStore = State(initialValue: envVar)
        _pluginStore = State(initialValue: pluginSt)
        _kanbanStore = State(initialValue: kanban)
        _editorStore = State(initialValue: editor)
        _toastManager = State(initialValue: toast)
    }

    var body: some Scene {
        WindowGroup {
            ShellView()
                .environment(sandboxStore)
                .environment(policyStore)
                .environment(sessionStore)
                .environment(envVarStore)
                .environment(pluginStore)
                .environment(kanbanStore)
                .environment(editorStore)
                .environment(settingsStore)
                .environment(toastManager)
                .preferredColorScheme(.dark)
        }
    }
}
