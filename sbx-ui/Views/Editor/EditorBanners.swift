import SwiftUI

struct EmptyWorkspacePlaceholder: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            Text("No workspace available")
                .font(.ui(14, weight: .semibold))
            Text("This sandbox has no workspace directory set.")
                .font(.ui(12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.surfaceLowest)
        .accessibilityIdentifier("editorEmptyWorkspacePlaceholder")
    }
}

struct LargeFileBanner: View {
    let relativePath: String
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.accent)
            Text("Large file — opened in read-only preview")
                .font(.ui(12))
            Spacer()
        }
        .padding(10)
        .background(Color.surfaceContainerHigh)
        .accessibilityIdentifier("editorLargeFileBanner")
    }
}

struct TooLargeFilePlaceholder: View {
    let relativePath: String
    let size: Int64
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "xmark.octagon.fill")
                .font(.system(size: 28))
                .foregroundStyle(Color.error)
            Text("File too large to open")
                .font(.ui(14, weight: .semibold))
            Text(relativePath)
                .font(.code(11))
                .foregroundStyle(.secondary)
            Text("\(size / (1024 * 1024)) MB")
                .font(.code(11))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.surfaceLowest)
    }
}

struct BinaryFilePlaceholder: View {
    let relativePath: String
    let onCopyPath: () -> Void
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "doc.questionmark")
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            Text("Binary file")
                .font(.ui(14, weight: .semibold))
            Text(relativePath)
                .font(.code(11))
                .foregroundStyle(.secondary)
            Button("Copy path", action: onCopyPath)
                .buttonStyle(.bordered)
                .font(.ui(11))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.surfaceLowest)
        .accessibilityIdentifier("editorBinaryBanner")
    }
}

struct SandboxStatusBanner: View {
    let message: String
    let severity: Severity

    enum Severity { case info, warning, error }

    private var color: Color {
        switch severity {
        case .info: .accent
        case .warning: .accent
        case .error: .error
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: severity == .error ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(color)
            Text(message).font(.ui(12))
            Spacer()
        }
        .padding(10)
        .background(Color.surfaceContainerHigh)
    }
}
