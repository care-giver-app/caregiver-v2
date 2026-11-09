import SwiftUI

/// Tracker detail — one tracker, whole: what it is, how it is doing, and every
/// entry logged, skipped or unrecorded against it, newest first (PRD "Tracker
/// detail"; Figma 371:3339 active, 371:3397 never logged, 372:3371 gap alert,
/// 372:3407 paused). Edit, Log an entry and Resume arrive with PR 4 / Home.
struct TrackerDetailV1View: View {
    let trackerID: String
    let receiver: TeamReceiver
    let service: TrackersService

    @State private var model: TrackerDetailV1Model?
    @State private var choosingDates = false
    @State private var rangeFrom = Date()
    @State private var rangeTo = Date()

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
        .tint(Theme.Colors.accent)
        .task {
            if model == nil {
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
                    .padding(.bottom, Theme.Spacing.sm)

                if choosingDates {
                    rangeEditor(entries)
                        .padding(.bottom, 10)
                }

                entryList(profile, entries: entries, now: now)
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.top, Theme.Spacing.sm)
            .padding(.bottom, Theme.Spacing.lg)
        }
        .refreshable { await model.load() }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if profile.status == .paused {
                pausedStatus(profile, now: now)
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
            NavigationLink(value: V1Route.schedules(trackerID: profile.id, trackerName: profile.name)) {
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

    /// Figma 424:3832, without Resume (PR 4).
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

    /// Figma 432:3941: ENTRIES, and the stretch they are narrowed to.
    private func entriesHeader(_ entries: EntriesPager, now: Date) -> some View {
        HStack {
            Text("ENTRIES")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.Colors.textTertiary)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Menu {
                Button("All time") {
                    choosingDates = false
                    Task { await entries.setRange(nil) }
                }
                Button("Choose dates\u{2026}") {
                    if !choosingDates {
                        rangeTo = now
                        rangeFrom = now.addingTimeInterval(-6 * 86_400)
                        choosingDates = true
                        applyRange(entries)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(rangeLabel(entries, now: now))
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.Colors.accent)
            }
        }
    }

    private func rangeLabel(_ entries: EntriesPager, now: Date) -> String {
        entries.range == nil
            ? "All time"
            : TrackerText.rangeLabel(from: rangeFrom, to: rangeTo, now: now, zone: zone)
    }

    /// The picked stretch's two ends, as days in the receiver's zone.
    private func rangeEditor(_ entries: EntriesPager) -> some View {
        VStack(spacing: 6) {
            DatePicker("From", selection: $rangeFrom, displayedComponents: .date)
            DatePicker("To", selection: $rangeTo, in: rangeFrom..., displayedComponents: .date)
        }
        .font(.system(size: 14))
        .foregroundStyle(Theme.Colors.textSecondary)
        .environment(\.timeZone, zone)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .card()
        .onChange(of: rangeFrom) {
            if rangeTo < rangeFrom { rangeTo = rangeFrom }
            applyRange(entries)
        }
        .onChange(of: rangeTo) { applyRange(entries) }
    }

    private func applyRange(_ entries: EntriesPager) {
        let range = EntryDateRange(from: TrackerText.dayString(rangeFrom, zone: zone),
                                   to: TrackerText.dayString(rangeTo, zone: zone))
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
                EntryTileV1(entry: entry, fields: profile.fields, zone: zone, now: now)
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
            .v1Destinations(service: TrackersFixtures.service())
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
#endif
