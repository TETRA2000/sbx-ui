import SwiftUI

struct ConfirmCloseDialog: View {
    let dirtyTabs: [DirtyTabSummary]
    let onSave: () -> Void
    let onDiscard: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(dirtyTabs.count == 1 ? "Unsaved changes" : "Unsaved changes in \(dirtyTabs.count) files")
                .font(.ui(16, weight: .semibold))
            if dirtyTabs.count > 1 {
                ForEach(dirtyTabs) { t in
                    Text(t.path.lastPathComponent)
                        .font(.code(11))
                        .foregroundStyle(.secondary)
                }
            } else if let single = dirtyTabs.first {
                Text(single.path.lastPathComponent)
                    .font(.code(12))
                    .foregroundStyle(.secondary)
            }
            Text("Save changes before closing?")
                .font(.ui(12))
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Discard", role: .destructive, action: onDiscard)
                Button("Save", action: onSave)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 420)
        .background(Color.surfaceContainer)
        .accessibilityIdentifier("editorConfirmCloseDialog")
    }
}

struct ExternalChangeDialog: View {
    let path: URL
    let onReload: () -> Void
    let onKeepMine: () -> Void
    let onShowDiff: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("File changed on disk")
                .font(.ui(16, weight: .semibold))
            Text(path.lastPathComponent)
                .font(.code(12))
                .foregroundStyle(.secondary)
            Text("Another process modified this file since it was opened.")
                .font(.ui(12))
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Show diff", action: onShowDiff)
                Button("Keep mine", action: onKeepMine)
                Button("Reload", action: onReload)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 420)
        .background(Color.surfaceContainer)
        .accessibilityIdentifier("editorExternalChangeDialog")
    }
}

struct TabLimitWarningDialog: View {
    let onDismiss: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tab limit reached")
                .font(.ui(16, weight: .semibold))
            Text("Close some tabs before opening more files (limit: \(EditorStore.maxOpenTabs)).")
                .font(.ui(12))
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("OK", action: onDismiss)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 380)
        .background(Color.surfaceContainer)
    }
}
