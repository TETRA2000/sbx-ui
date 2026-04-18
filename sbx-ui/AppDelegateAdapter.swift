import Foundation
import AppKit

/// NSApplicationDelegate attached via `@NSApplicationDelegateAdaptor`.
/// Implements the quit-with-dirty prompt from Requirement 10.7. Reads the
/// shared `EditorStore` lazily at termination time — no stored reference.
final class AppDelegateAdapter: NSObject, NSApplicationDelegate {
    private var pendingSaveAll = false

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let summary = EditorStore.shared.dirtyTabsSummary()
        guard !summary.isEmpty else { return .terminateNow }

        let alert = NSAlert()
        alert.messageText = summary.count == 1
            ? "1 file has unsaved changes."
            : "\(summary.count) files have unsaved changes."
        let paths = summary.map { $0.path.lastPathComponent }.joined(separator: ", ")
        alert.informativeText = "Save changes before quitting?\n\n\(paths)"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Save All")
        alert.addButton(withTitle: "Discard")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn: // Save All
            pendingSaveAll = true
            Task { @MainActor in
                var anyFailure = false
                for (name, _) in EditorStore.shared.workspaces {
                    let results = await EditorStore.shared.saveAll(sandboxName: name)
                    for (_, result) in results {
                        if case .failed = result { anyFailure = true }
                    }
                }
                sender.reply(toApplicationShouldTerminate: !anyFailure)
            }
            return .terminateLater
        case .alertSecondButtonReturn: // Discard
            return .terminateNow
        default: // Cancel
            return .terminateCancel
        }
    }
}
