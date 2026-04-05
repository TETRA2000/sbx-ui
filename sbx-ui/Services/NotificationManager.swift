import Foundation
import UserNotifications

protocol NotificationCenterProtocol: Sendable {
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
    func add(_ request: UNNotificationRequest) async throws
    func setNotificationCategories(_ categories: Set<UNNotificationCategory>)
    func isAuthorized() async -> Bool
}

extension UNUserNotificationCenter: @retroactive @unchecked Sendable {}

struct RealNotificationCenter: NotificationCenterProtocol {
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        try await UNUserNotificationCenter.current().requestAuthorization(options: options)
    }

    func add(_ request: UNNotificationRequest) async throws {
        try await UNUserNotificationCenter.current().add(request)
    }

    func setNotificationCategories(_ categories: Set<UNNotificationCategory>) {
        UNUserNotificationCenter.current().setNotificationCategories(categories)
    }

    func isAuthorized() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus == .authorized
    }
}

@MainActor @Observable
final class NotificationManager {
    private(set) var isAuthorized: Bool = false

    private let center: any NotificationCenterProtocol
    private var previousSandboxes: [Sandbox] = []

    init(center: any NotificationCenterProtocol = RealNotificationCenter()) {
        self.center = center
    }

    func requestAuthorization() async {
        do {
            isAuthorized = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            if isAuthorized {
                registerCategories()
            }
        } catch {
            isAuthorized = false
        }
    }

    func onSandboxesUpdated(previous: [Sandbox], current: [Sandbox], busyOperations: [String: SandboxOperation]) {
        guard isAuthorized else { return }

        let previousByName = Dictionary(previous.map { ($0.name, $0) }, uniquingKeysWith: { _, last in last })

        for sandbox in current {
            guard let prev = previousByName[sandbox.name] else { continue }

            if prev.status == .creating && sandbox.status == .running {
                postNotification(
                    title: "Creation Complete",
                    body: "Sandbox '\(sandbox.name)' is now running.",
                    category: "sandbox-lifecycle",
                    threadId: "sandbox-\(sandbox.name)",
                    sandboxName: sandbox.name
                )
            }

            if prev.status == .running && sandbox.status == .stopped {
                if busyOperations[sandbox.name] == .stopping { continue }
                postNotification(
                    title: "Unexpected Stop",
                    body: "Sandbox '\(sandbox.name)' stopped unexpectedly.",
                    category: "sandbox-lifecycle",
                    threadId: "sandbox-\(sandbox.name)",
                    sandboxName: sandbox.name
                )
            }
        }
    }

    func postPolicyViolation(sandboxName: String, blockedHost: String) {
        guard isAuthorized else { return }
        postNotification(
            title: "Policy Violation",
            body: "Sandbox '\(sandboxName)' was blocked from reaching \(blockedHost).",
            category: "policy-violation",
            threadId: "policy-\(sandboxName)",
            sandboxName: sandboxName
        )
    }

    func postSessionDisconnected(sandboxName: String) {
        guard isAuthorized else { return }
        postNotification(
            title: "Session Disconnected",
            body: "Terminal session for '\(sandboxName)' disconnected.",
            category: "session-event",
            threadId: "session-\(sandboxName)",
            sandboxName: sandboxName
        )
    }

    private func registerCategories() {
        let lifecycleCategory = UNNotificationCategory(
            identifier: "sandbox-lifecycle",
            actions: [UNNotificationAction(identifier: "open", title: "Open", options: .foreground)],
            intentIdentifiers: []
        )
        let policyCategory = UNNotificationCategory(
            identifier: "policy-violation",
            actions: [UNNotificationAction(identifier: "viewLog", title: "View Log", options: .foreground)],
            intentIdentifiers: []
        )
        let sessionCategory = UNNotificationCategory(
            identifier: "session-event",
            actions: [UNNotificationAction(identifier: "reconnect", title: "Reconnect", options: .foreground)],
            intentIdentifiers: []
        )
        center.setNotificationCategories([lifecycleCategory, policyCategory, sessionCategory])
    }

    private func postNotification(title: String, body: String, category: String, threadId: String, sandboxName: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.categoryIdentifier = category
        content.threadIdentifier = threadId
        content.userInfo = ["sandboxName": sandboxName]

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        Task {
            try? await center.add(request)
        }
    }
}
