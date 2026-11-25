import SwiftUI

/// The signed-in `/v1` app: four tabs and the ⊕ button, driven by `StrideTabBar` (PRD
/// "The tab bar"). Home holds the one `/v1` navigation stack and Team its own; Insights
/// and Settings are named placeholders until their areas are built on this path. Team is
/// where the caregiver's teams change while signed in, so the account Home chooses from
/// follows Team's (`TeamListModel.account`), and picking a receiver there lands on Home. Every way into Quick
/// log — ⊕, Home's empty day, Entry detail, Tracker detail — goes through one presenter
/// (`V1QuickLog` into `QuickLogPresenter`), which also tells the screens beneath when a
/// run has saved something (`v1QuickLogRuns`). Edits and deletes on Entry detail and
/// Journal note are counted the same way (`v1HomeWrote` into `v1HomeWrites`), and the
/// ones that leave nothing to show go back to Home (`v1PopToHome`).
struct V1TabShell: View {
    let account: Account
    let trackers: TrackersService
    let home: HomeService
    let team: TeamService
    let onSignOut: () async -> Void
    @Binding var path: [V1Route]

    @State private var selectedTab: StrideTab = .home
    @State private var quickLog = QuickLogPresenter()
    /// Edits and deletes on Entry detail and Journal note, which Home reflects.
    @State private var homeWrites = HomeWriteLog()
    @State private var receiver: ActiveReceiverModel
    @State private var teamList: TeamListModel

    init(account: Account, trackers: TrackersService, home: HomeService, team: TeamService,
         store: LastReceiverStore = .standard,
         onSignOut: @escaping () async -> Void, path: Binding<[V1Route]>) {
        self.account = account
        self.trackers = trackers
        self.home = home
        self.team = team
        self.onSignOut = onSignOut
        _path = path
        _receiver = State(initialValue: ActiveReceiverModel(account: account, service: trackers, store: store))
        _teamList = State(initialValue: TeamListModel(account: account, service: team))
    }

    /// Picking or adding a care receiver on Team: their Home, as the active one, with Home's
    /// stack emptied so nothing pushed for the last receiver stays under the new one's name.
    /// A receiver just added: active, and their Home is where setting them up starts (PRD "Team").
    private func pick(_ r: TeamReceiver) {
        selectedTab = .home
        switchTo(r)
    }

    /// Switch on Team: the caregiver stays where they are, and Home's stack goes back to its
    /// top so it never shows one receiver's screens under another's name (PRD "Team").
    private func switchTo(_ r: TeamReceiver) {
        path = []
        Task { await receiver.choose(r.id) }
    }

    /// A care receiver was renamed, moved zone, archived or restored on Care receiver: Home
    /// chooses again from the receivers now (an archived one is never chosen), and Team reads
    /// its lists again.
    private var receiverChanged: V1ReceiverChanged {
        V1ReceiverChanged { [receiver, teamList] in
            Task {
                await receiver.load()
                await teamList.load()
            }
        }
    }

    /// The tab bar. See `StrideTabBar.reservedHeight` for why it is an overlay.
    private var tabBar: some View {
        StrideTabBar(selection: $selectedTab) { quickLog.open(.pick, receiver: receiver.active?.receiver) }
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack(path: $path) {
                HomeV1View(receiver: receiver, home: home, trackers: trackers, team: team)
                    .v1Destinations(service: trackers, home: home, team: team)
                    .strideTabBarClearance()
                    .toolbar(.hidden, for: .tabBar)
            }
            .environment(\.v1Push, V1Push { [path = $path] in path.wrappedValue.append($0) })
            .environment(\.v1PopToTrackers, V1PopToTrackers { [path = $path] in
                path.wrappedValue = V1Route.poppedToTrackers(path.wrappedValue)
            })
            .environment(\.v1QuickLog, V1QuickLog { [quickLog = $quickLog, receiver] start, r in
                quickLog.wrappedValue.open(start, receiver: r ?? receiver.active?.receiver)
            })
            .environment(\.v1QuickLogRuns, quickLog.runs)
            .environment(\.v1HomeWrote, V1HomeWrote { [homeWrites = $homeWrites] write in
                homeWrites.wrappedValue.record(write)
            })
            .environment(\.v1HomeWrites, homeWrites)
            .environment(\.v1PopToHome, V1PopToHome { [path = $path] in path.wrappedValue = [] })
            .environment(\.v1ReceiverChanged, receiverChanged)
            .tag(StrideTab.home)

            NavigationStack {
                V1Placeholder(title: "Insights", line: "Insights is deferred.")
                    .strideTabBarClearance()
                    .toolbar(.hidden, for: .tabBar)
            }
            .tag(StrideTab.insights)

            TeamTabV1(model: teamList, service: team, activeReceiverID: receiver.active?.receiver.id,
                      onSwitch: switchTo, onAdded: pick)
                .environment(\.v1ReceiverChanged, receiverChanged)
                .tag(StrideTab.team)

            NavigationStack {
                V1Placeholder(title: "Settings", line: "Settings isn't built on this path yet.") {
                    SignOutButton(onSignOut: onSignOut)
                }
                .strideTabBarClearance()
                .toolbar(.hidden, for: .tabBar)
            }
            .tag(StrideTab.settings)
        }
        // Drawn over the tabs, not inset: pushed screens never see a container's inset,
        // so every screen clears the bar itself (`strideTabBarClearance`).
        .overlay(alignment: .bottom) { tabBar.ignoresSafeArea(.keyboard) }
        // Joined, created, left or closed a team on Team: Home chooses again from the teams now.
        .onChange(of: teamList.account) { _, account in
            Task { await receiver.adopt(account) }
        }
        .sheet(item: $quickLog.sheet, onDismiss: {
            // Add tracker in Quick log's place made one: push it on Home's stack now the sheet is down.
            guard let created = quickLog.takeCreated() else { return }
            selectedTab = .home
            path.append(.tracker(id: created.trackerID, receiver: created.receiver))
        }) { sheet in
            switch sheet {
            case .quickLog(let start, let r):
                QuickLogV1Sheet(start: start, receiver: r, home: home, trackers: trackers,
                                onAddTracker: { quickLog.swapToAddTracker(r) },
                                onEnd: { quickLog.quickLogEnded($0) })
            case .addTracker(let r):
                AddTrackerV1Sheet(receiver: r, service: trackers) { quickLog.trackerCreated($0.id, receiver: r) }
            case .noReceiver:
                QuickLogNoReceiverSheet()
            }
        }
        .tint(Theme.Colors.accent)
    }
}

/// A named stand-in for a screen not yet built on the `/v1` path, so no exit dangles.
struct V1Placeholder<Actions: View>: View {
    let title: String
    let line: String
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(title)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text(line)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            Spacer()
            actions
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .strideBackground()
        .toolbar(.hidden, for: .navigationBar)
    }
}

extension V1Placeholder where Actions == EmptyView {
    init(title: String, line: String) {
        self.init(title: title, line: line) { EmptyView() }
    }
}

/// Signs out, once: a second tap while the first is in flight does nothing.
private struct SignOutButton: View {
    let onSignOut: () async -> Void
    @State private var isSigningOut = false

    var body: some View {
        StrideButton(title: "Sign out", style: .secondary, isLoading: isSigningOut) {
            guard !isSigningOut else { return }
            isSigningOut = true
            Task { await onSignOut() }
        }
    }
}

/// Log it or Skip, on a picked occurrence's step.
enum OccurrenceChoice: Equatable, Sendable {
    case logIt, skip
}

/// How Quick log opens (PRD "Quick log").
enum QuickLogStart: Equatable, Identifiable, Sendable {
    /// At the picker: ⊕, and Home's empty-day Log an entry.
    case pick
    /// At the picker with a journal note already picked: Home's Write a note.
    case journalNote
    /// Entry detail's Log it or Skip: holding that one entry, past the picking part, at
    /// its step with the choice made.
    case entry(EntryDetailInfo, choice: OccurrenceChoice)
    /// Tracker detail's Log an entry: scoped to that tracker, past the picking part
    /// unless it has occurrences waiting to pick between.
    case tracker(id: String)

    var id: String {
        switch self {
        case .pick: "pick"
        case .journalNote: "journalNote"
        case .entry(let d, let choice): "entry-\(d.entry.id)-\(choice == .logIt ? "log" : "skip")"
        case .tracker(let id): "tracker-\(id)"
        }
    }
}

/// Opens Quick log. Every way in — ⊕, Home's empty-day Log an entry and Write a note,
/// Entry detail's Log it and Skip, Tracker detail's Log an entry — goes through this one
/// presenter. `receiver` is the screen's own; nil means the active care receiver.
/// V1TabShell supplies it; elsewhere it does nothing.
struct V1QuickLog: Sendable {
    let open: @MainActor @Sendable (QuickLogStart, TeamReceiver?) -> Void

    @MainActor func callAsFunction(_ start: QuickLogStart = .pick, receiver: TeamReceiver? = nil) {
        open(start, receiver)
    }
}

private struct V1QuickLogKey: EnvironmentKey {
    static let defaultValue = V1QuickLog { _, _ in }
}

extension EnvironmentValues {
    var v1QuickLog: V1QuickLog {
        get { self[V1QuickLogKey.self] }
        set { self[V1QuickLogKey.self] = newValue }
    }
}

/// ⊕ before there is anyone to record for: Quick log is about a care receiver.
struct QuickLogNoReceiverSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        V1Placeholder(title: "Quick log", line: QuickLogText.noReceiver) {
            StrideButton(title: "Close", style: .secondary) { dismiss() }
        }
    }
}

#if DEBUG
#Preview("Tabs") {
    @Previewable @State var path: [V1Route] = []
    V1TabShell(account: TeamFixtures.trevor, trackers: HomeFixtures.trackersService(),
               home: HomeFixtures.service(), team: TeamFixtures.service(), store: .inMemory(),
               onSignOut: {}, path: $path)
}

#Preview("Quick log, no one to record for") {
    QuickLogNoReceiverSheet()
}
#endif
