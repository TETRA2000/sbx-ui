import Foundation

enum NavigationRequest: Equatable {
    case sandbox(name: String)
    case policyLog(sandboxName: String)
    case createSheet
    case createWithWorkspace(path: String)
}

protocol WindowActivatorProtocol {
    func activateMainWindow()
}

@MainActor @Observable
final class NavigationCoordinator {
    var pendingNavigation: NavigationRequest?

    private let windowActivator: any WindowActivatorProtocol

    init(windowActivator: (any WindowActivatorProtocol)? = nil) {
        self.windowActivator = windowActivator ?? RealWindowActivator()
    }

    func navigate(to request: NavigationRequest) {
        pendingNavigation = request
        windowActivator.activateMainWindow()
    }

    func consumeNavigation() -> NavigationRequest? {
        guard let request = pendingNavigation else { return nil }
        pendingNavigation = nil
        return request
    }
}
