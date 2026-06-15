import SwiftUI
import CaregiverAPI

struct TrackerDetailView: View {
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    let me: Me
    let tracker: Components.Schemas.Tracker
    @State private var model = TrackerDetailModel()
    @State private var showLog = false
    @State private var showRename = false

    private var isAdmin: Bool { me.isAdmin(inCareGroup: tracker.careGroupId) }

    var body: some View {
        VStack(spacing: 0) {
            history
            PrimaryButton(title: "Log reading") { showLog = true }
                .padding(Theme.Spacing.md)
        }
        .navigationTitle(tracker.name)
        .toolbar {
            if isAdmin {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Rename") { showRename = true }
                        Button("Archive", role: .destructive) {
                            Task { if await model.archive(trackerId: tracker.trackerId, using: session) == nil { dismiss() } }
                        }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
        }
        .sheet(isPresented: $showLog) {
            LogEventView(tracker: tracker, existing: nil) {
                Task { await model.load(trackerId: tracker.trackerId, using: session) }
            }
        }
        .sheet(isPresented: $showRename) {
            RenameSheet(title: "Rename tracker", text: tracker.name) { newName in
                await model.rename(tracker: tracker, to: newName, using: session)
            }
        }
        .task { await model.load(trackerId: tracker.trackerId, using: session) }
    }

    @ViewBuilder private var history: some View {
        switch model.state {
        case .loading: LoadingView()
        case .empty: EmptyStateView(message: "No readings yet. Tap \u{201C}Log reading\u{201D}.")
        case .error(let m): ErrorStateView(message: m) { Task { await model.load(trackerId: tracker.trackerId, using: session) } }
        case .loaded(let events):
            List {
                ForEach(events, id: \.eventId) { event in
                    // TODO(I1): wrap in NavigationLink(value: Route.event(EventRef(tracker: tracker, event: event)))
                    EventRow(event: event, fields: tracker.fields)
                        .task { await model.loadMoreIfNeeded(current: event, trackerId: tracker.trackerId, using: session) }
                }
                if model.isLoadingMore { HStack { Spacer(); ProgressView(); Spacer() } }
            }
            .listStyle(.insetGrouped)
            .refreshable { await model.load(trackerId: tracker.trackerId, using: session) }
        }
    }
}

struct EventRow: View {
    let event: Components.Schemas.Event
    let fields: [Components.Schemas.Field]
    private static let formatter: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .short; return f
    }()
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(DynamicFormBuilder.display(values: event.values, fields: fields))
                .font(Theme.Typography.body).foregroundStyle(Theme.Colors.textPrimary)
            Text(Self.formatter.string(from: event.occurredAt))
                .font(Theme.Typography.caption).foregroundStyle(Theme.Colors.textSecondary)
        }
    }
}
