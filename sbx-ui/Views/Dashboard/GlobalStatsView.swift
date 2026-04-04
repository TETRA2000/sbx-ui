import SwiftUI

struct GlobalStatsView: View {
    @Environment(SandboxStore.self) private var sandboxStore

    private var runningCount: Int {
        sandboxStore.sandboxes.filter { $0.status == .running }.count
    }

    private var totalCount: Int {
        sandboxStore.sandboxes.count
    }

    var body: some View {
        HStack(spacing: 24) {
            StatItem(label: "RUNNING", value: "\(runningCount)", color: .secondary)
            StatItem(label: "TOTAL", value: "\(totalCount)", color: .accent)
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(Color.surfaceContainer)
    }
}

private struct StatItem: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Text(value)
                .font(.code(20, weight: .bold))
                .foregroundStyle(color)
            Text(label)
                .font(.label(10))
                .foregroundStyle(.secondary)
                .tracking(1.0)
        }
    }
}
