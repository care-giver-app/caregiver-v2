import SwiftUI

/// Home on the `/v1` path (PRD "Home"; Figma section 1 · Home 436:3225): the active care
/// receiver with their team, what needs attention, what is coming up, and one day of the
/// timeline. Every push goes on the one `/v1` stack as a `V1Route`; ⊕ and the empty day's
/// offers open Quick log through `V1QuickLog`. Who is on duty waits on the Team area.
struct HomeV1View: View {
    let receiver: ActiveReceiverModel
    let trackers: TrackersService

    @State private var model: HomeModel
    @State private var isAddingReceiver = false
    @State private var isAddingTracker = false
    /// The tracker Add tracker just made, pushed once its sheet is gone.
    @State private var created: String?
    @State private var isJumping = false
    @Environment(\.v1Push) private var push
    @Environment(\.v1QuickLog) private var quickLog

    init(receiver: ActiveReceiverModel, home: HomeService, trackers: TrackersService,
         model: HomeModel? = nil) {
        self.receiver = receiver
        self.trackers = trackers
        _model = State(initialValue: model ?? HomeModel(home: home, trackers: trackers))
    }

    var body: some View {
        Group {
            switch receiver.phase {
            case .loading:
                StrideLoadingView()
            case .failed(let error):
                StrideErrorState(message: error.message) { Task { await receiver.retry() } }
            case .noReceivers(let team, let canManage):
                noReceivers(team: team, canManage: canManage)
            case .active(let active):
                content(active)
                    // A new receiver starts over on today; reappearing refreshes in place.
                    .task(id: active.receiver) { await model.show(active.receiver) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .strideBackground()
        .toolbar(.hidden, for: .navigationBar)
        .task { if receiver.phase == .loading { await receiver.load() } }
        .sheet(isPresented: $isAddingReceiver) { AddCareReceiverPlaceholderSheet() }
        .sheet(isPresented: $isAddingTracker, onDismiss: {
            // Pushed only once the sheet is down, so the push lands on the stack beneath it.
            guard let id = created, let r = model.receiver else { return }
            created = nil
            push(.tracker(id: id, receiver: r))
        }) {
            if let r = model.receiver {
                AddTrackerV1Sheet(receiver: r, service: trackers) { created = $0.id }
            }
        }
        .sheet(isPresented: $isJumping) {
            JumpToDaySheet(today: model.today, showing: model.day) { picked in
                Task { await model.jump(to: picked) }
            }
        }
    }

    // MARK: - The receiver

    @ViewBuilder
    private func content(_ active: TeamedReceiver) -> some View {
        if model.receiver?.id != active.receiver.id {
            StrideLoadingView()
        } else {
            switch model.phase {
            case .loading:
                StrideLoadingView()
            case .failed:
                StrideErrorState(message: "Couldn't load Home.") { Task { await model.retry() } }
            case .loaded:
                loaded(active)
            }
        }
    }

    private func loaded(_ active: TeamedReceiver) -> some View {
        let r = active.receiver
        return ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header(active)
                if model.refreshFailed {
                    StrideAlertBanner(message: "Couldn't refresh Home.")
                }
                switch model.status {
                case .needsAttention(let items): needsAttention(items, receiver: r)
                case .allClear: allClear
                case .noActiveTrackers: noActiveTrackers(r)
                case nil: EmptyView()
                }
                if model.showsComingUp {
                    comingUp(r)
                }
                timeline(r)
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.top, Theme.Spacing.md)
            .padding(.bottom, 32)
        }
        .refreshable { await model.refresh() }
    }

    /// Figma Stride/Receiver Header 253:1126: the name leads to Care receiver; the team is
    /// context, not a destination; All trackers opens the Active list.
    private func header(_ active: TeamedReceiver) -> some View {
        HStack(spacing: 12) {
            Button { push(.careReceiver(active.receiver)) } label: {
                HStack(spacing: 12) {
                    Circle()
                        .fill(Theme.Colors.accentTint)
                        .frame(width: 42, height: 42)
                        .overlay {
                            Text(String(active.receiver.name.prefix(1)).uppercased())
                                .font(.system(size: 17, weight: .medium))
                                .foregroundStyle(Theme.Colors.accent)
                        }
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 6) {
                            Text(active.receiver.name)
                                .font(.system(size: 22, weight: .medium))
                                .foregroundStyle(Theme.Colors.textPrimary)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Theme.Colors.textTertiary)
                        }
                        Text(active.team.name)
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.Colors.textTertiary)
                    }
                    .lineLimit(1)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 1)
            Button { push(.trackers(active.receiver)) } label: {
                HStack(spacing: 6) {
                    Text("All trackers")
                        .font(.system(size: 13, weight: .semibold))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(Theme.Colors.accent)
                .padding(.leading, 14)
                .padding(.trailing, 11)
                .frame(height: 38)
                .background { Capsule().fill(Theme.Colors.accentTint) }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Needs attention

    private func needsAttention(_ items: [AttentionItem], receiver r: TeamReceiver) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Needs attention") { push(.trackers(r, filter: .needsAttention)) }
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                NavigationLink(value: Self.route(for: item, receiver: r)) {
                    StrideTrackerRow(
                        name: item.tracker.name,
                        subtitle: HomeText.attention(item.attention, now: model.now, zone: r.timeZone),
                        hue: Color(hex: item.tracker.color),
                        icon: item.tracker.icon,
                        subtitleColor: Self.causeColor(item.attention)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Unrecorded care and an out-of-range reading lead to their entry; a gap has none,
    /// so it leads to the tracker (PRD "Needs attention").
    static func route(for item: AttentionItem, receiver: TeamReceiver) -> V1Route {
        switch item.attention {
        case .unrecorded(let entryID, _), .outOfRange(let entryID, _, _, _, _, _):
            .entry(id: entryID, receiver: receiver)
        case .gap:
            .tracker(id: item.tracker.id, receiver: receiver)
        }
    }

    private static func causeColor(_ attention: NeedsAttention) -> Color {
        if case .outOfRange = attention { return Theme.Colors.alert }
        return Theme.Colors.warning
    }

    /// Figma 437:3887: said plainly rather than leaving a space where a warning would be.
    private var allClear: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(Theme.Colors.success)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(HomeText.allClearTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text(HomeText.allClearLine)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background { RoundedRectangle(cornerRadius: 14).fill(Theme.Colors.successTint) }
        .accessibilityElement(children: .combine)
    }

    /// Figma 438:3971 (admin) / 438:4075 (caregiver).
    private func noActiveTrackers(_ r: TeamReceiver) -> some View {
        emptyCard(icon: "plus", title: HomeText.noTrackersTitle,
                  line: r.canManage ? HomeText.noTrackersAdminLine : HomeText.noTrackersCaregiverLine) {
            if r.canManage {
                StrideButton(title: "Add a tracker") { isAddingTracker = true }
            }
        }
    }

    // MARK: - Coming up

    private func comingUp(_ r: TeamReceiver) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Coming up") { push(.comingUp(r)) }
            ForEach(model.comingUp) { item in
                NavigationLink(value: V1Route.entry(id: item.entry.id, receiver: r)) {
                    StrideTrackerRow(
                        name: item.tracker.name,
                        subtitle: HomeText.comingUp(item.entry, now: model.now, zone: r.timeZone),
                        hue: Color(hex: item.tracker.color),
                        icon: item.tracker.icon
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - The timeline

    private func timeline(_ r: TeamReceiver) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            dayBar
                .padding(.bottom, 2)
            switch model.dayPhase {
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 120)
            case .failed:
                VStack(spacing: Theme.Spacing.sm) {
                    Text("Couldn't load this day.")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.Colors.textSecondary)
                    StrideButton(title: "Try again", style: .compact) { Task { await model.retryDay() } }
                }
                .frame(maxWidth: .infinity, minHeight: 120)
            case .loaded(let items) where items.isEmpty:
                emptyDay
            case .loaded(let items):
                ForEach(items) { item in
                    NavigationLink(value: Self.route(for: item, receiver: r)) {
                        DayItemV1(item: item, fields: Self.fields(for: item, in: model.fields),
                                  zone: r.timeZone, now: model.now)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    static func route(for item: DayItem, receiver: TeamReceiver) -> V1Route {
        switch item {
        case .entry(let e): .entry(id: e.entry.id, receiver: receiver)
        case .note(let n): .journalNote(id: n.id, receiver: receiver)
        }
    }

    private static func fields(for item: DayItem, in known: [String: [TrackerFieldInfo]]) -> [TrackerFieldInfo]? {
        if case .entry(let e) = item { return known[e.tracker.id] }
        return nil
    }

    /// Figma 436:3307: the date, Today when it isn't today, back, the calendar, and
    /// forward only while there is a day ahead to go to — the stepper stops at today.
    private var dayBar: some View {
        let title = HomeText.dayTitle(model.day, today: model.today)
        return HStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title.title)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text(title.detail)
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .lineLimit(1)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 1)
            if model.showsTodayButton {
                Button { Task { await model.goToToday() } } label: {
                    Text("Today")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.Colors.accent)
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                        .background { RoundedRectangle(cornerRadius: 8).fill(Theme.Colors.accentTint) }
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: 4) {
                stepperButton("chevron.left", label: "Previous day") { Task { await model.stepBack() } }
                stepperButton("calendar", label: "Jump to day") { isJumping = true }
                if model.canStepForward {
                    stepperButton("chevron.right", label: "Next day") { Task { await model.stepForward() } }
                }
            }
        }
    }

    private func stepperButton(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: icon == "calendar" ? 14 : 13, weight: .semibold))
                .foregroundStyle(Theme.Colors.accent)
                .frame(width: 32, height: 32)
                .background { RoundedRectangle(cornerRadius: 10).fill(Theme.Colors.surface) }
                .overlay { RoundedRectangle(cornerRadius: 10).stroke(Theme.Colors.border, lineWidth: 1) }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    /// Figma 437:4427: nothing logged and nothing came due — said, with a first log or a note.
    private var emptyDay: some View {
        VStack(spacing: 4) {
            Text(HomeText.emptyDayTitle)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.Colors.textPrimary)
            Text(HomeText.emptyDayLine)
                .font(.system(size: 13))
                .foregroundStyle(Theme.Colors.textSecondary)
            HStack(spacing: 10) {
                ForEach(model.dayOffers, id: \.self) { offer in
                    switch offer {
                    case .logAnEntry:
                        StrideButton(title: "Log an entry") { quickLog(.pick) }
                    case .writeANote:
                        StrideButton(title: "Write a note", style: .secondary) { quickLog(.journalNote) }
                    }
                }
            }
            .padding(.top, 12)
        }
        .multilineTextAlignment(.center)
        .padding(14)
        .frame(maxWidth: .infinity)
        .background { RoundedRectangle(cornerRadius: 16).fill(Theme.Colors.surface) }
        .overlay { RoundedRectangle(cornerRadius: 16).stroke(Theme.Colors.border, lineWidth: 1) }
    }

    // MARK: - Nobody to care for

    /// Figma 438:3756 (admin) / 438:3865 (caregiver). A caregiver is told an admin adds
    /// them and is shown no control they cannot use.
    private func noReceivers(team: Account.Team, canManage: Bool) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(team.name)
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                    Text("Care team")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
                emptyCard(icon: "person.2", title: HomeText.noReceiversTitle,
                          line: canManage ? HomeText.noReceiversAdminLine : HomeText.noReceiversCaregiverLine) {
                    if canManage {
                        StrideButton(title: "Add a care receiver") { isAddingReceiver = true }
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.top, Theme.Spacing.md)
        }
    }

    // MARK: - Pieces

    private func sectionLabel(_ title: String, seeAll: @escaping () -> Void) -> some View {
        HStack {
            Text(title.uppercased())
                .font(.system(size: 12, weight: .semibold))
                .tracking(0.72)
                .foregroundStyle(Theme.Colors.textTertiary)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Button("See all", action: seeAll)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.Colors.accent)
                .buttonStyle(.plain)
        }
        .padding(.bottom, 2)
    }

    private func emptyCard<Action: View>(icon: String, title: String, line: String,
                                         @ViewBuilder action: () -> Action) -> some View {
        VStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 12)
                .fill(Theme.Colors.accentTint)
                .frame(width: 44, height: 44)
                .overlay {
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(Theme.Colors.accent)
                }
                .padding(.bottom, 10)
                .accessibilityHidden(true)
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.Colors.textPrimary)
            Text(line)
                .font(.system(size: 13))
                .foregroundStyle(Theme.Colors.textSecondary)
            action()
                .padding(.top, 14)
        }
        .multilineTextAlignment(.center)
        .padding(18)
        .frame(maxWidth: .infinity)
        .background { RoundedRectangle(cornerRadius: 16).fill(Theme.Colors.surface) }
        .overlay { RoundedRectangle(cornerRadius: 16).stroke(Theme.Colors.border, lineWidth: 1) }
    }
}

/// Stands in for Add care receiver — a Team-area sheet not yet built on this path.
struct AddCareReceiverPlaceholderSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        V1Placeholder(title: "Add care receiver",
                      line: "Adding a care receiver is part of Team, which isn't built on this path yet.") {
            StrideButton(title: "Close", style: .secondary) { dismiss() }
        }
    }
}

#if DEBUG
private enum HomePreview {
    /// Trevor as a caregiver, not an admin, on The Riverside Group.
    static let trevorCaregiver = Account(
        name: "Trevor", email: "twilliams0095@gmail.com",
        teams: [Account.Team(teamID: HomeFixtures.riverside.teamID, name: HomeFixtures.riverside.name,
                             role: "caregiver")])

    static let pausedOnly = TrackersFixtures.trackers.filter { $0.status == .paused }

    @MainActor
    static func view(account: Account = HomeFixtures.trevor,
                     byTeam: [String: [TeamReceiver]] = HomeFixtures.receiversByTeam,
                     trackers: [TrackerItem] = TrackersFixtures.trackers,
                     home: HomeService = HomeFixtures.service(timeline: { day in
                         DayTimeline(day: day, items: HomeFixtures.yesterdayTimeline.items)
                     }),
                     model: HomeModel? = nil) -> some View {
        var trackersService = HomeFixtures.trackersService(receiversByTeam: byTeam)
        trackersService.listTrackers = { _ in trackers }
        let active = ActiveReceiverModel(account: account, service: trackersService, store: .inMemory())
        return NavigationStack {
            HomeV1View(receiver: active, home: home, trackers: trackersService, model: model)
                .v1Destinations(service: trackersService, home: home)
        }
    }
}

#Preview("Needs attention (436:3226)") {
    HomePreview.view()
}

#Preview("All clear (437:3887)") {
    HomePreview.view(home: HomeFixtures.service(attention: [], timeline: { day in
        DayTimeline(day: day, items: HomeFixtures.yesterdayTimeline.items)
    }))
}

#Preview("An earlier day (437:4143)") {
    @Previewable @State var model = HomeModel(home: HomeFixtures.service(), trackers: HomeFixtures.trackersService())
    HomePreview.view(home: HomeFixtures.service(), model: model)
        .task {
            await model.show(HomeFixtures.eleanor.managed(by: HomeFixtures.riverside))
            await model.stepBack()
        }
}

#Preview("Nothing on this day (437:4427)") {
    HomePreview.view(home: HomeFixtures.service(attention: []))
}

#Preview("No care receivers, admin (438:3756)") {
    HomePreview.view(byTeam: [:])
}

#Preview("No care receivers, caregiver (438:3865)") {
    HomePreview.view(account: HomePreview.trevorCaregiver, byTeam: [:])
}

#Preview("No active trackers, admin (438:3971)") {
    HomePreview.view(trackers: HomePreview.pausedOnly,
                     home: HomeFixtures.service(attention: [], comingUp: []))
}

#Preview("No active trackers, caregiver (438:4075)") {
    HomePreview.view(account: HomePreview.trevorCaregiver, trackers: HomePreview.pausedOnly,
                     home: HomeFixtures.service(attention: [], comingUp: []))
}

#Preview("Failed") {
    HomePreview.view(home: HomeFixtures.service(fail: true))
}
#endif
