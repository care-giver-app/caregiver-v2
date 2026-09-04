import SwiftUI
import CaregiverAPI

struct TrackerDetailView: View {
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    let me: Me
    let tracker: Components.Schemas.Tracker
    @State private var model = TrackerDetailModel()
    @State private var showLog = false
    @State private var showSchedule = false
    @State private var showRename = false

    private var isAdmin: Bool { me.isAdmin(inCareGroup: tracker.careGroupId) }

    var body: some View {
        history
            .safeAreaInset(edge: .bottom, spacing: 0) { actionBar }
            .strideBackground()
            .navigationTitle(tracker.name)
        .navigationBarTitleDisplayMode(.inline)
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
        .sheet(isPresented: $showSchedule) {
            ScheduleItemFormView(tracker: tracker, onScheduled: {})
        }
        .sheet(isPresented: $showRename) {
            RenameSheet(title: "Rename tracker", text: tracker.name) { newName in
                await model.rename(tracker: tracker, to: newName, using: session)
            }
        }
        .task { await model.load(trackerId: tracker.trackerId, using: session) }
    }

    private var actionBar: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                Divider().overlay(Theme.Colors.border)
                VStack(spacing: Theme.Spacing.sm) {
                    if tracker.kind == .scheduled {
                        StrideButton(title: "Schedule item", style: .secondary) { showSchedule = true }
                    }
                    StrideButton(title: "Log reading") { showLog = true }
                }
                .padding(Theme.Spacing.md)
            }
            // Clears the persistent StrideTabBar, which sits as a safeAreaInset on the
            // root TabView and isn't accounted for by this pushed view's own inset.
            Color.clear.frame(height: StrideTabBar.reservedHeight)
        }
    }

    @ViewBuilder private var history: some View {
        switch model.state {
        case .loading:
            StrideLoadingView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .empty:
            StrideEmptyState(message: "No readings yet. Tap \u{201C}Log reading\u{201D}.")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .error(let m):
            StrideErrorState(message: m) { Task { await model.load(trackerId: tracker.trackerId, using: session) } }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded(let events):
            ScrollView {
                LazyVStack(spacing: Theme.Spacing.sm) {
                    ForEach(events, id: \.eventId) { event in
                        NavigationLink(value: Route.event(EventRef(tracker: tracker, event: event))) {
                            EventRow(event: event, fields: tracker.fields)
                        }
                        .buttonStyle(.plain)
                        .task { await model.loadMoreIfNeeded(current: event, trackerId: tracker.trackerId, using: session) }
                    }
                    if model.isLoadingMore {
                        HStack {
                            Spacer()
                            ProgressView().tint(Theme.Colors.accent)
                            Spacer()
                        }
                    }
                }
                .padding(Theme.Spacing.md)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    private enum Metrics {
        static let radius: CGFloat = 16
        static let padding: CGFloat = 14
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(DynamicFormBuilder.display(values: event.values, fields: fields))
                    .font(Theme.Typography.body).foregroundStyle(Theme.Colors.textPrimary)
                Text(Self.formatter.string(from: event.occurredAt))
                    .font(Theme.Typography.caption).foregroundStyle(Theme.Colors.textSecondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.Colors.textTertiary)
        }
        .padding(Metrics.padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: Metrics.radius)
                .fill(Theme.Colors.surface)
        }
        .overlay {
            RoundedRectangle(cornerRadius: Metrics.radius)
                .stroke(Theme.Colors.border, lineWidth: 1)
        }
    }
}
