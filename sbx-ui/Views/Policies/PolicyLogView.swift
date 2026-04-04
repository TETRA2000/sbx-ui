import SwiftUI

struct PolicyLogView: View {
    @Environment(PolicyStore.self) private var policyStore
    @Environment(SandboxStore.self) private var sandboxStore

    var body: some View {
        @Bindable var store = policyStore

        VStack(spacing: 0) {
            // Filters
            HStack(spacing: 12) {
                Text("Activity Log")
                    .font(.ui(14, weight: .semibold))

                Spacer()

                Picker("Sandbox", selection: $store.logFilter.sandboxName) {
                    Text("All Sandboxes").tag(nil as String?)
                    ForEach(sandboxStore.sandboxes) { sandbox in
                        Text(sandbox.name).tag(sandbox.name as String?)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 180)
                .accessibilityIdentifier("logSandboxFilter")

                Toggle("Blocked Only", isOn: $store.logFilter.blockedOnly)
                    .toggleStyle(.checkbox)
                    .font(.ui(12))
                    .accessibilityIdentifier("blockedOnlyToggle")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            // Table
            Table(policyStore.filteredLog) {
                TableColumn("Sandbox") { entry in
                    Text(entry.sandbox)
                        .font(.code(11))
                }
                .width(min: 100, ideal: 140)

                TableColumn("Host") { entry in
                    Text(entry.host)
                        .font(.code(11))
                }
                .width(min: 120, ideal: 180)

                TableColumn("Proxy") { entry in
                    Text(entry.proxy)
                        .font(.code(11))
                }
                .width(min: 60, ideal: 80)

                TableColumn("Rule") { entry in
                    Text(entry.rule)
                        .font(.code(11))
                }
                .width(min: 50, ideal: 60)

                TableColumn("Count") { entry in
                    Text("\(entry.count)")
                        .font(.code(11))
                }
                .width(min: 40, ideal: 50)

                TableColumn("Status") { entry in
                    Text(entry.blocked ? "Blocked" : "Allowed")
                        .font(.label(10))
                        .foregroundStyle(entry.blocked ? Color.error : Color.secondary)
                }
                .width(min: 60, ideal: 70)
            }
            .tableStyle(.inset)
            .scrollContentBackground(.hidden)
        }
        .background(Color.surface)
        .task {
            await policyStore.fetchLog()
        }
    }
}
