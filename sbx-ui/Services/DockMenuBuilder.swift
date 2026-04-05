import AppKit

enum DockMenuBuilder {
    /// Builds a dock menu from the current list of sandboxes.
    /// - Parameter sandboxes: All known sandboxes.
    /// - Returns: An `NSMenu` suitable for the application dock menu.
    nonisolated static func buildMenu(sandboxes: [Sandbox]) -> NSMenu {
        let menu = NSMenu()

        // Always include "New Sandbox…" at the top
        let newItem = NSMenuItem(title: "New Sandbox…", action: #selector(DockMenuActions.newSandbox(_:)), keyEquivalent: "")
        menu.addItem(newItem)

        guard !sandboxes.isEmpty else { return menu }

        // Separator between "New Sandbox…" and sandbox items
        menu.addItem(.separator())

        // Group by status: running first, then stopped
        let running = sandboxes.filter { $0.status == .running }
        let stopped = sandboxes.filter { $0.status == .stopped }
        let ordered = running + stopped

        for sandbox in ordered {
            let item = NSMenuItem(title: sandbox.name, action: nil, keyEquivalent: "")
            item.representedObject = sandbox.name

            let submenu = NSMenu()

            if sandbox.status == .running {
                let stopItem = NSMenuItem(title: "Stop", action: #selector(DockMenuActions.stopSandbox(_:)), keyEquivalent: "")
                stopItem.representedObject = sandbox.name
                submenu.addItem(stopItem)
            } else {
                let resumeItem = NSMenuItem(title: "Resume", action: #selector(DockMenuActions.resumeSandbox(_:)), keyEquivalent: "")
                resumeItem.representedObject = sandbox.name
                submenu.addItem(resumeItem)
            }

            let openItem = NSMenuItem(title: "Open", action: #selector(DockMenuActions.openSandbox(_:)), keyEquivalent: "")
            openItem.representedObject = sandbox.name
            submenu.addItem(openItem)

            item.submenu = submenu
            menu.addItem(item)
        }

        return menu
    }
}

// MARK: - Selector targets for dock menu actions

/// Objective-C compatible protocol providing selectors for dock menu items.
/// The actual action handling is wired in the AppDelegate.
@objc protocol DockMenuActions {
    @objc func newSandbox(_ sender: NSMenuItem)
    @objc func stopSandbox(_ sender: NSMenuItem)
    @objc func resumeSandbox(_ sender: NSMenuItem)
    @objc func openSandbox(_ sender: NSMenuItem)
}
