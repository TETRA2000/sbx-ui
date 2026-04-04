import Foundation

@MainActor @Observable final class SessionStore {
    var activeSandbox: String?
    var connected: Bool = false
    var error: String?
    var connectionStartTime: Date?

    private let service: any SbxServiceProtocol
    let isMock: Bool

    init(service: any SbxServiceProtocol) {
        self.service = service
        self.isMock = ProcessInfo.processInfo.environment["SBX_MOCK"] == "1"
    }

    func attach(name: String, ptyManager: PtySessionManager? = nil) async throws {
        if let prev = activeSandbox, let mgr = ptyManager {
            mgr.dispose(name: prev)
        }
        activeSandbox = name
        connected = true
        connectionStartTime = Date()
    }

    func sendMessage(_ message: String, ptyManager: PtySessionManager? = nil) async throws {
        guard let name = activeSandbox, connected else { return }
        if let mgr = ptyManager {
            mgr.write(name: name, data: message)
        }
        try await service.sendMessage(name: name, message: message)
    }

    func detach(ptyManager: PtySessionManager? = nil) {
        if let name = activeSandbox, let mgr = ptyManager {
            mgr.dispose(name: name)
        }
        activeSandbox = nil
        connected = false
        connectionStartTime = nil
    }
}
