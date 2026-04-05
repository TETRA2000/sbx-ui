import Foundation
import SwiftUI

// DropHandler — workspace drag-and-drop logic for the dashboard.
/// Handles drag-and-drop of workspace directories onto the dashboard.
struct DropHandler {
    /// Handle a drop event from NSItemProviders (used by SwiftUI onDrop).
    /// Loads the URL from the first provider and delegates to `handleDroppedURL`.
    @MainActor
    static func handleDrop(
        providers: [NSItemProvider],
        sandboxes: [Sandbox],
        coordinator: NavigationCoordinator,
        showCreateSheet: inout Bool,
        droppedWorkspacePath: inout String?
    ) -> Bool {
        guard let provider = providers.first else { return false }

        // Capture values before async closure
        let currentSandboxes = sandboxes
        let currentCoordinator = coordinator

        provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil) else { return }

            Task { @MainActor in
                var showSheet = false
                var droppedPath: String?
                let result = handleDroppedURL(
                    url,
                    sandboxes: currentSandboxes,
                    coordinator: currentCoordinator,
                    showCreateSheet: &showSheet,
                    droppedWorkspacePath: &droppedPath
                )
                if result, showSheet, let path = droppedPath {
                    currentCoordinator.navigate(to: .createWithWorkspace(path: path))
                }
            }
        }

        // Return true to accept the drop (actual handling is async)
        return true
    }

    /// Core testable logic: given a resolved URL, decide what to do.
    /// Returns true if the URL was a valid directory, false otherwise.
    @MainActor
    static func handleDroppedURL(
        _ url: URL,
        sandboxes: [Sandbox],
        coordinator: NavigationCoordinator,
        showCreateSheet: inout Bool,
        droppedWorkspacePath: inout String?
    ) -> Bool {
        guard url.hasDirectoryPath else { return false }

        // Directory file URLs end with "/" in modern Foundation.
        // Strip trailing slash for consistent comparison with Sandbox.workspace.
        let path = Self.normalizedPath(from: url)

        // Check if an existing running sandbox uses this workspace
        if let existing = sandboxes.first(where: { $0.workspace == path && $0.status == .running }) {
            coordinator.navigate(to: .sandbox(name: existing.name))
            return true
        }

        // Open create sheet pre-filled with the dropped workspace
        droppedWorkspacePath = path
        showCreateSheet = true
        return true
    }

    /// Extract a normalized filesystem path from a URL, stripping any trailing slash.
    /// On modern Foundation (macOS 26+), `url.path` preserves trailing slashes for directories.
    static func normalizedPath(from url: URL) -> String {
        // pathComponents already strips trailing slashes: ["/", "tmp", "my-project"]
        let components = url.pathComponents
        guard !components.isEmpty else { return "/" }
        if components.count == 1 { return components[0] }
        // Skip leading "/" component, rejoin with "/"
        return "/" + components.dropFirst().joined(separator: "/")
    }
}
