import SwiftUI

/// Coming up — the active care receiver's whole list: each tracker's next scheduled
/// entry, soonest first, with its time and the schedule it came from; each leads to the
/// entry itself (PRD "Coming up"; Figma 445:4053). Read again on every appearance, so
/// one logged or skipped from here is gone on the way back. Once everything on it has
/// been settled it says so where the caregiver is rather than dropping them back on Home
/// (Figma 445:4144).
struct ComingUpV1View: View {
    let receiver: TeamReceiver
    let home: HomeService

    @State private var model: HomeReadModel<[ReceiverEntryItem]>?

    var body: some View {
        Group {
            if let model {
                content(model)
            } else {
                Color.clear
            }
        }
        .homePushedChrome()
        .toolbar {
            ToolbarItem(placement: .principal) {
                StrideNavTitle(title: "Coming up", subtitle: receiver.name)
            }
        }
        .task {
            if let model {
                await model.load()
            } else {
                let model = HomeReadModel.comingUp(receiver.id, home: home)
                self.model = model
                await model.load()
            }
        }
    }

    @ViewBuilder
    private func content(_ model: HomeReadModel<[ReceiverEntryItem]>) -> some View {
        switch model.phase {
        case .loading:
            StrideLoadingView()
        case .failed, .gone:
            StrideErrorState(message: "Couldn't load what's coming up.") { Task { await model.retry() } }
        case .loaded(let items):
            ScrollView {
                VStack(spacing: Theme.Spacing.sm) {
                    if model.refreshFailed {
                        StrideAlertBanner(message: "Couldn't refresh what's coming up.")
                    }
                    if items.isEmpty {
                        emptied
                    }
                    ForEach(items) { item in
                        NavigationLink(value: V1Route.entry(id: item.entry.id, receiver: receiver)) {
                            StrideTrackerRow(
                                name: item.tracker.name,
                                subtitle: HomeText.comingUp(item.entry, now: model.now, zone: receiver.timeZone),
                                hue: Color(hex: item.tracker.color),
                                icon: item.tracker.icon
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.top, Theme.Spacing.md)
                .padding(.bottom, Theme.Spacing.lg)
            }
            .refreshable { await model.load() }
        }
    }

    /// Figma 445:4157.
    private var emptied: some View {
        VStack(spacing: 6) {
            Text(HomeText.comingUpEmptyTitle)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.Colors.textPrimary)
            Text(HomeText.comingUpEmptyLine)
                .font(.system(size: 14))
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 22)
        .padding(.vertical, 24)
        .homeDetailCard()
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
#Preview("Coming up (445:4053)") {
    NavigationStack {
        ComingUpV1View(receiver: HomeFixtures.eleanor, home: HomeFixtures.service())
            .v1Destinations(service: HomeFixtures.trackersService(), home: HomeFixtures.service())
    }
}

#Preview("Emptied (445:4144)") {
    NavigationStack {
        ComingUpV1View(receiver: HomeFixtures.eleanor, home: HomeFixtures.service(comingUp: []))
    }
}

#Preview("Failed") {
    NavigationStack {
        ComingUpV1View(receiver: HomeFixtures.eleanor, home: HomeFixtures.service(fail: true))
    }
}
#endif
