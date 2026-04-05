import SwiftUI

struct PolicyPanelView: View {
    @Environment(PolicyStore.self) private var policyStore
    @Environment(ToastManager.self) private var toastManager
    @State private var showAddSheet = false
    @State private var showLogView = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Network Policies")
                    .font(.ui(18, weight: .semibold))
                Spacer()

                Button {
                    showLogView.toggle()
                } label: {
                    Label("Activity Log", systemImage: "list.bullet.rectangle")
                        .font(.ui(12))
                }
                .buttonStyle(.bordered)

                Button {
                    showAddSheet = true
                } label: {
                    Label("Add Policy", systemImage: "plus")
                        .font(.ui(12))
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.accent)
                .accessibilityIdentifier("addPolicyButton")
            }
            .padding(20)

            if showLogView {
                PolicyLogView()
                    .frame(height: 300)
                Divider()
                    .background(Color.surfaceContainerHigh.opacity(0.15))
            }

            // Rules list
            if policyStore.loading && policyStore.rules.isEmpty {
                ProgressView("Loading policies\u{2026}")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if policyStore.rules.isEmpty {
                ContentUnavailableView("No Policies", systemImage: "shield.slash", description: Text("Add network policies to control sandbox access."))
                    .frame(maxHeight: .infinity)
            } else {
                List {
                    ForEach(policyStore.rules) { rule in
                        PolicyRuleRow(rule: rule)
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }
        }
        .background(Color.surface)
        .task {
            await policyStore.fetchPolicies()
        }
        .sheet(isPresented: $showAddSheet) {
            AddPolicySheet()
        }
    }
}

struct PolicyRuleRow: View {
    let rule: PolicyRule
    @Environment(PolicyStore.self) private var policyStore
    @Environment(ToastManager.self) private var toastManager

    var body: some View {
        HStack {
            // Decision badge
            Text(rule.decision.rawValue.uppercased())
                .font(.label(10))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .foregroundStyle(rule.decision == .allow ? Color.secondary : Color.error)
                .background(
                    (rule.decision == .allow ? Color.secondary : Color.error).opacity(0.15)
                )
                .clipShape(RoundedRectangle(cornerRadius: 4))

            Text(rule.resources)
                .font(.code(13))
                .foregroundStyle(.primary)

            Spacer()

            Button {
                Task {
                    do {
                        try await policyStore.removeRule(resource: rule.resources)
                    } catch {
                        toastManager.show(error.localizedDescription)
                    }
                }
            } label: {
                if policyStore.removingResources.contains(rule.resources) {
                    ProgressView()
                        .controlSize(.mini)
                } else {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.error.opacity(0.7))
                }
            }
            .buttonStyle(.plain)
            .disabled(policyStore.removingResources.contains(rule.resources))
            .accessibilityIdentifier("removePolicy-\(rule.resources)")
        }
        .padding(.vertical, 4)
        .listRowBackground(Color.surfaceContainer)
    }
}
