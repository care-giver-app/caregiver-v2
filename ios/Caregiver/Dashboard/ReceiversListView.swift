import SwiftUI
import CaregiverAPI

struct ReceiversListView: View {
    @Environment(Session.self) private var session
    let me: Me
    @State private var model = ReceiversListModel()
    @State private var showAdd = false

    var body: some View {
        Group {
            switch model.state {
            case .loading:
                LoadingView()
            case .empty:
                EmptyStateView(message: "No receivers yet. Add the person you're caring for.")
            case .error(let message):
                ErrorStateView(message: message) { Task { await model.load(using: session) } }
            case .loaded(let receivers):
                list(receivers)
            }
        }
        .navigationTitle("Receivers")
        .toolbar {
            if !me.adminGroups.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Add receiver")
                }
            }
        }
        .sheet(isPresented: $showAdd) {
            AddReceiverView(me: me) { Task { await model.load(using: session) } }
        }
        .task { await model.load(using: session) }
    }

    @ViewBuilder private func list(_ receivers: [Components.Schemas.Receiver]) -> some View {
        List {
            if me.memberships.count > 1 {
                ForEach(me.memberships, id: \.careGroupID) { group in
                    let inGroup = receivers.filter { $0.careGroupId == group.careGroupID }
                    if !inGroup.isEmpty {
                        Section(group.name) { ForEach(inGroup, id: \.receiverId, content: row) }
                    }
                }
            } else {
                ForEach(receivers, id: \.receiverId, content: row)
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { await model.load(using: session) }
    }

    private func row(_ receiver: Components.Schemas.Receiver) -> some View {
        NavigationLink(value: Route.receiver(receiver)) {
            Text(receiver.name).font(Theme.Typography.headline).foregroundStyle(Theme.Colors.textPrimary)
        }
    }
}
