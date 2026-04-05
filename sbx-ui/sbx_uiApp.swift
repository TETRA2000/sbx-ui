import SwiftUI

@main
struct sbx_uiApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var sandboxStore: SandboxStore
    @State private var policyStore: PolicyStore
    @State private var sessionStore: TerminalSessionStore
    @State private var settingsStore = SettingsStore()
    @State private var toastManager = ToastManager()
    @State private var logStore = LogStore.shared

    init() {
        ServiceContainer.initialize()
        let container = ServiceContainer.shared!
        _sandboxStore = State(initialValue: container.sandboxStore)
        _policyStore = State(initialValue: container.policyStore)
        _sessionStore = State(initialValue: container.sessionStore)
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
