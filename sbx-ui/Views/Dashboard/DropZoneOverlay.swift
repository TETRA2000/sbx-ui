import SwiftUI

struct DropZoneOverlay: View {
    let isVisible: Bool

    var body: some View {
        if isVisible {
            ZStack {
                RoundedRectangle(cornerRadius: DesignSystem.cornerRadius)
                    .fill(Color.surface.opacity(0.85))

                VStack(spacing: 12) {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 40))
                        .foregroundStyle(Color.accent)

                    Text("Drop to create sandbox")
                        .font(.ui(16, weight: .semibold))
                        .foregroundStyle(Color.accent)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.cornerRadius)
                    .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8, 4]))
                    .foregroundStyle(Color.accent)
            )
            .padding(16)
            .accessibilityIdentifier("dropZoneOverlay")
        }
    }
}
