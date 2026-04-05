import SwiftUI

struct MenuBarPopoverView: View {
    @State private var sandboxes: [Sandbox] = []
    @State private var isLoading = true

    private var runningSandboxes: [Sandbox] {
        sandboxes.filter { $0.status == .running }
    }

    private var stoppedSandboxes: [Sandbox] {
        sandboxes.filter { $0.status == .stopped }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Image(systemName: "shippingbox.fill")
                    .foregroundStyle(Color.accent)
                Text("sbx-ui")
                    .font(.headline)
                Spacer()
                if !runningSandboxes.isEmpty {
                    Text("\(runningSandboxes.count) running")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            if sandboxes.isEmpty && !isLoading {
                Text("No sandboxes")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(runningSandboxes) { sandbox in
                            sandboxRow(sandbox)
                        }
                        ForEach(stoppedSandboxes) { sandbox in
                            sandboxRow(sandbox)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: 300)
            }

            Divider()

            // Actions
            VStack(spacing: 2) {
                Button {
                    ServiceContainer.shared?.navigationCoordinator.navigate(to: .createSheet)
                } label: {
                    HStack {
                        Image(systemName: "plus.circle")
                        Text("New Sandbox…")
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("menuBarNewSandboxButton")

                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    HStack {
                        Image(systemName: "xmark.circle")
                        Text("Quit")
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("menuBarQuitButton")
            }
            .padding(.vertical, 4)
        }
        .frame(width: 280)
        .task {
            while !Task.isCancelled {
                sandboxes = ServiceContainer.shared?.sandboxStore.sandboxes ?? []
                isLoading = ServiceContainer.shared?.sandboxStore.initialLoading ?? false
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    @ViewBuilder
    private func sandboxRow(_ sandbox: Sandbox) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Circle()
                    .fill(sandbox.status == .running ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)
                Text(sandbox.name)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)
                Spacer()
                Text(sandbox.status.rawValue.uppercased())
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .accessibilityIdentifier("menuBarSandboxItem-\(sandbox.name)")

            HStack(spacing: 8) {
                if sandbox.status == .running {
                    Button("Stop") {
                        Task {
                            try? await ServiceContainer.shared?.sandboxStore.stopSandbox(name: sandbox.name)
                        }
                    }
                    .font(.caption)
                    .accessibilityIdentifier("menuBarStopButton-\(sandbox.name)")
                } else if sandbox.status == .stopped {
                    Button("Resume") {
                        Task {
                            try? await ServiceContainer.shared?.sandboxStore.resumeSandbox(name: sandbox.name)
                        }
                    }
                    .font(.caption)
                    .accessibilityIdentifier("menuBarResumeButton-\(sandbox.name)")
                }

                Button("Open in App") {
                    ServiceContainer.shared?.navigationCoordinator.navigate(to: .sandbox(name: sandbox.name))
                }
                .font(.caption)
                .accessibilityIdentifier("menuBarOpenButton-\(sandbox.name)")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.clear)
    }
}
