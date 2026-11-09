import SwiftUI

/// TEMPORARY. Where a caregiver on at least one care team lands while flag `v1_api`
/// is on. It stands in for Home and Team until those areas are built against `/v1`,
/// and exists only so the Getting in flow has somewhere real to end. Delete it when
/// Home ships.
struct V1PlaceholderView: View {
    let account: Account
    let onSignOut: () async -> Void
    /// TEMPORARY, with the "All trackers" button below.
    var trackers: TrackersService? = nil
    /// The stack's path; All trackers appends to it (see `V1Route`).
    @Binding var path: [V1Route]

    @State private var isSigningOut = false
    @State private var allTrackers: AllTrackersEntryModel?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            Spacer()
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("Signed in to \(account.teams.first?.name ?? "")")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text(account.name)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            Spacer()
            // TEMPORARY until Home is built: Home's receiver header is where "All
            // trackers" lives (PRD "Trackers"). This reaches the Trackers list for the
            // first team's first receiver so the area can be exercised behind v1_api.
            if let allTrackers {
                allTrackersEntry(allTrackers)
            }
            StrideButton(title: "Sign out", style: .secondary) {
                guard !isSigningOut else { return }
                isSigningOut = true
                Task { await onSignOut() }
            }
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .strideBackground()
        .toolbar(.hidden, for: .navigationBar)
        .onChange(of: allTrackers?.receiver) { _, receiver in
            guard let receiver else { return }
            path.append(.trackers(receiver))
            allTrackers?.receiver = nil
        }
        .onAppear {
            // No team, no receivers to reach: the button is left out rather than doing nothing.
            if allTrackers == nil, let trackers, let team = account.teams.first {
                allTrackers = AllTrackersEntryModel(team: team, service: trackers)
            }
        }
    }

    private func allTrackersEntry(_ model: AllTrackersEntryModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            switch model.outcome {
            case .idle:
                EmptyView()
            case .noReceivers(let teamName):
                Text("\(teamName) has no care receivers yet.")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.Colors.textTertiary)
            case .failed(let error):
                StrideAlertBanner(message: error.message)
            }
            StrideButton(title: "All trackers", style: .secondary, isLoading: model.isLoading) {
                Task { await model.open() }
            }
        }
    }
}

#if DEBUG
#Preview("Placeholder") {
    NavigationStack {
        V1PlaceholderView(account: GettingInFixtures.trevorOnRiverside, onSignOut: {},
                          trackers: TrackersFixtures.service(), path: .constant([]))
    }
}

#Preview("Team with no receivers") {
    NavigationStack {
        V1PlaceholderView(account: GettingInFixtures.trevorOnRiverside, onSignOut: {},
                          trackers: TrackersFixtures.service(receivers: []), path: .constant([]))
    }
}
#endif
