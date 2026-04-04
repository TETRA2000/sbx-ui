import SwiftUI

@main
struct sbx_uiApp: App {
    @State private var sandboxStore: SandboxStore
    @State private var policyStore: PolicyStore
    @State private var sessionStore: SessionStore
    @State private var settingsStore = SettingsStore()
    @State private var toastManager = ToastManager()

    init() {
        let service = ServiceFactory.create()
        let sandbox = SandboxStore(service: service)
        let policy = PolicyStore(service: service)
        let session = SessionStore(service: service)
        _sandboxStore = State(initialValue: sandbox)
        _policyStore = State(initialValue: policy)
        _sessionStore = State(initialValue: session)
    }

    var body: some Scene {
        WindowGroup {
            ShellView()
                .environment(sandboxStore)
                .environment(policyStore)
                .environment(sessionStore)
                .environment(settingsStore)
                .environment(toastManager)
                .preferredColorScheme(.dark)
        }
    }
}
