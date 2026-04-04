import Foundation

@MainActor @Observable final class SessionStore {
    var activeSandbox: String?
    var connected: Bool = false
    var error: String?
    var connectionStartTime: Date?

    private let service: any SbxServiceProtocol
    private let isMock: Bool

    init(service: any SbxServiceProtocol) {
        self.service = service
        self.isMock = ProcessInfo.processInfo.environment["SBX_MOCK"] == "1"
    }

    func attach(name: String) async throws {
        if activeSandbox != nil {
            detach()
        }
        activeSandbox = name
        connected = true
        connectionStartTime = Date()
    }

    func sendMessage(_ message: String) async throws {
        guard let name = activeSandbox, connected else { return }
        try await service.sendMessage(name: name, message: message)
    }

    func detach() {
        activeSandbox = nil
        connected = false
        connectionStartTime = nil
    }
}
