import SwiftUI
import AppKit

struct EditorPanelView: View {
    let sandboxName: String
    let rootURL: URL
    @Environment(EditorStore.self) private var store
    @State private var findBarVisible = false
    @State private var findQuery = ""
    @State private var findCaseSensitive = false
    @State private var findWholeWord = false

    private var state: SandboxWorkspaceState? {
        store.workspaces[sandboxName]
    }

    private var activeTab: EditorTab? {
        guard let state, let id = state.activeTabID else { return nil }
        return state.tabs.first(where: { $0.id == id })
    }

    var body: some View {
        VStack(spacing: 0) {
            if state?.isWorkspaceMissing == true {
                EmptyWorkspacePlaceholder()
            } else {
                HStack(spacing: 0) {
                    ChangedFilesListView(sandboxName: sandboxName, rootURL: rootURL)
                        .frame(width: 240)
                    Divider()
                    editorColumn
                }
            }
        }
        .background(Color.surface)
        .accessibilityIdentifier("editorPane-\(sandboxName)")
    }

    @ViewBuilder
    private var editorColumn: some View {
        VStack(spacing: 0) {
            EditorTabsView(sandboxName: sandboxName, rootURL: rootURL)
            if findBarVisible {
                EditorFindBar(
                    sandboxName: sandboxName,
                    isVisible: $findBarVisible,
                    query: $findQuery,
                    caseSensitive: $findCaseSensitive,
                    wholeWord: $findWholeWord,
                    matches: matchesInActiveTab,
                    currentIndex: 0,
                    onNext: {},
                    onPrev: {},
                    onDismiss: { findBarVisible = false; findQuery = "" }
                )
            }
            bufferOrPlaceholder
        }
    }

    @ViewBuilder
    private var bufferOrPlaceholder: some View {
        if let tab = activeTab {
            VStack(spacing: 0) {
                switch tab.status {
                case .tooLarge(let size):
                    TooLargeFilePlaceholder(relativePath: EditorPath.relative(tab.path, to: rootURL), size: size)
                case .binary:
                    BinaryFilePlaceholder(
                        relativePath: EditorPath.relative(tab.path, to: rootURL),
                        onCopyPath: {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(tab.path.path, forType: .string)
                        }
                    )
                case .deleted:
                    DeletedFilePlaceholder(relativePath: EditorPath.relative(tab.path, to: rootURL))
                case .readOnly:
                    LargeFileBanner(relativePath: EditorPath.relative(tab.path, to: rootURL))
                    EditorBufferView(
                        sandboxName: sandboxName,
                        tabID: tab.id,
                        initialContents: String(data: tab.contents, encoding: .utf8) ?? "",
                        readOnly: true,
                        loading: false,
                        store: store
                    )
                case .loading:
                    SkeletonBufferPlaceholder()
                case .failed(let message):
                    SandboxStatusBanner(message: message, severity: .error)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.surfaceLowest)
                case .editable, .saving, .savedFlash:
                    EditorBufferView(
                        sandboxName: sandboxName,
                        tabID: tab.id,
                        initialContents: String(data: tab.contents, encoding: .utf8) ?? "",
                        readOnly: false,
                        loading: false,
                        store: store
                    )
                }
                saveKeyboardCatcher(tab: tab)
            }
            .background(Color.surfaceLowest)
        } else {
            Color.surfaceLowest
                .overlay(
                    VStack(spacing: 8) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 28))
                            .foregroundStyle(.tertiary)
                        Text("Select a file to start editing")
                            .font(.ui(13))
                            .foregroundStyle(.secondary)
                    }
                )
        }
    }

    @ViewBuilder
    private func saveKeyboardCatcher(tab: EditorTab) -> some View {
        // Invisible button bound to Cmd+S so the editor pane responds to save
        // even while focus is in the NSTextView hosted by EditorBufferView.
        Button {
            Task { _ = await store.save(sandboxName: sandboxName, tabID: tab.id) }
        } label: { EmptyView() }
        .keyboardShortcut("s", modifiers: .command)
        .frame(width: 0, height: 0)
        .accessibilityIdentifier("editorSaveButton")
    }

    private var matchesInActiveTab: [Range<String.Index>] {
        guard let tab = activeTab, let str = String(data: tab.contents, encoding: .utf8) else { return [] }
        return EditorFindEngine.matches(in: str, query: findQuery,
                                        caseSensitive: findCaseSensitive, wholeWord: findWholeWord)
    }
}

private struct SkeletonBufferPlaceholder: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(0..<8, id: \.self) { i in
                Rectangle()
                    .fill(Color.surfaceContainer)
                    .frame(height: 10)
                    .frame(maxWidth: CGFloat(120 + (i % 3) * 80))
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.surfaceLowest)
    }
}
