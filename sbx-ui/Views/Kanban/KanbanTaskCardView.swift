import SwiftUI
import AppKit

struct KanbanTaskCardView: View {
    let task: KanbanTask
    let board: KanbanBoard
    var onEdit: () -> Void
    var onStart: () -> Void
    var onCancel: () -> Void
    var onDelete: () -> Void

    @Environment(TerminalSessionStore.self) private var sessionStore
    @State private var isHovered = false
    @State private var showDeleteConfirm = false

    private var statusColor: Color {
        switch task.status {
        case .pending: return Color.surfaceContainerHighest
        case .blocked: return Color(red: 0xFF / 255, green: 0xB7 / 255, blue: 0x4D / 255)
        case .creating: return Color.accent
        case .running: return Color.secondary
        case .completed: return Color.accent
        case .failed: return Color.error
        case .cancelled: return Color.surfaceContainerHighest
        }
    }

    private var statusLabel: String {
        switch task.status {
        case .pending: return "PENDING"
        case .blocked: return "BLOCKED"
        case .creating: return "CREATING"
        case .running: return "LIVE"
        case .completed: return "DONE"
        case .failed: return "FAILED"
        case .cancelled: return "CANCELLED"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header: title + status
            HStack(alignment: .top) {
                Text(task.title)
                    .font(.ui(13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                Spacer()
                statusChip
            }

            // Sandbox
            if let sbxName = task.sandboxName {
                HStack(spacing: 3) {
                    Image(systemName: "shippingbox")
                        .font(.system(size: 9))
                    Text(sbxName)
                        .font(.code(10))
                }
                .foregroundStyle(.secondary)
            }

            // Prompt preview
            if !task.prompt.isEmpty {
                Text(task.prompt)
                    .font(.ui(11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.tail)
            }

            // Terminal thumbnail (if sandbox is running)
            if let sbxName = task.sandboxName,
               let agentID = sessionStore.agentSessionID(for: sbxName),
               let thumbnail = sessionStore.thumbnails[agentID] {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .frame(height: 80)
                    .clipped()
                    .background(Color.surfaceLowest)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            // Bottom: dependency badge + actions
            HStack(spacing: 6) {
                KanbanDependencyBadge(task: task, board: board)

                Spacer()

                if task.status == .pending || task.status == .blocked {
                    Button {
                        onStart()
                    } label: {
                        Image(systemName: "play.fill")
                            .font(.system(size: 9))
                    }
                    .buttonStyle(.bordered)
                    .tint(Color.secondary)
                    .disabled(task.status == .blocked)
                    .accessibilityIdentifier("startTaskButton-\(task.id)")
                }

                if task.status == .running || task.status == .creating {
                    Button {
                        onCancel()
                    } label: {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 9))
                    }
                    .buttonStyle(.bordered)
                    .tint(Color.error)
                    .accessibilityIdentifier("cancelTaskButton-\(task.id)")
                }

                Button {
                    showDeleteConfirm = true
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 9))
                }
                .buttonStyle(.bordered)
                .tint(Color.error.opacity(0.6))
                .accessibilityIdentifier("deleteTaskButton-\(task.id)")
            }
        }
        .padding(12)
        .background(isHovered ? Color.surfaceContainerHigh : Color.surfaceContainer)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.cornerRadius))
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onEdit() }
        .confirmationDialog("Delete task '\(task.title)'?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) { onDelete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This task will be permanently removed.")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("kanbanTaskCard-\(task.id)")
    }

    private var statusChip: some View {
        HStack(spacing: 4) {
            if task.status == .running {
                Circle()
                    .fill(statusColor)
                    .frame(width: 4, height: 4)
                    .modifier(KanbanPulseModifier())
            } else if task.status == .creating {
                ProgressView()
                    .controlSize(.mini)
            }
            Text(statusLabel)
                .font(.label(9))
                .foregroundStyle(statusColor)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(statusColor.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

private struct KanbanPulseModifier: ViewModifier {
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .opacity(isPulsing ? 0.3 : 1.0)
            .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: isPulsing)
            .onAppear { isPulsing = true }
    }
}
