import SwiftUI
import CaregiverAPI

/// Filter chips for the Trackers browse list (trackers.md decision 6).
enum TrackerFilter: String, CaseIterable {
    case all = "All"
    case needsAttention = "Needs attention"
    case archived = "Archived"

    func apply(active: [TrackerSummary], archived: [TrackerSummary], now: Date) -> [TrackerSummary] {
        switch self {
        case .all: return active
        case .needsAttention: return active.filter { $0.needsAttention(now: now) }
        case .archived: return archived
        }
    }
}

/// The full tracker list for the active receiver (Figma `71:2`,
/// ios/specs/views/trackers.md), pushed from Home's "See all".
struct TrackersView: View {
    @Environment(Session.self) private var session
    @Environment(ReceiverContext.self) private var context
    @Environment(TrackerSummariesModel.self) private var summaries
    let me: Me

    @State private var filter: TrackerFilter = .all
    @State private var showAddTracker = false

    private var isAdminForActive: Bool {
        guard let groupID = context.activeReceiver?.careGroupId else { return false }
        return me.isAdmin(inCareGroup: groupID)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                subheader
                chips
                rows
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.top, Theme.Spacing.sm)
        }
        .strideBackground()
        .navigationTitle("Trackers")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showAddTracker) {
            if let receiver = context.activeReceiver {
                TemplatePickerView(receiverId: receiver.receiverId) {
                    Task { await reload() }
                }
            }
        }
    }

    private func reload() async {
        guard let id = context.activeReceiver?.receiverId else { return }
        await summaries.load(receiverID: id, using: session)
    }

    // "Eleanor · 12 active" + admin New button
    private var subheader: some View {
        HStack {
            if let receiver = context.activeReceiver {
                Text("\(receiver.name) · \(summaries.active.count) active")
                    .font(Theme.Typography.subhead)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            Spacer()
            if isAdminForActive {
                Button {
                    showAddTracker = true
                } label: {
                    Label("New", systemImage: "plus")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.Colors.textOnAccent)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background { Capsule().fill(Theme.Colors.accent) }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var chips: some View {
        HStack(spacing: Theme.Spacing.sm) {
            ForEach(TrackerFilter.allCases, id: \.rawValue) { f in
                StrideChip(label: f.rawValue, isSelected: filter == f) { filter = f }
            }
        }
    }

    @ViewBuilder private var rows: some View {
        let visible = filter.apply(active: summaries.active, archived: summaries.archived, now: Date())
        switch summaries.state {
        case .loading:
            StrideLoadingView().frame(height: 160)
        case .error(let message):
            StrideErrorState(message: message) { Task { await reload() } }
                .frame(height: 200)
        case .loaded:
            if visible.isEmpty {
                StrideEmptyState(message: emptyMessage).frame(height: 160)
            } else {
                LazyVStack(spacing: Theme.Spacing.sm) {
                    ForEach(visible) { summary in
                        NavigationLink(value: Route.tracker(summary.tracker)) {
                            row(for: summary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var emptyMessage: String {
        switch filter {
        case .all: "No trackers yet."
        case .needsAttention: "Nothing needs attention — all trackers are active."
        case .archived: "No archived trackers."
        }
    }

    private func row(for summary: TrackerSummary) -> some View {
        StrideTrackerRow(
            name: summary.tracker.name,
            subtitle: summary.lastValueText.map { "\(summary.kindLabel) · \($0)" } ?? summary.kindLabel,
            meta: summary.recencyText(),
            hue: summary.tracker.color.map { Color(hex: $0) } ?? Theme.Colors.accent,
            recency: summary.recency()
        )
    }
}
