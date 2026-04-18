import SwiftUI

struct EditorTabsView: View {
    let sandboxName: String
    let rootURL: URL
    @Environment(EditorStore.self) private var store

    private var tabs: [EditorTab] {
        store.workspaces[sandboxName]?.tabs ?? []
    }

    private var activeTabID: UUID? {
        store.workspaces[sandboxName]?.activeTabID
    }

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(tabs) { tab in
                        tabCell(tab)
                    }
                }
            }
            Spacer()
            if tabs.count > 0 {
                overflowMenu
            }
        }
        .frame(height: 32)
        .background(Color.surfaceContainer)
        .overlay(alignment: .bottom) { Rectangle().fill(.black.opacity(0.25)).frame(height: 1) }
    }

    @ViewBuilder
    private func tabCell(_ tab: EditorTab) -> some View {
        let relative = EditorPath.relative(tab.path, to: rootURL)
        let isActive = (tab.id == activeTabID)
        let isDirty = tab.tentativelyDirty || EditorStore.fingerprint(of: tab.contents) != tab.savedFingerprint
        let isSaving: Bool = { if case .saving = tab.status { return true } else { return false } }()
        let isFlashing: Bool = { if case .savedFlash = tab.status { return true } else { return false } }()

        HStack(spacing: 6) {
            if isDirty {
                Circle()
                    .fill(Color.accent)
                    .frame(width: 7, height: 7)
                    .accessibilityIdentifier("editorTabDirtyIndicator-\(relative)")
            } else if isSaving {
                ProgressView().controlSize(.mini)
            }
            Text(tab.path.lastPathComponent)
                .font(.ui(12))
                .foregroundStyle(isDirty ? Color.accent : Color.primary)
                .lineLimit(1)
            Button {
                _ = store.closeTab(sandboxName: sandboxName, tabID: tab.id, force: false)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("editorTabCloseButton-\(relative)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .frame(height: 32)
        .background(isActive ? Color.surfaceContainerHigh : Color.surfaceContainer)
        .overlay(alignment: .bottom) {
            if isActive {
                Rectangle().fill(Color.accent).frame(height: 2)
            }
        }
        .overlay {
            if isFlashing {
                Rectangle().fill(Color.secondary.opacity(0.18))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            store.activateTab(sandboxName: sandboxName, tabID: tab.id)
        }
        .accessibilityIdentifier("editorTab-\(relative)")
    }

    private var overflowMenu: some View {
        Menu {
            ForEach(tabs.sorted(by: { $0.path.lastPathComponent < $1.path.lastPathComponent })) { tab in
                Button {
                    store.activateTab(sandboxName: sandboxName, tabID: tab.id)
                } label: {
                    let isDirty = tab.tentativelyDirty || EditorStore.fingerprint(of: tab.contents) != tab.savedFingerprint
                    Text(isDirty ? "● \(tab.path.lastPathComponent)" : tab.path.lastPathComponent)
                }
            }
        } label: {
            Image(systemName: "chevron.down.square")
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .padding(.horizontal, 8)
    }
}
