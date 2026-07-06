import SwiftUI
import CaregiverAPI

private struct HomeTaskID: Equatable {
    let receiverID: String?
    let contextReady: Bool
}

struct HomeView: View {
    @Environment(Session.self) private var session
    @Environment(ReceiverContext.self) private var context
    @Environment(TrackerSummariesModel.self) private var summaries
    let me: Me

    @State private var showAddReceiver = false
    @State private var showAddTracker = false
    @State private var selectedRef: EventRef?
    @State private var pushTrackers = false

    private var isAdminForActive: Bool {
        guard let groupID = context.activeReceiver?.careGroupId else { return false }
        return me.isAdmin(inCareGroup: groupID)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                HomeHeaderView(me: me) { showAddReceiver = true }
                snapshotSection
                timelineSection
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.top, Theme.Spacing.md)
        }
        .refreshable { await reload() }
        .strideBackground()
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(item: $selectedRef) { ref in
            EventDetailView(tracker: ref.tracker, event: ref.event) {
                Task { await reload() }
            }
        }
        .navigationDestination(isPresented: $pushTrackers) {
            TrackersView(me: me)
        }
        .sheet(isPresented: $showAddReceiver) {
            AddReceiverView(me: me) {
                Task { await context.load(using: session) }
            }
        }
        .sheet(isPresented: $showAddTracker) {
            if let receiver = context.activeReceiver {
                TemplatePickerView(receiverId: receiver.receiverId) {
                    Task { await reload() }
                }
            }
        }
        .task(id: HomeTaskID(receiverID: context.activeReceiver?.receiverId,
                             contextReady: context.isLoaded)) {
            await reload()
        }
    }

    private func reload() async {
        guard let id = context.activeReceiver?.receiverId else { return }
        await summaries.load(receiverID: id, using: session)
    }

    // MARK: Tracker snapshot (home.md: 6 tiles, attention-first)

    @ViewBuilder private var snapshotSection: some View {
        let active = summaries.active
        VStack(alignment: .leading, spacing: Theme.Spacing.sm + 2) {
            StrideSectionHeader(
                title: "Trackers",
                actionLabel: active.isEmpty ? nil : "See all (\(active.count))",
                action: active.isEmpty ? nil : { pushTrackers = true }
            )
            switch summaries.state {
            case .loading:
                StrideLoadingView().frame(height: 120)
            case .error(let message):
                StrideErrorState(message: message) { Task { await reload() } }
                    .frame(height: 160)
            case .loaded:
                if active.isEmpty {
                    emptyState
                } else {
                    LazyVGrid(
                        columns: [GridItem(.flexible()), GridItem(.flexible())],
                        spacing: Theme.Spacing.sm + 2
                    ) {
                        ForEach(active.prefix(6)) { summary in
                            NavigationLink(value: Route.tracker(summary.tracker)) {
                                tile(for: summary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func tile(for summary: TrackerSummary) -> some View {
        StrideTrackerTile(
            name: summary.tracker.name,
            subtitle: summary.recencyText() ?? "Not logged yet",
            hue: summary.tracker.color.map { Color(hex: $0) } ?? Theme.Colors.accent,
            recency: summary.recency()
        )
    }

    @ViewBuilder private var emptyState: some View {
        VStack(spacing: Theme.Spacing.md) {
            StrideEmptyState(message: "No trackers yet.")
                .frame(maxHeight: 120)
            if isAdminForActive, context.activeReceiver != nil {
                StrideButton(title: "Add tracker") { showAddTracker = true }
                    .padding(.horizontal, Theme.Spacing.lg)
            }
        }
    }

    // MARK: Today timeline

    @ViewBuilder private var timelineSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm + 2) {
            StrideSectionHeader(title: "Today")
            if context.activeReceiver != nil {
                TodayTimelineCard { ref in selectedRef = ref }
            } else {
                StrideEmptyState(message: "No receiver selected.")
                    .frame(height: 120)
            }
        }
    }
}
