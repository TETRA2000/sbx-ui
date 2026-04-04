import SwiftUI

@MainActor @Observable final class ToastManager {
    struct Toast: Identifiable {
        let id = UUID()
        let message: String
        let isError: Bool
    }

    var toasts: [Toast] = []

    func show(_ message: String, isError: Bool = true) {
        let toast = Toast(message: message, isError: isError)
        toasts.append(toast)

        Task {
            try? await Task.sleep(for: .seconds(4))
            toasts.removeAll { $0.id == toast.id }
        }
    }
}

struct ToastOverlay: View {
    @Environment(ToastManager.self) private var toastManager

    var body: some View {
        VStack(spacing: 8) {
            ForEach(toastManager.toasts) { toast in
                HStack(spacing: 8) {
                    Image(systemName: toast.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(toast.isError ? Color.error : Color.secondary)
                    Text(toast.message)
                        .font(.ui(12))
                        .foregroundStyle(.white)
                    Spacer()
                    Button {
                        toastManager.toasts.removeAll { $0.id == toast.id }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(12)
                .background(Color.surfaceContainerHigh)
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.cornerRadius))
                .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .animation(.spring(duration: 0.3), value: toastManager.toasts.count)
    }
}
