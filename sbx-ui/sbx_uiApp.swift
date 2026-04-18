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
            // Prefer launching a fresh agent session with the prompt as a
            // positional argument (`sbx run <name> -- <prompt>`). Claude Code
            // and other agent CLIs accept a positional prompt and start
            // processing it immediately, which avoids the unreliable
            // type-into-TUI-then-press-Enter dance on the Ink-based UI.
            //
            // If an agent session already exists for the sandbox, the
            // launch-arg path is unavailable (process is already running), so
            // fall back to typing the prompt and sending Enter.
            if session.agentSessionID(for: sandboxName) == nil {
                _ = session.startSession(sandboxName: sandboxName, type: .agent, initialPrompt: prompt)
            } else {
                _ = session.startSession(sandboxName: sandboxName, type: .agent)
                session.sendMessage(prompt, to: sandboxName)
            }
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
