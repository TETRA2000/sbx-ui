import SwiftUI

/// Flat list of git-changed files for the editor's leading panel. Replaces
/// the original recursive file tree (per `editor` spec R2.*) — the list shows
/// only files reported by `git status --porcelain=v1`, sorted alphabetically
/// by relative path, with a tonal-colored change-type badge.
struct ChangedFilesListView: View {
    let sandboxName: String
    let rootURL: URL
    @Environment(EditorStore.self) private var store

    private var state: SandboxWorkspaceState? {
        store.workspaces[sandboxName]
    }

    private var entries: [ChangedFileEntry] {
        state?.changedFiles ?? []
    }

    private var loadState: ChangedFilesLoadState {
        state?.changedFilesLoadState ?? .notLoaded
    }

    private var isLoading: Bool {
        if case .loading = loadState { return true }
        return false
    }

    private var isNotGitRepo: Bool {
        if case .notGitRepository = loadState { return true }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            listContent
        }
        .background(Color.surfaceContainer)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text("CHANGES")
                .font(.label(11, weight: .semibold))
                .foregroundStyle(.secondary)
            if isLoading {
                ProgressView().controlSize(.mini)
            }
            Spacer()
            Button {
                Task { await store.refreshChangedFiles(sandboxName: sandboxName) }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .disabled(isLoading)
            .help("Refresh")
            .accessibilityLabel("Refresh")
            .accessibilityIdentifier("changedFileRefresh")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.surfaceContainer)
    }

    @ViewBuilder
    private var listContent: some View {
        if isNotGitRepo {
            NotGitRepoPlaceholder()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if entries.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(entries) { entry in
                        ChangedFileRow(
                            entry: entry,
                            sandboxName: sandboxName,
                            enabled: !isLoading
                        )
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.seal")
                .font(.system(size: 22))
                .foregroundStyle(.tertiary)
            Text(isLoading ? "Loading changes…" : "No changes")
                .font(.ui(12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}

private struct ChangedFileRow: View {
    let entry: ChangedFileEntry
    let sandboxName: String
    let enabled: Bool
    @Environment(EditorStore.self) private var store
    @State private var isHovering = false

    var body: some View {
        Button {
            guard enabled else { return }
            Task { await store.openFile(sandboxName: sandboxName, path: entry.url) }
        } label: {
            HStack(spacing: 8) {
                badge
                Text(entry.relativePath)
                    .font(.ui(12))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isHovering ? Color.surfaceContainerHigh : Color.surfaceContainer)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .onHover { hovering in isHovering = hovering }
        .accessibilityIdentifier("changedFileRow-\(entry.relativePath)")
    }

    private var badge: some View {
        Text(entry.changeType.rawValue)
            .font(.code(11, weight: .semibold))
            .foregroundStyle(badgeColor)
            .frame(width: 16, height: 16)
            .background(badgeBackground)
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .accessibilityIdentifier("changedFileBadge-\(entry.relativePath)")
    }

    private var badgeColor: Color {
        switch entry.changeType {
        case .modified: .accent
        case .added: .secondary
        case .deleted: .error
        case .renamed: .accent
        case .untracked: .secondary
        }
    }

    private var badgeBackground: Color {
        switch entry.changeType {
        case .modified: Color.accent.opacity(0.15)
        case .added: Color.secondary.opacity(0.15)
        case .deleted: Color.error.opacity(0.15)
        case .renamed: Color.accent.opacity(0.12)
        case .untracked: Color.secondary.opacity(0.12)
        }
    }
}
