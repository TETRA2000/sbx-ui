import SwiftUI

@main
struct sbx_uiApp: App {
    @State private var sandboxStore: SandboxStore
    @State private var policyStore: PolicyStore
    @State private var sessionStore: TerminalSessionStore
    @State private var envVarStore: EnvVarStore
    @State private var settingsStore = SettingsStore()
    @State private var toastManager = ToastManager()
    @State private var logStore = LogStore.shared

    init() {
        let service = ServiceFactory.create()
        let sandbox = SandboxStore(service: service)
        let policy = PolicyStore(service: service)
        let session = TerminalSessionStore(service: service)
        let envVar = EnvVarStore(service: service)
        _sandboxStore = State(initialValue: sandbox)
        _policyStore = State(initialValue: policy)
        _sessionStore = State(initialValue: session)
        _envVarStore = State(initialValue: envVar)
    }

    var body: some Scene {
        WindowGroup {
            ShellView()
                .environment(sandboxStore)
                .environment(policyStore)
                .environment(sessionStore)
                .environment(envVarStore)
                .environment(settingsStore)
                .environment(toastManager)
                .preferredColorScheme(.dark)
        }
    }
}
