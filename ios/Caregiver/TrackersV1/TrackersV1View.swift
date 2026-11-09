import SwiftUI

/// Trackers — every tracker of the active care receiver, in three filtered views
/// (PRD "Trackers"; Figma 369:3180 default, 369:3277 needs attention, 393:3597
/// paused, 369:3312 empty). Admins add trackers from Add new and the empty state's Add a
/// tracker; Create lands on the new tracker, pushed on the one `/v1` stack.
struct TrackersV1View: View {
    let receiver: TeamReceiver
    let service: TrackersService

    @State private var model: TrackersListModel?
    @State private var isAdding = false
    /// The tracker Add tracker just made, pushed once its sheet is gone.
    @State private var created: String?
    @Environment(\.v1Push) private var push

    var body: some View {
        Group {
            if let model {
                content(model)
            } else {
                Color.clear
            }
        }
        .strideBackground()
        .toolbar(.visible, for: .navigationBar)
        .strideBackButton()
        .toolbarBackground(.hidden, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                StrideNavTitle(title: "Trackers", subtitle: receiver.name)
            }
            if receiver.canManage {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { isAdding = true } label: {
                        Label("Add new", systemImage: "plus").labelStyle(.titleAndIcon)
                    }
                }
            }
        }
        .sheet(isPresented: $isAdding, onDismiss: {
            // Pushed only once the sheet is down, so the push lands on the stack beneath it.
            guard let id = created else { return }
            created = nil
            push(.tracker(id: id, receiver: receiver))
        }) {
            AddTrackerV1Sheet(receiver: receiver, service: service) { created = $0.id }
        }
        .tint(Theme.Colors.accent)
        .task {
            if let model {
                // Back from a tracker: refresh in place, with fresh relative times.
                await model.load()
            } else {
                let model = TrackersListModel(receiver: receiver, service: service)
                self.model = model
                await model.load()
            }
        }
    }

    @ViewBuilder
    private func content(_ model: TrackersListModel) -> some View {
        switch model.phase {
        case .loading:
            StrideLoadingView()
        case .failed:
            StrideErrorState(message: "Couldn't load trackers.") {
                Task { await model.retry() }
            }
        case .loaded where model.hasNoTrackers:
            empty
        case .loaded:
            list(model)
        }
    }

    /// Figma 369:3316. Add a tracker is an admin's; a caregiver sees the words alone.
    private var empty: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Text("Nothing is being tracked yet")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Theme.Colors.textPrimary)
            // A caregiver can't make one, so they're told who does (PRD "Trackers", empty).
            Text(receiver.canManage
                 ? "Create your first tracker for \(receiver.name)"
                 : "An admin on the team can add the first one.")
                .font(.system(size: 14))
                .foregroundStyle(Theme.Colors.textSecondary)
            if receiver.canManage {
                StrideButton(title: "Add a tracker") { isAdding = true }
                    .padding(.top, Theme.Spacing.md)
            }
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, Theme.Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func list(_ model: TrackersListModel) -> some View {
        @Bindable var model = model
        let now = model.now
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if model.refreshFailed {
                    StrideAlertBanner(message: "Couldn't refresh trackers.")
                        .padding(.bottom, Theme.Spacing.md)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Theme.Spacing.sm) {
                        ForEach(TrackerListFilter.allCases, id: \.self) { filter in
                            StrideChip(label: model.chipLabel(filter), isSelected: model.filter == filter) {
                                model.filter = filter
                            }
                        }
                    }
                }
                .scrollClipDisabled()
                .padding(.bottom, 18)

                let visible = model.visible
                if visible.isEmpty {
                    Text(model.filter.emptyLine)
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    VStack(spacing: Theme.Spacing.sm) {
                        ForEach(visible) { tracker in
                            NavigationLink(value: V1Route.tracker(id: tracker.id, receiver: receiver)) {
                                row(tracker, now: now)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.top, Theme.Spacing.md)
            .padding(.bottom, Theme.Spacing.lg)
        }
        .refreshable { await model.load() }
    }

    private func row(_ tracker: TrackerItem, now: Date) -> some View {
        StrideTrackerRow(
            name: tracker.name,
            subtitle: TrackerText.rowSubtitle(tracker, now: now, zone: receiver.timeZone),
            hue: Color(hex: tracker.color),
            // Says only that something is wrong; the cause waits on the tracker (PRD).
            badge: tracker.needsAttention && tracker.status == .active
                ? StrideBadge(status: .warning, label: "Needs attention") : nil,
            icon: tracker.icon,
            isMuted: tracker.status == .paused
        )
    }
}

/// A pushed screen's centered title with a smaller line beneath (Figma 378:3607).
struct StrideNavTitle: View {
    let title: String
    let subtitle: String?

    var body: some View {
        VStack(spacing: 0) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.Colors.textPrimary)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
        .lineLimit(1)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

#if DEBUG
#Preview("Active") {
    NavigationStack {
        TrackersV1View(receiver: TrackersFixtures.eleanor, service: TrackersFixtures.service())
            .v1Destinations(service: TrackersFixtures.service())
    }
}

#Preview("Empty receiver") {
    NavigationStack {
        TrackersV1View(receiver: TrackersFixtures.eleanor, service: TrackersFixtures.service(trackers: []))
    }
}

#Preview("Empty receiver, caregiver") {
    NavigationStack {
        TrackersV1View(receiver: TrackersFixtures.eleanorForCaregiver,
                       service: TrackersFixtures.service(trackers: []))
    }
}

#Preview("Add tracker, then its detail") {
    @Previewable @State var path: [V1Route] = []
    NavigationStack(path: $path) {
        TrackersV1View(receiver: TrackersFixtures.eleanor, service: TrackersFixtures.service())
            .v1Destinations(service: TrackersFixtures.service())
    }
    .environment(\.v1Push, V1Push { [path = $path] in path.wrappedValue.append($0) })
}

#Preview("Every tracker paused") {
    NavigationStack {
        TrackersV1View(receiver: TrackersFixtures.eleanor,
                       service: TrackersFixtures.service(trackers: TrackersFixtures.trackers.filter {
                           $0.status == .paused
                       }))
    }
}

#Preview("Failed") {
    NavigationStack {
        TrackersV1View(receiver: TrackersFixtures.eleanor, service: TrackersFixtures.service(failTrackers: true))
    }
}
#endif
