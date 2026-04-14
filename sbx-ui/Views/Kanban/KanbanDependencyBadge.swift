import SwiftUI

struct KanbanDependencyBadge: View {
    let task: KanbanTask
    let board: KanbanBoard

    private var totalDeps: Int { task.dependencyIDs.count }

    private var resolvedCount: Int {
        task.dependencyIDs.filter { depID in
            board.tasks.first { $0.id == depID }?.status == .completed
        }.count
    }

    private var hasFailed: Bool {
        task.dependencyIDs.contains { depID in
            board.tasks.first { $0.id == depID }?.status == .failed
        }
    }

    private var badgeColor: Color {
        if hasFailed { return Color.error }
        if resolvedCount == totalDeps { return Color.secondary }
        return Color(red: 0xFF / 255, green: 0xB7 / 255, blue: 0x4D / 255) // orange
    }

    var body: some View {
        if totalDeps > 0 {
            HStack(spacing: 3) {
                Image(systemName: "link")
                    .font(.system(size: 8))
                Text("\(resolvedCount)/\(totalDeps) deps")
                    .font(.code(9))
            }
            .foregroundStyle(badgeColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(badgeColor.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
    }
}
