import AppKit

struct RealWindowActivator: WindowActivatorProtocol {
    func activateMainWindow() {
        NSApplication.shared.activate()
        NSApplication.shared.keyWindow?.orderFrontRegardless()
    }
}
