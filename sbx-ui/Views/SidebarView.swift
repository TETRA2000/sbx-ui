import SwiftUI

struct SidebarView: View {
    @Binding var selection: SidebarDestination?
    @State private var showCreateSheet = false

    var body: some View {
        List(selection: $selection) {
            Section {
                Label {
                    Text("DASHBOARD")
                        .font(.label(11))
                        .tracking(1.2)
                } icon: {
                    Image(systemName: "square.grid.2x2")
                }
                .tag(SidebarDestination.dashboard)

                Label {
                    Text("POLICIES")
                        .font(.label(11))
                        .tracking(1.2)
                } icon: {
                    Image(systemName: "shield.lefthalf.filled")
                }
                .tag(SidebarDestination.policies)
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        .background(Color.surfaceContainer)
        .safeAreaInset(edge: .bottom) {
            Button {
                showCreateSheet = true
            } label: {
                Label {
                    Text("Deploy Agent")
                        .font(.label(12, weight: .semibold))
                } icon: {
                    Image(systemName: "plus.circle.fill")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.accent)
            .padding()
            .sheet(isPresented: $showCreateSheet) {
                CreateProjectSheet()
            }
        }
    }
}
