import SwiftUI

struct StatusChipView: View {
    let status: SandboxStatus

    var body: some View {
        HStack(spacing: 6) {
            switch status {
            case .running:
                Circle()
                    .fill(Color.secondary)
                    .frame(width: 4, height: 4)
                    .modifier(PulseModifier())
                Text("LIVE")
                    .font(.label(10))
                    .foregroundStyle(Color.secondary)
            case .stopped:
                Text("STOPPED")
                    .font(.label(10))
                    .foregroundStyle(Color.surfaceContainerHighest)
            case .creating, .removing:
                ProgressView()
                    .controlSize(.mini)
                Text(status == .creating ? "CREATING" : "REMOVING")
                    .font(.label(10))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            status == .running
                ? Color.secondary.opacity(0.15)
                : Color.surfaceContainerHigh.opacity(0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .accessibilityIdentifier("statusChip-\(status.rawValue)")
    }
}

private struct PulseModifier: ViewModifier {
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .opacity(isPulsing ? 0.3 : 1.0)
            .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: isPulsing)
            .onAppear { isPulsing = true }
    }
}
