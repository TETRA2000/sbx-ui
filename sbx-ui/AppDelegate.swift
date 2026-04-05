import AppKit
import UserNotifications

class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        Task { @MainActor in
            await ServiceContainer.shared?.notificationManager.requestAuthorization()
        }
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let sandboxes: [Sandbox]
        if Thread.isMainThread {
            sandboxes = ServiceContainer.shared?.sandboxStore.sandboxes ?? []
        } else {
            sandboxes = DispatchQueue.main.sync {
                ServiceContainer.shared?.sandboxStore.sandboxes ?? []
            }
        }
        let menu = DockMenuBuilder.buildMenu(sandboxes: sandboxes)

        // Wire actions
        for item in menu.items {
            item.target = self
            if item.action == nil && item.title == "New Sandbox…" {
                item.action = #selector(newSandboxAction)
            }
            if let submenu = item.submenu {
                for subItem in submenu.items {
                    subItem.target = self
                }
            }
        }
        return menu
    }

    // MARK: - Dock Menu Actions

    @objc func newSandbox(_ sender: NSMenuItem) {
        Task { @MainActor in
            ServiceContainer.shared?.navigationCoordinator.navigate(to: .createSheet)
        }
    }

    @objc func newSandboxAction(_ sender: NSMenuItem) {
        newSandbox(sender)
    }

    @objc func stopSandbox(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        Task { @MainActor in
            try? await ServiceContainer.shared?.sandboxStore.stopSandbox(name: name)
        }
    }

    @objc func resumeSandbox(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        Task { @MainActor in
            try? await ServiceContainer.shared?.sandboxStore.resumeSandbox(name: name)
        }
    }

    @objc func openSandbox(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        Task { @MainActor in
            ServiceContainer.shared?.navigationCoordinator.navigate(to: .sandbox(name: name))
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let content = response.notification.request.content
        let category = content.categoryIdentifier
        let sandboxName = content.userInfo["sandboxName"] as? String ?? ""

        Task { @MainActor in
            guard let coordinator = ServiceContainer.shared?.navigationCoordinator else {
                completionHandler()
                return
            }

            switch category {
            case "sandbox-lifecycle":
                coordinator.navigate(to: .sandbox(name: sandboxName))
            case "policy-violation":
                coordinator.navigate(to: .policyLog(sandboxName: sandboxName))
            case "session-event":
                coordinator.navigate(to: .sandbox(name: sandboxName))
            default:
                break
            }
            completionHandler()
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
