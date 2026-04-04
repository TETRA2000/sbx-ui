import SwiftUI

struct ChatInputView: View {
    @Environment(SessionStore.self) private var sessionStore
    @Environment(ToastManager.self) private var toastManager
    @State private var message = ""

    var body: some View {
        HStack(spacing: 8) {
            TextField("Send a message...", text: $message)
                .font(.code(13))
                .textFieldStyle(.plain)
                .padding(8)
                .background(Color.surfaceContainerHigh)
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.cornerRadius))
                .onSubmit { sendMessage() }
                .disabled(!sessionStore.connected)
                .accessibilityIdentifier("chatInput")

            Button {
                sendMessage()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(Color.accent)
            }
            .buttonStyle(.plain)
            .disabled(!sessionStore.connected || message.trimmingCharacters(in: .whitespaces).isEmpty)
            .accessibilityIdentifier("sendButton")
        }
        .padding(12)
        .background(Color.surfaceContainer)
    }

    private func sendMessage() {
        let text = message.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, sessionStore.connected else { return }
        message = ""
        Task {
            do {
                try await sessionStore.sendMessage(text)
            } catch {
                toastManager.show(error.localizedDescription)
            }
        }
    }
}
