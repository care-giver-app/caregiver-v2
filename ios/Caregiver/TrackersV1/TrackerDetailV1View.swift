import SwiftUI

/// Tracker detail — one tracker, whole: what it is, how it is doing, and every
/// entry logged, skipped or unrecorded against it, newest first (PRD "Tracker
/// detail"; Figma 371:3339 active, 371:3397 never logged, 372:3371 gap alert,
/// 372:3407 paused). Admins get Edit in the nav, and Resume on a paused tracker. An
/// active tracker offers Log an entry at the bottom — the never-logged state's offer of
/// the first entry included — opening Quick log scoped to it; the screen reads itself
/// again when a run saves.
struct TrackerDetailV1View: View {
    let trackerID: String
    let receiver: TeamReceiver
    let service: TrackersService

    @State private var model: TrackerDetailV1Model?
    /// All on open, every time — the choice is not remembered (PRD "Tracker detail").
    @State private var window: EntryWindow = .all
    @State private var choosingDates = false
    @State private var editing = false
    /// How Edit tracker ended, acted on once its sheet is down.
    @State private var editOutcome: EditTrackerOutcome?
    @Environment(\.v1PopToTrackers) private var popToTrackers
    @Environment(\.v1QuickLog) private var quickLog
    @Environment(\.v1QuickLogRuns) private var quickLogRuns

    private var zone: TimeZone { receiver.timeZone }

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
            if let model, model.canEdit {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Edit") { editing = true }
                }
            }
        }
        .sheet(isPresented: $editing, onDismiss: {
            let outcome = editOutcome
            editOutcome = nil
            switch outcome {
            case .saved, .schedulesChanged: Task { await model?.load() }
            case .paused: popToTrackers()
            case nil: break
            }
        }) {
            if let profile = model?.profile {
                EditTrackerV1Sheet(profile: profile, receiver: receiver, service: service) { editOutcome = $0 }
            }
        }
        .tint(Theme.Colors.accent)
        // Back from Quick log, with what was logged in the list.
        .onChange(of: quickLogRuns) { Task { await model?.load() } }
        .task {
            if let model {
                // Back from Schedules, where Edit tracker may have changed it.
                await model.load()
            } else {
                let model = TrackerDetailV1Model(trackerID: trackerID, receiver: receiver, service: service)
                self.model = model
                await model.load()
            }
        }
    }

    @ViewBuilder
    private func content(_ model: TrackerDetailV1Model) -> some View {
        switch model.phase {
        case .loading:
            StrideLoadingView()
        case .failed:
            StrideErrorState(message: "Couldn't load this tracker.") {
                Task { await model.retry() }
            }
        case .loaded(let profile):
            loaded(profile, entries: model.entries, model: model)
        }
    }

    private func loaded(_ profile: TrackerProfile, entries: EntriesPager,
                        model: TrackerDetailV1Model) -> some View {
        let now = Date()
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if model.showsRefreshFailure {
                    StrideAlertBanner(message: "Couldn't refresh this tracker.")
                        .padding(.bottom, Theme.Spacing.md)
                }

                identity(profile)
                    .padding(.bottom, Theme.Spacing.md)

                watchLine(profile)

                if !profile.attention.isEmpty {
                    attention(profile, now: now)
                        .padding(.bottom, Theme.Spacing.md)
                }

                entriesHeader(entries, now: now)
                    .padding(.top, Theme.Spacing.sm)
                    .padding(.bottom, 12)

                entryList(profile, entries: entries, now: now)
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.top, Theme.Spacing.sm)
            .padding(.bottom, Theme.Spacing.lg)
        }
        .refreshable { await model.load() }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if profile.status == .paused {
                VStack(spacing: 12) {
                    pausedStatus(profile, now: now)
                    if model.canResume {
                        resume(profile, model: model)
                    }
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.vertical, Theme.Spacing.sm)
            } else {
                // Figma 371:3339 / 371:3397.
                StrideButton(title: "Log an entry") { quickLog(.tracker(id: profile.id), receiver: receiver) }
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.vertical, Theme.Spacing.sm)
            }
        }
    }

    // MARK: Header

    /// Figma 424:3746: the icon on a tile of its color, and its name.
    private func identity(_ profile: TrackerProfile) -> some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(hex: profile.color))
                .frame(width: 56, height: 56)
                .overlay {
                    Image(systemName: profile.icon)
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(Color.white)
                }
                .accessibilityHidden(true)
            Text(profile.name)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(profile.status == .paused ? Theme.Colors.textTertiary : Theme.Colors.textPrimary)
                .accessibilityAddTraits(.isHeader)
        }
    }

    /// Its schedules (opening Schedules), or the gap that watches it instead (opening nothing).
    @ViewBuilder
    private func watchLine(_ profile: TrackerProfile) -> some View {
        if profile.scheduleCount > 0 {
            NavigationLink(value: V1Route.schedules(trackerID: profile.id, trackerName: profile.name,
                                                    receiver: receiver)) {
                HStack {
                    Text(TrackerText.scheduleCount(profile.scheduleCount))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Spacer(minLength: Theme.Spacing.sm)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
                .padding(14)
                .card()
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.bottom, Theme.Spacing.md)
        } else if let hours = profile.gapHours {
            Text(TrackerText.gapLine(hours: hours))
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.Colors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .card()
                .padding(.bottom, Theme.Spacing.md)
        }
    }

    /// Figma 424:3805: what is wrong right now, said in words.
    private func attention(_ profile: TrackerProfile, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Needs attention")
                .fontWeight(.semibold)
                .foregroundStyle(Theme.Colors.warning)
            ForEach(Array(profile.attention.enumerated()), id: \.offset) { _, item in
                Text(TrackerText.attention(item, fields: profile.fields, now: now, zone: zone))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(.system(size: 14))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background { RoundedRectangle(cornerRadius: 14).fill(Theme.Colors.warningTint) }
        .accessibilityElement(children: .combine)
    }

    /// Figma 372:3407: Resume, saying first what it starts again. It doesn't ask twice.
    private func resume(_ profile: TrackerProfile, model: TrackerDetailV1Model) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            if let failed = model.resumeFailed {
                StrideAlertBanner(message: "Couldn't resume the tracker. \(failed.message)")
            }
            Text(TrackerText.resumeExplanation(profile))
                .font(Theme.Typography.subhead)
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            StrideButton(title: "Resume", isLoading: model.isResuming) {
                Task { await model.resume() }
            }
        }
    }

    /// Figma 424:3832: when it was paused and what that means.
    private func pausedStatus(_ profile: TrackerProfile, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(TrackerText.paused(at: profile.pausedAt, now: now, zone: zone))
                .fontWeight(.semibold)
                .foregroundStyle(Theme.Colors.textSecondary)
            Text(TrackerText.pausedExplanation)
                .foregroundStyle(Theme.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: 14))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background { RoundedRectangle(cornerRadius: 14).fill(Theme.Colors.surface) }
        .overlay { RoundedRectangle(cornerRadius: 14).stroke(Theme.Colors.border, lineWidth: 1) }
        .accessibilityElement(children: .combine)
    }

    // MARK: Entries

    /// Figma 514:934: ENTRIES, and the chips that narrow them (513:922).
    private func entriesHeader(_ entries: EntriesPager, now: Date) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("ENTRIES")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.Colors.textTertiary)
                .accessibilityAddTraits(.isHeader)
            EntryWindowChips(window: window, today: LocalDay(now, zone: zone)) { chip in
                switch chip {
                case .all: apply(.all, entries)
                case .last7: apply(.last7, entries)
                case .last30: apply(.last30, entries)
                case .custom: choosingDates = true
                }
            }
        }
        .sheet(isPresented: $choosingDates) {
            ChooseDatesSheet(today: LocalDay(Date(), zone: zone), seed: window.customStretch) { chosen in
                apply(chosen, entries)
            }
        }
    }

    /// Narrows to `window`; 7 and 30 days count back from today in the receiver's zone.
    private func apply(_ window: EntryWindow, _ entries: EntriesPager) {
        self.window = window
        let range = window.range(today: LocalDay(Date(), zone: zone))
        Task { await entries.setRange(range) }
    }

    @ViewBuilder
    private func entryList(_ profile: TrackerProfile, entries: EntriesPager, now: Date) -> some View {
        switch entries.phase {
        case .loading:
            ProgressView()
                .tint(Theme.Colors.accent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Spacing.lg)
        case .failed:
            VStack(alignment: .leading, spacing: 10) {
                StrideAlertBanner(message: "Couldn't load the entries.")
                StrideButton(title: "Try again", style: .compact) {
                    Task { await entries.reload() }
                }
            }
        case .loaded where entries.entries.isEmpty:
            if entries.range == nil {
                neverLogged(profile)
            } else {
                Text("Nothing in these dates.")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .loaded:
            ForEach(entries.entries) { entry in
                // Every entry opens Entry detail, whatever its state (PRD "Tracker detail").
                NavigationLink(value: V1Route.entry(id: entry.id, receiver: receiver)) {
                    EntryTileV1(entry: entry, fields: profile.fields, zone: zone, now: now)
                }
                .buttonStyle(.plain)
                .padding(.bottom, 10)
                .task { await entries.entryAppeared(entry) }
            }
            if entries.isLoadingMore {
                ProgressView()
                    .tint(Theme.Colors.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Spacing.sm)
            } else if entries.moreFailed {
                StrideButton(title: "Try again", style: .compact) {
                    Task { await entries.loadMore() }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    /// Figma 371:3397 — the state every tracker passes through on the day it is made.
    private func neverLogged(_ profile: TrackerProfile) -> some View {
        VStack(spacing: 4) {
            Text("Nothing logged yet")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.Colors.textPrimary)
            if let hours = profile.gapHours, profile.status == .active {
                Text(TrackerText.neverLoggedGap(hours: hours))
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 120)
    }
}

/// Tracker detail's chips under ENTRIES — All, 7 days, 30 days, Custom — the same
/// look as the Trackers list's filters, without counts. Custom reads the stretch
/// while one is chosen, and opens Choose dates whether selected or not.
struct EntryWindowChips: View {
    let window: EntryWindow
    let today: LocalDay
    let onTap: (EntryWindowChip) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.sm) {
                ForEach(EntryWindowChip.allCases, id: \.self) { chip in
                    StrideChip(label: chip.label(for: window, today: today),
                               isSelected: chip.isSelected(by: window)) { onTap(chip) }
                }
            }
        }
        .scrollClipDisabled()
    }
}

private extension View {
    /// The white, hairline-bordered card rows on Tracker detail sit in.
    func card() -> some View {
        self
            .background { RoundedRectangle(cornerRadius: 16).fill(Theme.Colors.surface) }
            .overlay { RoundedRectangle(cornerRadius: 16).stroke(Theme.Colors.border, lineWidth: 1) }
    }
}

#if DEBUG
#Preview("Active, unrecorded") {
    NavigationStack {
        TrackerDetailV1View(trackerID: "medication", receiver: TrackersFixtures.eleanor,
                            service: TrackersFixtures.service())
            .v1Destinations(service: TrackersFixtures.service(), home: HomeFixtures.service())
    }
}

#Preview("Entry chips") {
    @Previewable @State var window: EntryWindow = .all
    let today = LocalDay(Date(), zone: TrackersFixtures.eleanor.timeZone)
    VStack(alignment: .leading, spacing: Theme.Spacing.md) {
        EntryWindowChips(window: .all, today: today) { _ in }
        EntryWindowChips(window: .last7, today: today) { _ in }
        EntryWindowChips(window: .custom(first: today.adding(days: -6), last: today.adding(days: -1)),
                         today: today) { _ in }
        EntryWindowChips(window: window, today: today) { chip in
            switch chip {
            case .all: window = .all
            case .last7: window = .last7
            case .last30: window = .last30
            case .custom: window = .custom(first: today.adding(days: -6), last: today.adding(days: -1))
            }
        }
    }
    .padding(Theme.Spacing.lg)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .strideBackground()
}

#Preview("Choose dates") {
    let today = LocalDay(Date(), zone: TrackersFixtures.eleanor.timeZone)
    Color.clear.sheet(isPresented: .constant(true)) {
        ChooseDatesSheet(today: today, seed: (today.adding(days: -6), today.adding(days: -1)),
                         onDone: { _ in })
    }
}

#Preview("Gap alert") {
    NavigationStack {
        TrackerDetailV1View(trackerID: "meals", receiver: TrackersFixtures.eleanor,
                            service: TrackersFixtures.service())
    }
}

#Preview("Out of range") {
    NavigationStack {
        TrackerDetailV1View(trackerID: "bp", receiver: TrackersFixtures.eleanor,
                            service: TrackersFixtures.service())
    }
}

#Preview("Never logged") {
    NavigationStack {
        TrackerDetailV1View(trackerID: "weight", receiver: TrackersFixtures.eleanor,
                            service: TrackersFixtures.service())
    }
}

#Preview("Paused") {
    NavigationStack {
        TrackerDetailV1View(trackerID: "walk", receiver: TrackersFixtures.eleanor,
                            service: TrackersFixtures.service())
    }
}

#Preview("Paused, caregiver") {
    NavigationStack {
        TrackerDetailV1View(trackerID: "walk", receiver: TrackersFixtures.eleanorForCaregiver,
                            service: TrackersFixtures.service())
    }
}
#endif
