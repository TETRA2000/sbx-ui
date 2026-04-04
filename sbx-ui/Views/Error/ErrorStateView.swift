import SwiftUI

struct ErrorStateView: View {
    let error: SbxServiceError

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: iconName)
                .font(.system(size: 48))
                .foregroundStyle(Color.error)

            Text(title)
                .font(.ui(20, weight: .bold))
                .foregroundStyle(.white)

            Text(error.localizedDescription)
                .font(.ui(14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if let guidance = guidance {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(guidance, id: \.self) { step in
                        HStack(alignment: .top, spacing: 8) {
                            Circle()
                                .fill(Color.accent)
                                .frame(width: 4, height: 4)
                                .padding(.top, 6)
                            Text(step)
                                .font(.ui(13))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(16)
                .background(Color.surfaceContainer)
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.cornerRadius))
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.surface)
    }

    private var iconName: String {
        switch error {
        case .dockerNotRunning: "shippingbox"
        case .cliError: "terminal"
        default: "exclamationmark.triangle"
        }
    }

    private var title: String {
        switch error {
        case .dockerNotRunning: "Docker Desktop Required"
        case .cliError: "sbx CLI Not Found"
        default: "Error"
        }
    }

    private var guidance: [String]? {
        switch error {
        case .dockerNotRunning:
            [
                "Open Docker Desktop from Applications",
                "Wait for Docker to finish starting",
                "Restart sbx-ui"
            ]
        case .cliError(let msg) where msg.contains("not found") || msg.contains("Failed to launch"):
            [
                "Install sbx CLI: npm install -g @anthropic-ai/sbx",
                "Verify installation: sbx --version",
                "Restart sbx-ui"
            ]
        default:
            nil
        }
    }
}
