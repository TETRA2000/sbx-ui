import SwiftUI

struct FileTreeView: View {
    let sandboxName: String
    let rootURL: URL
    @Environment(EditorStore.self) private var store

    private var showHidden: Bool {
        store.workspaces[sandboxName]?.showHidden ?? false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with hidden toggle.
            HStack {
                Text("FILES")
                    .font(.label(11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Toggle(isOn: Binding(
                    get: { store.workspaces[sandboxName]?.showHidden ?? false },
                    set: { store.setShowHidden($0, for: sandboxName) }
                )) {
                    Text("Show hidden")
                        .font(.ui(11))
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
                .accessibilityIdentifier("fileTreeHiddenToggle")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.surfaceContainer)

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    FileTreeNode(
                        sandboxName: sandboxName,
                        rootURL: rootURL,
                        entry: FileEntry(url: rootURL, name: rootURL.lastPathComponent,
                                         isDirectory: true, size: nil, mtime: nil),
                        depth: 0,
                        isRoot: true
                    )
                }
            }
        }
        .background(Color.surfaceContainer)
    }
}

private struct FileTreeNode: View {
    let sandboxName: String
    let rootURL: URL
    let entry: FileEntry
    let depth: Int
    let isRoot: Bool
    @Environment(EditorStore.self) private var store

    private var isExpanded: Bool {
        store.workspaces[sandboxName]?.expandedDirs.contains(entry.url.standardizedFileURL) ?? isRoot
    }

    private var loadState: DirectoryLoadState {
        store.workspaces[sandboxName]?.directoryLoadState[entry.url.standardizedFileURL] ?? .notLoaded
    }

    private var children: [FileEntry] {
        store.visibleChildren(sandboxName: sandboxName, path: entry.url)
    }

    private var relativePath: String {
        EditorPath.relative(entry.url, to: rootURL)
    }

    private var accessibilityID: String {
        relativePath.isEmpty ? "fileTreeNode-root" : "fileTreeNode-\(relativePath)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !isRoot {
                Button {
                    handleTap()
                } label: {
                    HStack(spacing: 4) {
                        if entry.isDirectory {
                            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                                .font(.system(size: 9))
                                .foregroundStyle(.tertiary)
                                .frame(width: 12)
                        } else {
                            Image(systemName: "doc")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                                .frame(width: 12)
                        }
                        Text(entry.name)
                            .font(.ui(12))
                            .lineLimit(1)
                            .foregroundStyle(.primary)
                        if entry.isDirectory, case .loading = loadState {
                            ProgressView().controlSize(.mini).padding(.leading, 4)
                        }
                        Spacer()
                    }
                    .padding(.leading, CGFloat(depth) * 12 + 12)
                    .padding(.vertical, 3)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(accessibilityID)
            }
            if entry.isDirectory && isExpanded {
                ForEach(children, id: \.url) { child in
                    FileTreeNode(
                        sandboxName: sandboxName,
                        rootURL: rootURL,
                        entry: child,
                        depth: isRoot ? 0 : depth + 1,
                        isRoot: false
                    )
                }
            }
        }
    }

    private func handleTap() {
        if entry.isDirectory {
            store.toggleDir(sandboxName: sandboxName, path: entry.url)
        } else {
            Task { await store.openFile(sandboxName: sandboxName, path: entry.url) }
        }
    }
}
