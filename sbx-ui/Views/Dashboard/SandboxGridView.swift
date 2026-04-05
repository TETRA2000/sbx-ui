import SwiftUI

struct SandboxGridView: View {
    var onSelectSandbox: (Sandbox) -> Void
    var onCreateNew: () -> Void
    var onOpenShellSession: (String) -> Void
    @Environment(SandboxStore.self) private var sandboxStore

    private let columns = [
        GridItem(.adaptive(minimum: 280, maximum: 400), spacing: 16)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 16) {
            ForEach(sandboxStore.sandboxes) { sandbox in
                SandboxCardView(
                    sandbox: sandbox,
                    onSelect: onSelectSandbox,
                    onOpenShellSession: onOpenShellSession
                )
            }

            // "+" placeholder card
            Button(action: onCreateNew) {
                VStack(spacing: 12) {
                    Image(systemName: "plus")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(.secondary)
                    Text("New Sandbox")
                        .font(.ui(13))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 160)
                .background(Color.surfaceContainer.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.cornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.cornerRadius)
                        .strokeBorder(Color.surfaceContainerHigh, style: StrokeStyle(lineWidth: 1, dash: [6]))
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("newSandboxButton")
        }
    }
}
