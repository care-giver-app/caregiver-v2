import SwiftUI

/// The signed-in `/v1` app: four tabs and the ⊕ button, driven by `StrideTabBar` (PRD
/// "The tab bar"). Home holds the one `/v1` navigation stack; Insights, Team and Settings
/// are named placeholders until their areas are built on this path, and ⊕ raises a
/// placeholder for Quick log.
struct V1TabShell: View {
    let account: Account
    let trackers: TrackersService
    let home: HomeService
    let onSignOut: () async -> Void
    @Binding var path: [V1Route]

    @State private var selectedTab: StrideTab = .home
    @State private var showQuickLog = false
    @State private var receiver: ActiveReceiverModel

    init(account: Account, trackers: TrackersService, home: HomeService,
         store: LastReceiverStore = .standard,
         onSignOut: @escaping () async -> Void, path: Binding<[V1Route]>) {
        self.account = account
        self.trackers = trackers
        self.home = home
        self.onSignOut = onSignOut
        _path = path
        _receiver = State(initialValue: ActiveReceiverModel(account: account, service: trackers, store: store))
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack(path: $path) {
                HomeV1View(receiver: receiver, service: home)
                    .v1Destinations(service: trackers)
                    .toolbar(.hidden, for: .tabBar)
            }
            .environment(\.v1Push, V1Push { [path = $path] in path.wrappedValue.append($0) })
            .environment(\.v1PopToTrackers, V1PopToTrackers { [path = $path] in
                path.wrappedValue = V1Route.poppedToTrackers(path.wrappedValue)
            })
            .tag(StrideTab.home)

            NavigationStack {
                V1Placeholder(title: "Insights", line: "Insights is deferred.")
                    .toolbar(.hidden, for: .tabBar)
            }
            .tag(StrideTab.insights)

            NavigationStack {
                V1Placeholder(title: "Team", line: "Team isn't built on this path yet.")
                    .toolbar(.hidden, for: .tabBar)
            }
            .tag(StrideTab.team)

            NavigationStack {
                V1Placeholder(title: "Settings", line: "Settings isn't built on this path yet.") {
                    SignOutButton(onSignOut: onSignOut)
                }
                .toolbar(.hidden, for: .tabBar)
            }
            .tag(StrideTab.settings)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            StrideTabBar(selection: $selectedTab) { showQuickLog = true }
        }
        .sheet(isPresented: $showQuickLog) {
            QuickLogPlaceholderSheet()
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

/// Stands in for Quick log, which is still to be built on this path.
struct QuickLogPlaceholderSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        V1Placeholder(title: "Quick log", line: "Quick log isn't built on this path yet.") {
            StrideButton(title: "Close", style: .secondary) { dismiss() }
        }
    }
}

#if DEBUG
#Preview("Tabs") {
    @Previewable @State var path: [V1Route] = []
    V1TabShell(account: HomeFixtures.trevor, trackers: HomeFixtures.trackersService(),
               home: HomeFixtures.service(), store: .inMemory(), onSignOut: {}, path: $path)
}

#Preview("Quick log placeholder") {
    QuickLogPlaceholderSheet()
}
#endif
