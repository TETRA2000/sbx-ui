import Foundation

@MainActor
final class ServiceContainer {
    private static var _shared: ServiceContainer?

    static var shared: ServiceContainer? {
        get { _shared }
        set { _shared = newValue }
    }

    let service: any SbxServiceProtocol
    let sandboxStore: SandboxStore
    let policyStore: PolicyStore
    let sessionStore: TerminalSessionStore
    let navigationCoordinator: NavigationCoordinator
    let notificationManager: NotificationManager

    static func initialize() {
        guard _shared == nil else { return }
        _shared = ServiceContainer(service: ServiceFactory.create())
    }

    init(service: any SbxServiceProtocol) {
        self.service = service
        self.sandboxStore = SandboxStore(service: service)
        self.policyStore = PolicyStore(service: service)
        self.sessionStore = TerminalSessionStore(service: service)
        self.navigationCoordinator = NavigationCoordinator()
        self.notificationManager = NotificationManager()
    }

    /// Test-only: replace the shared container with one backed by a given service.
    static func configure(service: any SbxServiceProtocol) {
        _shared = ServiceContainer(service: service)
    }
}
