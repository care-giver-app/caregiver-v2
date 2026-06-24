import SwiftUI
import CaregiverAPI

struct ReceiverDetailView: View {
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    let me: Me
    let receiver: Components.Schemas.Receiver
    @State private var model = ReceiverDetailModel()
    @State private var showAddTracker = false
    @State private var showRename = false

    private var isAdmin: Bool { me.isAdmin(inCareGroup: receiver.careGroupId) }

    var body: some View {
        Group {
            switch model.state {
            case .loading: StrideLoadingView()
            case .empty: StrideEmptyState(message: "No trackers yet. Add one from a template.")
            case .error(let m): StrideErrorState(message: m) { Task { await model.load(receiverId: receiver.receiverId, using: session) } }
            case .loaded(let trackers):
                List(trackers, id: \.trackerId) { tracker in
                    NavigationLink(value: Route.tracker(tracker)) { TrackerRow(tracker: tracker) }
                }.listStyle(.insetGrouped).refreshable { await model.load(receiverId: receiver.receiverId, using: session) }
            }
        }
        .navigationTitle(receiver.name)
        .toolbar {
            if isAdmin {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAddTracker = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Add tracker")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Rename") { showRename = true }
                        Button("Archive", role: .destructive) {
                            Task {
                                if await model.archive(receiverId: receiver.receiverId, using: session) == nil { dismiss() }
                            }
                        }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
        }
        .sheet(isPresented: $showAddTracker) {
            TemplatePickerView(receiverId: receiver.receiverId) {
                Task { await model.load(receiverId: receiver.receiverId, using: session) }
            }
        }
        .sheet(isPresented: $showRename) {
            RenameSheet(title: "Rename receiver", text: receiver.name) { newName in
                await model.rename(receiverId: receiver.receiverId, to: newName, using: session)
            }
        }
        .task { await model.load(receiverId: receiver.receiverId, using: session) }
    }
}

/// A tracker list row with a color-coded left edge from the tracker's own `color`.
struct TrackerRow: View {
    let tracker: Components.Schemas.Tracker
    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            RoundedRectangle(cornerRadius: 2)
                .fill(tracker.color.map { Color(hex: $0) } ?? Theme.Colors.accent)
                .frame(width: 4)
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(tracker.name).font(Theme.Typography.headline).foregroundStyle(Theme.Colors.textPrimary)
                Text(tracker.kind.rawValue.capitalized).font(Theme.Typography.caption).foregroundStyle(Theme.Colors.textSecondary)
            }
        }
    }
}
